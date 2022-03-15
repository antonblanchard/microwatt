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
        ICACHE_NUM_WAYS    : natural := 1;
        ICACHE_TLB_SIZE    : natural := 4;
        DCACHE_NUM_LINES   : natural := 4;
        DCACHE_NUM_WAYS    : natural := 1;
        DCACHE_TLB_SET_SIZE : natural := 2;
        DCACHE_TLB_NUM_WAYS : natural := 2;
        HAS_GPIO           : boolean := true;
        NGPIO              : natural := 32
        );
    port(
        ext_clk   : in  std_ulogic;
        ext_rst   : in  std_ulogic;

        -- UART0 signals:
        uart0_txd : out std_ulogic;
        uart0_rxd : in  std_ulogic;

        -- SPI
        spi_flash_cs_n    : out std_ulogic;
        spi_flash_clk     : out std_ulogic;
        spi_flash_sdat_i  : in std_ulogic_vector(3 downto 0);
        spi_flash_sdat_o  : out std_ulogic_vector(3 downto 0);
        spi_flash_sdat_oe : out std_ulogic_vector(3 downto 0);

        -- GPIO
        gpio_in  : in std_ulogic_vector(NGPIO - 1 downto 0);
        gpio_out : out std_ulogic_vector(NGPIO - 1 downto 0);
        gpio_dir : out std_ulogic_vector(NGPIO - 1 downto 0);

        -- JTAG signals:
        jtag_tck  : in std_ulogic;
        jtag_tdi  : in std_ulogic;
        jtag_tms  : in std_ulogic;
        jtag_trst : in std_ulogic;
        jtag_tdo  : out std_ulogic;

	-- simplebus
        simplebus_clk        : out std_logic;
        simplebus_bus_out    : out std_logic_vector(7 downto 0);
        simplebus_parity_out : out std_logic;
        simplebus_bus_in     : in std_logic_vector(7 downto 0);
        simplebus_parity_in  : in std_logic;
        simplebus_enabled    : out std_logic;
        simplebus_irq        : in std_ulogic;

        -- Add an I/O pin to select fetching from flash on reset
        alt_reset      : in std_ulogic
        );
end entity toplevel;

