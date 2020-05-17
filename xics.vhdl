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

        wb_in   : in wb_io_master_out;
        wb_out  : out wb_io_slave_out;

	int_level_in : in std_ulogic_vector(LEVEL_NUM - 1 downto 0);

	core_irq_out : out std_ulogic
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
	wb_rd_data : std_ulogic_vector(31 downto 0);
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
	end if;
    end process;

    wb_out.dat <= r.wb_rd_data;
    wb_out.ack <= r.wb_ack;
    wb_out.stall <= '0'; -- never stall wishbone
    core_irq_out <= r.irq;

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
	    v.wb_ack := '1'; -- always ack
	    if wb_in.we = '1' then -- write
		-- writes to both XIRR are the same
		case wb_in.adr(7 downto 0) is
                when XIRR_POLL =>
		    report "XICS XIRR_POLL write";
		    if wb_in.sel = x"f" then -- 4 bytes
			v.cppr := wb_in.dat(31 downto 24);
		    elsif wb_in.sel = x"1"  then -- 1 byte
			v.cppr := wb_in.dat(7 downto 0);
                    end if;
                when XIRR =>
		    if wb_in.sel = x"f"  then -- 4 byte
                        report "XICS XIRR write word:" & to_hstring(wb_in.dat);
			v.cppr := wb_in.dat(31 downto 24);
			irq_eoi := '1';
		    elsif wb_in.sel = x"1"  then -- 1 byte
                        report "XICS XIRR write byte:" & to_hstring(wb_in.dat(7 downto 0));
			v.cppr := wb_in.dat(7 downto 0);
                    else
                        report "XICS XIRR UNSUPPORTED write ! sel=" & to_hstring(wb_in.sel);
		    end if;
		when MFRR =>
		    if wb_in.sel = x"f" then -- 4 bytes
                        report "XICS MFRR write word:" & to_hstring(wb_in.dat);
			v.mfrr_pending := '1';
			v.mfrr := wb_in.dat(31 downto 24);
		    elsif wb_in.sel = x"1" then -- 1 byte
                        report "XICS MFRR write byte:" & to_hstring(wb_in.dat(7 downto 0));
			v.mfrr_pending := '1';
			v.mfrr := wb_in.dat(7 downto 0);
                    else
                        report "XICS MFRR UNSUPPORTED write ! sel=" & to_hstring(wb_in.sel);
		    end if;
                when others =>                        
		end case;

	    else -- read
		v.wb_rd_data := (others => '0');

		case wb_in.adr(7 downto 0) is
                when XIRR_POLL =>
                    report "XICS XIRR_POLL read";
		    if wb_in.sel = x"f" then
			v.wb_rd_data(23 downto  0) := r.xisr;
			v.wb_rd_data(31 downto 24) := r.cppr;
		    elsif wb_in.sel = x"1" then
			v.wb_rd_data(7 downto  0) := r.cppr;
                    end if;
                when XIRR =>
                    report "XICS XIRR read";
		    if wb_in.sel = x"f" then
			v.wb_rd_data(23 downto 0) := r.xisr;
			v.wb_rd_data(31 downto 24) := r.cppr;
			xirr_accept_rd := '1';
		    elsif wb_in.sel = x"1" then
			v.wb_rd_data(7 downto 0) := r.cppr;
		    end if;
		when MFRR =>
		    report "XICS MFRR read";
		    if wb_in.sel = x"f" then -- 4 bytes
			v.wb_rd_data(31 downto 24) := r.mfrr;
		    elsif wb_in.sel = x"1" then -- 1 byte
			v.wb_rd_data( 7 downto  0) := r.mfrr;
		    end if;
                when others =>                        
		end case;
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
