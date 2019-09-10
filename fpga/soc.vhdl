library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library work;
use work.wishbone_types.all;


-- 0x00000000: Main memory (1 MB)
-- 0xc0002000: UART0 (for host communication)
entity soc is
    generic (
	MEMORY_SIZE   : positive;
	RAM_INIT_FILE : string;
	RESET_LOW     : boolean
	);
    port(
	rst          : in  std_ulogic;
	system_clk   : in  std_logic;

	-- UART0 signals:
	uart0_txd    : out std_logic;
	uart0_rxd    : in  std_logic
	);
end entity soc;

architecture behaviour of soc is

    -- Wishbone master signals:
    signal wishbone_dcore_in : wishbone_slave_out;
    signal wishbone_dcore_out : wishbone_master_out;
    signal wishbone_icore_in : wishbone_slave_out;
    signal wishbone_icore_out : wishbone_master_out;

    -- Wishbone master (output of arbiter):
    signal wb_master_in : wishbone_slave_out;
    signal wb_master_out : wishbone_master_out;

    -- UART0 signals:
    signal uart0_adr_in  : std_logic_vector(11 downto 0);
    signal uart0_dat_in  : std_logic_vector( 7 downto 0);
    signal uart0_dat_out : std_logic_vector( 7 downto 0);
    signal uart0_cyc_in  : std_logic;
    signal uart0_stb_in  : std_logic;
    signal uart0_we_in   : std_logic;
    signal uart0_ack_out : std_logic;

    -- Main memory signals:
    signal main_memory_adr_in  : std_logic_vector(positive(ceil(log2(real(MEMORY_SIZE))))-1 downto 0);
    signal main_memory_dat_in  : std_logic_vector(63 downto 0);
    signal main_memory_dat_out : std_logic_vector(63 downto 0);
    signal main_memory_cyc_in  : std_logic;
    signal main_memory_stb_in  : std_logic;
    signal main_memory_sel_in  : std_logic_vector(7 downto 0);
    signal main_memory_we_in   : std_logic;
    signal main_memory_ack_out : std_logic;

begin

    -- Processor core
    processor: entity work.core
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_insn_in => wishbone_icore_in,
	    wishbone_insn_out => wishbone_icore_out,
	    wishbone_data_in => wishbone_dcore_in,
	    wishbone_data_out => wishbone_dcore_out
	    );

    -- Wishbone bus master arbiter & mux
    wishbone_arbiter_0: entity work.wishbone_arbiter
	port map(
	    clk => system_clk,
	    rst => rst,
	    wb1_in => wishbone_dcore_out,
	    wb1_out => wishbone_dcore_in,
	    wb2_in => wishbone_icore_out,
	    wb2_out => wishbone_icore_in,
	    wb_out => wb_master_out,
	    wb_in => wb_master_in
	    );

    -- Wishbone slaves address decoder & mux
    slave_intercon: process(wb_master_out,
			    main_memory_ack_out, main_memory_dat_out,
			    uart0_ack_out, uart0_dat_out)
	-- Selected slave
	type slave_type is (SLAVE_UART,
			    SLAVE_MEMORY,
			    SLAVE_NONE);
	variable slave : slave_type;
    begin
	-- Simple address decoder
	slave := SLAVE_NONE;
	if wb_master_out.adr(63 downto 24) = x"0000000000" then
	    slave := SLAVE_MEMORY;
	elsif wb_master_out.adr(63 downto 24) = x"00000000c0" then
	    if wb_master_out.adr(15 downto 12) = x"2" then
		slave := SLAVE_UART;
	    end if;
	end if;

	-- Wishbone muxing. Defaults:
	main_memory_cyc_in <= '0';
	uart0_cyc_in <= '0';
	case slave is
	when SLAVE_MEMORY =>
	    main_memory_cyc_in <= wb_master_out.cyc;
	    wb_master_in.ack <= main_memory_ack_out;
	    wb_master_in.dat <= main_memory_dat_out;
	when SLAVE_UART =>
	    uart0_cyc_in <= wb_master_out.cyc;
	    wb_master_in.ack <= uart0_ack_out;
	    wb_master_in.dat <= x"00000000000000" & uart0_dat_out;
	when others =>
	    wb_master_in.dat <= (others => '1');
	    wb_master_in.ack <= wb_master_out.stb and wb_master_out.cyc;
	end case;
    end process slave_intercon;

    -- UART0 wishbone slave
    uart0: entity work.pp_soc_uart
	generic map(
	    FIFO_DEPTH => 32
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    txd => uart0_txd,
	    rxd => uart0_rxd,
	    wb_adr_in => uart0_adr_in,
	    wb_dat_in => uart0_dat_in,
	    wb_dat_out => uart0_dat_out,
	    wb_cyc_in => uart0_cyc_in,
	    wb_stb_in => uart0_stb_in,
	    wb_we_in => uart0_we_in,
	    wb_ack_out => uart0_ack_out
	    );
    -- Wire it up: XXX FIXME: Need a proper wb64->wb8 adapter that
    --                 converts SELs into low address bits and muxes
    --                 data accordingly (either that or rejects large
    --                 cycles).
    uart0_adr_in <= wb_master_out.adr(uart0_adr_in'range);
    uart0_dat_in <= wb_master_out.dat(7 downto 0);
    uart0_we_in  <= wb_master_out.we;
    uart0_stb_in <= wb_master_out.stb;

    -- BRAM Memory slave
    main_memory: entity work.pp_soc_memory
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    wb_adr_in => main_memory_adr_in,
	    wb_dat_in => main_memory_dat_in,
	    wb_dat_out => main_memory_dat_out,
	    wb_cyc_in => main_memory_cyc_in,
	    wb_stb_in => main_memory_stb_in,
	    wb_sel_in => main_memory_sel_in,
	    wb_we_in => main_memory_we_in,
	    wb_ack_out => main_memory_ack_out
	    );
    main_memory_adr_in <= wb_master_out.adr(main_memory_adr_in'range);
    main_memory_dat_in <= wb_master_out.dat;
    main_memory_we_in  <= wb_master_out.we;
    main_memory_sel_in <= wb_master_out.sel;
    main_memory_stb_in <= wb_master_out.stb;

end architecture behaviour;
