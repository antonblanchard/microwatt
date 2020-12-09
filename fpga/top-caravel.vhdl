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
        HAS_UART1          : boolean := true;
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

        -- Wishbone over LA
        wb_la_adr   : out wishbone_addr_type;
        wb_la_dat_o : out wishbone_data_type;
        wb_la_cyc   : out std_ulogic;
        wb_la_stb   : out std_ulogic;
        wb_la_sel   : out wishbone_sel_type;
        wb_la_we    : out std_ulogic;

        wb_la_dat_i : in wishbone_data_type;
        wb_la_ack   : in std_ulogic;
        wb_la_stall : in std_ulogic

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

    -- wishbone over logic analyzer connection
    signal wb_la_out : wishbone_master_out;
    signal wb_la_in  : wishbone_slave_out;

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

            -- Use DRAM wishbone for wishbone over LA
            wb_dram_in           => wb_la_out,
            wb_dram_out          => wb_la_in
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
    wb_la_adr      <= wb_la_out.adr;
    wb_la_dat_o    <= wb_la_out.dat;
    wb_la_cyc      <= wb_la_out.cyc;
    wb_la_stb      <= wb_la_out.stb;
    wb_la_sel      <= wb_la_out.sel;
    wb_la_we       <= wb_la_out.we;

    wb_la_in.dat   <= wb_la_dat_i;
    wb_la_in.ack   <= wb_la_ack;
    wb_la_in.stall <= wb_la_stall;

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
