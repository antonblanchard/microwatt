library ieee;
use ieee.std_logic_1164.all;

entity arty_a7 is
    generic (
	MEMORY_SIZE   : positive := 524288;
	RAM_INIT_FILE : string   := "firmware.hex";
	RESET_LOW     : boolean  := true;
	CLK_INPUT     : positive := 100000000;
	CLK_FREQUENCY : positive := 100000000
	);
    port(
	ext_clk   : in  std_ulogic;
	ext_rst   : in  std_ulogic;

	-- UART0 signals:
	uart0_txd : out std_ulogic;
	uart0_rxd : in  std_ulogic;
	
	-- GPIO signals:
	gpio0 : inout std_logic_vector(55 downto 0);
	gpio1 : inout std_logic_vector(36 downto 0)
	);
end entity arty_a7;

architecture behaviour of arty_a7 is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk : std_ulogic;
    signal system_clk_locked : std_ulogic;

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
	    CLK_INPUT_HZ => CLK_INPUT,
	    CLK_OUTPUT_HZ => CLK_FREQUENCY
	    )
	port map(
	    ext_clk => ext_clk,
	    pll_rst_in => pll_rst,
	    pll_clk_out => system_clk,
	    pll_locked_out => system_clk_locked
	    );

    -- Main SoC
    soc0: entity work.soc
	generic map(
	    MEMORY_SIZE   => MEMORY_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE,
	    RESET_LOW     => RESET_LOW,
	    SIM           => false,
	    GPIO0_PINS    => 56,
	    GPIO1_PINS    => 37
	    )
	port map (
	    system_clk        => system_clk,
	    rst               => soc_rst,
	    uart0_txd         => uart0_txd,
	    uart0_rxd         => uart0_rxd,
	    gpio0             => gpio0,
	    gpio1             => gpio1
	    );

end architecture behaviour;
