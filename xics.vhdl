--
-- This is a simple XICS compliant interrupt controller.  This is a
-- Presenter (ICP) and Source (ICS) in two small units directly
-- connected to each other with no routing layer.
--
-- The sources have a configurable IRQ priority set a set of ICS
-- registers in the source units.
--
-- The source ids start at 16 for int_level_in(0) and go up from
-- there (ie int_level_in(1) is source id 17). XXX Make a generic
--
-- The presentation layer will pick an interupt that is more
-- favourable than the current CPPR and present it via the XISR and
-- send an interrpt to the processor (via e_out). This may not be the
-- highest priority interrupt currently presented (which is allowed
-- via XICS)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity xics_icp is
    port (
        clk          : in std_logic;
        rst          : in std_logic;

        wb_in        : in wb_io_master_out;
        wb_out       : out wb_io_slave_out;

        ics_in       : in ics_to_icp_t;
        core_irq_out : out std_ulogic
        );
end xics_icp;

architecture behaviour of xics_icp is
    type reg_internal_t is record
        xisr       : std_ulogic_vector(23 downto 0);
        cppr       : std_ulogic_vector(7 downto 0);
        mfrr       : std_ulogic_vector(7 downto 0);
        irq        : std_ulogic;
        wb_rd_data : std_ulogic_vector(31 downto 0);
        wb_ack     : std_ulogic;
    end record;
    constant reg_internal_init : reg_internal_t :=
        (wb_ack => '0',
         mfrr => x"ff", -- mask everything on reset
         irq => '0',
         others => (others => '0'));

    signal r, r_next : reg_internal_t;

    -- 8 bit offsets for each presentation
    constant XIRR_POLL : std_ulogic_vector(7 downto 0) := x"00";
    constant XIRR      : std_ulogic_vector(7 downto 0) := x"04";
    constant RESV0     : std_ulogic_vector(7 downto 0) := x"08";
    constant MFRR      : std_ulogic_vector(7 downto 0) := x"0c";

