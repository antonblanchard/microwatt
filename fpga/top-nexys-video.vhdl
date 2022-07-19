library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
	MEMORY_SIZE   : integer := 16384;
	RAM_INIT_FILE : string   := "firmware.hex";
	RESET_LOW     : boolean  := true;
	CLK_FREQUENCY : positive := 100000000;
        HAS_FPU       : boolean  := true;
        HAS_BTC       : boolean  := true;
	USE_LITEDRAM  : boolean  := false;
	NO_BRAM       : boolean  := false;
	DISABLE_FLATTEN_CORE : boolean := false;
        SPI_FLASH_OFFSET   : integer := 10485760;
        SPI_FLASH_DEF_CKDV : natural := 1;
        SPI_FLASH_DEF_QUAD : boolean := true;
        LOG_LENGTH         : natural := 2048;
        UART_IS_16550      : boolean := true;
        USE_LITEETH        : boolean := false;
        USE_LITESDCARD     : boolean := false
	);
    port(
	ext_clk   : in  std_ulogic;
        ext_rst_n   : in  std_ulogic;

	-- UART0 signals:
	uart_main_tx : out std_ulogic;
	uart_main_rx : in  std_ulogic;

        -- LEDs
        led0 : out std_ulogic;
        led1 : out std_ulogic;
        led2 : out std_ulogic;
        led3 : out std_ulogic;
        led4 : out std_ulogic;
        led5 : out std_ulogic;
        led6 : out std_ulogic;
        led7 : out std_ulogic;

        -- SPI
        spi_flash_cs_n   : out std_ulogic;
        spi_flash_mosi   : inout std_ulogic;
        spi_flash_miso   : inout std_ulogic;
        spi_flash_wp_n   : inout std_ulogic;
        spi_flash_hold_n : inout std_ulogic;

        -- Ethernet
        eth_clocks_tx    : out std_ulogic;
        eth_clocks_rx    : in std_ulogic;
        eth_rst_n        : out std_ulogic;
        eth_int_n        : in std_ulogic;
        eth_mdio         : inout std_ulogic;
        eth_mdc          : out std_ulogic;
        eth_rx_ctl       : in std_ulogic;
        eth_rx_data      : in std_ulogic_vector(3 downto 0);
        eth_tx_ctl       : out std_ulogic;
        eth_tx_data      : out std_ulogic_vector(3 downto 0);

        -- SD card
        sdcard_data   : inout std_ulogic_vector(3 downto 0);
        sdcard_cmd    : inout std_ulogic;
        sdcard_clk    : out   std_ulogic;
        sdcard_cd     : in    std_ulogic;
        sdcard_reset  : out   std_ulogic;

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
    signal wb_dram_in       : wishbone_master_out;
    signal wb_dram_out      : wishbone_slave_out;

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

    -- Control/status
    signal core_alt_reset : std_ulogic;

    -- SPI flash
    signal spi_sck     : std_ulogic;
    signal spi_cs_n    : std_ulogic;
    signal spi_sdat_o  : std_ulogic_vector(3 downto 0);
    signal spi_sdat_oe : std_ulogic_vector(3 downto 0);
    signal spi_sdat_i  : std_ulogic_vector(3 downto 0);

    -- ddram clock signals as vectors
    signal ddram_clk_p_vec : std_logic_vector(0 downto 0);
    signal ddram_clk_n_vec : std_logic_vector(0 downto 0);

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
	    MEMORY_SIZE   => BRAM_SIZE,
	    RAM_INIT_FILE => RAM_INIT_FILE,
	    SIM           => false,
	    CLK_FREQ      => CLK_FREQUENCY,
            HAS_FPU       => HAS_FPU,
            HAS_BTC       => HAS_BTC,
	    HAS_DRAM      => USE_LITEDRAM,
	    DRAM_SIZE     => 512 * 1024 * 1024,
            DRAM_INIT_SIZE => PAYLOAD_SIZE,
	    DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            HAS_SPI_FLASH      => true,
            SPI_FLASH_DLINES   => 4,
            SPI_FLASH_OFFSET   => SPI_FLASH_OFFSET,
            SPI_FLASH_DEF_CKDV => SPI_FLASH_DEF_CKDV,
            SPI_FLASH_DEF_QUAD => SPI_FLASH_DEF_QUAD,
            LOG_LENGTH         => LOG_LENGTH,
            UART0_IS_16550     => UART_IS_16550,
            HAS_LITEETH        => USE_LITEETH,
            HAS_SD_CARD        => USE_LITESDCARD
	    )
	port map (
            -- System signals
	    system_clk        => system_clk,
	    rst               => soc_rst,

            -- UART signals
            uart0_txd         => uart_main_tx,
	    uart0_rxd         => uart_main_rx,

            -- SPI signals
            spi_flash_sck     => spi_sck,
            spi_flash_cs_n    => spi_cs_n,
            spi_flash_sdat_o  => spi_sdat_o,
            spi_flash_sdat_oe => spi_sdat_oe,
            spi_flash_sdat_i  => spi_sdat_i,

            -- External interrupts
            ext_irq_eth       => ext_irq_eth,
            ext_irq_sdcard    => ext_irq_sdcard,

            -- IO wishbone
	    wb_dram_in          => wb_dram_in,
	    wb_dram_out         => wb_dram_out,
	    wb_ext_io_in        => wb_ext_io_in,
	    wb_ext_io_out       => wb_ext_io_out,
	    wb_ext_is_dram_csr  => wb_ext_is_dram_csr,
	    wb_ext_is_dram_init => wb_ext_is_dram_init,
            wb_ext_is_eth       => wb_ext_is_eth,
            wb_ext_is_sdcard    => wb_ext_is_sdcard,

            -- DMA wishbone
            wishbone_dma_in     => wb_sddma_in,
            wishbone_dma_out    => wb_sddma_out,

	    alt_reset           => core_alt_reset
	    );

    -- SPI Flash. The SPI clk needs to be fed through the STARTUPE2
    -- primitive of the FPGA as it's not a normal pin
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

	led0 <= '1';
	led1 <= not soc_rst;
        led2 <= '0';
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
                ext_rst_in => ext_rst_n,
		pll_rst_out => pll_rst,
                rst_out => open
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

	ddram_clk_p_vec <= (others => ddram_clk_p);
	ddram_clk_n_vec <= (others => ddram_clk_n);

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
		clk_in		=> ext_clk,
		rst             => pll_rst,
		system_clk	=> system_clk,
                system_reset	=> dram_sys_rst,
                core_alt_reset  => core_alt_reset,
		pll_locked	=> system_clk_locked,

		wb_in		=> wb_dram_in,
		wb_out		=> wb_dram_out,
		wb_ctrl_in	=> wb_ext_io_in,
                wb_ctrl_out	=> wb_dram_ctrl_out,
		wb_ctrl_is_csr  => wb_ext_is_dram_csr,
		wb_ctrl_is_init => wb_ext_is_dram_init,

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
		ddram_clk_p	=> ddram_clk_p_vec,
		ddram_clk_n	=> ddram_clk_n_vec,
		ddram_cke	=> ddram_cke,
		ddram_odt	=> ddram_odt,
		ddram_reset_n	=> ddram_reset_n
		);

        led0 <= not dram_init_done;
	led1 <= dram_init_error; -- Make it blink ?
        led2 <= dram_init_done and not dram_init_error;

    end generate;

    has_liteeth : if USE_LITEETH generate

        component liteeth_core port (
            sys_clock           : in std_ulogic;
            sys_reset           : in std_ulogic;
            rgmii_eth_clocks_tx : out std_ulogic;
            rgmii_eth_clocks_rx : in std_ulogic;
            rgmii_eth_rst_n     : out std_ulogic;
            rgmii_eth_int_n     : in std_ulogic;
            rgmii_eth_mdio      : inout std_ulogic;
            rgmii_eth_mdc       : out std_ulogic;
            rgmii_eth_rx_ctl    : in std_ulogic;
            rgmii_eth_rx_data   : in std_ulogic_vector(3 downto 0);
            rgmii_eth_tx_ctl    : out std_ulogic;
            rgmii_eth_tx_data   : out std_ulogic_vector(3 downto 0);
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
                rgmii_eth_clocks_tx => eth_clocks_tx,
                rgmii_eth_clocks_rx => eth_clocks_rx,
                rgmii_eth_rst_n     => eth_rst_n,
                rgmii_eth_int_n     => eth_int_n,
                rgmii_eth_mdio      => eth_mdio,
                rgmii_eth_mdc       => eth_mdc,
                rgmii_eth_rx_ctl    => eth_rx_ctl,
                rgmii_eth_rx_data   => eth_rx_data,
                rgmii_eth_tx_ctl    => eth_tx_ctl,
                rgmii_eth_tx_data   => eth_tx_data,
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
        signal wb_sdcard_adr : std_ulogic_vector(29 downto 0);

    begin
        litesdcard : litesdcard_core
            port map (
                clk           => system_clk,
                rst           => soc_rst,
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
                wb_dma_adr    => wb_sddma_nr.adr,
                wb_dma_dat_w  => wb_sddma_nr.dat,
                wb_dma_dat_r  => wb_sddma_ir.dat,
                wb_dma_sel    => wb_sddma_nr.sel,
                wb_dma_cyc    => wb_sddma_nr.cyc,
                wb_dma_stb    => wb_sddma_nr.stb,
                wb_dma_ack    => wb_sddma_ir.ack,
                wb_dma_we     => wb_sddma_nr.we,
                wb_dma_cti    => open,
                wb_dma_bte    => open,
                wb_dma_err    => '0',
                sdcard_data   => sdcard_data,
                sdcard_cmd    => sdcard_cmd,
                sdcard_clk    => sdcard_clk,
                sdcard_cd     => sdcard_cd,
                irq           => ext_irq_sdcard
                );

        -- Gate cyc with chip select from SoC
        wb_sdcard_cyc <= wb_ext_io_in.cyc and wb_ext_is_sdcard;

        wb_sdcard_adr <= x"0000" & wb_ext_io_in.adr(13 downto 0);

        wb_sdcard_out.stall <= not wb_sdcard_out.ack;

	sdcard_reset <= '0';

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

    no_sdcard : if not USE_LITESDCARD generate
        sdcard_reset <= '1';
    end generate;

    -- Mux WB response on the IO bus
    wb_ext_io_out <= wb_eth_out when wb_ext_is_eth = '1' else
                     wb_sdcard_out when wb_ext_is_sdcard = '1' else
                     wb_dram_ctrl_out;

    led4 <= system_clk_locked;
    led5 <= '1';
    led6 <= not soc_rst;
    led7 <= '0';

end architecture behaviour;
