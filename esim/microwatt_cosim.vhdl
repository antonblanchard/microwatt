-- =========================================================
-- Microwatt eSim / NGHDL ultra-minimal wrapper
-- Parser-safe scalar version
-- =========================================================

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity microwatt_cosim is
    port (
        clk      : in  std_logic;
        rst      : in  std_logic;
        uart_tx  : out std_logic
    );
end entity microwatt_cosim;

architecture rtl of microwatt_cosim is

    --------------------------------------------------------------------
    -- Internal SoC signals
    --------------------------------------------------------------------
    signal run_s       : std_ulogic;
    signal uart_tx_s   : std_ulogic;

    signal gpio_out_s  : std_ulogic_vector(31 downto 0);
    signal gpio_dir_s  : std_ulogic_vector(31 downto 0);
    signal gpio_in_s   : std_ulogic_vector(31 downto 0) := (others => '0');

    --------------------------------------------------------------------
    -- Dummy DRAM Wishbone signals
    --------------------------------------------------------------------
    signal wb_dram_in_s   : wishbone_master_out;
    signal wb_dram_out_s  : wishbone_slave_out := wishbone_slave_out_init;

    --------------------------------------------------------------------
    -- Dummy external IO signals
    --------------------------------------------------------------------
    signal wb_ext_io_in_s        : wb_io_master_out;
    signal wb_ext_io_out_s       : wb_io_slave_out := wb_io_slave_out_init;
    signal wb_ext_is_dram_csr_s  : std_ulogic;
    signal wb_ext_is_dram_init_s : std_ulogic;
    signal wb_ext_is_eth_s       : std_ulogic;
    signal wb_ext_is_sdcard_s    : std_ulogic;
    signal wb_ext_is_lcd_s       : std_ulogic;

    --------------------------------------------------------------------
    -- Dummy DMA signals
    --------------------------------------------------------------------
    signal wishbone_dma_in_s   : wb_io_slave_out;
    signal wishbone_dma_out_s  : wb_io_master_out := wb_io_master_out_init;

begin

    --------------------------------------------------------------------
    -- Microwatt SoC instance
    --------------------------------------------------------------------
    soc_inst: entity work.soc
        generic map (
            MEMORY_SIZE => 524288,
            RAM_INIT_FILE => "",
            CLK_FREQ => 100000000,
            SIM => true,
            NCPUS => 1,
            HAS_FPU => true,
            HAS_BTC => true,
            DISABLE_FLATTEN_CORE => false,
            HAS_DRAM => false,
            HAS_SPI_FLASH => false,
            HAS_LITEETH => false,
            HAS_UART1 => false,
            HAS_SD_CARD => false,
            HAS_SD_CARD2 => false,
            HAS_LCD => false,
            HAS_GPIO => false,
            NGPIO => 32
        )
        port map (
            rst => rst,
            system_clk => clk,

            run_out => run_s,
            run_outs => open,

            wb_dram_in => wb_dram_in_s,
            wb_dram_out => wb_dram_out_s,

            wb_ext_io_in => wb_ext_io_in_s,
            wb_ext_io_out => wb_ext_io_out_s,
            wb_ext_is_dram_csr => wb_ext_is_dram_csr_s,
            wb_ext_is_dram_init => wb_ext_is_dram_init_s,
            wb_ext_is_eth => wb_ext_is_eth_s,
            wb_ext_is_sdcard => wb_ext_is_sdcard_s,
            wb_ext_is_lcd => wb_ext_is_lcd_s,

            wishbone_dma_in => wishbone_dma_in_s,
            wishbone_dma_out => wishbone_dma_out_s,

            ext_irq_eth => '0',
            ext_irq_sdcard => '0',
            ext_irq_sdcard2 => '0',

            uart0_txd => uart_tx_s,
            uart0_rxd => '1',

            uart1_txd => open,
            uart1_rxd => '0',

            spi_flash_sck => open,
            spi_flash_cs_n => open,
            spi_flash_sdat_o => open,
            spi_flash_sdat_oe => open,
            spi_flash_sdat_i => (others => '1'),

            gpio_out => gpio_out_s,
            gpio_dir => gpio_dir_s,
            gpio_in => gpio_in_s,

            sw_soc_reset => open
        );

    --------------------------------------------------------------------
    -- Scalar output
    --------------------------------------------------------------------
    uart_tx <= std_logic(uart_tx_s);

end architecture rtl;
