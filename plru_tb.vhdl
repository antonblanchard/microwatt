library vunit_lib;
context vunit_lib.vunit_context;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity plru_tb is
    generic (runner_cfg : string := runner_cfg_default);
end plru_tb;

architecture behave of plru_tb is
    signal clk          : std_ulogic;
    signal rst          : std_ulogic;

    constant clk_period : time := 10 ns;
    constant plru_bits  : integer := 3;

    subtype plru_val_t  is std_ulogic_vector(plru_bits - 1 downto 0);
    subtype plru_tree_t is std_ulogic_vector(2 ** plru_bits - 2 downto 0);
    signal do_update : std_ulogic := '0';
    signal acc : plru_val_t;
    signal lru : plru_val_t;
    signal state : plru_tree_t;
    signal state_upd : plru_tree_t;

begin
    plrufn0: entity work.plrufn
        generic map(
            BITS => plru_bits
            )
        port map(
            acc => acc,
            tree_in => state,
            tree_out => state_upd,
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

    plru_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= (others => '0');
            elsif do_update = '1' then
                state <= state_upd;
            end if;
        end if;
    end process;

    stim_process: process
        procedure test_access(acc_val: integer; expected: integer) is
        begin
            acc <= std_ulogic_vector(to_unsigned(acc_val, acc'length));
            do_update <= '1';
            wait for clk_period;
            info("accessed " & integer'image(acc_val) & " LRU=" & to_hstring(lru));
            check_equal(lru, expected, result("LRU ACC=" & integer'image(acc_val)));
        end procedure;
    begin
        test_runner_setup(runner, runner_cfg);

        wait for 8*clk_period;

        info("reset state:" & to_hstring(lru));
        check_equal(lru, 0, result("LRU "));

        test_access(1, 4);
        test_access(2, 4);
        test_access(7, 0);
        test_access(4, 0);
        test_access(3, 6);
        test_access(5, 0);
        test_access(3, 6);
        test_access(5, 0);
        test_access(6, 0);
        test_access(0, 4);
        test_access(1, 4);
        test_access(2, 4);
        test_access(3, 4);
        test_access(4, 0);
        test_access(5, 0);
        test_access(6, 0);
        test_access(7, 0);
        test_access(6, 0);
        test_access(5, 0);
        test_access(4, 0);
        test_access(3, 7);
        test_access(2, 7);
        test_access(1, 7);
        test_access(0, 7);


        wait for clk_period;
        wait for clk_period;
        
        test_runner_cleanup(runner);
    end process;
end;
