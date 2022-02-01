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
        HAS_FPU            : boolean  := true;
        HAS_BTC            : boolean  := false;
        NO_BRAM            : boolean  := false;
        DISABLE_FLATTEN_CORE : boolean := false;
        ALT_RESET_ADDRESS  : std_logic_vector(63 downto 0) := (27 downto 0 => '0', others => '1');
        SPI_FLASH_OFFSET   : integer := 0;
        SPI_FLASH_DEF_CKDV : natural := 4;
        SPI_FLASH_DEF_QUAD : boolean := false;
        SPI_BOOT_CLOCKS    : boolean := false;
        LOG_LENGTH         : natural := 0;
        UART_IS_16550      : boolean := true;
        HAS_UART1          : boolean := false;
        HAS_JTAG           : boolean := true;
        ICACHE_NUM_LINES   : natural := 4;
        ICACHE_NUM_WAYS    : natural := 2;
        ICACHE_TLB_SIZE    : natural := 4;
        DCACHE_NUM_LINES   : natural := 4;
        DCACHE_NUM_WAYS    : natural := 2;
        DCACHE_TLB_SET_SIZE : natural := 2;
        DCACHE_TLB_NUM_WAYS : natural := 2
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
        spi_flash_cs_n    : out std_ulogic;
        spi_flash_clk     : out std_ulogic;
        spi_flash_sdat_i  : in std_ulogic_vector(3 downto 0);
        spi_flash_sdat_o  : out std_ulogic_vector(3 downto 0);
        spi_flash_sdat_oe : out std_ulogic_vector(3 downto 0);

        -- JTAG signals:
        jtag_tck  : in std_ulogic;
        jtag_tdi  : in std_ulogic;
        jtag_tms  : in std_ulogic;
        jtag_trst : in std_ulogic;
        jtag_tdo  : out std_ulogic;

        -- Add an I/O pin to select fetching from flash on reset
        alt_reset      : in std_ulogic
        );
end entity toplevel;

architecture behaviour of toplevel is
    -- reset signals
    signal system_rst : std_ulogic;
begin

    system_rst <= not ext_rst when RESET_LOW else ext_rst;

    -- Main SoC
    soc0: entity work.soc
        generic map(
            MEMORY_SIZE        => MEMORY_SIZE,
            RAM_INIT_FILE      => RAM_INIT_FILE,
            SIM                => false,
            CLK_FREQ           => CLK_FREQUENCY,
            HAS_FPU            => HAS_FPU,
            HAS_BTC            => HAS_BTC,
            HAS_DRAM           => false,
            DRAM_SIZE          => 0,
            DRAM_INIT_SIZE     => 0,
            DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            ALT_RESET_ADDRESS  => ALT_RESET_ADDRESS,
            HAS_SPI_FLASH      => true,
            SPI_FLASH_DLINES   => 4,
            SPI_FLASH_OFFSET   => SPI_FLASH_OFFSET,
            SPI_FLASH_DEF_CKDV => SPI_FLASH_DEF_CKDV,
            SPI_FLASH_DEF_QUAD => SPI_FLASH_DEF_QUAD,
            SPI_BOOT_CLOCKS    => SPI_BOOT_CLOCKS,
            LOG_LENGTH         => LOG_LENGTH,
            UART0_IS_16550     => UART_IS_16550,
            HAS_UART1          => HAS_UART1,
            HAS_JTAG           => HAS_JTAG,
            ICACHE_NUM_LINES   => ICACHE_NUM_LINES,
            ICACHE_NUM_WAYS    => ICACHE_NUM_WAYS,
            ICACHE_TLB_SIZE    => ICACHE_TLB_SIZE,
            DCACHE_NUM_LINES   => DCACHE_NUM_LINES,
            DCACHE_NUM_WAYS    => DCACHE_NUM_WAYS,
            DCACHE_TLB_SET_SIZE => DCACHE_TLB_SET_SIZE,
            DCACHE_TLB_NUM_WAYS => DCACHE_TLB_NUM_WAYS
            )
        port map (
            -- System signals
            system_clk        => ext_clk,
            rst               => system_rst,

            -- UART signals
            uart0_txd         => uart0_txd,
            uart0_rxd         => uart0_rxd,

            -- UART1 signals
            uart1_txd         => uart1_txd,
            uart1_rxd         => uart1_rxd,

            -- SPI signals
            spi_flash_sck     => spi_flash_clk,
            spi_flash_cs_n    => spi_flash_cs_n,
            spi_flash_sdat_o  => spi_flash_sdat_o,
            spi_flash_sdat_oe => spi_flash_sdat_oe,
            spi_flash_sdat_i  => spi_flash_sdat_i,

            -- JTAG signals
            jtag_tck          => jtag_tck,
            jtag_tdi          => jtag_tdi,
            jtag_tms          => jtag_tms,
            jtag_trst         => jtag_trst,
            jtag_tdo          => jtag_tdo,

            -- Reset PC to flash offset 0 (ie 0xf000000)
            alt_reset         => alt_reset
            );

end architecture behaviour;
