library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity plru_tb is
end plru_tb;

architecture behave of plru_tb is
    signal clk          : std_ulogic;
    signal rst          : std_ulogic;

    constant clk_period : time := 10 ns;

    signal acc_en : std_ulogic;
    signal acc : std_ulogic_vector(2 downto 0);
    signal lru : std_ulogic_vector(2 downto 0);

begin
    plru0: entity work.plru
        generic map(
            BITS => 3
            )
        port map(
            clk => clk,
            rst => rst,

	    acc => acc,
	    acc_en => acc_en,
	    lru => lru
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
        wait for 2*clk_period;
        rst <= '0';
        wait;
    end process;

    stim: process
    begin
	wait for 4*clk_period;

	report "accessing 1:";
	acc <= "001";
	acc_en <= '1';
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 2:";
	acc <= "010";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 7:";
	acc <= "111";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 4:";
	acc <= "100";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 3:";
	acc <= "011";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 5:";
	acc <= "101";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 3:";
	acc <= "011";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 5:";
	acc <= "101";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 6:";
	acc <= "110";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

	report "accessing 0:";
	acc <= "000";
	wait for clk_period;
	report "lru:" & to_hstring(lru);

        std.env.finish;
    end process;
end;
