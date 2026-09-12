library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mma_unit_tb is
end entity mma_unit_tb;


architecture tb of mma_unit_tb is

    -- Clock
    signal clk : std_ulogic := '0';

    -- Reset
    signal rst : std_ulogic := '0';

    -- Control
    signal start : std_ulogic := '0';
    signal clear : std_ulogic := '0';

    -- Inputs
    signal a : std_ulogic_vector(7 downto 0) := (others => '0');
    signal b : std_ulogic_vector(7 downto 0) := (others => '0');

    -- Outputs
    signal busy : std_ulogic;
    signal done : std_ulogic;

    signal result : std_ulogic_vector(31 downto 0);

begin

    ------------------------------------------------
    -- DUT INSTANTIATION
    ------------------------------------------------

    dut: entity work.mma_unit
        port map (
            clk    => clk,
            rst    => rst,

            start  => start,
            clear  => clear,

            a      => a,
            b      => b,

            busy   => busy,
            done   => done,

            result => result
        );


    ------------------------------------------------
    -- CLOCK GENERATION
    ------------------------------------------------

    clock_process: process
    begin

        while true loop

            clk <= '0';
            wait for 5 ns;

            clk <= '1';
            wait for 5 ns;

        end loop;

    end process;


    ------------------------------------------------
    -- TEST PROCESS
    ------------------------------------------------

    stimulus: process

    begin

        ------------------------------------------------
        -- RESET
        ------------------------------------------------

        rst <= '1';

        wait for 20 ns;

        rst <= '0';

        wait for 10 ns;


        ------------------------------------------------
        -- TEST 1
        -- 2 × 3
        -- ACC = 6
        ------------------------------------------------

        a <= std_ulogic_vector(to_signed(2, 8));
        b <= std_ulogic_vector(to_signed(3, 8));

        start <= '1';

        wait for 10 ns;

        start <= '0';

        wait until done = '1';

        wait for 1 ns;

        assert signed(result) = 6
        report "TEST 1 FAILED: Expected ACC = 6"
        severity error;

        report "TEST 1 PASSED: ACC = 6";


        ------------------------------------------------
        -- TEST 2
        -- 4 × 5
        -- Previous ACC = 6
        --
        -- ACC = 6 + 20
        -- ACC = 26
        ------------------------------------------------

        a <= std_ulogic_vector(to_signed(4, 8));
        b <= std_ulogic_vector(to_signed(5, 8));

        start <= '1';

        wait for 10 ns;

        start <= '0';

        wait until done = '1';

        wait for 1 ns;

        assert signed(result) = 26
        report "TEST 2 FAILED: Expected ACC = 26"
        severity error;

        report "TEST 2 PASSED: ACC = 26";


        ------------------------------------------------
        -- TEST 3
        -- -2 × 3
        --
        -- Previous ACC = 26
        --
        -- Product = -6
        --
        -- ACC = 20
        ------------------------------------------------

        a <= std_ulogic_vector(to_signed(-2, 8));
        b <= std_ulogic_vector(to_signed(3, 8));

        start <= '1';

        wait for 10 ns;

        start <= '0';

        wait until done = '1';

        wait for 1 ns;

        assert signed(result) = 20
        report "TEST 3 FAILED: Expected ACC = 20"
        severity error;

        report "TEST 3 PASSED: ACC = 20";


        ------------------------------------------------
        -- TEST 4
        -- CLEAR ACCUMULATOR
        ------------------------------------------------

        clear <= '1';

        wait for 10 ns;

        clear <= '0';

        wait for 10 ns;

        assert signed(result) = 0
        report "TEST 4 FAILED: Expected ACC = 0"
        severity error;

        report "TEST 4 PASSED: ACC = 0";


        ------------------------------------------------
        -- TEST 5
        -- -5 × -4
        --
        -- Product = 20
        --
        -- ACC = 20
        ------------------------------------------------

        a <= std_ulogic_vector(to_signed(-5, 8));
        b <= std_ulogic_vector(to_signed(-4, 8));

        start <= '1';

        wait for 10 ns;

        start <= '0';

        wait until done = '1';

        wait for 1 ns;

        assert signed(result) = 20
        report "TEST 5 FAILED: Expected ACC = 20"
        severity error;

        report "TEST 5 PASSED: ACC = 20";


        ------------------------------------------------
        -- TEST 6
        -- Maximum positive INT8
        --
        -- 127 × 127 = 16129
        --
        -- Previous ACC = 20
        --
        -- ACC = 16149
        ------------------------------------------------

        a <= std_ulogic_vector(to_signed(127, 8));
        b <= std_ulogic_vector(to_signed(127, 8));

        start <= '1';

        wait for 10 ns;

        start <= '0';

        wait until done = '1';

        wait for 1 ns;

        assert signed(result) = 16149
        report "TEST 6 FAILED"
        severity error;

        report "TEST 6 PASSED: ACC = 16149";


        ------------------------------------------------
        -- END SIMULATION
        ------------------------------------------------

        report "ALL MMA TESTS PASSED";

        wait;

    end process;

end architecture tb;
