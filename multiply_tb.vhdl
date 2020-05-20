library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.glibc_random.all;
use work.ppc_fx_insns.all;

entity multiply_tb is
end multiply_tb;

architecture behave of multiply_tb is
    signal clk              : std_ulogic;
    constant clk_period     : time := 10 ns;

    constant pipeline_depth : integer := 4;

    signal m1               : Execute1ToMultiplyType;
    signal m2               : MultiplyToExecute1Type;
begin
    multiply_0: entity work.multiply
        generic map (PIPELINE_DEPTH => pipeline_depth)
        port map (clk => clk, m_in => m1, m_out => m2);

    clk_process: process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    stim_process: process
        variable ra, rb, rt, behave_rt: std_ulogic_vector(63 downto 0);
        variable si: std_ulogic_vector(15 downto 0);
    begin
        wait for clk_period;

        m1.valid <= '1';
        m1.insn_type <= OP_MUL_L64;
        m1.data1 <= '0' & x"0000000000001000";
        m1.data2 <= '0' & x"0000000000001111";

        wait for clk_period;
        assert m2.valid = '0';

        m1.valid <= '0';

        wait for clk_period;
        assert m2.valid = '0';

        wait for clk_period;
        assert m2.valid = '0';

        wait for clk_period;
        assert m2.valid = '1';
        assert m2.write_reg_data = x"0000000001111000";

        wait for clk_period;
        assert m2.valid = '0';

        m1.valid <= '1';

        wait for clk_period;
        assert m2.valid = '0';

        m1.valid <= '0';

        wait for clk_period * (pipeline_depth-1);
        assert m2.valid = '1';
        assert m2.write_reg_data = x"0000000001111000";

        -- test mulld
        mulld_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mulld(ra, rb);

            m1.data1 <= '0' & ra;
            m1.data2 <= '0' & rb;
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_L64;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulld expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mulhdu
        mulhdu_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mulhdu(ra, rb);

            m1.data1 <= '0' & ra;
            m1.data2 <= '0' & rb;
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_H64;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulhdu expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mulhd
        mulhd_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mulhd(ra, rb);

            m1.data1 <= ra(63) & ra;
            m1.data2 <= rb(63) & rb;
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_H64;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulhd expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mullw
        mullw_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mullw(ra, rb);

            m1.data1 <= (others => ra(31));
            m1.data1(31 downto 0) <= ra(31 downto 0);
            m1.data2 <= (others => rb(31));
            m1.data2(31 downto 0) <= rb(31 downto 0);
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_L64;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mullw expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mulhw
        mulhw_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mulhw(ra, rb);

            m1.data1 <= (others => ra(31));
            m1.data1(31 downto 0) <= ra(31 downto 0);
            m1.data2 <= (others => rb(31));
            m1.data2(31 downto 0) <= rb(31 downto 0);
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_H32;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulhw expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mulhwu
        mulhwu_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            rb := pseudorand(rb'length);

            behave_rt := ppc_mulhwu(ra, rb);

            m1.data1 <= (others => '0');
            m1.data1(31 downto 0) <= ra(31 downto 0);
            m1.data2 <= (others => '0');
            m1.data2(31 downto 0) <= rb(31 downto 0);
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_H32;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulhwu expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        -- test mulli
        mulli_loop : for i in 0 to 1000 loop
            ra := pseudorand(ra'length);
            si := pseudorand(si'length);

            behave_rt := ppc_mulli(ra, si);

            m1.data1 <= ra(63) & ra;
            m1.data2 <= (others => si(15));
            m1.data2(15 downto 0) <= si;
            m1.valid <= '1';
            m1.insn_type <= OP_MUL_L64;

            wait for clk_period;

            m1.valid <= '0';

            wait for clk_period * (pipeline_depth-1);

            assert m2.valid = '1';

            assert to_hstring(behave_rt) = to_hstring(m2.write_reg_data)
                report "bad mulli expected " & to_hstring(behave_rt) & " got " & to_hstring(m2.write_reg_data);
        end loop;

        std.env.finish;
        wait;
    end process;
end behave;
