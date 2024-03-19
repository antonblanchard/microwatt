library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
        MEMORY_SIZE        : integer  := 16384;
        RAM_INIT_FILE      : string   := "firmware.hex";
        RESET_LOW          : boolean  := true;
        CLK_INPUT          : positive := 100000000;
        CLK_FREQUENCY      : positive := 50000000;
        HAS_FPU            : boolean  := false;
        HAS_BTC            : boolean  := false;
        USE_LITEDRAM       : boolean  := false;
        NO_BRAM            : boolean  := false;
        SCLK_STARTUPE2     : boolean := false;
        LOG_LENGTH         : natural := 0;
        UART_IS_16550      : boolean  := true;
        HAS_UART1          : boolean  := false;
        USE_LITESDCARD     : boolean := false;
        ICACHE_NUM_LINES   : natural := 64;
        NGPIO              : natural := 0
        );
    port(
        ext_clk   : in  std_ulogic;
        ext_rst_n : in  std_ulogic;
        gsrn      : in  std_ulogic;

        -- UART0 signals:
        uart0_txd : out std_ulogic;
        uart0_rxd : in  std_ulogic;

        -- LEDs
        led5_r_n  : out std_ulogic;
        led5_g_n  : out std_ulogic;
        led5_b_n  : out std_ulogic;
        led6_r_n  : out std_ulogic;
        led6_g_n  : out std_ulogic;
        led6_b_n  : out std_ulogic;
        led7_r_n  : out std_ulogic;
        led7_g_n  : out std_ulogic;
        led7_b_n  : out std_ulogic;
        led8_r_n  : out std_ulogic;
        led8_g_n  : out std_ulogic;
        led8_b_n  : out std_ulogic

        );
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- Fixup various memory sizes based on generics
    function get_bram_size return natural is
    begin
        if USE_LITEDRAM and NO_BRAM then
            return 0;
        else
            return MEMORY_SIZE;
        end if;
    end function;

    function get_payload_size return natural is
    begin
        if USE_LITEDRAM and NO_BRAM then
            return MEMORY_SIZE;
        else
            return 0;
        end if;
    end function;

    constant BRAM_SIZE    : natural := get_bram_size;
    constant PAYLOAD_SIZE : natural := get_payload_size;

begin

    -- Main SoC
    soc0: entity work.soc
        generic map(
            MEMORY_SIZE        => BRAM_SIZE,
            RAM_INIT_FILE      => RAM_INIT_FILE,
            SIM                => false,
            CLK_FREQ           => CLK_FREQUENCY,
            HAS_FPU            => HAS_FPU,
            HAS_BTC            => HAS_BTC,
            HAS_DRAM           => USE_LITEDRAM,
            DRAM_SIZE          => 512 * 1024 * 1024,
            DRAM_INIT_SIZE     => PAYLOAD_SIZE,
            HAS_SPI_FLASH      => false,
            LOG_LENGTH         => LOG_LENGTH,
            UART0_IS_16550     => UART_IS_16550,
            HAS_UART1          => HAS_UART1,
            HAS_SD_CARD        => USE_LITESDCARD,
            ICACHE_NUM_LINES   => ICACHE_NUM_LINES,
            NGPIO              => NGPIO
            )
        port map (
            -- System signals
            system_clk        => system_clk,
            rst               => soc_rst,

            -- UART signals
            uart0_txd         => uart0_txd,
            uart0_rxd         => uart0_rxd
            );

    nodram: if not USE_LITEDRAM generate
        signal div2 : std_ulogic := '0';
    begin
        reset_controller: entity work.soc_reset
            generic map(
                RESET_LOW => RESET_LOW
                )
            port map(
                ext_clk => ext_clk,
                pll_clk => system_clk,
                pll_locked_in => system_clk_locked,
                ext_rst_in => ext_rst_n and gsrn,
                pll_rst_out => pll_rst,
                rst_out => soc_rst
                );

        process(ext_clk)
        begin
            if rising_edge(ext_clk) then
                div2 <= not div2;
            end if;
        end process;
        
        system_clk <= div2;
        system_clk_locked <= '1';

    end generate;

    led5_r_n <= '0';
    led5_g_n <= '1';
    led5_b_n <= '1';
    led6_r_n <= '1';
    led6_g_n <= '0';
    led6_b_n <= '1';
    led7_r_n <= '1';
    led7_g_n <= '1';
    led7_b_n <= '0';
    led8_r_n <= '1';
    led8_g_n <= '1';
    led8_b_n <= '1';

end architecture behaviour;
