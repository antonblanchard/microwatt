library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;
use std.env.stop;

library work;
use work.common.all;
use work.wishbone_types.all;


-- Memory map. *** Keep include/microwatt_soc.h updated on changes ***
--
-- 0x00000000: Block RAM (MEMORY_SIZE) or DRAM depending on syscon
-- 0x40000000: DRAM (when present)
-- 0xc0000000: SYSCON
-- 0xc0002000: UART0
-- 0xc0004000: XICS ICP
-- 0xc0100000: LiteDRAM control (CSRs)
-- 0xf0000000: Block RAM (aliased & repeated)
-- 0xffff0000: DRAM init code (if any)

entity soc is
    generic (
	MEMORY_SIZE   : positive;
	RAM_INIT_FILE : string;
	RESET_LOW     : boolean;
	CLK_FREQ      : positive;
	SIM           : boolean;
	DISABLE_FLATTEN_CORE : boolean := false;
	HAS_DRAM      : boolean  := false;
	DRAM_SIZE     : integer := 0
	);
    port(
	rst          : in  std_ulogic;
	system_clk   : in  std_ulogic;

	-- DRAM controller signals
	wb_dram_in   : out wishbone_master_out;
	wb_dram_out  : in wishbone_slave_out;
	wb_dram_ctrl : out std_ulogic;
	wb_dram_init : out std_ulogic;

	-- UART0 signals:
	uart0_txd    : out std_ulogic;
	uart0_rxd    : in  std_ulogic;

	-- DRAM controller signals
	alt_reset    : in std_ulogic
	);
end entity soc;

architecture behaviour of soc is

    -- Wishbone master signals:
    signal wishbone_dcore_in  : wishbone_slave_out;
    signal wishbone_dcore_out : wishbone_master_out;
    signal wishbone_icore_in  : wishbone_slave_out;
    signal wishbone_icore_out : wishbone_master_out;
    signal wishbone_debug_in : wishbone_slave_out;
    signal wishbone_debug_out : wishbone_master_out;

    -- Arbiter array (ghdl doesnt' support assigning the array
    -- elements in the entity instantiation)
    constant NUM_WB_MASTERS : positive := 3;
    signal wb_masters_out : wishbone_master_out_vector(0 to NUM_WB_MASTERS-1);
    signal wb_masters_in  : wishbone_slave_out_vector(0 to NUM_WB_MASTERS-1);

    -- Wishbone master (output of arbiter):
    signal wb_master_in       : wishbone_slave_out;
    signal wb_master_out      : wishbone_master_out;

    -- Syscon signals
    signal dram_at_0     : std_ulogic;
    signal do_core_reset : std_ulogic;
    signal wb_syscon_in  : wishbone_master_out;
    signal wb_syscon_out : wishbone_slave_out;

    -- UART0 signals:
    signal wb_uart0_in   : wishbone_master_out;
    signal wb_uart0_out  : wishbone_slave_out;
    signal uart_dat8     : std_ulogic_vector(7 downto 0);

    -- XICS0 signals:
    signal wb_xics0_in   : wishbone_master_out;
    signal wb_xics0_out  : wishbone_slave_out;
    signal int_level_in  : std_ulogic_vector(15 downto 0);

    signal xics_to_execute1 : XicsToExecute1Type;

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

    -- Delayed/latched resets and alt_reset
    signal rst_core    : std_ulogic := '1';
    signal rst_uart    : std_ulogic := '1';
    signal rst_xics    : std_ulogic := '1';
    signal rst_bram    : std_ulogic := '1';
    signal rst_dtm     : std_ulogic := '1';
    signal rst_wbar    : std_ulogic := '1';
    signal rst_wbdb    : std_ulogic := '1';
    signal alt_reset_d : std_ulogic;

