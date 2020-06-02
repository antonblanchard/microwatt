library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
	MEMORY_SIZE   : positive := 16384;
	RAM_INIT_FILE : string   := "firmware.hex";
	RESET_LOW     : boolean  := true;
	CLK_FREQUENCY : positive := 100000000;
	USE_LITEDRAM  : boolean  := false;
	DISABLE_FLATTEN_CORE : boolean := false
	);
    port(
	ext_clk   : in  std_ulogic;
	ext_rst   : in  std_ulogic;

	-- UART0 signals:
	uart_main_tx : out std_ulogic;
	uart_main_rx : in  std_ulogic;

	-- LEDs
	led0	: out std_logic;
	led1	: out std_logic;

	-- DRAM wires
	ddram_a       : out std_logic_vector(14 downto 0);
	ddram_ba      : out std_logic_vector(2 downto 0);
	ddram_ras_n   : out std_logic;
	ddram_cas_n   : out std_logic;
	ddram_we_n    : out std_logic;
	ddram_dm      : out std_logic_vector(1 downto 0);
	ddram_dq      : inout std_logic_vector(15 downto 0);
	ddram_dqs_p   : inout std_logic_vector(1 downto 0);
	ddram_dqs_n   : inout std_logic_vector(1 downto 0);
	ddram_clk_p   : out std_logic;
	ddram_clk_n   : out std_logic;
	ddram_cke     : out std_logic;
	ddram_odt     : out std_logic;
	ddram_reset_n : out std_logic
	);
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- DRAM main data wishbone connection
    signal wb_dram_in       : wishbone_master_out;
    signal wb_dram_out      : wishbone_slave_out;

    -- DRAM control wishbone connection
    signal wb_dram_ctrl_in  : wb_io_master_out;
    signal wb_dram_ctrl_out : wb_io_slave_out;
    signal wb_dram_is_csr   : std_ulogic;
    signal wb_dram_is_init  : std_ulogic;

    -- Control/status
    signal core_alt_reset : std_ulogic;

begin

    -- Main SoC
    soc0: entity work.soc
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE,
	    RESET_LOW     => RESET_LOW,
	    SIM           => false,
	    CLK_FREQ      => CLK_FREQUENCY,
	    HAS_DRAM      => USE_LITEDRAM,
	    DRAM_SIZE     => 512 * 1024 * 1024,
	    DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE
	    )
	port map (
	    system_clk        => system_clk,
	    rst               => soc_rst,
	    uart0_txd         => uart_main_tx,
	    uart0_rxd         => uart_main_rx,
	    wb_dram_in        => wb_dram_in,
	    wb_dram_out       => wb_dram_out,
	    wb_dram_ctrl_in   => wb_dram_ctrl_in,
	    wb_dram_ctrl_out  => wb_dram_ctrl_out,
	    wb_dram_is_csr    => wb_dram_is_csr,
	    wb_dram_is_init   => wb_dram_is_init,
	    alt_reset         => core_alt_reset
	    );

    nodram: if not USE_LITEDRAM generate
        signal ddram_clk_dummy : std_ulogic;
    begin
	reset_controller: entity work.soc_reset
	    generic map(
		RESET_LOW => RESET_LOW
		)
	    port map(
		ext_clk => ext_clk,
		pll_clk => system_clk,
		pll_locked_in => system_clk_locked,
		ext_rst_in => ext_rst,
		pll_rst_out => pll_rst,
		rst_out => soc_rst
		);

	clkgen: entity work.clock_generator
	    generic map(
		CLK_INPUT_HZ => 100000000,
		CLK_OUTPUT_HZ => CLK_FREQUENCY
		)
	    port map(
		ext_clk => ext_clk,
		pll_rst_in => pll_rst,
		pll_clk_out => system_clk,
		pll_locked_out => system_clk_locked
		);

	led0 <= '1';
	led1 <= not soc_rst;
	core_alt_reset <= '0';

        -- Vivado barfs on those differential signals if left
        -- unconnected. So instanciate a diff. buffer and feed
        -- it a constant '0'.
        dummy_dram_clk: OBUFDS
            port map (
                O => ddram_clk_p,
                OB => ddram_clk_n,
                I => ddram_clk_dummy
                );
        ddram_clk_dummy <= '0';

    end generate;

    has_dram: if USE_LITEDRAM generate
	signal dram_init_done  : std_ulogic;
	signal dram_init_error : std_ulogic;
	signal dram_sys_rst    : std_ulogic;
    begin

	-- Eventually dig out the frequency from the generator
	-- but for now, assert it's 100Mhz
	assert CLK_FREQUENCY = 100000000;

	reset_controller: entity work.soc_reset
	    generic map(
		RESET_LOW => RESET_LOW,
                PLL_RESET_BITS => 18,
                SOC_RESET_BITS => 1
		)
	    port map(
		ext_clk => ext_clk,
		pll_clk => system_clk,
		pll_locked_in => '1',
		ext_rst_in => ext_rst,
		pll_rst_out => pll_rst,
		rst_out => open
		);

	dram: entity work.litedram_wrapper
	    generic map(
		DRAM_ABITS => 25,
		DRAM_ALINES => 15
		)
	    port map(
		clk_in		=> ext_clk,
		rst             => pll_rst,
		system_clk	=> system_clk,
		system_reset	=> soc_rst,
		pll_locked	=> system_clk_locked,

		wb_in		=> wb_dram_in,
		wb_out		=> wb_dram_out,
		wb_ctrl_in	=> wb_dram_ctrl_in,
		wb_ctrl_out	=> wb_dram_ctrl_out,
		wb_ctrl_is_csr  => wb_dram_is_csr,
		wb_ctrl_is_init => wb_dram_is_init,

		serial_tx	=> open,
		serial_rx	=> '0',

		init_done 	=> dram_init_done,
		init_error	=> dram_init_error,

		ddram_a		=> ddram_a,
		ddram_ba	=> ddram_ba,
		ddram_ras_n	=> ddram_ras_n,
		ddram_cas_n	=> ddram_cas_n,
		ddram_we_n	=> ddram_we_n,
		ddram_cs_n	=> open,
		ddram_dm	=> ddram_dm,
		ddram_dq	=> ddram_dq,
		ddram_dqs_p	=> ddram_dqs_p,
		ddram_dqs_n	=> ddram_dqs_n,
		ddram_clk_p	=> ddram_clk_p,
		ddram_clk_n	=> ddram_clk_n,
		ddram_cke	=> ddram_cke,
		ddram_odt	=> ddram_odt,
		ddram_reset_n	=> ddram_reset_n
		);

	led0 <= dram_init_done and not dram_init_error;
	led1 <= dram_init_error; -- Make it blink ?

    end generate;
end architecture behaviour;
