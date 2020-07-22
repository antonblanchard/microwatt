-- Floating-point unit for Microwatt

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.insn_helpers.all;
use work.decode_types.all;
use work.crhelpers.all;
use work.helpers.all;
use work.common.all;

entity fpu is
    port (
        clk : in std_ulogic;
        rst : in std_ulogic;

        e_in  : in  Execute1toFPUType;
        e_out : out FPUToExecute1Type;

        w_out : out FPUToWritebackType
        );
end entity fpu;

architecture behaviour of fpu is
    type fp_number_class is (ZERO, FINITE, INFINITY, NAN);

    constant EXP_BITS : natural := 13;

    type fpu_reg_type is record
        class    : fp_number_class;
        negative : std_ulogic;
        exponent : signed(EXP_BITS-1 downto 0);         -- unbiased
        mantissa : std_ulogic_vector(63 downto 0);      -- 10.54 format
    end record;

    type state_t is (IDLE,
                     DO_MCRFS, DO_MTFSB, DO_MTFSFI, DO_MFFS, DO_MTFSF,
                     DO_FMR, DO_FMRG,
                     DO_FCFID, DO_FCTI,
                     DO_FRSP, DO_FRI,
                     FRI_1,
                     INT_SHIFT, INT_ROUND, INT_ISHIFT,
                     INT_FINAL, INT_CHECK, INT_OFLOW,
                     FINISH, NORMALIZE,
                     ROUND_UFLOW, ROUND_OFLOW,
                     ROUNDING, ROUNDING_2, ROUNDING_3,
                     DENORM);

    type reg_type is record
        state        : state_t;
        busy         : std_ulogic;
        instr_done   : std_ulogic;
        do_intr      : std_ulogic;
        op           : insn_type_t;
        insn         : std_ulogic_vector(31 downto 0);
        dest_fpr     : gspr_index_t;
        fe_mode      : std_ulogic;
        rc           : std_ulogic;
        is_cmp       : std_ulogic;
        single_prec  : std_ulogic;
        fpscr        : std_ulogic_vector(31 downto 0);
        a            : fpu_reg_type;
        b            : fpu_reg_type;
        r            : std_ulogic_vector(63 downto 0);  -- 10.54 format
        x            : std_ulogic;
        result_sign  : std_ulogic;
        result_class : fp_number_class;
        result_exp   : signed(EXP_BITS-1 downto 0);
        shift        : signed(EXP_BITS-1 downto 0);
        writing_back : std_ulogic;
        int_result   : std_ulogic;
        cr_result    : std_ulogic_vector(3 downto 0);
        cr_mask      : std_ulogic_vector(7 downto 0);
        old_exc      : std_ulogic_vector(4 downto 0);
        update_fprf  : std_ulogic;
        quieten_nan  : std_ulogic;
        tiny         : std_ulogic;
        denorm       : std_ulogic;
        round_mode   : std_ulogic_vector(2 downto 0);
    end record;

    signal r, rin : reg_type;

    signal fp_result     : std_ulogic_vector(63 downto 0);
    signal opsel_a       : std_ulogic_vector(1 downto 0);
    signal opsel_b       : std_ulogic_vector(1 downto 0);
    signal opsel_r       : std_ulogic_vector(1 downto 0);
    signal opsel_ainv    : std_ulogic;
    signal opsel_amask   : std_ulogic;
    signal in_a          : std_ulogic_vector(63 downto 0);
    signal in_b          : std_ulogic_vector(63 downto 0);
    signal result        : std_ulogic_vector(63 downto 0);
    signal carry_in      : std_ulogic;
    signal lost_bits     : std_ulogic;
    signal r_hi_nz       : std_ulogic;
    signal r_lo_nz       : std_ulogic;
    signal misc_sel      : std_ulogic_vector(3 downto 0);

    -- opsel values
    constant AIN_R    : std_ulogic_vector(1 downto 0) := "00";
    constant AIN_A    : std_ulogic_vector(1 downto 0) := "01";
    constant AIN_B    : std_ulogic_vector(1 downto 0) := "10";

    constant BIN_ZERO : std_ulogic_vector(1 downto 0) := "00";
    constant BIN_R    : std_ulogic_vector(1 downto 0) := "01";
    constant BIN_MASK : std_ulogic_vector(1 downto 0) := "10";

    constant RES_SUM   : std_ulogic_vector(1 downto 0) := "00";
    constant RES_SHIFT : std_ulogic_vector(1 downto 0) := "01";
    constant RES_MISC  : std_ulogic_vector(1 downto 0) := "11";

    -- Left and right shifter with 120 bit input and 64 bit output.
    -- Shifts inp left by shift bits and returns the upper 64 bits of
    -- the result.  The shift parameter is interpreted as a signed
    -- number in the range -64..63, with negative values indicating
    -- right shifts.
    function shifter_64(inp: std_ulogic_vector(119 downto 0);
                        shift: std_ulogic_vector(6 downto 0))
        return std_ulogic_vector is
        variable s1 : std_ulogic_vector(94 downto 0);
        variable s2 : std_ulogic_vector(70 downto 0);
        variable result : std_ulogic_vector(63 downto 0);
    begin
        case shift(6 downto 5) is
            when "00" =>
                s1 := inp(119 downto 25);
            when "01" =>
                s1 := inp(87 downto 0) & "0000000";
            when "10" =>
                s1 := x"0000000000000000" & inp(119 downto 89);
            when others =>
                s1 := x"00000000" & inp(119 downto 57);
        end case;
        case shift(4 downto 3) is
            when "00" =>
                s2 := s1(94 downto 24);
            when "01" =>
                s2 := s1(86 downto 16);
            when "10" =>
                s2 := s1(78 downto 8);
            when others =>
                s2 := s1(70 downto 0);
        end case;
        case shift(2 downto 0) is
            when "000" =>
                result := s2(70 downto 7);
            when "001" =>
                result := s2(69 downto 6);
            when "010" =>
                result := s2(68 downto 5);
            when "011" =>
                result := s2(67 downto 4);
            when "100" =>
                result := s2(66 downto 3);
            when "101" =>
                result := s2(65 downto 2);
            when "110" =>
                result := s2(64 downto 1);
            when others =>
                result := s2(63 downto 0);
        end case;
        return result;
    end;

    -- Generate a mask with 0-bits on the left and 1-bits on the right which
    -- selects the bits will be lost in doing a right shift.  The shift
    -- parameter is the bottom 6 bits of a negative shift count,
    -- indicating a right shift.
    function right_mask(shift: unsigned(5 downto 0)) return std_ulogic_vector is
        variable result: std_ulogic_vector(63 downto 0);
    begin
        result := (others => '0');
        for i in 0 to 63 loop
            if i >= shift then
                result(63 - i) := '1';
            end if;
        end loop;
        return result;
    end;

    -- Split a DP floating-point number into components and work out its class.
    -- If is_int = 1, the input is considered an integer
    function decode_dp(fpr: std_ulogic_vector(63 downto 0); is_int: std_ulogic) return fpu_reg_type is
        variable r       : fpu_reg_type;
        variable exp_nz  : std_ulogic;
        variable exp_ao  : std_ulogic;
        variable frac_nz : std_ulogic;
        variable cls     : std_ulogic_vector(2 downto 0);
    begin
        r.negative := fpr(63);
        exp_nz := or (fpr(62 downto 52));
        exp_ao := and (fpr(62 downto 52));
        frac_nz := or (fpr(51 downto 0));
        if is_int = '0' then
            r.exponent := signed(resize(unsigned(fpr(62 downto 52)), EXP_BITS)) - to_signed(1023, EXP_BITS);
            if exp_nz = '0' then
                r.exponent := to_signed(-1022, EXP_BITS);
            end if;
            r.mantissa := "000000000" & exp_nz & fpr(51 downto 0) & "00";
            cls := exp_ao & exp_nz & frac_nz;
            case cls is
                when "000"  => r.class := ZERO;
                when "001"  => r.class := FINITE;    -- denormalized
                when "010"  => r.class := FINITE;
                when "011"  => r.class := FINITE;
                when "110"  => r.class := INFINITY;
                when others => r.class := NAN;
            end case;
        else
            r.mantissa := fpr;
            r.exponent := (others => '0');
            if (fpr(63) or exp_nz or frac_nz) = '1' then
                r.class := FINITE;
            else
                r.class := ZERO;
            end if;
        end if;
        return r;
    end;

    -- Construct a DP floating-point result from components
    function pack_dp(sign: std_ulogic; class: fp_number_class; exp: signed(EXP_BITS-1 downto 0);
                     mantissa: std_ulogic_vector; single_prec: std_ulogic; quieten_nan: std_ulogic)
        return std_ulogic_vector is
        variable result : std_ulogic_vector(63 downto 0);
    begin
        result := (others => '0');
        result(63) := sign;
        case class is
            when ZERO =>
            when FINITE =>
                if mantissa(54) = '1' then
                    -- normalized number
                    result(62 downto 52) := std_ulogic_vector(resize(exp, 11) + 1023);
                end if;
                result(51 downto 29) := mantissa(53 downto 31);
                if single_prec = '0' then
                    result(28 downto 0) := mantissa(30 downto 2);
                end if;
            when INFINITY =>
                result(62 downto 52) := "11111111111";
            when NAN =>
                result(62 downto 52) := "11111111111";
                result(51) := quieten_nan or mantissa(53);
                result(50 downto 29) := mantissa(52 downto 31);
                if single_prec = '0' then
                    result(28 downto 0) := mantissa(30 downto 2);
                end if;
        end case;
        return result;
    end;

    -- Determine whether to increment when rounding
    -- Returns rounding_inc & inexact
    -- Assumes x includes the bottom 29 bits of the mantissa already
    -- if single_prec = 1 (usually arranged by setting set_x = 1 earlier).
    function fp_rounding(mantissa: std_ulogic_vector(63 downto 0); x: std_ulogic;
                         single_prec: std_ulogic; rn: std_ulogic_vector(2 downto 0);
                         sign: std_ulogic)
        return std_ulogic_vector is
        variable grx : std_ulogic_vector(2 downto 0);
        variable ret : std_ulogic_vector(1 downto 0);
        variable lsb : std_ulogic;
    begin
        if single_prec = '0' then
            grx := mantissa(1 downto 0) & x;
            lsb := mantissa(2);
        else
            grx := mantissa(30 downto 29) & x;
            lsb := mantissa(31);
        end if;
        ret(1) := '0';
        ret(0) := or (grx);
        case rn(1 downto 0) is
            when "00" =>        -- round to nearest
                if grx = "100" and rn(2) = '0' then
                    ret(1) := lsb; -- tie, round to even
                else
                    ret(1) := grx(2);
                end if;
            when "01" =>        -- round towards zero
            when others =>      -- round towards +/- inf
                if rn(0) = sign then
                    -- round towards greater magnitude
                    ret(1) := ret(0);
                end if;
        end case;
        return ret;
    end;

    -- Determine result flags to write into the FPSCR
    function result_flags(sign: std_ulogic; class: fp_number_class; unitbit: std_ulogic)
        return std_ulogic_vector is
    begin
        case class is
            when ZERO =>
                return sign & "0010";
            when FINITE =>
                return (not unitbit) & sign & (not sign) & "00";
            when INFINITY =>
                return '0' & sign & (not sign) & "01";
            when NAN =>
                return "10001";
        end case;
    end;

