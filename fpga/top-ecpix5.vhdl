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
        HAS_FPU            : boolean  := true;
        HAS_BTC            : boolean  := true;
        USE_LITEDRAM       : boolean  := true;
        NO_BRAM            : boolean  := true;
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
        pmod7_7 : inout std_ulogic;

        -- DRAM wires
        ddram_a       : out std_ulogic_vector(14 downto 0);
        ddram_ba      : out std_ulogic_vector(2 downto 0);
        ddram_ras_n   : out std_ulogic;
        ddram_cas_n   : out std_ulogic;
        ddram_we_n    : out std_ulogic;
        ddram_dm      : out std_ulogic_vector(1 downto 0);
        ddram_dq      : inout std_ulogic_vector(15 downto 0);
        ddram_dqs_p   : inout std_ulogic_vector(1 downto 0);
        ddram_clk_p   : out std_ulogic_vector(0 downto 0);
        -- only the positive differential pin is instantiated
        --ddram_dqs_n   : inout std_ulogic_vector(1 downto 0);
        --ddram_clk_n   : out std_ulogic_vector(0 downto 0);
        ddram_cke     : out std_ulogic;
        ddram_odt     : out std_ulogic
        );
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;

    -- External IOs from the SoC
    signal wb_ext_io_in        : wb_io_master_out;
    signal wb_ext_io_out       : wb_io_slave_out;
    signal wb_ext_is_dram_csr  : std_ulogic;
    signal wb_ext_is_dram_init : std_ulogic;

    -- DRAM main data wishbone connection
    signal wb_dram_in          : wishbone_master_out;
    signal wb_dram_out         : wishbone_slave_out;

    -- DRAM control wishbone connection
    signal wb_dram_ctrl_out    : wb_io_slave_out := wb_io_slave_out_init;

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
            spi_flash_sdat_i  => spi_sdat_i,

            -- DRAM wishbone
            wb_dram_in           => wb_dram_in,
            wb_dram_out          => wb_dram_out,

            -- IO wishbone
            wb_ext_io_in         => wb_ext_io_in,
            wb_ext_io_out        => wb_ext_io_out,
            wb_ext_is_dram_csr   => wb_ext_is_dram_csr,
            wb_ext_is_dram_init  => wb_ext_is_dram_init
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

        led8_r_n <= '1';
        led8_g_n <= '1';
        led8_b_n <= '1';

    end generate;

    has_dram: if USE_LITEDRAM generate
        signal dram_init_done  : std_ulogic;
        signal dram_init_error : std_ulogic;
        signal dram_sys_rst    : std_ulogic;
    begin

        -- Eventually dig out the frequency from
        -- litesdram generate.py sys_clk_freq
        -- but for now, assert it's 50Mhz for ECPIX-5
        assert CLK_FREQUENCY = 50000000;

        reset_controller: entity work.soc_reset
            generic map(
                RESET_LOW => RESET_LOW,
                PLL_RESET_BITS => 18,
                SOC_RESET_BITS => 20
                )
            port map(
                ext_clk => ext_clk,
                pll_clk => system_clk,
                pll_locked_in => system_clk_locked and not dram_sys_rst,
                ext_rst_in => ext_rst_n and gsrn,
                pll_rst_out => pll_rst,
                rst_out => soc_rst
                );

        -- Generate SoC reset
        soc_rst_gen: process(system_clk)
        begin
            if ext_rst_n = '0' then
                soc_rst <= '1';
            elsif rising_edge(system_clk) then
                soc_rst <= dram_sys_rst or not system_clk_locked;
            end if;
        end process;

        dram: entity work.litedram_wrapper
            generic map(
                DRAM_ABITS => 25,
                DRAM_ALINES => 15,
                DRAM_DLINES => 16,
                DRAM_CKLINES => 1,
                DRAM_PORT_WIDTH => 128,
                PAYLOAD_FILE => RAM_INIT_FILE,
                PAYLOAD_SIZE => PAYLOAD_SIZE
                )
            port map(
                clk_in          => ext_clk,
                rst             => pll_rst,
                system_clk      => system_clk,
                system_reset    => dram_sys_rst,
                pll_locked      => system_clk_locked,

                wb_in           => wb_dram_in,
                wb_out          => wb_dram_out,
                wb_ctrl_in      => wb_ext_io_in,
                wb_ctrl_out     => wb_dram_ctrl_out,
                wb_ctrl_is_csr  => wb_ext_is_dram_csr,
                wb_ctrl_is_init => wb_ext_is_dram_init,

                init_done       => dram_init_done,
                init_error      => dram_init_error,

                ddram_a         => ddram_a,
                ddram_ba        => ddram_ba,
                ddram_ras_n     => ddram_ras_n,
                ddram_cas_n     => ddram_cas_n,
                ddram_we_n      => ddram_we_n,
                ddram_dm        => ddram_dm,
                ddram_dq        => ddram_dq,
                ddram_dqs_p     => ddram_dqs_p,
                ddram_clk_p     => ddram_clk_p,
                -- only the positive differential pin is instantiated
                --ddram_dqs_n     => ddram_dqs_n,
                --ddram_clk_n     => ddram_clk_n,
                ddram_cke       => ddram_cke,
                ddram_odt       => ddram_odt
                );

        -- active-low outputs to the LED
        led8_b_n <= dram_init_done;
        led8_r_n <= not dram_init_error;
        led8_g_n <= not (dram_init_done and not dram_init_error);
    end generate;

    -- Mux WB response on the IO bus
    wb_ext_io_out <= wb_dram_ctrl_out;

    led5_r_n <= '1';
    led5_g_n <= '1';
    led5_b_n <= '1';
    led6_r_n <= '1';
    led6_g_n <= '1';
    led6_b_n <= '1';
    led7_r_n <= not soc_rst;
    led7_g_n <= not system_clk_locked;
    led7_b_n <= '1';

end architecture behaviour;
