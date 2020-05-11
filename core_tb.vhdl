library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core_tb is
end core_tb;

architecture behave of core_tb is
	signal clk, rst: std_logic;

	-- testbench signals
	constant clk_period : time := 10 ns;

        -- Dummy DRAM
	signal wb_dram_in : wishbone_master_out;
	signal wb_dram_out : wishbone_slave_out;
	signal wb_dram_ctrl_in : wb_io_master_out;
	signal wb_dram_ctrl_out : wb_io_slave_out;
begin

    soc0: entity work.soc
	generic map(
	    SIM => true,
	    MEMORY_SIZE => (384*1024),
	    RAM_INIT_FILE => "main_ram.bin",
	    RESET_LOW => false,
	    CLK_FREQ => 100000000
	    )
	port map(
	    rst => rst,
	    system_clk => clk,
	    uart0_rxd => '0',
	    uart0_txd => open,
	    wb_dram_in => wb_dram_in,
	    wb_dram_out => wb_dram_out,
	    wb_dram_ctrl_in => wb_dram_ctrl_in,
	    wb_dram_ctrl_out => wb_dram_ctrl_out,
	    alt_reset => '0'
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

    -- Dummy DRAM
    wb_dram_out.ack <= wb_dram_in.cyc and wb_dram_in.stb;
    wb_dram_out.dat <= x"FFFFFFFFFFFFFFFF";
    wb_dram_out.stall <= '0';
    wb_dram_ctrl_out.ack <= wb_dram_ctrl_in.cyc and wb_dram_ctrl_in.stb;
    wb_dram_ctrl_out.dat <= x"FFFFFFFF";
    wb_dram_ctrl_out.stall <= '0';

end;
