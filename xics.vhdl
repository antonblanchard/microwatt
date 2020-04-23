--
-- This is a simple XICS compliant interrupt controller.  This is a
-- Presenter (ICP) and Source (ICS) in a single unit with no routing
-- layer.
--
-- The sources have a fixed IRQ priority set by HW_PRIORITY. The
-- source id starts at 16 for int_level_in(0) and go up from
-- there (ie int_level_in(1) is source id 17).
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

entity xics is
    generic (
        LEVEL_NUM : positive := 16
        );
    port (
        clk          : in std_logic;
        rst          : in std_logic;

        wb_in   : in wishbone_master_out;
        wb_out  : out wishbone_slave_out;

	int_level_in : in std_ulogic_vector(LEVEL_NUM - 1 downto 0);

	e_out : out XicsToExecute1Type
        );
end xics;

architecture behaviour of xics is
    type reg_internal_t is record
	xisr : std_ulogic_vector(23 downto 0);
	cppr : std_ulogic_vector(7 downto 0);
	pending_priority : std_ulogic_vector(7 downto 0);
	mfrr : std_ulogic_vector(7 downto 0);
	mfrr_pending : std_ulogic;
	irq : std_ulogic;
	wb_rd_data : wishbone_data_type;
	wb_ack : std_ulogic;
    end record;
    constant reg_internal_init : reg_internal_t :=
	(wb_ack => '0',
	 mfrr_pending => '0',
	 mfrr => x"00", -- mask everything on reset
	 irq => '0',
	 others => (others => '0'));

    signal r, r_next : reg_internal_t;

    -- hardwire the hardware IRQ priority
    constant HW_PRIORITY : std_ulogic_vector(7 downto 0) := x"80";

    -- 32 bit offsets for each presentation
    constant XIRR_POLL : std_ulogic_vector(31 downto 0) := x"00000000";
    constant XIRR      : std_ulogic_vector(31 downto 0) := x"00000004";
    constant RESV0     : std_ulogic_vector(31 downto 0) := x"00000008";
    constant MFRR      : std_ulogic_vector(31 downto 0) := x"0000000c";

begin

    regs : process(clk)
    begin
	if rising_edge(clk) then
	    r <= r_next;
	end if;
    end process;

    wb_out.dat <= r.wb_rd_data;
    wb_out.ack <= r.wb_ack;
    wb_out.stall <= '0'; -- never stall wishbone
    e_out.irq <= r.irq;

    comb : process(all)
	variable v : reg_internal_t;
	variable xirr_accept_rd : std_ulogic;
	variable irq_eoi : std_ulogic;
    begin
	v := r;

	v.wb_ack := '0';

	xirr_accept_rd := '0';
	irq_eoi := '0';

	if wb_in.cyc = '1' and wb_in.stb = '1' then
	    -- wishbone addresses we get are 64 bit alligned, so we
	    -- need to use the sel bits to get 32 bit chunks.
	    v.wb_ack := '1'; -- always ack
	    if wb_in.we = '1' then -- write
		-- writes to both XIRR are the same
		if wb_in.adr = XIRR_POLL then
		    report "XICS XIRR_POLL/XIRR write";
		    if wb_in.sel = x"0f" then -- 4 bytes
			v.cppr := wb_in.dat(31 downto 24);
		    elsif wb_in.sel = x"f0"  then -- 4 byte
			v.cppr := wb_in.dat(63 downto 56);
			irq_eoi := '1';
		    elsif wb_in.sel = x"01"  then -- 1 byte
			v.cppr := wb_in.dat(7 downto 0);
		    elsif wb_in.sel = x"10"  then -- 1 byte
			v.cppr := wb_in.dat(39 downto 32);
		    end if;

		elsif wb_in.adr = RESV0 then
		    report "XICS MFRR write";
		    if wb_in.sel = x"f0" then -- 4 bytes
			v.mfrr_pending := '1';
			v.mfrr := wb_in.dat(63 downto 56);
		    elsif wb_in.sel = x"10" then -- 1 byte
			v.mfrr_pending := '1';
			v.mfrr := wb_in.dat(39 downto 32);
		    end if;

		end if;

	    else -- read
		v.wb_rd_data := (others => '0');

		if wb_in.adr = XIRR_POLL then
		    report "XICS XIRR_POLL/XIRR read";
		    if wb_in.sel = x"0f" then
			v.wb_rd_data(23 downto  0) := r.xisr;
			v.wb_rd_data(31 downto 24) := r.cppr;
		    elsif wb_in.sel = x"f0" then
			v.wb_rd_data(55 downto 32) := r.xisr;
			v.wb_rd_data(63 downto 56) := r.cppr;
			xirr_accept_rd := '1';
		    elsif wb_in.sel = x"01" then
			v.wb_rd_data(7 downto  0) := r.cppr;
		    elsif wb_in.sel = x"10" then
			v.wb_rd_data(39 downto 32) := r.cppr;
		    end if;

		elsif wb_in.adr = RESV0 then
		    report "XICS MFRR read";
		    if wb_in.sel = x"f0" then -- 4 bytes
			v.wb_rd_data(63 downto 56) := r.mfrr;
		    elsif wb_in.sel = x"10" then -- 1 byte
			v.wb_rd_data( 7 downto  0) := r.mfrr;
		    end if;
		end if;
	    end if;
	end if;

	-- generate interrupt
	if r.irq = '0' then
	    -- Here we just present any interrupt that's valid and
	    -- below cppr. For ordering, we ignore hardware
	    -- priorities.
	    if unsigned(HW_PRIORITY) < unsigned(r.cppr) then --
		-- lower HW sources are higher priority
		for i in LEVEL_NUM - 1 downto 0 loop
		    if int_level_in(i) = '1' then
			v.irq := '1';
			v.xisr := std_ulogic_vector(to_unsigned(16 + i, 24));
			v.pending_priority := HW_PRIORITY; -- hardware HW IRQs
		    end if;
		end loop;
	    end if;

	    -- Do mfrr as a higher priority so mfrr_pending is cleared
	    if unsigned(r.mfrr) < unsigned(r.cppr) then --
		report "XICS: MFRR INTERRUPT";
		-- IPI
		if r.mfrr_pending = '1' then
		    v.irq := '1';
		    v.xisr := x"000002"; -- special XICS MFRR IRQ source number
		    v.pending_priority := r.mfrr;
		    v.mfrr_pending := '0';
		end if;
	    end if;
	end if;

	-- Accept the interrupt
	if xirr_accept_rd = '1' then
	    report "XICS: ACCEPT" &
		" cppr:" &  to_hstring(r.cppr) &
		" xisr:" & to_hstring(r.xisr) &
		" mfrr:" & to_hstring(r.mfrr);
	    v.cppr := r.pending_priority;
	end if;

	if irq_eoi = '1' then
	    v.irq := '0';
	end if;

	if rst = '1' then
	    v := reg_internal_init;
	end if;

	r_next <= v;

    end process;

end architecture behaviour;
