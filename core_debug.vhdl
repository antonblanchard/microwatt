library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity core_debug is
    port (
        clk          : in std_logic;
        rst          : in std_logic;

	dmi_addr	: in std_ulogic_vector(3 downto 0);
	dmi_din	        : in std_ulogic_vector(63 downto 0);
	dmi_dout	: out std_ulogic_vector(63 downto 0);
	dmi_req	        : in std_ulogic;
	dmi_wr		: in std_ulogic;
	dmi_ack	        : out std_ulogic;

	-- Debug actions
	core_stop       : out std_ulogic;
	core_rst        : out std_ulogic;
	icache_rst      : out std_ulogic;

	-- Core status inputs
	terminate       : in std_ulogic;
	core_stopped    : in std_ulogic;
	nia             : in std_ulogic_vector(63 downto 0);
        msr             : in std_ulogic_vector(63 downto 0);

        -- GSPR register read port
        dbg_gpr_req     : out std_ulogic;
        dbg_gpr_ack     : in std_ulogic;
        dbg_gpr_addr    : out gspr_index_t;
        dbg_gpr_data    : in std_ulogic_vector(63 downto 0);

	-- Misc
	terminated_out  : out std_ulogic
        );
end core_debug;

architecture behave of core_debug is
        -- DMI needs fixing... make a one clock pulse
    signal dmi_req_1: std_ulogic;

    -- CTRL register (direct actions, write 1 to act, read back 0)
    -- bit     0 : Core stop
    -- bit     1 : Core reset (doesn't clear stop)
    -- bit     2 : Icache reset
    -- bit     3 : Single step
    -- bit     4 : Core start
    constant DBG_CORE_CTRL	   : std_ulogic_vector(3 downto 0) := "0000";
    constant DBG_CORE_CTRL_STOP    : integer := 0;
    constant DBG_CORE_CTRL_RESET   : integer := 1;
    constant DBG_CORE_CTRL_ICRESET : integer := 2;
    constant DBG_CORE_CTRL_STEP    : integer := 3;
    constant DBG_CORE_CTRL_START   : integer := 4;

    -- STAT register (read only)
    -- bit    0 : Core stopping (wait til bit 1 set)
    -- bit    1 : Core stopped
    -- bit    2 : Core terminated (clears with start or reset)
    constant DBG_CORE_STAT	   : std_ulogic_vector(3 downto 0) := "0001";
    constant DBG_CORE_STAT_STOPPING  : integer := 0;
    constant DBG_CORE_STAT_STOPPED   : integer := 1;
    constant DBG_CORE_STAT_TERM      : integer := 2;

    -- NIA register (read only for now)
    constant DBG_CORE_NIA	     : std_ulogic_vector(3 downto 0) := "0010";

    -- MSR (read only)
    constant DBG_CORE_MSR            : std_ulogic_vector(3 downto 0) := "0011";

    -- GSPR register index
    constant DBG_CORE_GSPR_INDEX     : std_ulogic_vector(3 downto 0) := "0100";

    -- GSPR register data
    constant DBG_CORE_GSPR_DATA      : std_ulogic_vector(3 downto 0) := "0101";

    -- Some internal wires
    signal stat_reg : std_ulogic_vector(63 downto 0);

    -- Some internal latches
    signal stopping     : std_ulogic;
    signal do_step      : std_ulogic;
    signal do_reset     : std_ulogic;
    signal do_icreset   : std_ulogic;
    signal terminated   : std_ulogic;
    signal do_gspr_rd   : std_ulogic;
    signal gspr_index   : gspr_index_t;

begin
       -- Single cycle register accesses on DMI except for GSPR data
    dmi_ack <= dmi_req when dmi_addr /= DBG_CORE_GSPR_DATA
               else dbg_gpr_ack;
    dbg_gpr_req <= dmi_req when dmi_addr = DBG_CORE_GSPR_DATA
                   else '0';

    -- Status register read composition
    stat_reg <= (2 => terminated,
		 1 => core_stopped,
		 0 => stopping,
		 others => '0');

    -- DMI read data mux
    with dmi_addr select dmi_dout <=
	stat_reg        when DBG_CORE_STAT,
	nia             when DBG_CORE_NIA,
        msr             when DBG_CORE_MSR,
        dbg_gpr_data    when DBG_CORE_GSPR_DATA,
	(others => '0') when others;

    -- DMI writes
    reg_write: process(clk)
    begin
	if rising_edge(clk) then
	    -- Reset the 1-cycle "do" signals
	    do_step <= '0';
	    do_reset <= '0';
	    do_icreset <= '0';

	    if (rst) then
		stopping <= '0';
		terminated <= '0';
	    else
		-- Edge detect on dmi_req for 1-shot pulses
		dmi_req_1 <= dmi_req;
		if dmi_req = '1' and dmi_req_1 = '0' then
		    if dmi_wr = '1' then
			report("DMI write to " & to_hstring(dmi_addr));

			-- Control register actions
			if dmi_addr = DBG_CORE_CTRL then
			    if dmi_din(DBG_CORE_CTRL_RESET) = '1' then
				do_reset <= '1';
				terminated <= '0';
			    end if;
			    if dmi_din(DBG_CORE_CTRL_STOP) = '1' then
				stopping <= '1';
			    end if;
			    if dmi_din(DBG_CORE_CTRL_STEP) = '1' then
				do_step <= '1';
				terminated <= '0';
			    end if;
			    if dmi_din(DBG_CORE_CTRL_ICRESET) = '1' then
				do_icreset <= '1';
			    end if;
			    if dmi_din(DBG_CORE_CTRL_START) = '1' then
				stopping <= '0';
				terminated <= '0';
			    end if;
                        elsif dmi_addr = DBG_CORE_GSPR_INDEX then
                            gspr_index <= dmi_din(gspr_index_t'left downto 0);
			end if;
		    else
			report("DMI read from " & to_string(dmi_addr));
		    end if;
		end if;

		-- Set core stop on terminate. We'll be stopping some time *after*
		-- the offending instruction, at least until we can do back flushes
		-- that preserve NIA which we can't just yet.
		if terminate = '1' then
		    stopping <= '1';
		    terminated <= '1';
		end if;
	    end if;
	end if;
    end process;

    dbg_gpr_addr <= gspr_index;

    -- Core control signals generated by the debug module
    core_stop <= stopping and not do_step;
    core_rst <= do_reset;
    icache_rst <= do_icreset;
    terminated_out <= terminated;
end behave;

