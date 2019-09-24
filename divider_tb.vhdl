library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.glibc_random.all;
use work.ppc_fx_insns.all;

entity divider_tb is
end divider_tb;

architecture behave of divider_tb is
    signal clk              : std_ulogic;
    signal rst              : std_ulogic;
    constant clk_period     : time := 10 ns;

    signal d1               : Decode2ToDividerType;
    signal d2               : DividerToWritebackType;
begin
    divider_0: entity work.divider
        port map (clk => clk, rst => rst, d_in => d1, d_out => d2);

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
        variable d128: std_ulogic_vector(127 downto 0);
        variable q128: std_ulogic_vector(127 downto 0);
    begin
        rst <= '1';
        wait for clk_period;
        rst <= '0';

        d1.valid <= '1';
        d1.write_reg <= "10001";
        d1.dividend <= x"0000000010001000";
        d1.divisor  <= x"0000000000001111";
        d1.neg_result <= '0';
        d1.is_32bit <= '0';
        d1.is_extended <= '0';
        d1.is_modulus <= '0';
        d1.rc <= '0';

        wait for clk_period;
        assert d2.valid = '0';

        d1.valid <= '0';

        for j in 0 to 64 loop
            wait for clk_period;
            if d2.valid = '1' then
                exit;
            end if;
        end loop;

        assert d2.valid = '1';
        assert d2.write_reg_enable = '1';
        assert d2.write_reg_nr = "10001";
        assert d2.write_reg_data = x"000000000000f001" report "result " & to_hstring(d2.write_reg_data);
        assert d2.write_cr_enable = '0';

        wait for clk_period;
        assert d2.valid = '0' report "valid";

        d1.valid <= '1';
        d1.rc <= '1';

        wait for clk_period;
        assert d2.valid = '0' report "valid";

        d1.valid <= '0';

        for j in 0 to 64 loop
            wait for clk_period;
            if d2.valid = '1' then
                exit;
            end if;
        end loop;

        assert d2.valid = '1';
        assert d2.write_reg_enable = '1';
        assert d2.write_reg_nr = "10001";
        assert d2.write_reg_data = x"000000000000f001" report "result " & to_hstring(d2.write_reg_data);
        assert d2.write_cr_enable = '1';
        assert d2.write_cr_mask = "10000000";
        assert d2.write_cr_data = x"40000000" report "cr data is " & to_hstring(d2.write_cr_data);

        wait for clk_period;
        assert d2.valid = '0';

        -- test divd
        report "test divd";
        divd_loop : for dlength in 1 to 8 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    if ra(63) = rb(63) then
                        d1.neg_result <= '0';
                    else
                        d1.neg_result <= '1';
                    end if;
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := ppc_divd(ra, rb);
                        assert to_hstring(behave_rt) = to_hstring(d2.write_reg_data)
                            report "bad divd expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divd";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divdu
        report "test divdu";
        divdu_loop : for dlength in 1 to 8 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := ppc_divdu(ra, rb);
                        assert to_hstring(behave_rt) = to_hstring(d2.write_reg_data)
                            report "bad divdu expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divdu";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divde
        report "test divde";
        divde_loop : for vlength in 1 to 8 loop
            for dlength in 1 to vlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    if ra(63) = rb(63) then
                        d1.neg_result <= '0';
                    else
                        d1.neg_result <= '1';
                    end if;
                    d1.is_extended <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if unsigned(d1.divisor) > unsigned(d1.dividend) then
                        d128 := ra & x"0000000000000000";
                        q128 := std_ulogic_vector(signed(d128) / signed(rb));
                        behave_rt := q128(63 downto 0);
                        assert to_hstring(behave_rt) = to_hstring(d2.write_reg_data)
                            report "bad divde expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data) & " for ra = " & to_hstring(ra) & " rb = " & to_hstring(rb);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divde";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divdeu
        report "test divdeu";
        divdeu_loop : for vlength in 1 to 8 loop
            for dlength in 1 to vlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.is_extended <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if unsigned(d1.divisor) > unsigned(d1.dividend) then
                        d128 := ra & x"0000000000000000";
                        q128 := std_ulogic_vector(unsigned(d128) / unsigned(rb));
                        behave_rt := q128(63 downto 0);
                        assert to_hstring(behave_rt) = to_hstring(d2.write_reg_data)
                            report "bad divdeu expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data) & " for ra = " & to_hstring(ra) & " rb = " & to_hstring(rb);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divdeu";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divw
        report "test divw";
        divw_loop : for dlength in 1 to 4 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    if ra(63) = rb(63) then
                        d1.neg_result <= '0';
                    else
                        d1.neg_result <= '1';
                    end if;
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := ppc_divw(ra, rb);
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad divw expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divw";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divwu
        report "test divwu";
        divwu_loop : for dlength in 1 to 4 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := ppc_divwu(ra, rb);
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad divwu expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divwu";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divwe
        report "test divwe";
        divwe_loop : for vlength in 1 to 4 loop
            for dlength in 1 to vlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 32)) & x"00000000";
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    if ra(63) = rb(63) then
                        d1.neg_result <= '0';
                    else
                        d1.neg_result <= '1';
                    end if;
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if unsigned(d1.divisor(31 downto 0)) > unsigned(d1.dividend(63 downto 32)) then
                        behave_rt := std_ulogic_vector(signed(ra) / signed(rb));
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad divwe expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data) & " for ra = " & to_hstring(ra) & " rb = " & to_hstring(rb);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divwe";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test divweu
        report "test divweu";
        divweu_loop : for vlength in 1 to 4 loop
            for dlength in 1 to vlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 32)) & x"00000000";
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if unsigned(d1.divisor(31 downto 0)) > unsigned(d1.dividend(63 downto 32)) then
                        behave_rt := std_ulogic_vector(unsigned(ra) / unsigned(rb));
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad divweu expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data) & " for ra = " & to_hstring(ra) & " rb = " & to_hstring(rb);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for divweu";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test modsd
        report "test modsd";
        modsd_loop : for dlength in 1 to 8 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    d1.neg_result <= ra(63);
                    d1.is_extended <= '0';
                    d1.is_32bit <= '0';
                    d1.is_modulus <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := std_ulogic_vector(signed(ra) rem signed(rb));
                        assert behave_rt = d2.write_reg_data
                            report "bad modsd expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for modsd";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test modud
        report "test modud";
        modud_loop : for dlength in 1 to 8 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.is_extended <= '0';
                    d1.is_32bit <= '0';
                    d1.is_modulus <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := std_ulogic_vector(unsigned(ra) rem unsigned(rb));
                        assert behave_rt = d2.write_reg_data
                            report "bad modud expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('1', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for modud";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test modsw
        report "test modsw";
        modsw_loop : for dlength in 1 to 4 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(signed(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(signed(pseudorand(vlength * 8)), 64));

                    if ra(63) = '1' then
                        d1.dividend <= std_ulogic_vector(- signed(ra));
                    else
                        d1.dividend <= ra;
                    end if;
                    if rb(63) = '1' then
                        d1.divisor <= std_ulogic_vector(- signed(rb));
                    else
                        d1.divisor <= rb;
                    end if;
                    d1.neg_result <= ra(63);
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.is_modulus <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := x"00000000" & std_ulogic_vector(signed(ra(31 downto 0)) rem signed(rb(31 downto 0)));
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad modsw expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for modsw";
                    end if;
                end loop;
            end loop;
        end loop;

        -- test moduw
        report "test moduw";
        moduw_loop : for dlength in 1 to 4 loop
            for vlength in 1 to dlength loop
                for i in 0 to 100 loop
                    ra := std_ulogic_vector(resize(unsigned(pseudorand(dlength * 8)), 64));
                    rb := std_ulogic_vector(resize(unsigned(pseudorand(vlength * 8)), 64));

                    d1.dividend <= ra;
                    d1.divisor <= rb;
                    d1.neg_result <= '0';
                    d1.is_extended <= '0';
                    d1.is_32bit <= '1';
                    d1.is_modulus <= '1';
                    d1.valid <= '1';

                    wait for clk_period;

                    d1.valid <= '0';
                    for j in 0 to 64 loop
                        wait for clk_period;
                        if d2.valid = '1' then
                            exit;
                        end if;
                    end loop;
                    assert d2.valid = '1';

                    if rb /= x"0000000000000000" then
                        behave_rt := x"00000000" & std_ulogic_vector(unsigned(ra(31 downto 0)) rem unsigned(rb(31 downto 0)));
                        assert behave_rt(31 downto 0) = d2.write_reg_data(31 downto 0)
                            report "bad moduw expected " & to_hstring(behave_rt) & " got " & to_hstring(d2.write_reg_data);
                        assert ppc_cmpi('0', behave_rt, x"0000") & x"0000000" = d2.write_cr_data
                            report "bad CR setting for moduw";
                    end if;
                end loop;
            end loop;
        end loop;

        assert false report "end of test" severity failure;
        wait;
    end process;
end behave;
