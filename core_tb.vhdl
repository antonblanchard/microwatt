library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core_tb is
end core_tb;

architecture behave of core_tb is
	signal clk, rst: std_logic;

	signal wishbone_dcore_in : wishbone_slave_out;
	signal wishbone_dcore_out : wishbone_master_out;

	signal wishbone_icore_in : wishbone_slave_out;
	signal wishbone_icore_out : wishbone_master_out;

	signal wishbone_core_in : wishbone_slave_out;
	signal wishbone_core_out : wishbone_master_out;

	signal wishbone_ram_in : wishbone_slave_out;
	signal wishbone_ram_out : wishbone_master_out;

	signal wishbone_uart_in : wishbone_slave_out;
	signal wishbone_uart_out : wishbone_master_out;

	signal registers : regfile;
	signal terminate : std_ulogic;

	-- testbench signals
	constant clk_period : time := 10 ns;
begin
	core_0: entity work.core
		generic map (SIM => true)
	    port map (clk => clk, rst => rst,
		      wishbone_insn_in => wishbone_icore_in,
		      wishbone_insn_out => wishbone_icore_out,
		      wishbone_data_in => wishbone_dcore_in,
		      wishbone_data_out => wishbone_dcore_out,
		      registers => registers, terminate_out => terminate);

	simple_ram_0: entity work.simple_ram_behavioural
		generic map ( filename => "simple_ram_behavioural.bin", size => 524288)
		port map (clk => clk, rst => rst, wishbone_in => wishbone_ram_out, wishbone_out => wishbone_ram_in);

	simple_uart_0: entity work.sim_uart
		port map ( clk => clk, reset => rst, wishbone_in => wishbone_uart_out, wishbone_out => wishbone_uart_in);


	wishbone_arbiter_0: entity work.wishbone_arbiter
		port map (clk => clk, rst => rst,
			  wb1_in => wishbone_dcore_out, wb1_out => wishbone_dcore_in,
			  wb2_in => wishbone_icore_out, wb2_out => wishbone_icore_in,
			  wb_out => wishbone_core_out, wb_in => wishbone_core_in);

	bus_process: process(wishbone_core_out, wishbone_ram_in, wishbone_uart_in)
	  -- Selected slave
	  type slave_type is (SLAVE_UART, SLAVE_MEMORY, SLAVE_NONE);
	  variable slave : slave_type;
	begin
		-- Simple address decoder
		slave := SLAVE_NONE;
		if wishbone_core_out.adr(31 downto 24) = x"00" then
			slave := SLAVE_MEMORY;
		elsif wishbone_core_out.adr(31 downto 24) = x"c0" then
			if wishbone_core_out.adr(15 downto 12) = x"2" then
				slave := SLAVE_UART;
			end if;
		end if;

		-- Wishbone muxing:
		-- Start with all master signals to all slaves, then override
		-- cyc and stb accordingly
		wishbone_ram_out <= wishbone_core_out;
		wishbone_uart_out <= wishbone_core_out;
		if slave = SLAVE_MEMORY then
			wishbone_core_in <= wishbone_ram_in;
		else
			wishbone_ram_out.cyc <= '0';
			wishbone_ram_out.stb <= '0';
		end if;
		if slave = SLAVE_UART then
			wishbone_core_in <= wishbone_uart_in;
		else
			wishbone_uart_out.cyc <= '0';
			wishbone_uart_out.stb <= '0';
		end if;
		if slave = SLAVE_NONE then
			wishbone_core_in.dat <= (others => '1');
			wishbone_core_in.ack <= wishbone_core_out.cyc and
						wishbone_core_out.stb;
		end if;
	end process;

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
