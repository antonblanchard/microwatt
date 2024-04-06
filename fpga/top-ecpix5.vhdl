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
        USE_LITEETH        : boolean := true;
        USE_LITESDCARD     : boolean := true;
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

        -- Ethernet
        rgmii_clocks_rx  : in    std_ulogic;
        rgmii_clocks_tx  : out   std_ulogic;
        rgmii_rst_n      : out   std_ulogic;
        rgmii_int_n      : in    std_ulogic;
        rgmii_mdc        : out   std_ulogic;
        rgmii_mdio       : inout std_ulogic;
        rgmii_rx_ctl     : in    std_ulogic;
        rgmii_rx_data    : in    std_ulogic_vector(3 downto 0);
        rgmii_tx_ctl     : out   std_ulogic;
        rgmii_tx_data    : out   std_ulogic_vector(3 downto 0);

        -- SD card wires
        sdcard_data      : inout std_ulogic_vector(3 downto 0);
        sdcard_cmd       : inout std_ulogic;
        sdcard_clk       : out   std_ulogic;
        sdcard_cd        : in    std_ulogic;
        sdcard_cmd_dir   : out   std_ulogic;
        sdcard_dat0_dir  : out   std_ulogic;
        sdcard_dat13_dir : out   std_ulogic;
        sdcard_vsel      : out   std_ulogic;

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
    signal wb_ext_is_eth       : std_ulogic;
    signal wb_ext_is_sdcard    : std_ulogic;

    -- DRAM main data wishbone connection
    signal wb_dram_in          : wishbone_master_out;
    signal wb_dram_out         : wishbone_slave_out;

    -- DRAM control wishbone connection
    signal wb_dram_ctrl_out    : wb_io_slave_out := wb_io_slave_out_init;

    -- LiteEth connection
    signal ext_irq_eth         : std_ulogic;
    signal wb_eth_out          : wb_io_slave_out := wb_io_slave_out_init;

    -- LiteSDCard connection
    signal ext_irq_sdcard      : std_ulogic := '0';
    signal wb_sdcard_out       : wb_io_slave_out := wb_io_slave_out_init;
    signal wb_sddma_out        : wb_io_master_out := wb_io_master_out_init;
    signal wb_sddma_in         : wb_io_slave_out;
    signal wb_sddma_nr         : wb_io_master_out;
    signal wb_sddma_ir         : wb_io_slave_out;
    -- for conversion from non-pipelined wishbone to pipelined
    signal wb_sddma_stb_sent   : std_ulogic;

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
            HAS_LITEETH        => USE_LITEETH,
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

            -- External interrupts
            ext_irq_eth       => ext_irq_eth,
            ext_irq_sdcard    => ext_irq_sdcard,

            -- DRAM wishbone
            wb_dram_in           => wb_dram_in,
            wb_dram_out          => wb_dram_out,

            -- IO wishbone
            wb_ext_io_in         => wb_ext_io_in,
            wb_ext_io_out        => wb_ext_io_out,
            wb_ext_is_dram_csr   => wb_ext_is_dram_csr,
            wb_ext_is_dram_init  => wb_ext_is_dram_init,
            wb_ext_is_eth       => wb_ext_is_eth,
            wb_ext_is_sdcard     => wb_ext_is_sdcard,

            -- DMA wishbone
            wishbone_dma_in      => wb_sddma_in,
            wishbone_dma_out     => wb_sddma_out
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

    has_liteeth : if USE_LITEETH generate

        component liteeth_core port (
            sys_clock           : in std_ulogic;
            sys_reset           : in std_ulogic;
            rgmii_clocks_tx     : out std_ulogic;
            rgmii_clocks_rx     : in std_ulogic;
            rgmii_rst_n         : out std_ulogic;
            rgmii_int_n         : in std_ulogic;
            rgmii_mdio          : inout std_ulogic;
            rgmii_mdc           : out std_ulogic;
            rgmii_rx_ctl        : in std_ulogic;
            rgmii_rx_data       : in std_ulogic_vector(3 downto 0);
            rgmii_tx_ctl        : out std_ulogic;
            rgmii_tx_data       : out std_ulogic_vector(3 downto 0);
            wishbone_adr        : in std_ulogic_vector(29 downto 0);
            wishbone_dat_w      : in std_ulogic_vector(31 downto 0);
            wishbone_dat_r      : out std_ulogic_vector(31 downto 0);
            wishbone_sel        : in std_ulogic_vector(3 downto 0);
            wishbone_cyc        : in std_ulogic;
            wishbone_stb        : in std_ulogic;
            wishbone_ack        : out std_ulogic;
            wishbone_we         : in std_ulogic;
            wishbone_cti        : in std_ulogic_vector(2 downto 0);
            wishbone_bte        : in std_ulogic_vector(1 downto 0);
            wishbone_err        : out std_ulogic;
            interrupt           : out std_ulogic
            );
        end component;

        signal wb_eth_cyc     : std_ulogic;
        signal wb_eth_adr     : std_ulogic_vector(29 downto 0);

    begin
        liteeth :  liteeth_core
            port map(
                sys_clock           => system_clk,
                sys_reset           => soc_rst,
                rgmii_clocks_tx     => rgmii_clocks_tx,
                rgmii_clocks_rx     => rgmii_clocks_rx,
                rgmii_rst_n         => rgmii_rst_n,
                rgmii_int_n         => rgmii_int_n,
                rgmii_mdio          => rgmii_mdio,
                rgmii_mdc           => rgmii_mdc,
                rgmii_rx_ctl        => rgmii_rx_ctl,
                rgmii_rx_data       => rgmii_rx_data,
                rgmii_tx_ctl        => rgmii_tx_ctl,
                rgmii_tx_data       => rgmii_tx_data,
                wishbone_adr        => wb_eth_adr,
                wishbone_dat_w      => wb_ext_io_in.dat,
                wishbone_dat_r      => wb_eth_out.dat,
                wishbone_sel        => wb_ext_io_in.sel,
                wishbone_cyc        => wb_eth_cyc,
                wishbone_stb        => wb_ext_io_in.stb,
                wishbone_ack        => wb_eth_out.ack,
                wishbone_we         => wb_ext_io_in.we,
                wishbone_cti        => "000",
                wishbone_bte        => "00",
                wishbone_err        => open,
                interrupt           => ext_irq_eth
                );

        -- Gate cyc with "chip select" from soc
        wb_eth_cyc <= wb_ext_io_in.cyc and wb_ext_is_eth;

        -- Remove top address bits as liteeth decoder doesn't know about them
        wb_eth_adr <= x"000" & "000" & wb_ext_io_in.adr(14 downto 0);

        -- LiteETH isn't pipelined
        wb_eth_out.stall <= not wb_eth_out.ack;

    end generate;

    no_liteeth : if not USE_LITEETH generate
        ext_irq_eth    <= '0';
    end generate;

    -- SD card
    -- The ECPIX-5 has a buffer/level translator chip in order to be able to
    -- support 1.8V signalling to the SD card as well as 3V signalling.
    -- Litesdcard doesn't currently support voltage selection, or the higher
    -- data transfer rates that require the lower voltage.
    has_sdcard : if USE_LITESDCARD generate
        component litesdcard_core port (
            clk              : in    std_ulogic;
            rst              : in    std_ulogic;
            irq              : out   std_ulogic;
            -- wishbone for accessing control registers
            wb_ctrl_adr      : in    std_ulogic_vector(29 downto 0);
            wb_ctrl_dat_w    : in    std_ulogic_vector(31 downto 0);
            wb_ctrl_dat_r    : out   std_ulogic_vector(31 downto 0);
            wb_ctrl_sel      : in    std_ulogic_vector(3 downto 0);
            wb_ctrl_cyc      : in    std_ulogic;
            wb_ctrl_stb      : in    std_ulogic;
            wb_ctrl_ack      : out   std_ulogic;
            wb_ctrl_we       : in    std_ulogic;
            wb_ctrl_cti      : in    std_ulogic_vector(2 downto 0);
            wb_ctrl_bte      : in    std_ulogic_vector(1 downto 0);
            wb_ctrl_err      : out   std_ulogic;
            -- wishbone for SD card core to use for DMA
            wb_dma_adr       : out   std_ulogic_vector(29 downto 0);
            wb_dma_dat_w     : out   std_ulogic_vector(31 downto 0);
            wb_dma_dat_r     : in    std_ulogic_vector(31 downto 0);
            wb_dma_sel       : out   std_ulogic_vector(3 downto 0);
            wb_dma_cyc       : out   std_ulogic;
            wb_dma_stb       : out   std_ulogic;
            wb_dma_ack       : in    std_ulogic;
            wb_dma_we        : out   std_ulogic;
            wb_dma_cti       : out   std_ulogic_vector(2 downto 0);
            wb_dma_bte       : out   std_ulogic_vector(1 downto 0);
            wb_dma_err       : in    std_ulogic;
            -- connections to SD card
            sdcard_data      : inout std_ulogic_vector(3 downto 0);
            sdcard_cmd       : inout std_ulogic;
            sdcard_clk       : out   std_ulogic;
            sdcard_cd        : in    std_ulogic;
            sdcard_cmd_dir   : out   std_ulogic;
            sdcard_dat0_dir  : out   std_ulogic;
            sdcard_dat13_dir : out   std_ulogic
            );
        end component;

        signal wb_sdcard_cyc : std_ulogic;
        signal wb_sdcard_adr : std_ulogic_vector(29 downto 0);

    begin
        litesdcard : litesdcard_core
            port map (
                clk              => system_clk,
                rst              => soc_rst,
                irq              => ext_irq_sdcard,
                wb_ctrl_adr      => wb_sdcard_adr,
                wb_ctrl_dat_w    => wb_ext_io_in.dat,
                wb_ctrl_dat_r    => wb_sdcard_out.dat,
                wb_ctrl_sel      => wb_ext_io_in.sel,
                wb_ctrl_cyc      => wb_sdcard_cyc,
                wb_ctrl_stb      => wb_ext_io_in.stb,
                wb_ctrl_ack      => wb_sdcard_out.ack,
                wb_ctrl_we       => wb_ext_io_in.we,
                wb_ctrl_cti      => "000",
                wb_ctrl_bte      => "00",
                wb_ctrl_err      => open,
                wb_dma_adr       => wb_sddma_nr.adr,
                wb_dma_dat_w     => wb_sddma_nr.dat,
                wb_dma_dat_r     => wb_sddma_ir.dat,
                wb_dma_sel       => wb_sddma_nr.sel,
                wb_dma_cyc       => wb_sddma_nr.cyc,
                wb_dma_stb       => wb_sddma_nr.stb,
                wb_dma_ack       => wb_sddma_ir.ack,
                wb_dma_we        => wb_sddma_nr.we,
                wb_dma_cti       => open,
                wb_dma_bte       => open,
                wb_dma_err       => '0',
                sdcard_data      => sdcard_data,
                sdcard_cmd       => sdcard_cmd,
                sdcard_clk       => sdcard_clk,
                sdcard_cd        => sdcard_cd,
                sdcard_cmd_dir   => sdcard_cmd_dir,
                sdcard_dat0_dir  => sdcard_dat0_dir,
                sdcard_dat13_dir => sdcard_dat13_dir
                );

        -- Select 3V signalling
        sdcard_vsel <= '0';

        -- Gate cyc with chip select from SoC
        wb_sdcard_cyc <= wb_ext_io_in.cyc and wb_ext_is_sdcard;

        wb_sdcard_adr <= x"0000" & wb_ext_io_in.adr(13 downto 0);

        wb_sdcard_out.stall <= not wb_sdcard_out.ack;

        -- Convert non-pipelined DMA wishbone to pipelined by suppressing
        -- non-acknowledged strobes
        process(system_clk)
        begin
            if rising_edge(system_clk) then
                wb_sddma_out <= wb_sddma_nr;
                if wb_sddma_stb_sent = '1' or
                    (wb_sddma_out.stb = '1' and wb_sddma_in.stall = '0') then
                    wb_sddma_out.stb <= '0';
                end if;
                if wb_sddma_nr.cyc = '0' or wb_sddma_ir.ack = '1' then
                    wb_sddma_stb_sent <= '0';
                elsif wb_sddma_in.stall = '0' then
                    wb_sddma_stb_sent <= wb_sddma_nr.stb;
                end if;
                wb_sddma_ir <= wb_sddma_in;
            end if;
        end process;

    end generate;

    -- Mux WB response on the IO bus
    wb_ext_io_out <= wb_eth_out when wb_ext_is_eth = '1' else
                     wb_sdcard_out when wb_ext_is_sdcard = '1' else
                     wb_dram_ctrl_out;

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