architecture behaviour of toplevel is
    -- reset signals
    signal system_rst : std_ulogic;

    -- simplebus wishbone connection
    signal wb_simplebus_out : wishbone_master_out;
    signal wb_simplebus_in  : wishbone_slave_out;

    -- simplebus split out wishbone
    signal wb_simplebus_adr   : wishbone_addr_type;
    signal wb_simplebus_dat_o : wishbone_data_type;
    signal wb_simplebus_cyc   : std_ulogic;
    signal wb_simplebus_stb   : std_ulogic;
    signal wb_simplebus_sel   : wishbone_sel_type;
    signal wb_simplebus_we    : std_ulogic;
    signal wb_simplebus_dat_i : wishbone_data_type;
    signal wb_simplebus_ack   : std_ulogic;
    signal wb_simplebus_stall : std_ulogic;

    -- simplebus I/O wishbone
    signal wb_ext_io_in        : wb_io_master_out;
    signal wb_ext_io_out       : wb_io_slave_out;
    signal wb_ext_is_simplebus : std_ulogic;

    -- simplebus I/O split out wishbone
    signal wb_simplebus_ctrl_adr   : std_ulogic_vector(29 downto 0);
    signal wb_simplebus_ctrl_dat_o : std_ulogic_vector(31 downto 0);
    signal wb_simplebus_ctrl_cyc   : std_ulogic;
    signal wb_simplebus_ctrl_stb   : std_ulogic;
    signal wb_simplebus_ctrl_sel   : std_ulogic_vector(3 downto 0);
    signal wb_simplebus_ctrl_we    : std_ulogic;
    signal wb_simplebus_ctrl_dat_i : std_ulogic_vector(31 downto 0);
    signal wb_simplebus_ctrl_ack   : std_ulogic;
    signal wb_simplebus_ctrl_stall : std_ulogic;

    component simplebus_host port(
        clk           : in std_logic;
        rst           : in std_logic;

        wb_cyc        : in std_logic;
        wb_stb        : in std_logic;
        wb_we         : in std_logic;
        wb_adr        : in wishbone_addr_type;
        wb_dat_w      : in wishbone_data_type;
        wb_sel        : in std_logic_vector;
        wb_ack        : out std_logic;
        wb_stall      : out std_logic;
        wb_dat_r      : out wishbone_data_type;

        wb_ctrl_cyc   : in std_logic;
        wb_ctrl_stb   : in std_logic;
        wb_ctrl_we    : in std_logic;
        wb_ctrl_adr   : in std_logic_vector(29 downto 0);
        wb_ctrl_dat_w : in std_logic_vector(31 downto 0);
        wb_ctrl_sel   : in std_logic_vector(3 downto 0);
        wb_ctrl_ack   : out std_logic;
        wb_ctrl_stall : out std_logic;
        wb_ctrl_dat_r : out std_logic_vector(31 downto 0);

        clk_out       : out std_logic;
        bus_out       : out std_logic_vector(7 downto 0);
        parity_out    : out std_logic;
        bus_in        : in std_logic_vector(7 downto 0);
        parity_in     : in std_logic;
        enabled       : out std_logic
        );
    end component simplebus_host;

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
            HAS_DRAM           => true,
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
            HAS_GPIO           => HAS_GPIO,
            NGPIO              => NGPIO,
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

            -- SPI signals
            spi_flash_sck     => spi_flash_clk,
            spi_flash_cs_n    => spi_flash_cs_n,
            spi_flash_sdat_o  => spi_flash_sdat_o,
            spi_flash_sdat_oe => spi_flash_sdat_oe,
            spi_flash_sdat_i  => spi_flash_sdat_i,

            -- GPIO signals
            gpio_in           => gpio_in,
            gpio_out          => gpio_out,
            gpio_dir          => gpio_dir,

            -- JTAG signals
            jtag_tck          => jtag_tck,
            jtag_tdi          => jtag_tdi,
            jtag_tms          => jtag_tms,
            jtag_trst         => jtag_trst,
            jtag_tdo          => jtag_tdo,

	    -- simplebus 64-bit wishbone
            wb_dram_in         => wb_simplebus_out,
            wb_dram_out        => wb_simplebus_in,

            -- simplebus 32-bit external IO wishbone
            wb_ext_io_in       => wb_ext_io_in,
            wb_ext_io_out      => wb_ext_io_out,
            wb_ext_is_dram_csr => wb_ext_is_simplebus,

            ext_irq_eth        => simplebus_irq,

            -- Reset PC to flash offset 0 (ie 0xf000000)
            alt_reset         => alt_reset
            );

        -- simplebus wishbone
        wb_simplebus_adr      <= wb_simplebus_out.adr;
        wb_simplebus_dat_o    <= wb_simplebus_out.dat;
        wb_simplebus_cyc      <= wb_simplebus_out.cyc;
        wb_simplebus_stb      <= wb_simplebus_out.stb;
        wb_simplebus_sel      <= wb_simplebus_out.sel;
        wb_simplebus_we       <= wb_simplebus_out.we;

        wb_simplebus_in.dat   <= wb_simplebus_dat_i;
        wb_simplebus_in.ack   <= wb_simplebus_ack;
        wb_simplebus_in.stall <= wb_simplebus_stall;

        -- simplebus I/O wishbone
        wb_simplebus_ctrl_adr   <= wb_ext_io_in.adr;
        wb_simplebus_ctrl_dat_o <= wb_ext_io_in.dat;
        wb_simplebus_ctrl_cyc   <= wb_ext_io_in.cyc and wb_ext_is_simplebus;
        wb_simplebus_ctrl_stb   <= wb_ext_io_in.stb and wb_ext_is_simplebus;
        wb_simplebus_ctrl_sel   <= wb_ext_io_in.sel;
        wb_simplebus_ctrl_we    <= wb_ext_io_in.we;

        wb_ext_io_out.dat       <= wb_simplebus_ctrl_dat_i;
        wb_ext_io_out.ack       <= wb_simplebus_ctrl_ack;
        wb_ext_io_out.stall     <= wb_simplebus_ctrl_stall;

        simplebus_0: simplebus_host
            port map(
                clk           => ext_clk,
                rst           => system_rst,

                wb_cyc        => wb_simplebus_cyc,
                wb_stb        => wb_simplebus_stb,
                wb_we         => wb_simplebus_we,
                wb_adr        => wb_simplebus_adr,
                wb_dat_w      => wb_simplebus_dat_o,
                wb_sel        => wb_simplebus_sel,
                wb_ack        => wb_simplebus_ack,
                wb_stall      => wb_simplebus_stall,
                wb_dat_r      => wb_simplebus_dat_i,

                wb_ctrl_cyc   => wb_simplebus_ctrl_cyc,
                wb_ctrl_stb   => wb_simplebus_ctrl_stb,
                wb_ctrl_we    => wb_simplebus_ctrl_we,
                wb_ctrl_adr   => wb_simplebus_ctrl_adr,
                wb_ctrl_dat_w => wb_simplebus_ctrl_dat_o,
                wb_ctrl_sel   => wb_simplebus_ctrl_sel,
                wb_ctrl_ack   => wb_simplebus_ctrl_ack,
                wb_ctrl_stall => wb_simplebus_ctrl_stall,
                wb_ctrl_dat_r => wb_simplebus_ctrl_dat_i,

                clk_out       => simplebus_clk,
                bus_out       => simplebus_bus_out,
                parity_out    => simplebus_parity_out,
                bus_in        => simplebus_bus_in,
                parity_in     => simplebus_parity_in,
		enabled       => simplebus_enabled
        );

end architecture behaviour;
