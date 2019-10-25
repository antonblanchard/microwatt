library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use std.env.stop;

library work;
use work.common.all;
use work.wishbone_types.all;


-- 0x00000000: Main memory (1 MB)
-- 0xc0002000: UART0 (for host communication)
entity soc is
    generic (
	MEMORY_SIZE   : positive;
	RAM_INIT_FILE : string;
	RESET_LOW     : boolean;
	SIM           : boolean
	);
    port(
	rst          : in  std_ulogic;
	system_clk   : in  std_ulogic;

	-- UART0 signals:
	uart0_txd    : out std_ulogic;
	uart0_rxd    : in  std_ulogic;

	-- Misc (to use for things like LEDs)
	core_terminated : out std_ulogic
	);
end entity soc;

architecture behaviour of soc is

    -- Wishbone master signals:
    signal wishbone_dcore_in : wishbone_slave_out;
    signal wishbone_dcore_out : wishbone_master_out;
    signal wishbone_icore_in : wishbone_slave_out;
    signal wishbone_icore_out : wishbone_master_out;
    signal wishbone_debug_in : wishbone_slave_out;
    signal wishbone_debug_out : wishbone_master_out;

    -- Wishbone master (output of arbiter):
    signal wb_master_in : wishbone_slave_out;
    signal wb_master_out : wishbone_master_out;

    -- UART0 signals:
    signal wb_uart0_in   : wishbone_master_out;
    signal wb_uart0_out  : wishbone_slave_out;
    signal uart_dat8     : std_ulogic_vector(7 downto 0);

    -- Main memory signals:
    signal wb_bram_in     : wishbone_master_out;
    signal wb_bram_out    : wishbone_slave_out;
    constant mem_adr_bits : positive := positive(ceil(log2(real(MEMORY_SIZE))));

    -- DMI debug bus signals
    signal dmi_addr	: std_ulogic_vector(7 downto 0);
    signal dmi_din	: std_ulogic_vector(63 downto 0);
    signal dmi_dout	: std_ulogic_vector(63 downto 0);
    signal dmi_req	: std_ulogic;
    signal dmi_wr	: std_ulogic;
    signal dmi_ack	: std_ulogic;

    -- Per slave DMI signals
    signal dmi_wb_dout  : std_ulogic_vector(63 downto 0);
    signal dmi_wb_req   : std_ulogic;
    signal dmi_wb_ack   : std_ulogic;
    signal dmi_core_dout  : std_ulogic_vector(63 downto 0);
    signal dmi_core_req   : std_ulogic;
    signal dmi_core_ack   : std_ulogic;
