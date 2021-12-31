library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
        CPUS               : natural  := 1;
        MEMORY_SIZE        : integer  := 16384;
        RAM_INIT_FILE      : string   := "firmware.hex";
        RESET_LOW          : boolean  := true;
        CLK_FREQUENCY      : positive := 100000000;
        HAS_FPU            : boolean  := true;
        HAS_BTC            : boolean  := true;
        USE_LITEDRAM       : boolean  := false;
        NO_BRAM            : boolean  := false;
        DISABLE_FLATTEN_CORE : boolean := false;
        SCLK_STARTUPE2     : boolean := false;
        SPI_FLASH_OFFSET   : integer := 4194304;
        SPI_FLASH_DEF_CKDV : natural := 1;
        SPI_FLASH_DEF_QUAD : boolean := true;
        LOG_LENGTH         : natural := 512;
        USE_LITEETH        : boolean  := false;
        UART_IS_16550      : boolean  := false;
        HAS_UART1          : boolean  := true;
        USE_LITESDCARD     : boolean := false;
        HAS_GPIO           : boolean := true;
        USE_LCD            : boolean := true;
        NGPIO              : natural := 32
        );
    port(
        ext_clk   : in  std_ulogic;
        ext_rst_n : in  std_ulogic;

        -- UART0 signals:
        uart_main_tx : out std_ulogic;
        uart_main_rx : in  std_ulogic;

        -- LEDs
        led_b   : out std_ulogic_vector(3 downto 0);
        led_g   : out std_ulogic_vector(3 downto 0);
        led_r   : out std_ulogic_vector(3 downto 0);
        led4    : out std_ulogic;
        led5    : out std_ulogic;
        led6    : out std_ulogic;
        led7    : out std_ulogic;

        -- SPI
        spi_flash_cs_n   : out std_ulogic;
        spi_flash_clk    : out std_ulogic;
        spi_flash_mosi   : inout std_ulogic;
        spi_flash_miso   : inout std_ulogic;
        spi_flash_wp_n   : inout std_ulogic;
        spi_flash_hold_n : inout std_ulogic;

        -- Switches and buttons
        btn0        : in std_ulogic;
        btn1        : in std_ulogic;
        btn2        : in std_ulogic;
        btn3        : in std_ulogic;
        sw0         : in std_ulogic;
        sw1         : in std_ulogic;
        sw2         : in std_ulogic;
        sw3         : in std_ulogic;

        -- GPIO
        --shield_io0       : inout std_ulogic;
        --shield_io1       : inout std_ulogic;
        --shield_io2       : inout std_ulogic;
        --shield_io3       : inout std_ulogic;
        --shield_io4       : inout std_ulogic;
        --shield_io5       : inout std_ulogic;
        --shield_io6       : inout std_ulogic;
        --shield_io7       : inout std_ulogic;
        --shield_io8       : inout std_ulogic;
        shield_io9       : inout std_ulogic;
        --shield_io10      : inout std_ulogic;
        --shield_io11      : inout std_ulogic;
        --shield_io12      : inout std_ulogic;
        --shield_io13      : inout std_ulogic;
        --shield_io26      : inout std_ulogic;
        --shield_io27      : inout std_ulogic;
        --shield_io28      : inout std_ulogic;
        --shield_io29      : inout std_ulogic;
        shield_io30      : inout std_ulogic;
        shield_io31      : inout std_ulogic;
        shield_io32      : inout std_ulogic;
        shield_io33      : inout std_ulogic;
        --shield_io34      : inout std_ulogic;
        --shield_io35      : inout std_ulogic;
        --shield_io36      : inout std_ulogic;
        --shield_io37      : inout std_ulogic;
        --shield_io38      : inout std_ulogic;
        --shield_io39      : inout std_ulogic;
        --shield_io40      : inout std_ulogic;
        --shield_io41      : inout std_ulogic;
        --shield_io43      : inout std_ulogic;
        --shield_io44      : inout std_ulogic;
        pmod_jb_1        : inout std_ulogic;
        pmod_jb_2        : inout std_ulogic;
        pmod_jb_3        : inout std_ulogic;
        pmod_jb_4        : inout std_ulogic;
        pmod_jb_7        : inout std_ulogic;
        pmod_jb_8        : inout std_ulogic;
        pmod_jb_9        : inout std_ulogic;
        pmod_jb_10       : inout std_ulogic;

        -- Ethernet
        eth_ref_clk      : out std_ulogic;
        eth_clocks_tx    : in std_ulogic;
        eth_clocks_rx    : in std_ulogic;
        eth_rst_n        : out std_ulogic;
        eth_mdio         : inout std_ulogic;
        eth_mdc          : out std_ulogic;
        eth_rx_dv        : in std_ulogic;
        eth_rx_er        : in std_ulogic;
        eth_rx_data      : in std_ulogic_vector(3 downto 0);
        eth_tx_en        : out std_ulogic;
        eth_tx_data      : out std_ulogic_vector(3 downto 0);
        eth_col          : in std_ulogic;
        eth_crs          : in std_ulogic;

        -- SD card pmod on JA
        ja_sdcard_data   : inout std_ulogic_vector(3 downto 0);
        ja_sdcard_cmd    : inout std_ulogic;
        ja_sdcard_clk    : out   std_ulogic;
        ja_sdcard_cd     : in    std_ulogic;

        -- SD card slot on touchscreen/LCD board
        ts_sdcard_data   : inout std_ulogic_vector(3 downto 0);
        ts_sdcard_cmd    : inout std_ulogic;
        ts_sdcard_clk    : out   std_ulogic;
        ts_sdcard_cd     : in    std_ulogic;

        -- Second SD card
        sdcard2_data  : inout std_ulogic_vector(3 downto 0);
        sdcard2_cmd   : inout std_ulogic;
        sdcard2_clk   : out   std_ulogic;
        sdcard2_cd    : in    std_ulogic;

        -- I2C RTC chip
        i2c_rtc_d : inout std_ulogic;
        i2c_rtc_c : inout std_ulogic;

        -- LCD display interface
        lcd_d   : inout std_ulogic_vector(7 downto 0);
        lcd_rs  : out   std_ulogic;
        lcd_cs  : out   std_ulogic;
        lcd_rd  : out   std_ulogic;
        lcd_wr  : out   std_ulogic;
        lcd_rst : out   std_ulogic;

        -- Differential analog inputs from touchscreen
        a2_p : in std_ulogic;
        a2_n : in std_ulogic;
        a3_p : in std_ulogic;
        a3_n : in std_ulogic;
        a4_p : in std_ulogic;
        a4_n : in std_ulogic;
        a5_p : in std_ulogic;
        a5_n : in std_ulogic;

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

    -- Status
    signal run_out : std_ulogic;
    signal run_outs : std_ulogic_vector(CPUS-1 downto 0);
    signal init_done : std_ulogic;
    signal init_err  : std_ulogic;

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;
    signal sw_rst  : std_ulogic;
    signal periph_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;
    signal eth_clk_locked    : std_ulogic;

    -- External IOs from the SoC
    signal wb_ext_io_in        : wb_io_master_out;
    signal wb_ext_io_out       : wb_io_slave_out;
    signal wb_ext_is_dram_csr  : std_ulogic;
    signal wb_ext_is_dram_init : std_ulogic;
    signal wb_ext_is_eth       : std_ulogic;
    signal wb_ext_is_sdcard    : std_ulogic;
    signal wb_ext_is_lcd       : std_ulogic;

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
    signal ext_irq_sdcard2     : std_ulogic := '0';
    signal wb_sdcard_out       : wb_io_slave_out := wb_io_slave_out_init;
    signal wb_sdcard2_out      : wb_io_slave_out := wb_io_slave_out_init;
    signal wb_sddma_out        : wb_io_master_out := wb_io_master_out_init;
    signal wb_sddma_in         : wb_io_slave_out;
    signal wb_sddma_nr         : wb_io_master_out;
    signal wb_sddma1_nr        : wb_io_master_out;
    signal wb_sddma2_nr        : wb_io_master_out;
    signal wb_sddma_ir         : wb_io_slave_out;
    signal wb_sddma1_ack       : std_ulogic;
    signal wb_sddma2_ack       : std_ulogic;
    -- for conversion from non-pipelined wishbone to pipelined
    signal wb_sddma_stb_sent   : std_ulogic;

    -- LCD touchscreen connection
    signal wb_lcd_out          : wb_io_slave_out := wb_io_slave_out_init;

    -- Status LED
    signal led_b_pwm : std_ulogic_vector(3 downto 0) := (others => '0');
    signal led_r_pwm : std_ulogic_vector(3 downto 0) := (others => '0');
    signal led_g_pwm : std_ulogic_vector(3 downto 0) := (others => '0');
    signal disk_activity : std_ulogic := '0';

    -- Dumb PWM for the LEDs, those RGB LEDs are too bright otherwise
    signal pwm_counter  : std_ulogic_vector(8 downto 0);

    -- SPI flash
    signal spi_sck     : std_ulogic;
    signal spi_cs_n    : std_ulogic;
    signal spi_sdat_o  : std_ulogic_vector(3 downto 0);
    signal spi_sdat_oe : std_ulogic_vector(3 downto 0);
    signal spi_sdat_i  : std_ulogic_vector(3 downto 0);

    -- GPIO
    signal gpio_in     : std_ulogic_vector(NGPIO - 1 downto 0);
    signal gpio_out    : std_ulogic_vector(NGPIO - 1 downto 0);
    signal gpio_dir    : std_ulogic_vector(NGPIO - 1 downto 0);

    -- ddram clock signals as vectors
    signal ddram_clk_p_vec : std_logic_vector(0 downto 0);
    signal ddram_clk_n_vec : std_logic_vector(0 downto 0);

    signal uart1_rxd : std_ulogic;
    signal uart1_txd : std_ulogic;

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
            NCPUS              => CPUS,
            CLK_FREQ           => CLK_FREQUENCY,
            HAS_FPU            => HAS_FPU,
            HAS_BTC            => HAS_BTC,
            HAS_DRAM           => USE_LITEDRAM,
            DRAM_SIZE          => 256 * 1024 * 1024,
            DRAM_INIT_SIZE     => PAYLOAD_SIZE,
            DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            HAS_SPI_FLASH      => true,
            SPI_FLASH_DLINES   => 4,
            SPI_FLASH_OFFSET   => SPI_FLASH_OFFSET,
            SPI_FLASH_DEF_CKDV => SPI_FLASH_DEF_CKDV,
            SPI_FLASH_DEF_QUAD => SPI_FLASH_DEF_QUAD,
            LOG_LENGTH         => LOG_LENGTH,
            HAS_LITEETH        => USE_LITEETH,
            UART0_IS_16550     => UART_IS_16550,
            HAS_UART1          => HAS_UART1,
            HAS_SD_CARD        => USE_LITESDCARD,
            HAS_SD_CARD2       => USE_LITESDCARD,
            HAS_LCD            => USE_LCD,
            HAS_GPIO           => HAS_GPIO,
            NGPIO              => NGPIO
            )
        port map (
            -- System signals
            system_clk        => system_clk,
            rst               => soc_rst,
            sw_soc_reset      => sw_rst,
            run_out           => run_out,
            run_outs          => run_outs,

            -- UART signals
            uart0_txd         => uart_main_tx,
            uart0_rxd         => uart_main_rx,

	    -- UART1 signals
            uart1_txd         => uart1_txd,
            uart1_rxd         => uart1_rxd,

            -- SPI signals
            spi_flash_sck     => spi_sck,
            spi_flash_cs_n    => spi_cs_n,
            spi_flash_sdat_o  => spi_sdat_o,
            spi_flash_sdat_oe => spi_sdat_oe,
            spi_flash_sdat_i  => spi_sdat_i,

            -- GPIO signals
            gpio_in           => gpio_in,
            gpio_out          => gpio_out,
            gpio_dir          => gpio_dir,

            -- External interrupts
            ext_irq_eth       => ext_irq_eth,
            ext_irq_sdcard    => ext_irq_sdcard,
            ext_irq_sdcard2   => ext_irq_sdcard2,

            -- DRAM wishbone
            wb_dram_in           => wb_dram_in,
            wb_dram_out          => wb_dram_out,

            -- IO wishbone
            wb_ext_io_in         => wb_ext_io_in,
            wb_ext_io_out        => wb_ext_io_out,
            wb_ext_is_dram_csr   => wb_ext_is_dram_csr,
            wb_ext_is_dram_init  => wb_ext_is_dram_init,
            wb_ext_is_eth        => wb_ext_is_eth,
            wb_ext_is_sdcard     => wb_ext_is_sdcard,
            wb_ext_is_lcd        => wb_ext_is_lcd,

            -- DMA wishbone
            wishbone_dma_in      => wb_sddma_in,
            wishbone_dma_out     => wb_sddma_out
            );

    uart1_txd <= '1';

    -- SPI Flash
    --
    -- Note: Unlike many other boards, the SPI flash on the Arty has
    -- an actual pin to generate the clock and doesn't require to use
    -- the STARTUPE2 primitive.
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

    spi_sclk_startupe2: if SCLK_STARTUPE2 generate
        spi_flash_clk    <= 'Z';

        STARTUPE2_INST: STARTUPE2
            port map (
                CLK => '0',
                GSR => '0',
                GTS => '0',
                KEYCLEARB => '0',
                PACK => '0',
                USRCCLKO => spi_sck,
                USRCCLKTS => '0',
                USRDONEO => '1',
                USRDONETS => '0'
                );
    end generate;

    spi_direct_sclk: if not SCLK_STARTUPE2 generate
        spi_flash_clk    <= spi_sck;
    end generate;

    nodram: if not USE_LITEDRAM generate
        signal ddram_clk_dummy : std_ulogic;
        signal gen_rst         : std_ulogic;
    begin
        reset_controller: entity work.soc_reset
            generic map(
                RESET_LOW => RESET_LOW
                )
            port map(
                ext_clk => ext_clk,
                pll_clk => system_clk,
                pll_locked_in => system_clk_locked and eth_clk_locked,
                ext_rst_in => ext_rst_n,
                pll_rst_out => pll_rst,
                rst_out => gen_rst
                );

        soc_rst <= gen_rst;

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

        init_done <= '1';
        init_err  <= '0';

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
        signal gen_rst         : std_ulogic;
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
                pll_locked_in => eth_clk_locked,
                ext_rst_in => ext_rst_n,
                pll_rst_out => pll_rst,
                rst_out => open
                );

        -- Generate SoC reset
        soc_rst_gen: process(system_clk, ext_rst_n)
        begin
            -- XXX why does this need to be an asynchronous reset?
            if ext_rst_n = '0' then
                soc_rst <= '1';
            elsif rising_edge(system_clk) then
                soc_rst <= gen_rst or not eth_clk_locked or not system_clk_locked;
            end if;
        end process;

	ddram_clk_p_vec <= (others => ddram_clk_p);
	ddram_clk_n_vec <= (others => ddram_clk_n);

        dram: entity work.litedram_wrapper
            generic map(
                DRAM_ABITS => 24,
                DRAM_ALINES => 14,
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
                system_reset    => gen_rst,
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
                ddram_cs_n      => ddram_cs_n,
                ddram_dm        => ddram_dm,
                ddram_dq        => ddram_dq,
                ddram_dqs_p     => ddram_dqs_p,
                ddram_dqs_n     => ddram_dqs_n,
                ddram_clk_p     => ddram_clk_p_vec,
                ddram_clk_n     => ddram_clk_n_vec,
                ddram_cke       => ddram_cke,
                ddram_odt       => ddram_odt,
                ddram_reset_n   => ddram_reset_n
                );

        init_done <= dram_init_done;
        init_err  <= dram_init_error;

    end generate;

    periph_rst <= soc_rst or sw_rst;

    has_liteeth : if USE_LITEETH generate

        component liteeth_core port (
            sys_clock           : in std_ulogic;
            sys_reset           : in std_ulogic;
            mii_clocks_tx       : in std_ulogic;
            mii_clocks_rx       : in std_ulogic;
            mii_rst_n           : out std_ulogic;
            mii_mdio            : in std_ulogic;
            mii_mdc             : out std_ulogic;
            mii_rx_dv           : in std_ulogic;
            mii_rx_er           : in std_ulogic;
            mii_rx_data         : in std_ulogic_vector(3 downto 0);
            mii_tx_en           : out std_ulogic;
            mii_tx_data         : out std_ulogic_vector(3 downto 0);
            mii_col             : in std_ulogic;
            mii_crs             : in std_ulogic;
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

        -- Change this to use a PLL instead of a BUFR to generate the 25Mhz
        -- reference clock to the PHY.
        constant USE_PLL : boolean := false;
    begin
        eth_use_pll: if USE_PLL generate
            signal eth_clk_25     : std_ulogic;
            signal eth_clkfb      : std_ulogic;
        begin
            pll_eth : PLLE2_BASE
                generic map (
                    BANDWIDTH          => "OPTIMIZED",
                    CLKFBOUT_MULT      => 16,
                    CLKIN1_PERIOD      => 10.0,
                    CLKOUT0_DIVIDE     => 64,
                    DIVCLK_DIVIDE      => 1,
                    STARTUP_WAIT       => "FALSE")
                port map (
                    CLKOUT0  => eth_clk_25,
                    CLKOUT1  => open,
                    CLKOUT2  => open,
                    CLKOUT3  => open,
                    CLKOUT4  => open,
                    CLKOUT5  => open,
                    CLKFBOUT => eth_clkfb,
                    LOCKED   => eth_clk_locked,
                    CLKIN1   => ext_clk,
                    PWRDWN   => '0',
                    RST      => pll_rst,
                    CLKFBIN  => eth_clkfb);

            eth_clk_buf: BUFG
                port map (
                    I => eth_clk_25,
                    O => eth_ref_clk
                    );
        end generate;

        eth_use_bufr: if not USE_PLL generate
            eth_clk_div: BUFR
                generic map (
                    BUFR_DIVIDE => "4"
                    )
                port map (
                    I => system_clk,
                    O => eth_ref_clk,
                    CE => '1',
                    CLR => '0'
                    );
            eth_clk_locked <= '1';
        end generate;

        liteeth :  liteeth_core
            port map(
                sys_clock         => system_clk,
                sys_reset         => periph_rst,
                mii_clocks_tx     => eth_clocks_tx,
                mii_clocks_rx     => eth_clocks_rx,
                mii_rst_n         => eth_rst_n,
                mii_mdio          => eth_mdio,
                mii_mdc           => eth_mdc,
                mii_rx_dv         => eth_rx_dv,
                mii_rx_er         => eth_rx_er,
                mii_rx_data       => eth_rx_data,
                mii_tx_en         => eth_tx_en,
                mii_tx_data       => eth_tx_data,
                mii_col           => eth_col,
                mii_crs           => eth_crs,
                wishbone_adr      => wb_eth_adr,
                wishbone_dat_w    => wb_ext_io_in.dat,
                wishbone_dat_r    => wb_eth_out.dat,
                wishbone_sel      => wb_ext_io_in.sel,
                wishbone_cyc      => wb_eth_cyc,
                wishbone_stb      => wb_ext_io_in.stb,
                wishbone_ack      => wb_eth_out.ack,
                wishbone_we       => wb_ext_io_in.we,
                wishbone_cti      => "000",
                wishbone_bte      => "00",
                wishbone_err      => open,
                interrupt         => ext_irq_eth
                );

        -- Gate cyc with "chip select" from soc
        wb_eth_cyc <= wb_ext_io_in.cyc and wb_ext_is_eth;

        -- Remove top address bits as liteeth decoder doesn't know about them
        wb_eth_adr <= x"000" & "000" & wb_ext_io_in.adr(14 downto 0);

        -- LiteETH isn't pipelined
        wb_eth_out.stall <= not wb_eth_out.ack;

    end generate;

    no_liteeth : if not USE_LITEETH generate
        eth_clk_locked <= '1';
        ext_irq_eth    <= '0';
    end generate;

    -- SD card pmod, two interfaces
    has_sdcard : if USE_LITESDCARD generate
        component litesdcard_core port (
            clk           : in    std_ulogic;
            rst           : in    std_ulogic;
            -- wishbone for accessing control registers
            wb_ctrl_adr   : in    std_ulogic_vector(29 downto 0);
            wb_ctrl_dat_w : in    std_ulogic_vector(31 downto 0);
            wb_ctrl_dat_r : out   std_ulogic_vector(31 downto 0);
            wb_ctrl_sel   : in    std_ulogic_vector(3 downto 0);
            wb_ctrl_cyc   : in    std_ulogic;
            wb_ctrl_stb   : in    std_ulogic;
            wb_ctrl_ack   : out   std_ulogic;
            wb_ctrl_we    : in    std_ulogic;
            wb_ctrl_cti   : in    std_ulogic_vector(2 downto 0);
            wb_ctrl_bte   : in    std_ulogic_vector(1 downto 0);
            wb_ctrl_err   : out   std_ulogic;
            -- wishbone for SD card core to use for DMA
            wb_dma_adr    : out   std_ulogic_vector(29 downto 0);
            wb_dma_dat_w  : out   std_ulogic_vector(31 downto 0);
            wb_dma_dat_r  : in    std_ulogic_vector(31 downto 0);
            wb_dma_sel    : out   std_ulogic_vector(3 downto 0);
            wb_dma_cyc    : out   std_ulogic;
            wb_dma_stb    : out   std_ulogic;
            wb_dma_ack    : in    std_ulogic;
            wb_dma_we     : out   std_ulogic;
            wb_dma_cti    : out   std_ulogic_vector(2 downto 0);
            wb_dma_bte    : out   std_ulogic_vector(1 downto 0);
            wb_dma_err    : in    std_ulogic;
            -- connections to SD card
            sdcard_data   : inout std_ulogic_vector(3 downto 0);
            sdcard_cmd    : inout std_ulogic;
            sdcard_clk    : out   std_ulogic;
            sdcard_cd     : in    std_ulogic;
            irq           : out   std_ulogic
            );
        end component;

        signal wb_sdcard_cyc : std_ulogic;
        signal wb_sdcard2_cyc : std_ulogic;
        signal wb_sdcard_adr : std_ulogic_vector(29 downto 0);
        signal dma_msel : std_ulogic;
        signal other_cyc : std_ulogic;
        signal sdc0_activity : std_ulogic := '0';
        signal sdc1_activity : std_ulogic := '0';

    begin
        sdcard_ja: if not USE_LCD generate
            litesdcard : litesdcard_core
                port map (
                    clk           => system_clk,
                    rst           => periph_rst,
                    wb_ctrl_adr   => wb_sdcard_adr,
                    wb_ctrl_dat_w => wb_ext_io_in.dat,
                    wb_ctrl_dat_r => wb_sdcard_out.dat,
                    wb_ctrl_sel   => wb_ext_io_in.sel,
                    wb_ctrl_cyc   => wb_sdcard_cyc,
                    wb_ctrl_stb   => wb_ext_io_in.stb,
                    wb_ctrl_ack   => wb_sdcard_out.ack,
                    wb_ctrl_we    => wb_ext_io_in.we,
                    wb_ctrl_cti   => "000",
                    wb_ctrl_bte   => "00",
                    wb_ctrl_err   => open,
                    wb_dma_adr    => wb_sddma1_nr.adr,
                    wb_dma_dat_w  => wb_sddma1_nr.dat,
                    wb_dma_dat_r  => wb_sddma_ir.dat,
                    wb_dma_sel    => wb_sddma1_nr.sel,
                    wb_dma_cyc    => wb_sddma1_nr.cyc,
                    wb_dma_stb    => wb_sddma1_nr.stb,
                    wb_dma_ack    => wb_sddma1_ack,
                    wb_dma_we     => wb_sddma1_nr.we,
                    wb_dma_cti    => open,
                    wb_dma_bte    => open,
                    wb_dma_err    => '0',
                    sdcard_data   => ja_sdcard_data,
                    sdcard_cmd    => ja_sdcard_cmd,
                    sdcard_clk    => ja_sdcard_clk,
                    sdcard_cd     => ja_sdcard_cd,
                    irq           => ext_irq_sdcard
                    );
        end generate;

        sdcard_ts: if USE_LCD generate
            litesdcard : litesdcard_core
                port map (
                    clk           => system_clk,
                    rst           => periph_rst,
                    wb_ctrl_adr   => wb_sdcard_adr,
                    wb_ctrl_dat_w => wb_ext_io_in.dat,
                    wb_ctrl_dat_r => wb_sdcard_out.dat,
                    wb_ctrl_sel   => wb_ext_io_in.sel,
                    wb_ctrl_cyc   => wb_sdcard_cyc,
                    wb_ctrl_stb   => wb_ext_io_in.stb,
                    wb_ctrl_ack   => wb_sdcard_out.ack,
                    wb_ctrl_we    => wb_ext_io_in.we,
                    wb_ctrl_cti   => "000",
                    wb_ctrl_bte   => "00",
                    wb_ctrl_err   => open,
                    wb_dma_adr    => wb_sddma1_nr.adr,
                    wb_dma_dat_w  => wb_sddma1_nr.dat,
                    wb_dma_dat_r  => wb_sddma_ir.dat,
                    wb_dma_sel    => wb_sddma1_nr.sel,
                    wb_dma_cyc    => wb_sddma1_nr.cyc,
                    wb_dma_stb    => wb_sddma1_nr.stb,
                    wb_dma_ack    => wb_sddma1_ack,
                    wb_dma_we     => wb_sddma1_nr.we,
                    wb_dma_cti    => open,
                    wb_dma_bte    => open,
                    wb_dma_err    => '0',
                    sdcard_data   => ts_sdcard_data,
                    sdcard_cmd    => ts_sdcard_cmd,
                    sdcard_clk    => ts_sdcard_clk,
                    sdcard_cd     => ts_sdcard_cd,
                    irq           => ext_irq_sdcard
                    );
        end generate;

        litesdcard2 : litesdcard_core
            port map (
                clk           => system_clk,
                rst           => periph_rst,
                wb_ctrl_adr   => wb_sdcard_adr,
                wb_ctrl_dat_w => wb_ext_io_in.dat,
                wb_ctrl_dat_r => wb_sdcard2_out.dat,
                wb_ctrl_sel   => wb_ext_io_in.sel,
                wb_ctrl_cyc   => wb_sdcard2_cyc,
                wb_ctrl_stb   => wb_ext_io_in.stb,
                wb_ctrl_ack   => wb_sdcard2_out.ack,
                wb_ctrl_we    => wb_ext_io_in.we,
                wb_ctrl_cti   => "000",
                wb_ctrl_bte   => "00",
                wb_ctrl_err   => open,
                wb_dma_adr    => wb_sddma2_nr.adr,
                wb_dma_dat_w  => wb_sddma2_nr.dat,
                wb_dma_dat_r  => wb_sddma_ir.dat,
                wb_dma_sel    => wb_sddma2_nr.sel,
                wb_dma_cyc    => wb_sddma2_nr.cyc,
                wb_dma_stb    => wb_sddma2_nr.stb,
                wb_dma_ack    => wb_sddma2_ack,
                wb_dma_we     => wb_sddma2_nr.we,
                wb_dma_cti    => open,
                wb_dma_bte    => open,
                wb_dma_err    => '0',
                sdcard_data   => sdcard2_data,
                sdcard_cmd    => sdcard2_cmd,
                sdcard_clk    => sdcard2_clk,
                sdcard_cd     => sdcard2_cd,
                irq           => ext_irq_sdcard2
                );

        -- Gate cyc with chip selects from SoC
        -- Select first or second interface based on real address bit 15
        wb_sdcard_cyc  <= wb_ext_io_in.cyc and wb_ext_is_sdcard and not wb_ext_io_in.adr(13);
        wb_sdcard2_cyc <= wb_ext_io_in.cyc and wb_ext_is_sdcard and wb_ext_io_in.adr(13);

        wb_sdcard_adr <= 17x"0" & wb_ext_io_in.adr(12 downto 0);

        wb_sdcard_out.stall <= not wb_sdcard_out.ack;
        wb_sdcard2_out.stall <= not wb_sdcard2_out.ack;

        -- Simple arbiter to multiplex the two DMA wishbones
        wb_sddma_nr <= wb_sddma1_nr when dma_msel = '0' else wb_sddma2_nr;
        wb_sddma1_ack <= wb_sddma_ir.ack and not dma_msel;
        wb_sddma2_ack <= wb_sddma_ir.ack and dma_msel;
        other_cyc <= wb_sddma2_nr.cyc when dma_msel = '0' else wb_sddma1_nr.cyc;
       
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

                -- Decide which wishbone to use next cycle
                if periph_rst = '1' then
                    dma_msel <= '0';
                elsif wb_sddma_nr.cyc = '0' and other_cyc = '1' then
                    dma_msel <= not dma_msel;
                end if;
            end if;
        end process;

        -- Capture writes to the interrupt enable registers, and record
        -- the state of the command-done interrupt enable bit to use
        -- as an activity indicator.
        process(system_clk)
        begin
            if rising_edge(system_clk) then
                if periph_rst = '1' then
                    sdc0_activity <= '0';
                    sdc1_activity <= '0';
                elsif wb_sdcard_adr(11 downto 0) = x"602"
                    and wb_ext_io_in.stb = '1' and wb_ext_io_in.we = '1' then
                    if wb_sdcard_cyc = '1' then
                        sdc0_activity <= wb_ext_io_in.dat(3);
                    end if;
                    if wb_sdcard2_cyc = '1' then
                        sdc1_activity <= wb_ext_io_in.dat(3);
                    end if;
                end if;
            end if;
        end process;
        disk_activity <= sdc0_activity or sdc1_activity;
    end generate;

    -- LCD touchscreen on arduino-compatible pins
    has_lcd : if USE_LCD generate
        signal lcd_dout : std_ulogic_vector(7 downto 0);
        signal lcd_doe  : std_ulogic;
        signal lcd_doe0 : std_ulogic;
        signal lcd_doe1 : std_ulogic;
        signal lcd_rso  : std_ulogic;
        signal lcd_rsoe : std_ulogic;
        signal lcd_cso  : std_ulogic;
        signal lcd_csoe : std_ulogic;
        signal tp       : std_ulogic;
    begin
        lcd0 : entity work.lcd_touchscreen
            port map (
                clk    => system_clk,
                rst    => soc_rst,
                wb_in  => wb_ext_io_in,
                wb_out => wb_lcd_out,
                wb_sel => wb_ext_is_lcd,
                tp     => tp,

                lcd_din  => lcd_d,
                lcd_dout => lcd_dout,
                lcd_doe  => lcd_doe,
                lcd_doe0 => lcd_doe0,
                lcd_doe1 => lcd_doe1,
                lcd_rd   => lcd_rd,
                lcd_wr   => lcd_wr,
                lcd_rs   => lcd_rso,
                lcd_rsoe => lcd_rsoe,
                lcd_cs   => lcd_cso,
                lcd_csoe => lcd_csoe,
                lcd_rst  => lcd_rst,

                a2_p => a2_p,
                a2_n => a2_n,
                a3_p => a3_p,
                a3_n => a3_n,
                a4_p => a4_p,
                a4_n => a4_n,
                a5_p => a5_p,
                a5_n => a5_n
                );
        -- lcd_d(0), lcd_d(1), lcd_rs, lcd_cs are used for the touchscreen
        -- interface and hence have individual output enables.
        lcd_d(0) <= lcd_dout(0) when lcd_doe0 = '1' else 'Z';
        lcd_d(1) <= lcd_dout(1) when lcd_doe1 = '1' else 'Z';
        lcd_d(7 downto 2) <= lcd_dout(7 downto 2) when lcd_doe = '1' else (others => 'Z');
        lcd_rs <= lcd_rso when lcd_rsoe = '1' else 'Z';
        lcd_cs <= lcd_cso when lcd_csoe = '1' else 'Z';
    end generate;

    -- Mux WB response on the IO bus
    wb_ext_io_out <= wb_eth_out when wb_ext_is_eth = '1' else
                     wb_sdcard_out when wb_ext_is_sdcard = '1' and wb_ext_io_in.adr(13) = '0' else
                     wb_sdcard2_out when wb_ext_is_sdcard = '1' and wb_ext_io_in.adr(13) = '1' else
                     wb_lcd_out when wb_ext_is_lcd = '1' else
                     wb_dram_ctrl_out;

    status_led_colour : process(all)
        variable rgb : std_ulogic_vector(2 downto 0);
    begin
        if soc_rst = '1' then
            rgb := "000";
        elsif system_clk_locked = '0' then
            rgb := "110";
        else
            rgb := init_err & (init_done and not init_err) & (not init_done);
        end if;
        led_r_pwm(0) <= rgb(2);
        led_g_pwm(0) <= rgb(1);
        led_b_pwm(0) <= rgb(0);
    end process;

    leds_pwm : process(system_clk)
    begin
        if rising_edge(system_clk) then
            pwm_counter <= std_ulogic_vector(signed(pwm_counter) + 1);
            if pwm_counter(8 downto 4) = "00000" then
                led_b <= led_b_pwm;
                led_r <= led_r_pwm;
                led_g <= led_g_pwm;
            else
                led_b <= "0000";
                led_r <= "0000";
                led_g <= "0000";
            end if;
        end if;
    end process;

    led4 <= '0';
    led5 <= disk_activity;
    led6 <= run_outs(1) when CPUS > 1 else '0';
    led7 <= run_outs(0);

    -- GPIO
    gpio_in(10) <= btn0;
    gpio_in(11) <= btn1;
    gpio_in(12) <= btn2;
    gpio_in(13) <= btn3;
    gpio_in(14) <= sw0;
    gpio_in(15) <= sw1;
    gpio_in(16) <= sw2;
    gpio_in(17) <= sw3;

    gpio_in(0) <= '0';
    gpio_in(1) <= '0';
    gpio_in(2) <= '0';
    gpio_in(3) <= '0';
    gpio_in(4) <= '0';
    gpio_in(5) <= '0';
    gpio_in(6) <= '0';
    gpio_in(7) <= '0';
    gpio_in(8) <= '0';

    gpio_in(9) <= shield_io9;
    gpio_in(18) <= shield_io30;
    gpio_in(19) <= shield_io31;
    gpio_in(20) <= shield_io32;
    gpio_in(21) <= shield_io33;
    gpio_in(22) <= i2c_rtc_d;
    gpio_in(23) <= i2c_rtc_c;
    gpio_in(24) <= pmod_jb_1;
    gpio_in(25) <= pmod_jb_2;
    gpio_in(26) <= pmod_jb_3;
    gpio_in(27) <= pmod_jb_4;
    gpio_in(28) <= pmod_jb_7;
    gpio_in(29) <= pmod_jb_8;
    gpio_in(30) <= pmod_jb_9;
    gpio_in(31) <= pmod_jb_10;

    led_b_pwm(1) <= gpio_out(0) and gpio_dir(0);
    led_g_pwm(1) <= gpio_out(1) and gpio_dir(1);
    led_r_pwm(1) <= gpio_out(2) and gpio_dir(2);

    led_b_pwm(2) <= gpio_out(3) and gpio_dir(3);
    led_g_pwm(2) <= gpio_out(4) and gpio_dir(4);
    led_r_pwm(2) <= gpio_out(5) and gpio_dir(5);

    led_b_pwm(3) <= gpio_out(6) and gpio_dir(6);
    led_g_pwm(3) <= gpio_out(7) and gpio_dir(7);
    led_r_pwm(3) <= gpio_out(8) and gpio_dir(8);

    shield_io9 <= gpio_out(9) when gpio_dir(9) = '1' else 'Z';
    shield_io30 <= gpio_out(18) when gpio_dir(18) = '1' else 'Z';
    shield_io31 <= gpio_out(19) when gpio_dir(19) = '1' else 'Z';
    shield_io32 <= gpio_out(20) when gpio_dir(20) = '1' else 'Z';
    shield_io33 <= gpio_out(21) when gpio_dir(21) = '1' else 'Z';
    i2c_rtc_d <= gpio_out(22) when gpio_dir(22) = '1' else 'Z';
    i2c_rtc_c <= gpio_out(23) when gpio_dir(23) = '1' else 'Z';
    pmod_jb_1   <= gpio_out(24) when gpio_dir(24) = '1' else 'Z';
    pmod_jb_2   <= gpio_out(25) when gpio_dir(25) = '1' else 'Z';
    pmod_jb_3   <= gpio_out(26) when gpio_dir(26) = '1' else 'Z';
    pmod_jb_4   <= gpio_out(27) when gpio_dir(27) = '1' else 'Z';
    pmod_jb_7   <= gpio_out(28) when gpio_dir(28) = '1' else 'Z';
    pmod_jb_8   <= gpio_out(29) when gpio_dir(29) = '1' else 'Z';
    pmod_jb_9   <= gpio_out(30) when gpio_dir(30) = '1' else 'Z';
    pmod_jb_10  <= gpio_out(31) when gpio_dir(31) = '1' else 'Z';

end architecture behaviour;
