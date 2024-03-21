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
        SPI_FLASH_OFFSET   : integer := 4194304;
        SPI_FLASH_DEF_CKDV : natural := 0;
        SPI_FLASH_DEF_QUAD : boolean := true;
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
        led8_b_n  : out std_ulogic;

        -- SPI
        spi_flash_cs_n   : out std_ulogic;
        spi_flash_mosi   : inout std_ulogic;
        spi_flash_miso   : inout std_ulogic;
        spi_flash_wp_n   : inout std_ulogic;
        spi_flash_hold_n : inout std_ulogic;

        -- PMOD ports 0 - 7
        pmod0_0 : inout std_ulogic;
        pmod0_1 : inout std_ulogic;
        pmod0_2 : inout std_ulogic;
        pmod0_3 : inout std_ulogic;
        pmod0_4 : inout std_ulogic;
        pmod0_5 : inout std_ulogic;
        pmod0_6 : inout std_ulogic;
        pmod0_7 : inout std_ulogic;
        pmod1_0 : inout std_ulogic;
        pmod1_1 : inout std_ulogic;
        pmod1_2 : inout std_ulogic;
        pmod1_3 : inout std_ulogic;
        pmod1_4 : inout std_ulogic;
        pmod1_5 : inout std_ulogic;
        pmod1_6 : inout std_ulogic;
        pmod1_7 : inout std_ulogic;
        pmod2_0 : inout std_ulogic;
        pmod2_1 : inout std_ulogic;
        pmod2_2 : inout std_ulogic;
        pmod2_3 : inout std_ulogic;
        pmod2_4 : inout std_ulogic;
        pmod2_5 : inout std_ulogic;
        pmod2_6 : inout std_ulogic;
        pmod2_7 : inout std_ulogic;
        pmod3_0 : inout std_ulogic;
        pmod3_1 : inout std_ulogic;
        pmod3_2 : inout std_ulogic;
        pmod3_3 : inout std_ulogic;
        pmod3_4 : inout std_ulogic;
        pmod3_5 : inout std_ulogic;
        pmod3_6 : inout std_ulogic;
        pmod3_7 : inout std_ulogic;
        pmod4_0 : inout std_ulogic;     -- 0n
        pmod4_1 : inout std_ulogic;     -- 0p
        pmod4_2 : inout std_ulogic;     -- 1n
        pmod4_3 : inout std_ulogic;     -- 1p
        pmod4_4 : inout std_ulogic;     -- 2n
        pmod4_5 : inout std_ulogic;     -- 2p
        pmod4_6 : inout std_ulogic;     -- 3n
        pmod4_7 : inout std_ulogic;     -- 3p
        pmod5_0 : inout std_ulogic;
        pmod5_1 : inout std_ulogic;
        pmod5_2 : inout std_ulogic;
        pmod5_3 : inout std_ulogic;
        pmod5_4 : inout std_ulogic;
        pmod5_5 : inout std_ulogic;
        pmod5_6 : inout std_ulogic;
        pmod5_7 : inout std_ulogic;
        pmod6_0 : inout std_ulogic;
        pmod6_1 : inout std_ulogic;
        pmod6_2 : inout std_ulogic;
        pmod6_3 : inout std_ulogic;
        pmod6_4 : inout std_ulogic;
        pmod6_5 : inout std_ulogic;
        pmod6_6 : inout std_ulogic;
        pmod6_7 : inout std_ulogic;
        pmod7_0 : inout std_ulogic;
        pmod7_1 : inout std_ulogic;
        pmod7_2 : inout std_ulogic;
        pmod7_3 : inout std_ulogic;
        pmod7_4 : inout std_ulogic;
        pmod7_5 : inout std_ulogic;
        pmod7_6 : inout std_ulogic;
        pmod7_7 : inout std_ulogic

        );
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- SPI flash
    signal spi_sck     : std_ulogic;
    signal spi_sck_ts  : std_ulogic;
    signal spi_cs_n    : std_ulogic;
    signal spi_sdat_o  : std_ulogic_vector(3 downto 0);
    signal spi_sdat_oe : std_ulogic_vector(3 downto 0);
    signal spi_sdat_i  : std_ulogic_vector(3 downto 0);

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

    COMPONENT USRMCLK
        PORT(
            USRMCLKI : IN STD_ULOGIC;
            USRMCLKTS : IN STD_ULOGIC
        );
    END COMPONENT;
    attribute syn_noprune: boolean ;
    attribute syn_noprune of USRMCLK: component is true;

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
            HAS_SPI_FLASH      => true,
            SPI_FLASH_DLINES   => 4,
            SPI_FLASH_OFFSET   => SPI_FLASH_OFFSET,
            SPI_FLASH_DEF_CKDV => SPI_FLASH_DEF_CKDV,
            SPI_FLASH_DEF_QUAD => SPI_FLASH_DEF_QUAD,
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
            uart0_rxd         => uart0_rxd,

            -- SPI signals
            spi_flash_sck     => spi_sck,
            spi_flash_cs_n    => spi_cs_n,
            spi_flash_sdat_o  => spi_sdat_o,
            spi_flash_sdat_oe => spi_sdat_oe,
            spi_flash_sdat_i  => spi_sdat_i
            );

    -- SPI Flash
    --
    spi_flash_cs_n   <= spi_cs_n;
    spi_flash_mosi   <= spi_sdat_o(0) when spi_sdat_oe(0) = '1' else 'Z';
    spi_flash_miso   <= spi_sdat_o(1) when spi_sdat_oe(1) = '1' else 'Z';
    spi_flash_wp_n   <= spi_sdat_o(2) when spi_sdat_oe(2) = '1' else 'Z';
    spi_flash_hold_n <= spi_sdat_o(3) when spi_sdat_oe(3) = '1' else 'Z';
    spi_sdat_i(0)    <= spi_flash_mosi;
    spi_sdat_i(1)    <= spi_flash_miso;
    spi_sdat_i(2)    <= spi_flash_wp_n;
    spi_sdat_i(3)    <= spi_flash_hold_n;
    spi_sck_ts       <= '0';

    uclk: USRMCLK port map (
        USRMCLKI => spi_sck,
        USRMCLKTS => spi_sck_ts
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
