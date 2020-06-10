library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core_dram_tb is
    generic (
	MEMORY_SIZE    : natural := (384*1024);
        MAIN_RAM_FILE  : string  := "main_ram.bin";
        DRAM_INIT_FILE : string  := "";
        DRAM_INIT_SIZE : natural := 16#c000#
        );
end core_dram_tb;

architecture behave of core_dram_tb is
    signal clk, rst: std_logic;
    signal system_clk, soc_rst : std_ulogic;

    -- testbench signals
    constant clk_period : time := 10 ns;

    -- Sim DRAM
    signal wb_dram_in : wishbone_master_out;
    signal wb_dram_out : wishbone_slave_out;
    signal wb_dram_ctrl_in : wb_io_master_out;
    signal wb_dram_ctrl_out : wb_io_slave_out;
    signal wb_dram_is_csr   : std_ulogic;
    signal wb_dram_is_init  : std_ulogic;
    signal core_alt_reset : std_ulogic;

    -- ROM size
    function get_rom_size return natural is
    begin
        if MEMORY_SIZE = 0 then
            return DRAM_INIT_SIZE;
        else
            return 0;
        end if;
    end function;

    constant ROM_SIZE : natural := get_rom_size;
begin

    soc0: entity work.soc
	generic map(
	    SIM => true,
	    MEMORY_SIZE => MEMORY_SIZE,
	    RAM_INIT_FILE => MAIN_RAM_FILE,
	    RESET_LOW => false,
            HAS_DRAM => true,
	    DRAM_SIZE => 256 * 1024 * 1024,
            DRAM_INIT_SIZE => ROM_SIZE,
	    CLK_FREQ => 100000000
	    )
	port map(
	    rst => soc_rst,
	    system_clk => system_clk,
	    uart0_rxd => '0',
	    uart0_txd => open,
	    wb_dram_in => wb_dram_in,
	    wb_dram_out => wb_dram_out,
	    wb_dram_ctrl_in => wb_dram_ctrl_in,
	    wb_dram_ctrl_out => wb_dram_ctrl_out,
            wb_dram_is_csr => wb_dram_is_csr,
            wb_dram_is_init => wb_dram_is_init,
	    alt_reset => core_alt_reset
	    );

    dram: entity work.litedram_wrapper
        generic map(
            DRAM_ABITS => 24,
            DRAM_ALINES => 1,
            PAYLOAD_FILE => DRAM_INIT_FILE,
            PAYLOAD_SIZE => ROM_SIZE
            )
        port map(
            clk_in		=> clk,
            rst             => rst,
            system_clk	=> system_clk,
            system_reset	=> soc_rst,
            core_alt_reset	=> core_alt_reset,
            pll_locked	=> open,

            wb_in		=> wb_dram_in,
            wb_out		=> wb_dram_out,
            wb_ctrl_in	=> wb_dram_ctrl_in,
            wb_ctrl_out	=> wb_dram_ctrl_out,
            wb_ctrl_is_csr  => wb_dram_is_csr,
            wb_ctrl_is_init => wb_dram_is_init,

            init_done 	=> open,
            init_error	=> open,

            ddram_a		=> open,
            ddram_ba	=> open,
            ddram_ras_n	=> open,
            ddram_cas_n	=> open,
            ddram_we_n	=> open,
            ddram_cs_n	=> open,
            ddram_dm	=> open,
            ddram_dq	=> open,
            ddram_dqs_p	=> open,
            ddram_dqs_n	=> open,
            ddram_clk_p	=> open,
            ddram_clk_n	=> open,
            ddram_cke	=> open,
            ddram_odt	=> open,
            ddram_reset_n	=> open
            );

    clk_process: process
    begin
	clk <= '0';
	wait for clk_period/2;
	clk <= '1';
	wait for clk_period/2;
    end process;

    rst_process: process
    begin
	rst <= '1';
	wait for 10*clk_period;
	rst <= '0';
	wait;
    end process;

    jtag: entity work.sim_jtag;

end;
