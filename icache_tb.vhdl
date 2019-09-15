library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity icache_tb is
end icache_tb;

architecture behave of icache_tb is
    signal clk          : std_ulogic;
    signal rst          : std_ulogic;

    signal i_out        : Fetch2ToIcacheType;
    signal i_in         : IcacheToFetch2Type;

    signal wb_bram_in   : wishbone_master_out;
    signal wb_bram_out  : wishbone_slave_out;

    constant clk_period : time := 10 ns;
begin
    icache0: entity work.icache
        generic map(
            LINE_SIZE_DW => 8,
            NUM_LINES => 4
            )
        port map(
            clk => clk,
            rst => rst,
            i_in => i_out,
            i_out => i_in,
            wishbone_out => wb_bram_in,
            wishbone_in => wb_bram_out
            );

    -- BRAM Memory slave
    bram0: entity work.mw_soc_memory
        generic map(
            MEMORY_SIZE   => 128,
            RAM_INIT_FILE => "icache_test.bin"
            )
        port map(
            clk => clk,
            rst => rst,
            wishbone_in => wb_bram_in,
            wishbone_out => wb_bram_out
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
        i_out.req <= '0';
        i_out.addr <= (others => '0');

        wait for 4*clk_period;

        i_out.req <= '1';
        i_out.addr <= x"0000000000000004";

        wait for 30*clk_period;

        assert i_in.ack = '1';
        assert i_in.insn = x"00000001";

        i_out.req <= '0';

        wait for clk_period;

        -- hit
        i_out.req <= '1';
        i_out.addr <= x"0000000000000008";
        wait for clk_period/2;
        assert i_in.ack = '1';
        assert i_in.insn = x"00000002";
        wait for clk_period/2;

        -- another miss
        i_out.req <= '1';
        i_out.addr <= x"0000000000000040";

        wait for 30*clk_period;

        assert i_in.ack = '1';
        assert i_in.insn = x"00000010";

        -- test something that aliases
        i_out.req <= '1';
        i_out.addr <= x"0000000000000100";
        wait for clk_period/2;
        assert i_in.ack = '0';
        wait for clk_period/2;

        wait for 30*clk_period;

        assert i_in.ack = '1';
        assert i_in.insn = x"00000040";

        i_out.req <= '0';

        assert false report "end of test" severity failure;
        wait;

    end process;
end;