begin
    fpu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.busy <= '0';
                r.instr_done <= '0';
                r.do_intr <= '0';
                r.fpscr <= (others => '0');
                r.writing_back <= '0';
            else
                assert not (r.state /= IDLE and e_in.valid = '1') severity failure;
                r <= rin;
            end if;
        end if;
    end process;

    e_out.busy <= r.busy;
    e_out.exception <= r.fpscr(FPSCR_FEX);
    e_out.interrupt <= r.do_intr;

    w_out.valid <= r.instr_done and not r.do_intr;
    w_out.write_enable <= r.writing_back;
    w_out.write_reg <= r.dest_fpr;
    w_out.write_data <= fp_result;
    w_out.write_cr_enable <= r.instr_done and (r.rc or r.is_cmp);
    w_out.write_cr_mask <= r.cr_mask;
    w_out.write_cr_data <= r.cr_result & r.cr_result & r.cr_result & r.cr_result &
                           r.cr_result & r.cr_result & r.cr_result & r.cr_result;

    fpu_1: process(all)
        variable v           : reg_type;
        variable adec        : fpu_reg_type;
        variable bdec        : fpu_reg_type;
        variable fpscr_mask  : std_ulogic_vector(31 downto 0);
        variable illegal     : std_ulogic;
        variable j, k        : integer;
        variable flm         : std_ulogic_vector(7 downto 0);
        variable int_input   : std_ulogic;
        variable mask        : std_ulogic_vector(63 downto 0);
        variable in_a0       : std_ulogic_vector(63 downto 0);
        variable in_b0       : std_ulogic_vector(63 downto 0);
        variable misc        : std_ulogic_vector(63 downto 0);
        variable shift_res   : std_ulogic_vector(63 downto 0);
        variable round       : std_ulogic_vector(1 downto 0);
        variable update_fx   : std_ulogic;
        variable arith_done  : std_ulogic;
        variable invalid     : std_ulogic;
        variable mant_nz     : std_ulogic;
        variable min_exp     : signed(EXP_BITS-1 downto 0);
        variable max_exp     : signed(EXP_BITS-1 downto 0);
        variable bias_exp    : signed(EXP_BITS-1 downto 0);
        variable new_exp     : signed(EXP_BITS-1 downto 0);
        variable exp_tiny    : std_ulogic;
        variable exp_huge    : std_ulogic;
        variable renormalize : std_ulogic;
        variable clz         : std_ulogic_vector(5 downto 0);
        variable set_x       : std_ulogic;
        variable mshift      : signed(EXP_BITS-1 downto 0);
        variable need_check  : std_ulogic;
        variable msb         : std_ulogic;
    begin
        v := r;
        illegal := '0';
        v.busy := '0';
        int_input := '0';

        -- capture incoming instruction
        if e_in.valid = '1' then
            v.insn := e_in.insn;
            v.op := e_in.op;
            v.fe_mode := or (e_in.fe_mode);
            v.dest_fpr := e_in.frt;
            v.single_prec := e_in.single;
            v.int_result := '0';
            v.rc := e_in.rc;
            v.is_cmp := e_in.out_cr;
            if e_in.out_cr = '0' then
                v.cr_mask := num_to_fxm(1);
            else
                v.cr_mask := num_to_fxm(to_integer(unsigned(insn_bf(e_in.insn))));
            end if;
            int_input := '0';
            if e_in.op = OP_FPOP_I then
                int_input := '1';
            end if;
            v.quieten_nan := '1';
            v.tiny := '0';
            v.denorm := '0';
            v.round_mode := '0' & r.fpscr(FPSCR_RN+1 downto FPSCR_RN);
            adec := decode_dp(e_in.fra, int_input);
            bdec := decode_dp(e_in.frb, int_input);
            v.a := adec;
            v.b := bdec;
        end if;

        r_hi_nz <= or (r.r(55 downto 31));
        r_lo_nz <= or (r.r(30 downto 2));

        if r.single_prec = '0' then
            max_exp := to_signed(1023, EXP_BITS);
            min_exp := to_signed(-1022, EXP_BITS);
            bias_exp := to_signed(1536, EXP_BITS);
        else
            max_exp := to_signed(127, EXP_BITS);
            min_exp := to_signed(-126, EXP_BITS);
            bias_exp := to_signed(192, EXP_BITS);
        end if;
        new_exp := r.result_exp - r.shift;
        exp_tiny := '0';
        exp_huge := '0';
        if new_exp < min_exp then
            exp_tiny := '1';
        end if;
        if new_exp > max_exp then
            exp_huge := '1';
        end if;

        v.writing_back := '0';
        v.instr_done := '0';
        v.update_fprf := '0';
        v.shift := to_signed(0, EXP_BITS);
        opsel_a <= AIN_R;
        opsel_ainv <= '0';
        opsel_amask <= '0';
        opsel_b <= BIN_ZERO;
        opsel_r <= RES_SUM;
        carry_in <= '0';
        misc_sel <= "0000";
        fpscr_mask := (others => '1');
        update_fx := '0';
        arith_done := '0';
        invalid := '0';
        renormalize := '0';
        set_x := '0';

        case r.state is
            when IDLE =>
                if e_in.valid = '1' then
                    case e_in.insn(5 downto 1) is
                        when "00000" =>
                            v.state := DO_MCRFS;
                        when "00110" =>
                            if e_in.insn(10) = '0' then
                                if e_in.insn(8) = '0' then
                                    v.state := DO_MTFSB;
                                else
                                    v.state := DO_MTFSFI;
                                end if;
                            else
                                v.state := DO_FMRG;
                            end if;
                        when "00111" =>
                            if e_in.insn(8) = '0' then
                                v.state := DO_MFFS;
                            else
                                v.state := DO_MTFSF;
                            end if;
                        when "01000" =>
                            if e_in.insn(9 downto 8) /= "11" then
                                v.state := DO_FMR;
                            else
                                v.state := DO_FRI;
                            end if;
                        when "01100" =>
                            v.state := DO_FRSP;
                        when "01110" =>
                            if int_input = '1' then
                                -- fcfid[u][s]
                                v.state := DO_FCFID;
                            else
                                v.state := DO_FCTI;
                            end if;
                        when "01111" =>
                            v.round_mode := "001";
                            v.state := DO_FCTI;
                        when others =>
                            illegal := '1';
                    end case;
                end if;
                v.x := '0';
                v.old_exc := r.fpscr(FPSCR_VX downto FPSCR_XX);

            when DO_MCRFS =>
                j := to_integer(unsigned(insn_bfa(r.insn)));
                for i in 0 to 7 loop
                    if i = j then
                        k := (7 - i) * 4;
                        v.cr_result := r.fpscr(k + 3 downto k);
                        fpscr_mask(k + 3 downto k) := "0000";
                    end if;
                end loop;
                v.fpscr := r.fpscr and (fpscr_mask or x"6007F8FF");
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSB =>
                -- mtfsb{0,1}
                j := to_integer(unsigned(insn_bt(r.insn)));
                for i in 0 to 31 loop
                    if i = j then
                        v.fpscr(31 - i) := r.insn(6);
                    end if;
                end loop;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSFI =>
                -- mtfsfi
                j := to_integer(unsigned(insn_bf(r.insn)));
                if r.insn(16) = '0' then
                    for i in 0 to 7 loop
                        if i = j then
                            k := (7 - i) * 4;
                            v.fpscr(k + 3 downto k) := insn_u(r.insn);
                        end if;
                    end loop;
                end if;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_FMRG =>
                -- fmrgew, fmrgow
                opsel_r <= RES_MISC;
                misc_sel <= "01" & r.insn(8) & '0';
                v.int_result := '1';
                v.writing_back := '1';
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MFFS =>
                v.int_result := '1';
                v.writing_back := '1';
                opsel_r <= RES_MISC;
                case r.insn(20 downto 16) is
                    when "00000" =>
                        -- mffs
                    when "00001" =>
                        -- mffsce
                        v.fpscr(FPSCR_VE downto FPSCR_XE) := "00000";
                    when "10100" | "10101" =>
                        -- mffscdrn[i] (but we don't implement DRN)
                        fpscr_mask := x"000000FF";
                    when "10110" =>
                        -- mffscrn
                        fpscr_mask := x"000000FF";
                        v.fpscr(FPSCR_RN+1 downto FPSCR_RN) :=
                            r.b.mantissa(FPSCR_RN+1 downto FPSCR_RN);
                    when "10111" =>
                        -- mffscrni
                        fpscr_mask := x"000000FF";
                        v.fpscr(FPSCR_RN+1 downto FPSCR_RN) := r.insn(12 downto 11);
                    when "11000" =>
                        -- mffsl
                        fpscr_mask := x"0007F0FF";
                    when others =>
                        illegal := '1';
                end case;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSF =>
                if r.insn(25) = '1' then
                    flm := x"FF";
                elsif r.insn(16) = '1' then
                    flm := x"00";
                else
                    flm := r.insn(24 downto 17);
                end if;
                for i in 0 to 7 loop
                    k := i * 4;
                    if flm(i) = '1' then
                        v.fpscr(k + 3 downto k) := r.b.mantissa(k + 3 downto k);
                    end if;
                end loop;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_FMR =>
                opsel_a <= AIN_B;
                v.result_class := r.b.class;
                v.result_exp := r.b.exponent;
                v.quieten_nan := '0';
                if r.insn(9) = '1' then
                    v.result_sign := '0';              -- fabs
                elsif r.insn(8) = '1' then
                    v.result_sign := '1';              -- fnabs
                elsif r.insn(7) = '1' then
                    v.result_sign := r.b.negative;     -- fmr
                elsif r.insn(6) = '1' then
                    v.result_sign := not r.b.negative; -- fneg
                else
                    v.result_sign := r.a.negative;     -- fcpsgn
                end if;
                v.writing_back := '1';
                v.instr_done := '1';
                v.state := IDLE;

            when DO_FRI =>    -- fri[nzpm]
                opsel_a <= AIN_B;
                v.result_class := r.b.class;
                v.result_sign := r.b.negative;
                v.result_exp := r.b.exponent;
                v.fpscr(FPSCR_FR) := '0';
                v.fpscr(FPSCR_FI) := '0';
                if r.b.class = NAN and r.b.mantissa(53) = '0' then
                    -- Signalling NAN
                    v.fpscr(FPSCR_VXSNAN) := '1';
                    invalid := '1';
                end if;
                if r.b.class = FINITE then
                    if r.b.exponent >= to_signed(52, EXP_BITS) then
                        -- integer already, no rounding required
                        arith_done := '1';
                    else
                        v.shift := r.b.exponent - to_signed(52, EXP_BITS);
                        v.state := FRI_1;
                        v.round_mode := '1' & r.insn(7 downto 6);
                    end if;
                else
                    arith_done := '1';
                end if;

            when DO_FRSP =>
                opsel_a <= AIN_B;
                v.result_class := r.b.class;
                v.result_sign := r.b.negative;
                v.result_exp := r.b.exponent;
                v.fpscr(FPSCR_FR) := '0';
                v.fpscr(FPSCR_FI) := '0';
                if r.b.class = NAN and r.b.mantissa(53) = '0' then
                    -- Signalling NAN
                    v.fpscr(FPSCR_VXSNAN) := '1';
                    invalid := '1';
                end if;
                set_x := '1';
                if r.b.class = FINITE then
                    if r.b.exponent < to_signed(-126, EXP_BITS) then
                        v.shift := r.b.exponent - to_signed(-126, EXP_BITS);
                        v.state := ROUND_UFLOW;
                    elsif r.b.exponent > to_signed(127, EXP_BITS) then
                        v.state := ROUND_OFLOW;
                    else
                        v.shift := to_signed(-2, EXP_BITS);
                        v.state := ROUNDING;
                    end if;
                else
                    arith_done := '1';
                end if;

            when DO_FCTI =>
                -- instr bit 9: 1=dword 0=word
                -- instr bit 8: 1=unsigned 0=signed
                -- instr bit 1: 1=round to zero 0=use fpscr[RN]
                opsel_a <= AIN_B;
                v.result_class := r.b.class;
                v.result_sign := r.b.negative;
                v.result_exp := r.b.exponent;
                v.fpscr(FPSCR_FR) := '0';
                v.fpscr(FPSCR_FI) := '0';
                if r.b.class = NAN and r.b.mantissa(53) = '0' then
                    -- Signalling NAN
                    v.fpscr(FPSCR_VXSNAN) := '1';
                    invalid := '1';
                end if;

                v.int_result := '1';
                case r.b.class is
                    when ZERO =>
                        arith_done := '1';
                    when FINITE =>
                        if r.b.exponent >= to_signed(64, EXP_BITS) or
                            (r.insn(9) = '0' and r.b.exponent >= to_signed(32, EXP_BITS)) then
                            v.state := INT_OFLOW;
                        elsif r.b.exponent >= to_signed(52, EXP_BITS) then
                            -- integer already, no rounding required,
                            -- shift into final position
                            v.shift := r.b.exponent - to_signed(54, EXP_BITS);
                            if r.insn(8) = '1' and r.b.negative = '1' then
                                v.state := INT_OFLOW;
                            else
                                v.state := INT_ISHIFT;
                            end if;
                        else
                            v.shift := r.b.exponent - to_signed(52, EXP_BITS);
                            v.state := INT_SHIFT;
                        end if;
                    when INFINITY | NAN =>
                        v.state := INT_OFLOW;
                end case;

            when DO_FCFID =>
                v.result_sign := '0';
                opsel_a <= AIN_B;
                if r.insn(8) = '0' and r.b.negative = '1' then
                    -- fcfid[s] with negative operand, set R = -B
                    opsel_ainv <= '1';
                    carry_in <= '1';
                    v.result_sign := '1';
                end if;
                v.result_class := r.b.class;
                v.result_exp := to_signed(54, EXP_BITS);
                v.fpscr(FPSCR_FR) := '0';
                v.fpscr(FPSCR_FI) := '0';
                if r.b.class = ZERO then
                    arith_done := '1';
                else
                    v.state := FINISH;
                end if;

            when INT_SHIFT =>
                opsel_r <= RES_SHIFT;
                set_x := '1';
                v.state := INT_ROUND;
                v.shift := to_signed(-2, EXP_BITS);

            when INT_ROUND =>
                opsel_r <= RES_SHIFT;
                round := fp_rounding(r.r, r.x, '0', r.round_mode, r.result_sign);
                v.fpscr(FPSCR_FR downto FPSCR_FI) := round;
                -- Check for negative values that don't round to 0 for fcti*u*
                if r.insn(8) = '1' and r.result_sign = '1' and
                    (r_hi_nz or r_lo_nz or v.fpscr(FPSCR_FR)) = '1' then
                    v.state := INT_OFLOW;
                else
                    v.state := INT_FINAL;
                end if;

            when INT_ISHIFT =>
                opsel_r <= RES_SHIFT;
                v.state := INT_FINAL;

            when INT_FINAL =>
                -- Negate if necessary, and increment for rounding if needed
                opsel_ainv <= r.result_sign;
                carry_in <= r.fpscr(FPSCR_FR) xor r.result_sign;
                -- Check for possible overflows
                case r.insn(9 downto 8) is
                    when "00" =>        -- fctiw[z]
                        need_check := r.r(31) or (r.r(30) and not r.result_sign);
                    when "01" =>        -- fctiwu[z]
                        need_check := r.r(31);
                    when "10" =>        -- fctid[z]
                        need_check := r.r(63) or (r.r(62) and not r.result_sign);
                    when others =>      -- fctidu[z]
                        need_check := r.r(63);
                end case;
                if need_check = '1' then
                    v.state := INT_CHECK;
                else
                    if r.fpscr(FPSCR_FI) = '1' then
                        v.fpscr(FPSCR_XX) := '1';
                    end if;
                    arith_done := '1';
                end if;

            when INT_CHECK =>
                if r.insn(9) = '0' then
                    msb := r.r(31);
                else
                    msb := r.r(63);
                end if;
                misc_sel <= '1' & r.insn(9 downto 8) & r.result_sign;
                if (r.insn(8) = '0' and msb /= r.result_sign) or
                    (r.insn(8) = '1' and msb /= '1') then
                    opsel_r <= RES_MISC;
                    v.fpscr(FPSCR_VXCVI) := '1';
                    invalid := '1';
                else
                    if r.fpscr(FPSCR_FI) = '1' then
                        v.fpscr(FPSCR_XX) := '1';
                    end if;
                end if;
                arith_done := '1';

            when INT_OFLOW =>
                opsel_r <= RES_MISC;
                misc_sel <= '1' & r.insn(9 downto 8) & r.result_sign;
                if r.b.class = NAN then
                    misc_sel(0) <= '1';
                end if;
                v.fpscr(FPSCR_VXCVI) := '1';
                invalid := '1';
                arith_done := '1';

            when FRI_1 =>
                opsel_r <= RES_SHIFT;
                set_x := '1';
                v.shift := to_signed(-2, EXP_BITS);
                v.state := ROUNDING;

            when FINISH =>
                if r.r(63 downto 54) /= "0000000001" then
                    renormalize := '1';
                    v.state := NORMALIZE;
                else
                    set_x := '1';
                    if exp_tiny = '1' then
                        v.shift := new_exp - min_exp;
                        v.state := ROUND_UFLOW;
                    elsif exp_huge = '1' then
                        v.state := ROUND_OFLOW;
                    else
                        v.shift := to_signed(-2, EXP_BITS);
                        v.state := ROUNDING;
                    end if;
                end if;

            when NORMALIZE =>
                -- Shift so we have 9 leading zeroes (we know R is non-zero)
                opsel_r <= RES_SHIFT;
                set_x := '1';
                if exp_tiny = '1' then
                    v.shift := new_exp - min_exp;
                    v.state := ROUND_UFLOW;
                elsif exp_huge = '1' then
                    v.state := ROUND_OFLOW;
                else
                    v.shift := to_signed(-2, EXP_BITS);
                    v.state := ROUNDING;
                end if;

            when ROUND_UFLOW =>
                v.tiny := '1';
                if r.fpscr(FPSCR_UE) = '0' then
                    -- disabled underflow exception case
                    -- have to denormalize before rounding
                    opsel_r <= RES_SHIFT;
                    set_x := '1';
                    v.shift := to_signed(-2, EXP_BITS);
                    v.state := ROUNDING;
                else
                    -- enabled underflow exception case
                    -- if denormalized, have to normalize before rounding
                    v.fpscr(FPSCR_UX) := '1';
                    v.result_exp := r.result_exp + bias_exp;
                    if r.r(54) = '0' then
                        renormalize := '1';
                        v.state := NORMALIZE;
                    else
                        v.shift := to_signed(-2, EXP_BITS);
                        v.state := ROUNDING;
                    end if;
                end if;

            when ROUND_OFLOW =>
                v.fpscr(FPSCR_OX) := '1';
                if r.fpscr(FPSCR_OE) = '0' then
                    -- disabled overflow exception
                    -- result depends on rounding mode
                    v.fpscr(FPSCR_XX) := '1';
                    v.fpscr(FPSCR_FI) := '1';
                    if r.round_mode(1 downto 0) = "00" or
                        (r.round_mode(1) = '1' and r.round_mode(0) = r.result_sign) then
                        v.result_class := INFINITY;
                        v.fpscr(FPSCR_FR) := '1';
                    else
                        v.fpscr(FPSCR_FR) := '0';
                    end if;
                    -- construct largest representable number
                    v.result_exp := max_exp;
                    opsel_r <= RES_MISC;
                    misc_sel <= "001" & r.single_prec;
                    arith_done := '1';
                else
                    -- enabled overflow exception
                    v.result_exp := r.result_exp - bias_exp;
                    v.shift := to_signed(-2, EXP_BITS);
                    v.state := ROUNDING;
                end if;

            when ROUNDING =>
                opsel_amask <= '1';
                round := fp_rounding(r.r, r.x, r.single_prec, r.round_mode, r.result_sign);
                v.fpscr(FPSCR_FR downto FPSCR_FI) := round;
                if round(1) = '1' then
                    -- set mask to increment the LSB for the precision
                    opsel_b <= BIN_MASK;
                    carry_in <= '1';
                    v.shift := to_signed(-1, EXP_BITS);
                    v.state := ROUNDING_2;
                else
                    if r.r(54) = '0' then
                        -- result after masking could be zero, or could be a
                        -- denormalized result that needs to be renormalized
                        renormalize := '1';
                        v.state := ROUNDING_3;
                    else
                        arith_done := '1';
                    end if;
                end if;
                if round(0) = '1' then
                    v.fpscr(FPSCR_XX) := '1';
                    if r.tiny = '1' then
                        v.fpscr(FPSCR_UX) := '1';
                    end if;
                end if;

            when ROUNDING_2 =>
                -- Check for overflow during rounding
                v.x := '0';
                if r.r(55) = '1' then
                    opsel_r <= RES_SHIFT;
                    if exp_huge = '1' then
                        v.state := ROUND_OFLOW;
                    else
                        arith_done := '1';
                    end if;
                elsif r.r(54) = '0' then
                    -- Do CLZ so we can renormalize the result
                    renormalize := '1';
                    v.state := ROUNDING_3;
                else
                    arith_done := '1';
                end if;

            when ROUNDING_3 =>
                mant_nz := r_hi_nz or (r_lo_nz and not r.single_prec);
                if mant_nz = '0' then
                    v.result_class := ZERO;
                    arith_done := '1';
                else
                    -- Renormalize result after rounding
                    opsel_r <= RES_SHIFT;
                    v.denorm := exp_tiny;
                    v.shift := new_exp - to_signed(-1022, EXP_BITS);
                    if new_exp < to_signed(-1022, EXP_BITS) then
                        v.state := DENORM;
                    else
                        arith_done := '1';
                    end if;
                end if;

            when DENORM =>
                opsel_r <= RES_SHIFT;
                arith_done := '1';

        end case;

        if arith_done = '1' then
            -- Enabled invalid exception doesn't write result or FPRF
            if (invalid and r.fpscr(FPSCR_VE)) = '0' then
                v.writing_back := '1';
                v.update_fprf := '1';
            end if;
            v.instr_done := '1';
            v.state := IDLE;
            update_fx := '1';
        end if;

        -- Data path.
        -- This has A and B input multiplexers, an adder, a shifter,
        -- count-leading-zeroes logic, and a result mux.
        if r.single_prec = '1' then
            mshift := r.shift + to_signed(-29, EXP_BITS);
        else
            mshift := r.shift;
        end if;
        if mshift < to_signed(-64, EXP_BITS) then
            mask := (others => '1');
        elsif mshift >= to_signed(0, EXP_BITS) then
            mask := (others => '0');
        else
            mask := right_mask(unsigned(mshift(5 downto 0)));
        end if;
        case opsel_a is
            when AIN_R =>
                in_a0 := r.r;
            when AIN_A =>
                in_a0 := r.a.mantissa;
            when others =>
                in_a0 := r.b.mantissa;
        end case;
        if (or (mask and in_a0)) = '1' and set_x = '1' then
            v.x := '1';
        end if;
        if opsel_ainv = '1' then
            in_a0 := not in_a0;
        end if;
        if opsel_amask = '1' then
            in_a0 := in_a0 and not mask;
        end if;
        in_a <= in_a0;
        case opsel_b is
            when BIN_ZERO =>
                in_b0 := (others => '0');
            when BIN_R =>
                in_b0 := r.r;
            when BIN_MASK =>
                in_b0 := mask;
            when others =>
                in_b0 := (others => '0');
        end case;
        in_b <= in_b0;
        if r.shift >= to_signed(-64, EXP_BITS) and r.shift <= to_signed(63, EXP_BITS) then
            shift_res := shifter_64(r.r & x"00000000000000",
                                    std_ulogic_vector(r.shift(6 downto 0)));
        else
            shift_res := (others => '0');
        end if;
        case opsel_r is
            when RES_SUM =>
                result <= std_ulogic_vector(unsigned(in_a) + unsigned(in_b) + carry_in);
            when RES_SHIFT =>
                result <= shift_res;
            when others =>
                case misc_sel is
                    when "0000" =>
                        misc := x"00000000" & (r.fpscr and fpscr_mask);
                    when "0010" =>
                        -- mantissa of max representable DP number
                        misc := x"007ffffffffffffc";
                    when "0011" =>
                        -- mantissa of max representable SP number
                        misc := x"007fffff80000000";
                    when "0100" =>
                        -- fmrgow result
                        misc := r.a.mantissa(31 downto 0) & r.b.mantissa(31 downto 0);
                    when "0110" =>
                        -- fmrgew result
                        misc := r.a.mantissa(63 downto 32) & r.b.mantissa(63 downto 32);
                    when "1000" =>
                        -- max positive result for fctiw[z]
                        misc := x"000000007fffffff";
                    when "1001" =>
                        -- max negative result for fctiw[z]
                        misc := x"ffffffff80000000";
                    when "1010" =>
                        -- max positive result for fctiwu[z]
                        misc := x"00000000ffffffff";
                    when "1011" =>
                        -- max negative result for fctiwu[z]
                        misc := x"0000000000000000";
                    when "1100" =>
                        -- max positive result for fctid[z]
                        misc := x"7fffffffffffffff";
                    when "1101" =>
                        -- max negative result for fctid[z]
                        misc := x"8000000000000000";
                    when "1110" =>
                        -- max positive result for fctidu[z]
                        misc := x"ffffffffffffffff";
                    when "1111" =>
                        -- max negative result for fctidu[z]
                        misc := x"0000000000000000";
                    when others =>
                        misc := x"0000000000000000";
                end case;
                result <= misc;
        end case;
        v.r := result;

        if opsel_r = RES_SHIFT then
            v.result_exp := new_exp;
        end if;

        if renormalize = '1' then
            clz := count_left_zeroes(r.r);
            v.shift := resize(signed('0' & clz) - 9, EXP_BITS);
        end if;

        if r.int_result = '1' then
            fp_result <= r.r;
        else
            fp_result <= pack_dp(r.result_sign, r.result_class, r.result_exp, r.r,
                                 r.single_prec, r.quieten_nan);
        end if;
        if r.update_fprf = '1' then
            v.fpscr(FPSCR_C downto FPSCR_FU) := result_flags(r.result_sign, r.result_class,
                                                             r.r(54) and not r.denorm);
        end if;

        v.fpscr(FPSCR_VX) := (or (v.fpscr(FPSCR_VXSNAN downto FPSCR_VXVC))) or
                             (or (v.fpscr(FPSCR_VXSOFT downto FPSCR_VXCVI)));
        v.fpscr(FPSCR_FEX) := or (v.fpscr(FPSCR_VX downto FPSCR_XX) and
                                  v.fpscr(FPSCR_VE downto FPSCR_XE));
        if update_fx = '1' and
            (v.fpscr(FPSCR_VX downto FPSCR_XX) and not r.old_exc) /= "00000" then
            v.fpscr(FPSCR_FX) := '1';
        end if;
        if r.rc = '1' then
            v.cr_result := v.fpscr(FPSCR_FX downto FPSCR_OX);
        end if;

        if illegal = '1' then
            v.instr_done := '0';
            v.do_intr := '0';
            v.writing_back := '0';
            v.busy := '0';
            v.state := IDLE;
        else
            v.do_intr := v.instr_done and v.fpscr(FPSCR_FEX) and r.fe_mode;
            if v.state /= IDLE or v.do_intr = '1' then
                v.busy := '1';
            end if;
        end if;

        rin <= v;
        e_out.illegal <= illegal;
    end process;

end architecture behaviour;
