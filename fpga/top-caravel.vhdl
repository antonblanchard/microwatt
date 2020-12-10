library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;

entity toplevel is
    generic (
        MEMORY_SIZE        : integer  := 8192;
        RAM_INIT_FILE      : string   := "firmware.hex";
        RESET_LOW          : boolean  := true;
        CLK_INPUT          : positive := 100000000;
        CLK_FREQUENCY      : positive := 100000000;
        HAS_FPU            : boolean  := false;
        NO_BRAM            : boolean  := false;
        DISABLE_FLATTEN_CORE : boolean := false;
        SPI_FLASH_OFFSET   : integer := 4194304;
        SPI_FLASH_DEF_CKDV : natural := 1;
        SPI_FLASH_DEF_QUAD : boolean := true;
        LOG_LENGTH         : natural := 16;
        UART_IS_16550      : boolean := true;
        HAS_UART1          : boolean := false;
        HAS_JTAG           : boolean := true
        );
    port(
        ext_clk   : in  std_ulogic;
        ext_rst   : in  std_ulogic;

        -- UART0 signals:
        uart0_txd : out std_ulogic;
        uart0_rxd : in  std_ulogic;

        -- UART1 signals:
        uart1_txd : out std_ulogic;
        uart1_rxd : in std_ulogic;

        -- SPI
        spi_flash_cs_n   : out std_ulogic;
        spi_flash_clk    : out std_ulogic;
        spi_flash_mosi   : inout std_ulogic;
        spi_flash_miso   : inout std_ulogic;
        spi_flash_wp_n   : inout std_ulogic;
        spi_flash_hold_n : inout std_ulogic;

        -- JTAG signals:
        jtag_tck  : in std_ulogic;
        jtag_tdi  : in std_ulogic;
        jtag_tms  : in std_ulogic;
        jtag_trst : in std_ulogic;
        jtag_tdo  : out std_ulogic;

	-- bills bus
	oib_clk        : out std_ulogic;
	ob_data        : out std_ulogic_vector(7 downto 0);
	ob_pty         : out std_ulogic;

	ib_data        : in  std_ulogic_vector(7 downto 0);
	ib_pty         : in  std_ulogic

        -- XXX Add simple external bus

	-- Add an I/O pin to select fetching from flash on reset
        );
end entity toplevel;

architecture behaviour of toplevel is

    -- Reset signals:
    signal soc_rst : std_ulogic;
    signal pll_rst : std_ulogic;

    -- Internal clock signals:
    signal system_clk        : std_ulogic;
    signal system_clk_locked : std_ulogic;
    signal ext_rst_n : std_ulogic;

    -- wishbone over logic analyzer connection
    signal wb_dram_out : wishbone_master_out;
    signal wb_dram_in  : wishbone_slave_out;

    -- Wishbone over LA
    signal wb_mc_adr   : wishbone_addr_type;
    signal wb_mc_dat_o : wishbone_data_type;
    signal wb_mc_cyc   : std_ulogic;
    signal wb_mc_stb   : std_ulogic;
    signal wb_mc_sel   : wishbone_sel_type;
    signal wb_mc_we    : std_ulogic;
    signal wb_mc_dat_i : wishbone_data_type;
    signal wb_mc_ack   : std_ulogic;
    signal wb_mc_stall : std_ulogic;

    -- SPI flash
    signal spi_sck     : std_ulogic;
    signal spi_cs_n    : std_ulogic;
    signal spi_sdat_o  : std_ulogic_vector(3 downto 0);
    signal spi_sdat_oe : std_ulogic_vector(3 downto 0);
    signal spi_sdat_i  : std_ulogic_vector(3 downto 0);
