library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;

entity simple_ram_behavioural_tb is
end simple_ram_behavioural_tb;

architecture behave of simple_ram_behavioural_tb is
    signal clk          : std_ulogic;
    signal rst          : std_ulogic := '1';

    constant clk_period : time := 10 ns;

    signal w_in         : wishbone_slave_out;
    signal w_out        : wishbone_master_out;

    impure function to_adr(a: integer) return std_ulogic_vector is
    begin
	return std_ulogic_vector(to_unsigned(a, w_out.adr'length));
    end;
begin
    simple_ram_0: entity work.mw_soc_memory
        generic map (
            RAM_INIT_FILE => "simple_ram_behavioural_tb.bin",
            MEMORY_SIZE => 16
            )
        port map (
            clk => clk,
            rst => rst,
            wishbone_out => w_in,
            wishbone_in => w_out
            );

    clock: process
    begin
        clk <= '1';
        wait for clk_period / 2;
        clk <= '0';
        wait for clk_period / 2;
    end process clock;

    stim: process
    begin
        w_out.adr <= (others => '0');
        w_out.dat <= (others => '0');
        w_out.cyc <= '0';
        w_out.stb <= '0';
        w_out.sel <= (others => '0');
        w_out.we  <= '0';

        wait for clk_period;
        rst <= '0';

        wait for clk_period;

        w_out.cyc <= '1';

        -- test various read lengths and alignments
        w_out.stb <= '1';
        w_out.sel <= "00000001";
        w_out.adr <= to_adr(0);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(7 downto 0) = x"00" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000001";
        w_out.adr <= to_adr(1);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(7 downto 0) = x"01" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000001";
        w_out.adr <= to_adr(7);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(7 downto 0) = x"07" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000011";
        w_out.adr <= to_adr(0);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(15 downto 0) = x"0100" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000011";
        w_out.adr <= to_adr(1);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(15 downto 0) = x"0201" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000011";
        w_out.adr <= to_adr(7);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(15 downto 0) = x"0807" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00001111";
        w_out.adr <= to_adr(0);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(31 downto 0) = x"03020100" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00001111";
        w_out.adr <= to_adr(1);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(31 downto 0) = x"04030201" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00001111";
        w_out.adr <= to_adr(7);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(31 downto 0) = x"0A090807" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "11111111";
        w_out.adr <= to_adr(0);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(63 downto 0) = x"0706050403020100" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "11111111";
        w_out.adr <= to_adr(1);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(63 downto 0) = x"0807060504030201" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "11111111";
        w_out.adr <= to_adr(7);
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(63 downto 0) = x"0E0D0C0B0A090807" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        -- test various write lengths and alignments
        w_out.stb <= '1';
        w_out.sel <= "00000001";
        w_out.adr <= to_adr(0);
        w_out.we <= '1';
        w_out.dat(7 downto 0) <= x"0F";
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "00000001";
        w_out.adr <= to_adr(0);
        w_out.we <= '0';
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat(7 downto 0) = x"0F" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "11111111";
        w_out.adr <= to_adr(7);
        w_out.we <= '1';
        w_out.dat <= x"BADC0FFEBADC0FFE";
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        w_out.stb <= '1';
        w_out.sel <= "11111111";
        w_out.adr <= to_adr(7);
        w_out.we <= '0';
        assert w_in.ack = '0';
        wait for clk_period;
        assert w_in.ack = '1';
        assert w_in.dat = x"BADC0FFEBADC0FFE" report to_hstring(w_in.dat);
        w_out.stb <= '0';
        wait for clk_period;
        assert w_in.ack = '0';

        assert false report "end of test" severity failure;
        wait;
    end process;
end behave;
