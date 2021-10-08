library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
	MEMORY_SIZE   : positive := (384*1024);
	RAM_INIT_FILE : string   := "firmware.hex";
	RESET_LOW     : boolean  := true;
	CLK_INPUT     : positive := 100000000;
	CLK_FREQUENCY : positive := 100000000;
        HAS_FPU       : boolean  := true;
        HAS_BTC       : boolean  := false;
        HAS_SHORT_MULT: boolean  := false;
        ICACHE_NUM_LINES : natural := 64;
        LOG_LENGTH    : natural := 512;
	DISABLE_FLATTEN_CORE : boolean := false;
        UART_IS_16550 : boolean  := true;
        HAS_LPC       : boolean  := true
	);
    port(
	ext_clk   : in  std_ulogic;
	ext_rst   : in  std_ulogic;

	-- UART0 signals:
	uart0_txd : out std_ulogic;
	uart0_rxd : in  std_ulogic;

	-- LPC
	lpc_clock      : in std_ulogic;

        lpc_frame_n    : in std_ulogic;
        lpc_reset_n    : in std_ulogic;
        lpc_data_i     : in std_ulogic_vector(3 downto 0);
        lpc_irq_i      : in std_ulogic;

        lpc_data_oe    : out std_ulogic;
        lpc_data_o_reg : out std_ulogic_vector(3 downto 0);
        lpc_irq_o2     : out std_ulogic
	);
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- LPC
    signal lpc_data_i_reg    : std_ulogic_vector(3 downto 0);
    signal lpc_data_o        : std_ulogic_vector(3 downto 0);
    signal lpc_irq_o         : std_ulogic;
    signal lpc_irq_oe        : std_ulogic;
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
	    SIM           => false,
	    CLK_FREQ      => CLK_FREQUENCY,
            HAS_FPU       => HAS_FPU,
            HAS_BTC       => HAS_BTC,
            HAS_SHORT_MULT => HAS_SHORT_MULT,
	    ICACHE_NUM_LINES => ICACHE_NUM_LINES,
            LOG_LENGTH    => LOG_LENGTH,
	    DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            UART0_IS_16550     => UART_IS_16550,
	    HAS_LPC       => HAS_LPC
	    )
	port map (
	    system_clk        => system_clk,
	    rst               => soc_rst,
	    uart0_txd         => uart0_txd,
	    uart0_rxd         => uart0_rxd,

	    -- LPC
	    lpc_data_o        => lpc_data_o,
	    lpc_data_oe       => lpc_data_oe,
	    lpc_data_i        => lpc_data_i,
	    lpc_frame_n       => lpc_frame_n,
	    lpc_reset_n       => lpc_reset_n,
	    lpc_clock         => lpc_clock,
	    lpc_irq_o         => lpc_irq_o,
	    lpc_irq_oe        => lpc_irq_oe,
	    lpc_irq_i         => lpc_irq_i
	    );

    process(lpc_clock)
    begin
        if rising_edge(lpc_clock) then
            lpc_data_i_reg <= lpc_data_i;
            lpc_data_o_reg <= lpc_data_o when lpc_data_oe = '1' and ext_rst = '1' else "ZZZZ";
        end if;
    end process;

    lpc_irq_o2 <= lpc_irq_o  when lpc_irq_oe  = '1' and ext_rst = '1' else 'Z';

end architecture behaviour;