begin

    -- Main SoC
    soc0: entity work.soc
        generic map(
            MEMORY_SIZE        => MEMORY_SIZE,
            RAM_INIT_FILE      => RAM_INIT_FILE,
            SIM                => false,
            CLK_FREQ           => CLK_FREQUENCY,
            HAS_FPU            => HAS_FPU,
            HAS_DRAM           => true,
            DRAM_SIZE          => 0,
            DRAM_INIT_SIZE     => 0,
            DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            HAS_SPI_FLASH      => true,
            SPI_FLASH_DLINES   => 4,
            SPI_FLASH_OFFSET   => SPI_FLASH_OFFSET,
            SPI_FLASH_DEF_CKDV => SPI_FLASH_DEF_CKDV,
            SPI_FLASH_DEF_QUAD => SPI_FLASH_DEF_QUAD,
            LOG_LENGTH         => LOG_LENGTH,
            UART0_IS_16550     => UART_IS_16550,
            HAS_UART1          => HAS_UART1,
            HAS_JTAG           => HAS_JTAG
            )
        port map (
            -- System signals
            system_clk        => system_clk,
            rst               => soc_rst,

            -- UART signals
            uart0_txd         => uart0_txd,
            uart0_rxd         => uart0_rxd,

            -- UART1 signals
            uart1_txd         => uart1_txd,
            uart1_rxd         => uart1_rxd,

            -- SPI signals
            spi_flash_sck     => spi_sck,
            spi_flash_cs_n    => spi_cs_n,
            spi_flash_sdat_o  => spi_sdat_o,
            spi_flash_sdat_oe => spi_sdat_oe,
            spi_flash_sdat_i  => spi_sdat_i,

            -- JTAG signals
            jtag_tck          => jtag_tck,
            jtag_tdi          => jtag_tdi,
            jtag_tms          => jtag_tms,
            jtag_trst         => jtag_trst,
            jtag_tdo          => jtag_tdo,

            -- Use DRAM wishbone for Bill's bus
            wb_dram_in           => wb_dram_out,
            wb_dram_out          => wb_dram_in
            );

    ext_rst_n <= not ext_rst;

    mc0: entity work.mc
	generic map(
	    WB_AW          => 32,        -- wishbone_addr_bits
	    WB_DW          => 64,        -- wishbone_data_bits
	    OIB_DW         => 8,
	    OIB_RATIO      => 2,         -- bill said this
	    BAR_INIT       => x"1fff"    -- dram has 512 bit space. CPU gives
					 -- top 3 bits as 0. carve off small
					 -- chunk at top for config space.
	    )
	port map (
	    clk	         => system_clk,
	    rst   	 => ext_rst_n,

	    wb_cyc       => wb_mc_cyc,
	    wb_stb       => wb_mc_stb,
	    wb_we        => wb_mc_we,
	    wb_addr      => wb_mc_adr,
	    wb_wr_data   => wb_mc_dat_o,
	    wb_sel       => wb_mc_sel,
	    wb_ack       => wb_mc_ack,
--	    wb_err       => wb_mc_err, ??
	    wb_stall     => wb_mc_stall,
	    wb_rd_data   => wb_mc_dat_i,
	    oib_clk      => oib_clk,
	    ob_data      => ob_data,
	    ob_pty       => ob_pty,
	    ib_data      => ib_data,
	    ib_pty       => ib_pty
--	    err          => ob _err,
--	    int          => ob int
    );

    -- SPI Flash
    spi_flash_cs_n   <= spi_cs_n;
    spi_flash_mosi   <= spi_sdat_o(0) when spi_sdat_oe(0) = '1' else 'Z';
    spi_flash_miso   <= spi_sdat_o(1) when spi_sdat_oe(1) = '1' else 'Z';
    spi_flash_wp_n   <= spi_sdat_o(2) when spi_sdat_oe(2) = '1' else 'Z';
    spi_flash_hold_n <= spi_sdat_o(3) when spi_sdat_oe(3) = '1' else 'Z';
    spi_sdat_i(0)    <= spi_flash_mosi;
    spi_sdat_i(1)    <= spi_flash_miso;
    spi_sdat_i(2)    <= spi_flash_wp_n;
    spi_sdat_i(3)    <= spi_flash_hold_n;
    spi_flash_clk    <= spi_sck;

    -- Wishbone over LA
    wb_mc_adr      <= wb_dram_out.adr;
    wb_mc_dat_o    <= wb_dram_out.dat;
    wb_mc_cyc      <= wb_dram_out.cyc;
    wb_mc_stb      <= wb_dram_out.stb;
    wb_mc_sel      <= wb_dram_out.sel;
    wb_mc_we       <= wb_dram_out.we;

    wb_dram_in.dat   <= wb_mc_dat_i;
    wb_dram_in.ack   <= wb_mc_ack;
    wb_dram_in.stall <= wb_mc_stall;

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

end architecture behaviour;
