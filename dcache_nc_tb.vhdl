library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity dcache_nc_tb is
end entity dcache_nc_tb;

architecture test of dcache_nc_tb is
    signal clk : std_ulogic := '0';
    signal rst : std_ulogic := '1';
    signal d_in : Loadstore1ToDcacheType := Loadstore1ToDcacheInit;
    signal d_out : DcacheToLoadstore1Type;
    signal m_in : MmuToDcacheType := (
        valid => '0', tlbie => '0', doall => '0', tlbld => '0',
        addr => (others => '0'), pte => (others => '0'));
    signal m_out : DcacheToMmuType;
    signal wb_in : wishbone_slave_out := wishbone_slave_out_init;
    signal wb_out : wishbone_master_out;
    signal stall : std_ulogic;

    constant clk_period : time := 10 ns;
begin
    dcache0 : entity work.dcache
        generic map (LINE_SIZE => 64, NUM_LINES => 4)
        port map (
            clk => clk, rst => rst, d_in => d_in, d_out => d_out,
            m_in => m_in, m_out => m_out, stall_out => stall,
            wishbone_out => wb_out, wishbone_in => wb_in,
            events => open, log_out => open);

    clk <= not clk after clk_period / 2;

    stimulus : process
        alias req_nc is << signal .dcache_nc_tb.dcache0.req_nc : std_ulogic >>;
        variable request : Loadstore1ToDcacheType;
    begin
        request := Loadstore1ToDcacheInit;
        request.nc := '1';
        d_in <= request;
        wait for 2 * clk_period;
        rst <= '0';

        -- Prime the process-local nc value with a stable non-cacheable request.
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;
        assert req_nc = '1'
            report "non-cacheable request flag was not propagated"
            severity failure;

        -- Changing the request to cacheable must update req_nc immediately.
        request.nc := '0';
        d_in <= request;
        wait until rising_edge(clk);
        wait for 1 ns;
        assert req_nc = '0'
            report "req_nc retained the preceding request's non-cacheable value"
            severity failure;

        report "dcache non-cacheable request flag test passed";
        std.env.finish;
    end process;
end architecture test;
