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

	-- DRAM UART signals (PMOD)
	uart_pmod_tx    : out std_ulogic;
	uart_pmod_rx    : in std_ulogic;
	uart_pmod_cts_n : in std_ulogic;
	uart_pmod_rts_n : out std_ulogic;

	-- LEDs
	led0_b	: out std_ulogic;
	led0_g	: out std_ulogic;
	led0_r	: out std_ulogic;

	-- DRAM wires
	ddram_a       : out std_ulogic_vector(13 downto 0);
	ddram_ba      : out std_ulogic_vector(2 downto 0);
	ddram_ras_n   : out std_ulogic;
	ddram_cas_n   : out std_ulogic;
	ddram_we_n    : out std_ulogic;
	ddram_cs_n    : out std_ulogic;
	ddram_dm      : out std_ulogic_vector(1 downto 0);
	ddram_dq      : inout std_ulogic_vector(15 downto 0);
	ddram_dqs_p   : inout std_ulogic_vector(1 downto 0);
	ddram_dqs_n   : inout std_ulogic_vector(1 downto 0);
	ddram_clk_p   : out std_ulogic;
	ddram_clk_n   : out std_ulogic;
	ddram_cke     : out std_ulogic;
	ddram_odt     : out std_ulogic;
	ddram_reset_n : out std_ulogic
	);
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- DRAM wishbone connection
    signal wb_dram_in   : wishbone_master_out;
    signal wb_dram_out  : wishbone_slave_out;
    signal wb_dram_ctrl : std_ulogic;
    signal wb_dram_init : std_ulogic;

    -- Control/status
    signal core_alt_reset : std_ulogic;

    -- Status LED
    signal led0_b_pwm : std_ulogic;
    signal led0_r_pwm : std_ulogic;
    signal led0_g_pwm : std_ulogic;

    -- Dumb PWM for the LEDs, those RGB LEDs are too bright otherwise
    signal pwm_counter  : std_ulogic_vector(8 downto 0);
begin

    uart_pmod_rts_n <= '0';

    -- Main SoC
    soc0: entity work.soc
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE,
	    RESET_LOW     => RESET_LOW,
	    SIM           => false,
	    CLK_FREQ      => CLK_FREQUENCY,
	    HAS_DRAM      => USE_LITEDRAM,
	    DRAM_SIZE     => 256 * 1024 * 1024,
	    DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE
	    )
	port map (
	    system_clk        => system_clk,
	    rst               => soc_rst,
	    uart0_txd         => uart_main_tx,
	    uart0_rxd         => uart_main_rx,
	    wb_dram_in        => wb_dram_in,
	    wb_dram_out       => wb_dram_out,
	    wb_dram_ctrl      => wb_dram_ctrl,
	    wb_dram_init      => wb_dram_init,
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

	led0_b_pwm <= '1';
	led0_r_pwm <= '1';
	led0_g_pwm <= '0';
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
	signal soc_rst_0       : std_ulogic;
	signal soc_rst_1       : std_ulogic;
    begin

	-- Eventually dig out the frequency from the generator
	-- but for now, assert it's 100Mhz
	assert CLK_FREQUENCY = 100000000;

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
		rst_out => soc_rst_0
		);

	dram: entity work.litedram_wrapper
	    generic map(
		DRAM_ABITS => 24,
		DRAM_ALINES => 14
		)
	    port map(
		clk_in		=> ext_clk,
		rst             => pll_rst,
		system_clk	=> system_clk,
		system_reset	=> soc_rst_1,
		core_alt_reset	=> core_alt_reset,
		pll_locked	=> system_clk_locked,

		wb_in		=> wb_dram_in,
		wb_out		=> wb_dram_out,
		wb_is_ctrl      => wb_dram_ctrl,
		wb_is_init      => wb_dram_init,

		serial_tx	=> uart_pmod_tx,
		serial_rx	=> uart_pmod_rx,

		init_done 	=> dram_init_done,
		init_error	=> dram_init_error,

		ddram_a		=> ddram_a,
		ddram_ba	=> ddram_ba,
		ddram_ras_n	=> ddram_ras_n,
		ddram_cas_n	=> ddram_cas_n,
		ddram_we_n	=> ddram_we_n,
		ddram_cs_n	=> ddram_cs_n,
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

	led0_b_pwm <= not dram_init_done;
	led0_r_pwm <= dram_init_error;
	led0_g_pwm <= dram_init_done and not dram_init_error;
	soc_rst <= soc_rst_0 or soc_rst_1;

    end generate;

    leds_pwm : process(system_clk)
    begin
	if rising_edge(system_clk) then
	    pwm_counter <= std_ulogic_vector(signed(pwm_counter) + 1);
	    if pwm_counter(8 downto 4) = "00000" then
		led0_b <= led0_b_pwm;
		led0_r <= led0_r_pwm;
		led0_g <= led0_g_pwm;
	    else
		led0_b <= '0';
		led0_r <= '0';
		led0_g <= '0';
	    end if;
	end if;
    end process;

end architecture behaviour;
