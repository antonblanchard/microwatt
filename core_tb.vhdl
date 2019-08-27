library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core_tb is
end core_tb;

architecture behave of core_tb is
	signal clk, rst: std_logic;

	signal wishbone_in : wishbone_slave_out;
	signal wishbone_out : wishbone_master_out;

	signal registers : regfile;
	signal terminate : std_ulogic;

	-- testbench signals
	constant clk_period : time := 10 ns;
begin
	core_0: entity work.core
		generic map (SIM => true)
		port map (clk => clk, rst => rst, wishbone_in => wishbone_in,
			  wishbone_out => wishbone_out, registers => registers, terminate_out => terminate);

	simple_ram_0: entity work.simple_ram_behavioural
		generic map ( filename => "simple_ram_behavioural.bin", size => 524288)
		port map (clk => clk, rst => rst, wishbone_in => wishbone_out, wishbone_out => wishbone_in);

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

	dump_registers: process(all)
	begin
		if terminate = '1' then
			loop_0: for i in 0 to 31 loop
				report "REG " & to_hstring(registers(i));
			end loop loop_0;
			assert false report "end of test" severity failure;
		end if;
	end process;
end;