begin

    -- Processor core
    processor: entity work.core
	generic map(
	    SIM => SIM
	    )
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_insn_in => wishbone_icore_in,
	    wishbone_insn_out => wishbone_icore_out,
	    wishbone_data_in => wishbone_dcore_in,
	    wishbone_data_out => wishbone_dcore_out,
	    dmi_addr => dmi_addr(3 downto 0),
	    dmi_dout => dmi_core_dout,
	    dmi_din => dmi_dout,
	    dmi_wr => dmi_wr,
	    dmi_ack => dmi_core_ack,
	    dmi_req => dmi_core_req
	    );

    -- Wishbone bus master arbiter & mux
    wishbone_arbiter_0: entity work.wishbone_arbiter
	port map(
	    clk => system_clk, rst => rst,
	    wb1_in => wishbone_dcore_out, wb1_out => wishbone_dcore_in,
	    wb2_in => wishbone_icore_out, wb2_out => wishbone_icore_in,
	    wb3_in => wishbone_debug_out, wb3_out => wishbone_debug_in,
	    wb_out => wb_master_out, wb_in => wb_master_in
	    );

    -- Wishbone slaves address decoder & mux
    slave_intercon: process(wb_master_out, wb_bram_out, wb_uart0_out)
	-- Selected slave
	type slave_type is (SLAVE_UART_0,
			    SLAVE_MEMORY,
			    SLAVE_NONE);
	variable slave : slave_type;
    begin
	-- Simple address decoder.
	slave := SLAVE_NONE;
	if wb_master_out.adr(31 downto 24) = x"00" then
	    slave := SLAVE_MEMORY;
	elsif wb_master_out.adr(31 downto 24) = x"c0" then
	    if wb_master_out.adr(23 downto 12) = x"002" then
		slave := SLAVE_UART_0;
	    end if;
	end if;

	-- Wishbone muxing. Defaults:
	wb_bram_in <= wb_master_out;
	wb_bram_in.cyc  <= '0';
	wb_uart0_in <= wb_master_out;
	wb_uart0_in.cyc <= '0';
	case slave is
	when SLAVE_MEMORY =>
	    wb_bram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_bram_out;
	when SLAVE_UART_0 =>
	    wb_uart0_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_uart0_out;
	when others =>
	    wb_master_in.dat <= (others => '1');
	    wb_master_in.ack <= wb_master_out.stb and wb_master_out.cyc;
	end case;
    end process slave_intercon;

    -- Simulated memory and UART

    -- UART0 wishbone slave
    -- XXX FIXME: Need a proper wb64->wb8 adapter that
    --            converts SELs into low address bits and muxes
    --            data accordingly (either that or rejects large
    --            cycles).
    uart0: entity work.pp_soc_uart
	generic map(
	    FIFO_DEPTH => 32
	    )
	port map(
	    clk => system_clk,
	    reset => rst,
	    txd => uart0_txd,
	    rxd => uart0_rxd,
	    wb_adr_in => wb_uart0_in.adr(11 downto 0),
	    wb_dat_in => wb_uart0_in.dat(7 downto 0),
	    wb_dat_out => uart_dat8,
	    wb_cyc_in => wb_uart0_in.cyc,
	    wb_stb_in => wb_uart0_in.stb,
	    wb_we_in => wb_uart0_in.we,
	    wb_ack_out => wb_uart0_out.ack
	    );
    wb_uart0_out.dat <= x"00000000000000" & uart_dat8;

    -- BRAM Memory slave
    bram0: entity work.mw_soc_memory
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE
	    )
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_in => wb_bram_in,
	    wishbone_out => wb_bram_out
	    );

    -- DMI(debug bus) <-> JTAG bridge
    dtm: entity work.dmi_dtm
	generic map(
	    ABITS => 8,
	    DBITS => 64
	    )
	port map(
	    sys_clk	=> system_clk,
	    sys_reset	=> rst,
	    dmi_addr	=> dmi_addr,
	    dmi_din	=> dmi_din,
	    dmi_dout	=> dmi_dout,
	    dmi_req	=> dmi_req,
	    dmi_wr	=> dmi_wr,
	    dmi_ack	=> dmi_ack
	    );

    -- DMI interconnect
    dmi_intercon: process(dmi_addr, dmi_req,
			  dmi_wb_ack, dmi_wb_dout,
			  dmi_core_ack, dmi_core_dout)

	-- DMI address map (each address is a full 64-bit register)
	--
	-- Offset:   Size:    Slave:
	--  0         4       Wishbone
	-- 10        16       Core

	type slave_type is (SLAVE_WB,
			    SLAVE_CORE,
			    SLAVE_NONE);
	variable slave : slave_type;
    begin
	-- Simple address decoder
	slave := SLAVE_NONE;
	if std_match(dmi_addr, "000000--") then
	    slave := SLAVE_WB;
	elsif std_match(dmi_addr, "0001----") then
	    slave := SLAVE_CORE;
	end if;

	-- DMI muxing
	dmi_wb_req <= '0';
	dmi_core_req <= '0';
	case slave is
	when SLAVE_WB =>
	    dmi_wb_req <= dmi_req;
	    dmi_ack <= dmi_wb_ack;
	    dmi_din <= dmi_wb_dout;
	when SLAVE_CORE =>
	    dmi_core_req <= dmi_req;
	    dmi_ack <= dmi_core_ack;
	    dmi_din <= dmi_core_dout;
	when others =>
	    dmi_ack <= dmi_req;
	    dmi_din <= (others => '1');
	end case;

	-- SIM magic exit
	if SIM and dmi_req = '1' and dmi_addr = "11111111" and dmi_wr = '1' then
	    stop;
	end if;
    end process;

    -- Wishbone debug master (TODO: Add a DMI address decoder)
    wishbone_debug: entity work.wishbone_debug_master
	port map(clk => system_clk, rst => rst,
		 dmi_addr => dmi_addr(1 downto 0),
		 dmi_dout => dmi_wb_dout,
		 dmi_din => dmi_dout,
		 dmi_wr => dmi_wr,
		 dmi_ack => dmi_wb_ack,
		 dmi_req => dmi_wb_req,
		 wb_in => wishbone_debug_in,
		 wb_out => wishbone_debug_out);


end architecture behaviour;
