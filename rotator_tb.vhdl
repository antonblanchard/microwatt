library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.glibc_random.all;
use work.ppc_fx_insns.all;
use work.insn_helpers.all;

entity rotator_tb is
end rotator_tb;

architecture behave of rotator_tb is
    constant clk_period: time := 10 ns;
    signal ra, rs: std_ulogic_vector(63 downto 0);
    signal shift: std_ulogic_vector(6 downto 0) := (others => '0');
    signal insn: std_ulogic_vector(31 downto 0) := (others => '0');
    signal is_32bit, right_shift, arith, clear_left, clear_right: std_ulogic := '0';
    signal result: std_ulogic_vector(63 downto 0);
    signal carry_out: std_ulogic;
    signal extsw: std_ulogic;

begin
    rotator_0: entity work.rotator
	port map (
	    rs => rs,
	    ra => ra,
	    shift => shift,
	    insn => insn,
	    is_32bit => is_32bit,
	    right_shift => right_shift,
	    arith => arith,
	    clear_left => clear_left,
	    clear_right => clear_right,
            sign_ext_rs => extsw,
	    result => result,
	    carry_out => carry_out
	);

    stim_process: process
        variable behave_ra: std_ulogic_vector(63 downto 0);
	variable behave_ca_ra: std_ulogic_vector(64 downto 0);
    begin
	-- rlwinm, rlwnm
        report "test rlw[i]nm";
	ra <= (others => '0');
	is_32bit <= '1';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '1';
	clear_right <= '1';
        extsw <= '0';
        rlwnm_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rlwinm(rs, shift(4 downto 0), insn_mb32(insn), insn_me32(insn));
	    assert behave_ra = result
		report "bad rlwnm expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- rlwimi
        report "test rlwimi";
	is_32bit <= '1';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '1';
	clear_right <= '1';
        rlwimi_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    ra <= pseudorand(64);
	    shift <= "00" & pseudorand(5);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rlwimi(ra, rs, shift(4 downto 0), insn_mb32(insn), insn_me32(insn));
	    assert behave_ra = result
		report "bad rlwimi expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- rldicl, rldcl
        report "test rld[i]cl";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '1';
	clear_right <= '0';
        rldicl_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rldicl(rs, shift(5 downto 0), insn_mb(insn));
	    assert behave_ra = result
		report "bad rldicl expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- rldicr, rldcr
        report "test rld[i]cr";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '1';
        rldicr_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rldicr(rs, shift(5 downto 0), insn_me(insn));
	    --report "rs = " & to_hstring(rs);
	    --report "ra = " & to_hstring(ra);
	    --report "shift = " & to_hstring(shift);
	    --report "insn me = " & to_hstring(insn_me(insn));
	    --report "result = " & to_hstring(result);
	    assert behave_ra = result
		report "bad rldicr expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- rldic
        report "test rldic";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '1';
	clear_right <= '1';
        rldic_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= '0' & pseudorand(6);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rldic(rs, shift(5 downto 0), insn_mb(insn));
	    assert behave_ra = result
		report "bad rldic expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- rldimi
        report "test rldimi";
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '1';
	clear_right <= '1';
        rldimi_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    ra <= pseudorand(64);
	    shift <= '0' & pseudorand(6);
	    insn <= x"00000" & '0' & pseudorand(10) & '0';
	    wait for clk_period;
	    behave_ra := ppc_rldimi(ra, rs, shift(5 downto 0), insn_mb(insn));
	    assert behave_ra = result
		report "bad rldimi expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- slw
        report "test slw";
	ra <= (others => '0');
	is_32bit <= '1';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '0';
        slw_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    wait for clk_period;
	    behave_ra := ppc_slw(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    assert behave_ra = result
		report "bad slw expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- sld
        report "test sld";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '0';
        sld_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    wait for clk_period;
	    behave_ra := ppc_sld(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    assert behave_ra = result
		report "bad sld expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- srw
        report "test srw";
	ra <= (others => '0');
	is_32bit <= '1';
	right_shift <= '1';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '0';
        srw_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    wait for clk_period;
	    behave_ra := ppc_srw(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    assert behave_ra = result
		report "bad srw expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- srd
        report "test srd";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '1';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '0';
        srd_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    wait for clk_period;
	    behave_ra := ppc_srd(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    assert behave_ra = result
		report "bad srd expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

	-- sraw[i]
        report "test sraw[i]";
	ra <= (others => '0');
	is_32bit <= '1';
	right_shift <= '1';
	arith <= '1';
	clear_left <= '0';
	clear_right <= '0';
        sraw_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= '0' & pseudorand(6);
	    wait for clk_period;
	    behave_ca_ra := ppc_sraw(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    --report "rs = " & to_hstring(rs);
	    --report "ra = " & to_hstring(ra);
	    --report "shift = " & to_hstring(shift);
	    --report "result = " & to_hstring(carry_out & result);
	    assert behave_ca_ra(63 downto 0) = result and behave_ca_ra(64) = carry_out
		report "bad sraw expected " & to_hstring(behave_ca_ra) & " got " & to_hstring(carry_out & result);
        end loop;

	-- srad[i]
        report "test srad[i]";
	ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '1';
	arith <= '1';
	clear_left <= '0';
	clear_right <= '0';
        srad_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= pseudorand(7);
	    wait for clk_period;
	    behave_ca_ra := ppc_srad(rs, std_ulogic_vector(resize(unsigned(shift), 64)));
	    --report "rs = " & to_hstring(rs);
	    --report "ra = " & to_hstring(ra);
	    --report "shift = " & to_hstring(shift);
	    --report "result = " & to_hstring(carry_out & result);
	    assert behave_ca_ra(63 downto 0) = result and behave_ca_ra(64) = carry_out
		report "bad srad expected " & to_hstring(behave_ca_ra) & " got " & to_hstring(carry_out & result);
        end loop;

        -- extswsli
        report "test extswsli";
        ra <= (others => '0');
	is_32bit <= '0';
	right_shift <= '0';
	arith <= '0';
	clear_left <= '0';
	clear_right <= '0';
        extsw <= '1';
        extswsli_loop : for i in 0 to 1000 loop
	    rs <= pseudorand(64);
	    shift <= '0' & pseudorand(6);
	    wait for clk_period;
	    behave_ra := rs;
            behave_ra(63 downto 32) := (others => rs(31));
            behave_ra := std_ulogic_vector(shift_left(unsigned(behave_ra),
                                                      to_integer(unsigned(shift))));
	    --report "rs = " & to_hstring(rs);
	    --report "ra = " & to_hstring(ra);
	    --report "shift = " & to_hstring(shift);
	    --report "result = " & to_hstring(carry_out & result);
	    assert behave_ra = result
		report "bad extswsli expected " & to_hstring(behave_ra) & " got " & to_hstring(result);
        end loop;

        std.env.finish;
    end process;
end behave;
