library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
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
        NGPIO              : natural := 32
        );
    port(
        ext_clk   : in  std_ulogic;
        ext_rst_n : in  std_ulogic;

        -- UART0 signals:
        uart_main_tx : out std_ulogic;
        uart_main_rx : in  std_ulogic;

	-- UART1 signals:
	uart_pmod_tx    : out std_ulogic;
	uart_pmod_rx    : in std_ulogic;
	uart_pmod_cts_n : in std_ulogic;
	uart_pmod_rts_n : out std_ulogic;

        -- LEDs
        led0_b  : out std_ulogic;
        led0_g  : out std_ulogic;
        led0_r  : out std_ulogic;
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

        -- GPIO
        shield_io        : inout std_ulogic_vector(44 downto 0);

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
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;
    signal eth_clk_locked    : std_ulogic;

    -- External IOs from the SoC
    signal wb_ext_io_in        : wb_io_master_out;
    signal wb_ext_io_out       : wb_io_slave_out;
    signal wb_ext_is_dram_csr  : std_ulogic;
    signal wb_ext_is_dram_init : std_ulogic;
    signal wb_ext_is_eth       : std_ulogic;

    -- DRAM main data wishbone connection
    signal wb_dram_in          : wishbone_master_out;
    signal wb_dram_out         : wishbone_slave_out;

    -- DRAM control wishbone connection
    signal wb_dram_ctrl_out    : wb_io_slave_out := wb_io_slave_out_init;

    -- LiteEth connection
    signal ext_irq_eth         : std_ulogic;
    signal wb_eth_out          : wb_io_slave_out := wb_io_slave_out_init;

    -- Control/status
    signal core_alt_reset : std_ulogic;

    -- Status LED
    signal led0_b_pwm : std_ulogic;
    signal led0_r_pwm : std_ulogic;
    signal led0_g_pwm : std_ulogic;

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
            NGPIO              => NGPIO
            )
        port map (
            -- System signals
            system_clk        => system_clk,
            rst               => soc_rst,

            -- UART signals
            uart0_txd         => uart_main_tx,
            uart0_rxd         => uart_main_rx,

	    -- UART1 signals
	    uart1_txd         => uart_pmod_tx,
	    uart1_rxd         => uart_pmod_rx,

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

            -- DRAM wishbone
            wb_dram_in           => wb_dram_in,
            wb_dram_out          => wb_dram_out,
            wb_ext_io_in         => wb_ext_io_in,
            wb_ext_io_out        => wb_ext_io_out,
            wb_ext_is_dram_csr   => wb_ext_is_dram_csr,
            wb_ext_is_dram_init  => wb_ext_is_dram_init,
            wb_ext_is_eth        => wb_ext_is_eth,
            alt_reset            => core_alt_reset
            );

    uart_pmod_rts_n <= '0';

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
        signal dram_sys_rst    : std_ulogic;
        signal rst_gen_rst     : std_ulogic;
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
                rst_out => rst_gen_rst
                );

        -- Generate SoC reset
        soc_rst_gen: process(system_clk)
        begin
            if ext_rst_n = '0' then
                soc_rst <= '1';
            elsif rising_edge(system_clk) then
                soc_rst <= dram_sys_rst or not eth_clk_locked or not system_clk_locked;
            end if;
        end process;

        dram: entity work.litedram_wrapper
            generic map(
                DRAM_ABITS => 24,
                DRAM_ALINES => 14,
                DRAM_DLINES => 16,
                DRAM_PORT_WIDTH => 128,
                PAYLOAD_FILE => RAM_INIT_FILE,
                PAYLOAD_SIZE => PAYLOAD_SIZE
                )
            port map(
                clk_in          => ext_clk,
                rst             => pll_rst,
                system_clk      => system_clk,
                system_reset    => dram_sys_rst,
                core_alt_reset  => core_alt_reset,
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
                ddram_clk_p     => ddram_clk_p,
                ddram_clk_n     => ddram_clk_n,
                ddram_cke       => ddram_cke,
                ddram_odt       => ddram_odt,
                ddram_reset_n   => ddram_reset_n
                );

        led0_b_pwm <= not dram_init_done;
        led0_r_pwm <= dram_init_error;
        led0_g_pwm <= dram_init_done and not dram_init_error;

    end generate;

    has_liteeth : if USE_LITEETH generate

        component liteeth_core port (
            sys_clock           : in std_ulogic;
            sys_reset           : in std_ulogic;
            mii_eth_clocks_tx   : in std_ulogic;
            mii_eth_clocks_rx   : in std_ulogic;
            mii_eth_rst_n       : out std_ulogic;
            mii_eth_mdio        : in std_ulogic;
            mii_eth_mdc         : out std_ulogic;
            mii_eth_rx_dv       : in std_ulogic;
            mii_eth_rx_er       : in std_ulogic;
            mii_eth_rx_data     : in std_ulogic_vector(3 downto 0);
            mii_eth_tx_en       : out std_ulogic;
            mii_eth_tx_data     : out std_ulogic_vector(3 downto 0);
            mii_eth_col         : in std_ulogic;
            mii_eth_crs         : in std_ulogic;
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
                sys_reset         => soc_rst,
                mii_eth_clocks_tx => eth_clocks_tx,
                mii_eth_clocks_rx => eth_clocks_rx,
                mii_eth_rst_n     => eth_rst_n,
                mii_eth_mdio      => eth_mdio,
                mii_eth_mdc       => eth_mdc,
                mii_eth_rx_dv     => eth_rx_dv,
                mii_eth_rx_er     => eth_rx_er,
                mii_eth_rx_data   => eth_rx_data,
                mii_eth_tx_en     => eth_tx_en,
                mii_eth_tx_data   => eth_tx_data,
                mii_eth_col       => eth_col,
                mii_eth_crs       => eth_crs,
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
        wb_eth_adr <= x"000" & "000" & wb_ext_io_in.adr(16 downto 2);

        -- LiteETH isn't pipelined
        wb_eth_out.stall <= not wb_eth_out.ack;

    end generate;

    no_liteeth : if not USE_LITEETH generate
        eth_clk_locked <= '1';
        ext_irq_eth    <= '0';
    end generate;

    -- Mux WB response on the IO bus
    wb_ext_io_out <= wb_eth_out when wb_ext_is_eth = '1' else wb_dram_ctrl_out;

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

    led4 <= system_clk_locked;
    led5 <= eth_clk_locked;
    led6 <= not soc_rst;

    -- GPIO
    gpio_in(0) <= shield_io(0);
    gpio_in(1) <= shield_io(1);
    gpio_in(2) <= shield_io(2);
    gpio_in(3) <= shield_io(3);
    gpio_in(4) <= shield_io(4);
    gpio_in(5) <= shield_io(5);
    gpio_in(6) <= shield_io(6);
    gpio_in(7) <= shield_io(7);
    gpio_in(8) <= shield_io(8);
    gpio_in(9) <= shield_io(9);
    gpio_in(10) <= shield_io(10);
    gpio_in(11) <= shield_io(11);
    gpio_in(12) <= shield_io(12);
    gpio_in(13) <= shield_io(13);
    gpio_in(14) <= shield_io(26);
    gpio_in(15) <= shield_io(27);
    gpio_in(16) <= shield_io(28);
    gpio_in(17) <= shield_io(29);
    gpio_in(18) <= shield_io(30);
    gpio_in(19) <= shield_io(31);
    gpio_in(20) <= shield_io(32);
    gpio_in(21) <= shield_io(33);
    gpio_in(22) <= shield_io(34);
    gpio_in(23) <= shield_io(35);
    gpio_in(24) <= shield_io(36);
    gpio_in(25) <= shield_io(37);
    gpio_in(26) <= shield_io(38);
    gpio_in(27) <= shield_io(39);
    gpio_in(28) <= shield_io(40);
    gpio_in(29) <= shield_io(41);
    gpio_in(30) <= shield_io(42);
    gpio_in(31) <= gpio_out(31);

    shield_io(0) <= gpio_out(0) when gpio_dir(0) = '1' else 'Z';
    shield_io(1) <= gpio_out(1) when gpio_dir(1) = '1' else 'Z';
    shield_io(2) <= gpio_out(2) when gpio_dir(2) = '1' else 'Z';
    shield_io(3) <= gpio_out(3) when gpio_dir(3) = '1' else 'Z';
    shield_io(4) <= gpio_out(4) when gpio_dir(4) = '1' else 'Z';
    shield_io(5) <= gpio_out(5) when gpio_dir(5) = '1' else 'Z';
    shield_io(6) <= gpio_out(6) when gpio_dir(6) = '1' else 'Z';
    shield_io(7) <= gpio_out(7) when gpio_dir(7) = '1' else 'Z';
    shield_io(8) <= gpio_out(8) when gpio_dir(8) = '1' else 'Z';
    shield_io(9) <= gpio_out(9) when gpio_dir(9) = '1' else 'Z';
    shield_io(10) <= gpio_out(10) when gpio_dir(10) = '1' else 'Z';
    shield_io(11) <= gpio_out(11) when gpio_dir(11) = '1' else 'Z';
    shield_io(12) <= gpio_out(12) when gpio_dir(12) = '1' else 'Z';
    shield_io(13) <= gpio_out(13) when gpio_dir(13) = '1' else 'Z';
    shield_io(26) <= gpio_out(14) when gpio_dir(14) = '1' else 'Z';
    shield_io(27) <= gpio_out(15) when gpio_dir(15) = '1' else 'Z';
    shield_io(28) <= gpio_out(16) when gpio_dir(16) = '1' else 'Z';
    shield_io(29) <= gpio_out(17) when gpio_dir(17) = '1' else 'Z';
    shield_io(30) <= gpio_out(18) when gpio_dir(18) = '1' else 'Z';
    shield_io(31) <= gpio_out(19) when gpio_dir(19) = '1' else 'Z';
    shield_io(32) <= gpio_out(20) when gpio_dir(20) = '1' else 'Z';
    shield_io(33) <= gpio_out(21) when gpio_dir(21) = '1' else 'Z';
    shield_io(34) <= gpio_out(22) when gpio_dir(22) = '1' else 'Z';
    shield_io(35) <= gpio_out(23) when gpio_dir(23) = '1' else 'Z';
    shield_io(36) <= gpio_out(24) when gpio_dir(24) = '1' else 'Z';
    shield_io(37) <= gpio_out(25) when gpio_dir(25) = '1' else 'Z';
    shield_io(38) <= gpio_out(26) when gpio_dir(26) = '1' else 'Z';
    shield_io(39) <= gpio_out(27) when gpio_dir(27) = '1' else 'Z';
    shield_io(40) <= gpio_out(28) when gpio_dir(28) = '1' else 'Z';
    shield_io(41) <= gpio_out(29) when gpio_dir(29) = '1' else 'Z';
    shield_io(42) <= gpio_out(30) when gpio_dir(30) = '1' else 'Z';
    led7 <= gpio_out(31) and gpio_dir(31);

end architecture behaviour;