begin

    regs : process(clk)
    begin
        if rising_edge(clk) then
            r <= r_next;

            -- We delay core_irq_out by a cycle to help with timing
            core_irq_out <= r.irq;
        end if;
    end process;

    wb_out.dat <= r.wb_rd_data;
    wb_out.ack <= r.wb_ack;
    wb_out.stall <= '0'; -- never stall wishbone

    comb : process(all)
        variable v : reg_internal_t;
        variable xirr_accept_rd : std_ulogic;

        function  bswap(vec : in std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
            variable rout : std_ulogic_vector(31 downto 0);
        begin
            rout( 7 downto  0) := vec(31 downto 24);
            rout(15 downto  8) := vec(23 downto 16);
            rout(23 downto 16) := vec(15 downto  8);
            rout(31 downto 24) := vec( 7 downto  0);
            return rout;
        end function;

        variable be_in  : std_ulogic_vector(31 downto 0);
        variable be_out : std_ulogic_vector(31 downto 0);

        variable pending_priority : std_ulogic_vector(7 downto 0);
    begin
        v := r;

        v.wb_ack := '0';

        xirr_accept_rd := '0';

        be_in := bswap(wb_in.dat);
        be_out := (others => '0');

        if wb_in.cyc = '1' and wb_in.stb = '1' then
            v.wb_ack := '1'; -- always ack
            if wb_in.we = '1' then -- write
                -- writes to both XIRR are the same
                case wb_in.adr(5 downto 0) & "00" is
                when XIRR_POLL =>
                    report "ICP XIRR_POLL write";
                    v.cppr := be_in(31 downto 24);
                when XIRR =>
                    v.cppr := be_in(31 downto 24);
                    if wb_in.sel = x"f"  then -- 4 byte
                        report "ICP XIRR write word (EOI) :" & to_hstring(be_in);
                    elsif wb_in.sel = x"1"  then -- 1 byte
                        report "ICP XIRR write byte (CPPR):" & to_hstring(be_in(31 downto 24));
                    else
                        report "ICP XIRR UNSUPPORTED write ! sel=" & to_hstring(wb_in.sel);
                    end if;
                when MFRR =>
                    v.mfrr := be_in(31 downto 24);
                    if wb_in.sel = x"f" then -- 4 bytes
                        report "ICP MFRR write word:" & to_hstring(be_in);
                    elsif wb_in.sel = x"1" then -- 1 byte
                        report "ICP MFRR write byte:" & to_hstring(be_in(31 downto 24));
                    else
                        report "ICP MFRR UNSUPPORTED write ! sel=" & to_hstring(wb_in.sel);
                    end if;
                when others =>                        
                end case;

            else -- read

                case wb_in.adr(5 downto 0) & "00" is
                when XIRR_POLL =>
                    report "ICP XIRR_POLL read";
                    be_out := r.cppr & r.xisr;
                when XIRR =>
                    report "ICP XIRR read";
                    be_out := r.cppr & r.xisr;
                    if wb_in.sel = x"f" then
                        xirr_accept_rd := '1';
                    end if;
                when MFRR =>
                    report "ICP MFRR read";
                    be_out(31 downto 24) := r.mfrr;
                when others =>                        
                end case;
            end if;
        end if;

        pending_priority := x"ff";
        v.xisr := x"000000";
        v.irq := '0';

        if ics_in.pri /= x"ff" then
            v.xisr := x"00001" & ics_in.src;
            pending_priority := ics_in.pri;
        end if;

        -- Check MFRR
        if unsigned(r.mfrr) < unsigned(pending_priority) then --
            v.xisr := x"000002"; -- special XICS MFRR IRQ source number
            pending_priority := r.mfrr;
        end if;

        -- Accept the interrupt
        if xirr_accept_rd = '1' then
            report "XICS: ICP ACCEPT" &
                " cppr:" &  to_hstring(r.cppr) &
                " xisr:" & to_hstring(r.xisr) &
                " mfrr:" & to_hstring(r.mfrr);
            v.cppr := pending_priority;
        end if;

        v.wb_rd_data := bswap(be_out);

        if unsigned(pending_priority) < unsigned(v.cppr) then
            if r.irq = '0' then
                report "IRQ set";
            end if;
            v.irq := '1';
        elsif r.irq = '1' then
            report "IRQ clr";
        end if;

        if rst = '1' then
            v := reg_internal_init;
        end if;

        r_next <= v;

    end process;

end architecture behaviour;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.utils.all;
use work.wishbone_types.all;
use work.helpers.all;

entity xics_ics is
    generic (
        SRC_NUM    : integer range 1 to 256  := 16;
        PRIO_BITS  : integer range 1 to 8    := 3
        );
    port (
        clk          : in std_logic;
        rst          : in std_logic;

        wb_in        : in wb_io_master_out;
        wb_out       : out wb_io_slave_out;

        int_level_in : in std_ulogic_vector(SRC_NUM - 1 downto 0);
        icp_out      : out ics_to_icp_t
        );
end xics_ics;

architecture rtl of xics_ics is

    constant SRC_NUM_BITS : natural := log2(SRC_NUM);

    subtype pri_t is std_ulogic_vector(PRIO_BITS-1 downto 0);
    type xive_t is record
        pri : pri_t;
    end record;
    constant pri_masked : pri_t := (others => '1');

    subtype pri_vector_t is std_ulogic_vector(2**PRIO_BITS - 1 downto 0);

    type xive_array_t is array(0 to SRC_NUM-1) of xive_t;
    signal xives : xive_array_t;

    signal wb_valid : std_ulogic;
    signal reg_idx : integer range 0 to SRC_NUM - 1;
    signal icp_out_next : ics_to_icp_t;
    signal int_level_l : std_ulogic_vector(SRC_NUM - 1 downto 0);

    function bswap(v : in std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
        variable r : std_ulogic_vector(31 downto 0);
    begin
        r( 7 downto  0) := v(31 downto 24);
        r(15 downto  8) := v(23 downto 16);
        r(23 downto 16) := v(15 downto  8);
        r(31 downto 24) := v( 7 downto  0);
        return r;
    end function;

    function get_config return std_ulogic_vector is
        variable r: std_ulogic_vector(31 downto 0);
    begin
        r := (others => '0');
        r(23 downto  0) := std_ulogic_vector(to_unsigned(SRC_NUM, 24));
        r(27 downto 24) := std_ulogic_vector(to_unsigned(PRIO_BITS, 4));
        return r;
    end function;

    function prio_pack(pri8: std_ulogic_vector(7 downto 0)) return pri_t is
        variable masked : std_ulogic_vector(7 downto 0);
    begin
        masked := x"00";
        masked(PRIO_BITS - 1 downto 0) := (others => '1');
        if unsigned(pri8) >= unsigned(masked) then
            return pri_masked;
        else
            return pri8(PRIO_BITS-1 downto 0);
        end if;
    end function;

    function prio_unpack(pri: pri_t) return std_ulogic_vector is
        variable r : std_ulogic_vector(7 downto 0);
    begin
        if pri = pri_masked then
            r := x"ff";
        else
            r := (others => '0');
            r(PRIO_BITS-1 downto 0) := pri;
        end if;
        return r;
    end function;

    function prio_decode(pri: pri_t) return pri_vector_t is
        variable v: pri_vector_t;
    begin
        v := (others => '0');
        v(to_integer(unsigned(pri))) := '1';
        return v;
    end function;

    -- Assumes nbits <= 6; v is 2^nbits wide
    function priority_encoder(v: std_ulogic_vector; nbits: natural) return std_ulogic_vector is
        variable h: std_ulogic_vector(2**nbits - 1 downto 0);
        variable p: std_ulogic_vector(5 downto 0);
    begin
        -- Set the lowest-priority (highest-numbered) bit
        h := v;
        h(2**nbits - 1) := '1';
        p := count_right_zeroes(h);
        return p(nbits - 1 downto 0);
    end function;

-- Register map
    --     0  : Config
    --     4  : Debug/diagnostics
    --   800  : XIVE0
    --   804  : XIVE1 ...
    --
    -- Config register format:
    --
    --  23..  0 : Interrupt base (hard wired to 16)
    --  27.. 24 : #prio bits (1..8)
    --
    -- XIVE register format:
    --
    --       31 : input bit (reflects interrupt input)
    --       30 : reserved
    --       29 : P (mirrors input for now)
    --       28 : Q (not implemented in this version)
    -- 30 ..    : reserved
    -- 19 ..  8 : target (not implemented in this version)
    --  7 ..  0 : prio/mask

    signal reg_is_xive   : std_ulogic;
    signal reg_is_config : std_ulogic;
    signal reg_is_debug  : std_ulogic;

begin

    assert SRC_NUM = 16 report "Fixup address decode with log2";

    reg_is_xive   <= wb_in.adr(9);
    reg_is_config <= '1' when wb_in.adr(9 downto 0) = 10x"000" else '0';
    reg_is_debug  <= '1' when wb_in.adr(9 downto 0) = 10x"001" else '0';

    -- Register index XX FIXME: figure out bits from SRC_NUM
    reg_idx <= to_integer(unsigned(wb_in.adr(3 downto 0)));

    -- Latch interrupt inputs for timing
    int_latch: process(clk)
    begin
        if rising_edge(clk) then
            int_level_l <= int_level_in;
        end if;
    end process;

    -- We don't stall. Acks are sent by the read machine one cycle
    -- after a request, but we can handle one access per cycle.
    wb_out.stall <= '0';
    wb_valid <= wb_in.cyc and wb_in.stb;

    -- Big read mux. This could be replaced by a slower state
    -- machine iterating registers instead if timing gets tight.
    reg_read: process(clk)
        variable be_out : std_ulogic_vector(31 downto 0);
    begin
        if rising_edge(clk) then
            be_out := (others => '0');

            if reg_is_xive = '1' then
                be_out := int_level_l(reg_idx) &
                          '0' &
                          int_level_l(reg_idx) &
                          '0' &
                          x"00000" &
                          prio_unpack(xives(reg_idx).pri);
            elsif reg_is_config = '1' then
                be_out := get_config;
            elsif reg_is_debug = '1' then
                be_out := x"00000" & icp_out_next.src & icp_out_next.pri;
            end if;
            wb_out.dat <= bswap(be_out);
            wb_out.ack <= wb_valid;
        end if;
    end process;

    -- Register write machine
    reg_write: process(clk)
        variable be_in  : std_ulogic_vector(31 downto 0);
    begin
        -- Byteswapped input
        be_in := bswap(wb_in.dat);

        if rising_edge(clk) then
            if rst = '1' then
                for i in 0 to SRC_NUM - 1 loop
                    xives(i) <= (pri => pri_masked);
                end loop;
            elsif wb_valid = '1' and wb_in.we = '1' then
                if reg_is_xive then
                    -- TODO: When adding support for other bits, make sure to
                    -- properly implement wb_in.sel to allow partial writes.
                    xives(reg_idx).pri <= prio_pack(be_in(7 downto 0));
                    report "ICS irq " & integer'image(reg_idx) &
                        " set to:" & to_hstring(be_in(7 downto 0));
                end if;
            end if;
        end if;
    end process;

    -- generate interrupt. This is a simple combinational process,
    -- potentially wasteful in HW for large number of interrupts.
    --
    -- could be replaced with iterative state machines and a message
    -- system between ICSs' (plural) and ICP  incl. reject etc...
    --
    irq_gen_sync: process(clk)
    begin
        if rising_edge(clk) then
            icp_out <= icp_out_next;
        end if;
    end process;

    irq_gen: process(all)
        variable max_idx : std_ulogic_vector(SRC_NUM_BITS - 1 downto 0);
        variable max_pri : pri_t;
        variable pending_pri : pri_vector_t;
        variable pending_at_pri : std_ulogic_vector(SRC_NUM - 1 downto 0);
    begin
        -- Work out the most-favoured (lowest) priority of the pending interrupts
        pending_pri := (others => '0');
        for i in 0 to SRC_NUM - 1 loop
            if int_level_l(i) = '1' then
                pending_pri := pending_pri or prio_decode(xives(i).pri);
            end if;
        end loop;
        max_pri := priority_encoder(pending_pri, PRIO_BITS);

        -- Work out which interrupts are pending at that priority
        pending_at_pri := (others => '0');
        for i in 0 to SRC_NUM - 1 loop
            if int_level_l(i) = '1' and xives(i).pri = max_pri then
                pending_at_pri(i) := '1';
            end if;
        end loop;
        max_idx := priority_encoder(pending_at_pri, SRC_NUM_BITS);

        if max_pri /= pri_masked then
            report "MFI: " & integer'image(to_integer(unsigned(max_idx))) & " pri=" & to_hstring(prio_unpack(max_pri));
        end if;
        icp_out_next.src <= max_idx;
        icp_out_next.pri <= prio_unpack(max_pri);
    end process;

end architecture rtl;