begin

    resets: process(system_clk)
    begin
        if rising_edge(system_clk) then
            rst_core    <= rst or do_core_reset;
            rst_uart    <= rst;
            rst_xics    <= rst;
            rst_bram    <= rst;
            rst_dtm     <= rst;
            rst_wbar    <= rst;
            rst_wbdb    <= rst;
            alt_reset_d <= alt_reset;
        end if;
    end process;

    -- Processor core
    processor: entity work.core
	generic map(
	    SIM => SIM,
	    DISABLE_FLATTEN => DISABLE_FLATTEN_CORE,
	    ALT_RESET_ADDRESS => (15 downto 0 => '0', others => '1')
	    )
	port map(
	    clk => system_clk,
	    rst => rst_core,
	    alt_reset => alt_reset_d,
	    wishbone_insn_in => wishbone_icore_in,
	    wishbone_insn_out => wishbone_icore_out,
	    wishbone_data_in => wishbone_dcore_in,
	    wishbone_data_out => wishbone_dcore_out,
	    dmi_addr => dmi_addr(3 downto 0),
	    dmi_dout => dmi_core_dout,
	    dmi_din => dmi_dout,
	    dmi_wr => dmi_wr,
	    dmi_ack => dmi_core_ack,
	    dmi_req => dmi_core_req,
	    xics_in => xics_to_execute1
	    );

    -- Wishbone bus master arbiter & mux
    wb_masters_out <= (0 => wishbone_dcore_out,
		       1 => wishbone_icore_out,
		       2 => wishbone_debug_out);
    wishbone_dcore_in <= wb_masters_in(0);
    wishbone_icore_in <= wb_masters_in(1);
    wishbone_debug_in <= wb_masters_in(2);
    wishbone_arbiter_0: entity work.wishbone_arbiter
	generic map(
	    NUM_MASTERS => NUM_WB_MASTERS
	    )
	port map(
	    clk => system_clk,
            rst => rst_wbar,
	    wb_masters_in => wb_masters_out,
	    wb_masters_out => wb_masters_in,
	    wb_slave_out => wb_master_out,
	    wb_slave_in => wb_master_in
	    );

    -- Wishbone slaves address decoder & mux
    slave_intercon: process(wb_master_out, wb_bram_out, wb_uart0_out, wb_dram_out, wb_syscon_out)
	-- Selected slave
	type slave_type is (SLAVE_SYSCON,
			    SLAVE_UART,
			    SLAVE_BRAM,
			    SLAVE_DRAM,
			    SLAVE_DRAM_INIT,
			    SLAVE_DRAM_CTRL,
			    SLAVE_ICP_0,
			    SLAVE_NONE);
	variable slave : slave_type;
    begin
	-- Simple address decoder.
	slave := SLAVE_NONE;
	-- Simple address decoder. Ignore top bits to save silicon for now
	slave := SLAVE_NONE;
	if    std_match(wb_master_out.adr, x"0-------") then
	    slave := SLAVE_DRAM when HAS_DRAM and dram_at_0 = '1' else
		     SLAVE_BRAM;
	elsif std_match(wb_master_out.adr, x"FFFF----") then
	    slave := SLAVE_DRAM_INIT;
	elsif std_match(wb_master_out.adr, x"F-------") then
	    slave := SLAVE_BRAM;
	elsif std_match(wb_master_out.adr, x"4-------") and HAS_DRAM then
	    slave := SLAVE_DRAM;
	elsif std_match(wb_master_out.adr, x"C0000---") then
	    slave := SLAVE_SYSCON;
	elsif std_match(wb_master_out.adr, x"C0002---") then
	    slave := SLAVE_UART;
	elsif std_match(wb_master_out.adr, x"C01-----") then
	    slave := SLAVE_DRAM_CTRL;
	elsif std_match(wb_master_out.adr, x"C0004---") then
	    slave := SLAVE_ICP_0;
	end if;

	-- Wishbone muxing. Defaults:
	wb_bram_in <= wb_master_out;
	wb_bram_in.cyc  <= '0';
	wb_uart0_in <= wb_master_out;
	wb_uart0_in.cyc <= '0';

	 -- Only give xics 8 bits of wb addr
	wb_xics0_in <= wb_master_out;
	wb_xics0_in.adr <= (others => '0');
	wb_xics0_in.adr(7 downto 0) <= wb_master_out.adr(7 downto 0);
	wb_xics0_in.cyc  <= '0';

	wb_dram_in <= wb_master_out;
	wb_dram_in.cyc <= '0';
	wb_dram_ctrl <= '0';
	wb_dram_init <= '0';
	wb_syscon_in <= wb_master_out;
	wb_syscon_in.cyc <= '0';
	case slave is
	when SLAVE_BRAM =>
	    wb_bram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_bram_out;
	when SLAVE_DRAM =>
	    wb_dram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_dram_out;
	when SLAVE_DRAM_INIT =>
	    wb_dram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_dram_out;
	    wb_dram_init <= '1';
	when SLAVE_DRAM_CTRL =>
	    wb_dram_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_dram_out;
	    wb_dram_ctrl <= '1';
	when SLAVE_SYSCON =>
	    wb_syscon_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_syscon_out;
	when SLAVE_UART =>
	    wb_uart0_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_uart0_out;
	when SLAVE_ICP_0 =>
	    wb_xics0_in.cyc <= wb_master_out.cyc;
	    wb_master_in <= wb_xics0_out;
	when others =>
	    wb_master_in.dat <= (others => '1');
	    wb_master_in.ack <= wb_master_out.stb and wb_master_out.cyc;
	    wb_master_in.stall <= '0';
	end case;
    end process slave_intercon;

    -- Syscon slave
    syscon0: entity work.syscon
	generic map(
	    HAS_UART => true,
	    HAS_DRAM => HAS_DRAM,
	    BRAM_SIZE => MEMORY_SIZE,
	    DRAM_SIZE => DRAM_SIZE,
	    CLK_FREQ => CLK_FREQ
	)
	port map(
	    clk => system_clk,
	    rst => rst,
	    wishbone_in => wb_syscon_in,
	    wishbone_out => wb_syscon_out,
	    dram_at_0 => dram_at_0,
	    core_reset => do_core_reset,
	    soc_reset => open -- XXX TODO
	    );

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
	    reset => rst_uart,
	    txd => uart0_txd,
	    rxd => uart0_rxd,
	    irq => int_level_in(0),
	    wb_adr_in => wb_uart0_in.adr(11 downto 0),
	    wb_dat_in => wb_uart0_in.dat(7 downto 0),
	    wb_dat_out => uart_dat8,
	    wb_cyc_in => wb_uart0_in.cyc,
	    wb_stb_in => wb_uart0_in.stb,
	    wb_we_in => wb_uart0_in.we,
	    wb_ack_out => wb_uart0_out.ack
	    );
    wb_uart0_out.dat <= x"00000000000000" & uart_dat8;
    wb_uart0_out.stall <= '0' when wb_uart0_in.cyc = '0' else not wb_uart0_out.ack;

    xics0: entity work.xics
	generic map(
	    LEVEL_NUM => 16
	    )
	port map(
	    clk => system_clk,
	    rst => rst_xics,
	    wb_in => wb_xics0_in,
	    wb_out => wb_xics0_out,
	    int_level_in => int_level_in,
	    e_out => xics_to_execute1
	    );

    -- BRAM Memory slave
    bram0: entity work.wishbone_bram_wrapper
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE
	    )
	port map(
	    clk => system_clk,
	    rst => rst_bram,
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
	    sys_reset	=> rst_dtm,
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
	port map(clk => system_clk,
                 rst => rst_wbdb,
		 dmi_addr => dmi_addr(1 downto 0),
		 dmi_dout => dmi_wb_dout,
		 dmi_din => dmi_dout,
		 dmi_wr => dmi_wr,
		 dmi_ack => dmi_wb_ack,
		 dmi_req => dmi_wb_req,
		 wb_in => wishbone_debug_in,
		 wb_out => wishbone_debug_out);


end architecture behaviour;
