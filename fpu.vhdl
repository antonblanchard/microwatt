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
        flush_in : in std_ulogic;

        e_in  : in  Execute1ToFPUType;
        e_out : out FPUToExecute1Type;

        w_out : out FPUToWritebackType
        );
end entity fpu;

architecture behaviour of fpu is
    type fp_number_class is (ZERO, FINITE, INFINITY, NAN);

    constant EXP_BITS : natural := 13;
    constant UNIT_BIT : natural := 56;
    constant QNAN_BIT : natural := UNIT_BIT - 1;
    constant SP_LSB   : natural := UNIT_BIT - 23;
    constant SP_GBIT  : natural := SP_LSB - 1;
    constant SP_RBIT  : natural := SP_LSB - 2;
    constant DP_LSB   : natural := UNIT_BIT - 52;
    constant DP_GBIT  : natural := DP_LSB - 1;
    constant DP_RBIT  : natural := DP_LSB - 2;

    type fpu_reg_type is record
        class    : fp_number_class;
        negative : std_ulogic;
        denorm   : std_ulogic;
        naninf   : std_ulogic;
        zeroexp  : std_ulogic;
        exponent : signed(EXP_BITS-1 downto 0);         -- unbiased
        mantissa : std_ulogic_vector(63 downto 0);      -- 8.56 format
    end record;

    type state_t is (IDLE, DO_ILLEGAL, DO_SPECIAL,
                     DO_MCRFS, DO_MTFSB, DO_MTFSFI, DO_MFFS, DO_MTFSF,
                     DO_FMR, DO_FMRG, DO_FCMP, DO_FTDIV, DO_FTSQRT,
                     DO_FCFID, DO_FCTI,
                     DO_FRSP, DO_FRSP_2, DO_FRI,
                     DO_FADD, DO_FMUL, DO_FDIV, DO_FSQRT, DO_FMADD,
                     DO_FRE,
                     DO_FSEL,
                     DO_IDIVMOD,
                     FRI_1,
                     ADD_1, ADD_SHIFT, ADD_2, ADD_2B, ADD_3,
                     CMP_1, CMP_2,
                     MULT_1,
                     FMADD_0, FMADD_1, FMADD_2, FMADD_3,
                     FMADD_4, FMADD_5, FMADD_6,
                     DIV_2, DIV_3, DIV_4, DIV_5, DIV_6,
                     FRE_1,
                     SQRT_ODD, RSQRT_1,
                     FTDIV_1,
                     SQRT_1, SQRT_2, SQRT_3, SQRT_4,
                     SQRT_5, SQRT_6, SQRT_7, SQRT_8,
                     SQRT_9, SQRT_10, SQRT_11, SQRT_12,
                     INT_SHIFT, INT_ROUND, INT_ISHIFT,
                     INT_FINAL, INT_CHECK, INT_OFLOW,
                     FINISH, NORMALIZE,
                     ROUND_UFLOW, ROUND_OFLOW,
                     ROUNDING, ROUND_INC, ROUNDING_2, ROUNDING_3,
                     DENORM,
                     RENORM_A, RENORM_B, RENORM_C,
                     RENORM_1, RENORM_2,
                     IDIV_NORMB, IDIV_NORMB2, IDIV_NORMB3,
                     IDIV_CLZA, IDIV_CLZA2, IDIV_CLZA3,
                     IDIV_NR0, IDIV_NR1, IDIV_NR2, IDIV_USE0_5,
                     IDIV_DODIV, IDIV_SH32,
                     IDIV_DIV, IDIV_DIV2, IDIV_DIV3, IDIV_DIV4, IDIV_DIV5,
                     IDIV_DIV6, IDIV_DIV7, IDIV_DIV8, IDIV_DIV9,
                     IDIV_EXT_TBH, IDIV_EXT_TBH2, IDIV_EXT_TBH3,
                     IDIV_EXT_TBH4, IDIV_EXT_TBH5,
                     IDIV_EXTDIV, IDIV_EXTDIV1, IDIV_EXTDIV2, IDIV_EXTDIV3,
                     IDIV_EXTDIV4, IDIV_EXTDIV5, IDIV_EXTDIV6,
                     IDIV_MODADJ, IDIV_MODADJ_NEG, IDIV_MODSUB,
                     IDIV_DIVADJ, IDIV_OVFCHK, IDIV_DONE, IDIV_ZERO);

    type decode32 is array(0 to 31) of state_t;
    type decode8 is array(0 to 7) of state_t;

    type specialcase_t is record
        invalid       : std_ulogic;
        zero_divide   : std_ulogic;
        new_fpscr     : std_ulogic_vector(31 downto 0);
        immed_result  : std_ulogic;      -- result is an input, zero, infinity or NaN
        qnan_result   : std_ulogic;
        result_sel    : std_ulogic_vector(2 downto 0);
        result_class  : fp_number_class;
        rsgn_op       : std_ulogic_vector(1 downto 0);
    end record;

    type reg_type is record
        state        : state_t;
        busy         : std_ulogic;
        f2stall      : std_ulogic;
        instr_done   : std_ulogic;
        complete     : std_ulogic;
        do_intr      : std_ulogic;
        illegal      : std_ulogic;
        op           : insn_type_t;
        insn         : std_ulogic_vector(31 downto 0);
        instr_tag    : instr_tag_t;
        dest_fpr     : gspr_index_t;
        fe_mode      : std_ulogic;
        rc           : std_ulogic;
        fp_rc        : std_ulogic;
        is_cmp       : std_ulogic;
        single_prec  : std_ulogic;
        sp_result    : std_ulogic;
        fpscr        : std_ulogic_vector(31 downto 0);
        comm_fpscr   : std_ulogic_vector(31 downto 0);  -- committed FPSCR value
        a            : fpu_reg_type;
        b            : fpu_reg_type;
        c            : fpu_reg_type;
        r            : std_ulogic_vector(63 downto 0);  -- 8.56 format
        s            : std_ulogic_vector(55 downto 0);  -- extended fraction
        x            : std_ulogic;
        p            : std_ulogic_vector(63 downto 0);  -- 8.56 format
        y            : std_ulogic_vector(63 downto 0);  -- 8.56 format
        result_sign  : std_ulogic;
        result_class : fp_number_class;
        result_exp   : signed(EXP_BITS-1 downto 0);
        shift        : signed(EXP_BITS-1 downto 0);
        writing_fpr  : std_ulogic;
        write_reg    : gspr_index_t;
        complete_tag : instr_tag_t;
        writing_cr   : std_ulogic;
        writing_xer  : std_ulogic;
        int_result   : std_ulogic;
        cr_result    : std_ulogic_vector(3 downto 0);
        cr_mask      : std_ulogic_vector(7 downto 0);
        old_exc      : std_ulogic_vector(4 downto 0);
        update_fprf  : std_ulogic;
        quieten_nan  : std_ulogic;
        nsnan_result : std_ulogic;
        tiny         : std_ulogic;
        denorm       : std_ulogic;
        round_mode   : std_ulogic_vector(2 downto 0);
        is_subtract  : std_ulogic;
        add_bsmall   : std_ulogic;
        is_arith     : std_ulogic;
        is_addition  : std_ulogic;
        is_multiply  : std_ulogic;
        is_inverse   : std_ulogic;
        is_sqrt      : std_ulogic;
        first        : std_ulogic;
        count        : unsigned(1 downto 0);
        doing_ftdiv  : std_ulogic_vector(1 downto 0);
        use_a        : std_ulogic;
        use_b        : std_ulogic;
        use_c        : std_ulogic;
        invalid      : std_ulogic;
        negate       : std_ulogic;
        longmask     : std_ulogic;
        integer_op   : std_ulogic;
        divext       : std_ulogic;
        divmod       : std_ulogic;
        is_signed    : std_ulogic;
        int_ovf      : std_ulogic;
        div_close    : std_ulogic;
        inc_quot     : std_ulogic;
        a_hi         : std_ulogic_vector(7 downto 0);
        a_lo         : std_ulogic_vector(55 downto 0);
        m32b         : std_ulogic;
        oe           : std_ulogic;
        xerc         : xer_common_t;
        xerc_result  : xer_common_t;
        res_sign     : std_ulogic;
        res_int      : std_ulogic;
        exec_state   : state_t;
        cycle_1      : std_ulogic;
        cycle_1_ar   : std_ulogic;
        regsel       : std_ulogic_vector(2 downto 0);
        is_nan_inf   : std_ulogic;
    end record;

    type lookup_table is array(0 to 1023) of std_ulogic_vector(17 downto 0);

    signal r, rin : reg_type;

    signal fp_result     : std_ulogic_vector(63 downto 0);
    signal opsel_a       : std_ulogic_vector(2 downto 0);
    signal opsel_b       : std_ulogic_vector(2 downto 0);
    signal opsel_c       : std_ulogic_vector(2 downto 0);
    signal opsel_r       : std_ulogic_vector(1 downto 0);
    signal opsel_s       : std_ulogic_vector(1 downto 0);
    signal opsel_aneg    : std_ulogic;
    signal opsel_aabs    : std_ulogic;
    signal opsel_mask    : std_ulogic;
    signal opsel_sel     : std_ulogic_vector(2 downto 0);
    signal in_a          : std_ulogic_vector(63 downto 0);
    signal in_b          : std_ulogic_vector(63 downto 0);
    signal result        : std_ulogic_vector(63 downto 0);
    signal lost_bits     : std_ulogic;
    signal r_hi_nz       : std_ulogic;
    signal r_lo_nz       : std_ulogic;
    signal r_gt_1        : std_ulogic;
    signal s_nz          : std_ulogic;
    signal misc_sel      : std_ulogic_vector(2 downto 0);
    signal f_to_multiply : MultiplyInputType;
    signal multiply_to_f : MultiplyOutputType;
    signal msel_1        : std_ulogic_vector(1 downto 0);
    signal msel_2        : std_ulogic_vector(1 downto 0);
    signal msel_add      : std_ulogic_vector(1 downto 0);
    signal msel_inv      : std_ulogic;
    signal inverse_est   : std_ulogic_vector(18 downto 0);

    -- opsel values
    constant AIN_ZERO     : std_ulogic_vector(2 downto 0) := "000";
    constant AIN_A        : std_ulogic_vector(2 downto 0) := "001";
    constant AIN_B        : std_ulogic_vector(2 downto 0) := "010";
    constant AIN_C        : std_ulogic_vector(2 downto 0) := "011";
    constant AIN_PS8      : std_ulogic_vector(2 downto 0) := "100";
    constant AIN_RND_B32  : std_ulogic_vector(2 downto 0) := "101";
    constant AIN_RND_RBIT : std_ulogic_vector(2 downto 0) := "110";
    constant AIN_RND      : std_ulogic_vector(2 downto 0) := "111";

    constant BIN_ZERO     : std_ulogic_vector(2 downto 0) := "000";
    constant BIN_R        : std_ulogic_vector(2 downto 0) := "001";
    constant BIN_MINUSR   : std_ulogic_vector(2 downto 0) := "100";
    constant BIN_ABSR     : std_ulogic_vector(2 downto 0) := "101";
    constant BIN_ADDSUBR  : std_ulogic_vector(2 downto 0) := "110";
    constant BIN_RSIGNR   : std_ulogic_vector(2 downto 0) := "111";

    constant CIN_ZERO     : std_ulogic_vector(2 downto 0) := "000";
    constant CIN_SUBEXT   : std_ulogic_vector(2 downto 0) := "001";
    constant CIN_ABSEXT   : std_ulogic_vector(2 downto 0) := "010";
    constant CIN_INC      : std_ulogic_vector(2 downto 0) := "011";
    constant CIN_ROUND    : std_ulogic_vector(2 downto 0) := "100";
    constant CIN_RNDX     : std_ulogic_vector(2 downto 0) := "101";
    constant CIN_RNDQ     : std_ulogic_vector(2 downto 0) := "110";

    constant RES_SUM   : std_ulogic_vector(1 downto 0) := "00";
    constant RES_SHIFT : std_ulogic_vector(1 downto 0) := "01";
    constant RES_MULT  : std_ulogic_vector(1 downto 0) := "10";
    constant RES_MISC  : std_ulogic_vector(1 downto 0) := "11";

    constant S_ZERO  : std_ulogic_vector(1 downto 0) := "00";
    constant S_NEG   : std_ulogic_vector(1 downto 0) := "01";
    constant S_SHIFT : std_ulogic_vector(1 downto 0) := "10";
    constant S_MULT  : std_ulogic_vector(1 downto 0) := "11";

    -- msel values
    constant MUL1_A : std_ulogic_vector(1 downto 0) := "00";
    constant MUL1_B : std_ulogic_vector(1 downto 0) := "01";
    constant MUL1_Y : std_ulogic_vector(1 downto 0) := "10";
    constant MUL1_R : std_ulogic_vector(1 downto 0) := "11";

    constant MUL2_C   : std_ulogic_vector(1 downto 0) := "00";
    constant MUL2_LUT : std_ulogic_vector(1 downto 0) := "01";
    constant MUL2_P   : std_ulogic_vector(1 downto 0) := "10";
    constant MUL2_R   : std_ulogic_vector(1 downto 0) := "11";

    constant MULADD_ZERO  : std_ulogic_vector(1 downto 0) := "00";
    constant MULADD_CONST : std_ulogic_vector(1 downto 0) := "01";
    constant MULADD_A     : std_ulogic_vector(1 downto 0) := "10";
    constant MULADD_RS    : std_ulogic_vector(1 downto 0) := "11";

    -- control signals and values for exponent data path
    constant REXP1_ZERO  : std_ulogic_vector(1 downto 0) := "00";
    constant REXP1_R     : std_ulogic_vector(1 downto 0) := "01";
    constant REXP1_A     : std_ulogic_vector(1 downto 0) := "10";
    constant REXP1_BHALF : std_ulogic_vector(1 downto 0) := "11";

    constant REXP2_CON   : std_ulogic_vector(1 downto 0) := "00";
    constant REXP2_NE    : std_ulogic_vector(1 downto 0) := "01";
    constant REXP2_C     : std_ulogic_vector(1 downto 0) := "10";
    constant REXP2_B     : std_ulogic_vector(1 downto 0) := "11";

    constant RECON2_ZERO : std_ulogic_vector(1 downto 0) := "00";
    constant RECON2_UNIT : std_ulogic_vector(1 downto 0) := "01";
    constant RECON2_BIAS : std_ulogic_vector(1 downto 0) := "10";
    constant RECON2_MAX  : std_ulogic_vector(1 downto 0) := "11";

    signal re_sel1       : std_ulogic_vector(1 downto 0);
    signal re_sel2       : std_ulogic_vector(1 downto 0);
    signal re_con2       : std_ulogic_vector(1 downto 0);
    signal re_neg1       : std_ulogic;
    signal re_neg2       : std_ulogic;
    signal re_set_result : std_ulogic;

    constant RSH1_ZERO   : std_ulogic_vector(1 downto 0) := "00";
    constant RSH1_B      : std_ulogic_vector(1 downto 0) := "01";
    constant RSH1_NE     : std_ulogic_vector(1 downto 0) := "10";
    constant RSH1_S      : std_ulogic_vector(1 downto 0) := "11";

    constant RSH2_CON    : std_ulogic := '0';
    constant RSH2_A      : std_ulogic := '1';

    constant RSCON2_ZERO    : std_ulogic_vector(3 downto 0) := "0000";
    constant RSCON2_1       : std_ulogic_vector(3 downto 0) := "0001";
    constant RSCON2_UNIT_52 : std_ulogic_vector(3 downto 0) := "0010";
    constant RSCON2_64_UNIT : std_ulogic_vector(3 downto 0) := "0011";
    constant RSCON2_32      : std_ulogic_vector(3 downto 0) := "0100";
    constant RSCON2_52      : std_ulogic_vector(3 downto 0) := "0101";
    constant RSCON2_UNIT    : std_ulogic_vector(3 downto 0) := "0110";
    constant RSCON2_63      : std_ulogic_vector(3 downto 0) := "0111";
    constant RSCON2_64      : std_ulogic_vector(3 downto 0) := "1000";
    constant RSCON2_MINEXP  : std_ulogic_vector(3 downto 0) := "1001";

    signal rs_sel1       : std_ulogic_vector(1 downto 0);
    signal rs_sel2       : std_ulogic;
    signal rs_con2       : std_ulogic_vector(3 downto 0);
    signal rs_neg1       : std_ulogic;
    signal rs_neg2       : std_ulogic;
    signal rs_norm       : std_ulogic;

    constant RSGN_NOP : std_ulogic_vector(1 downto 0) := "00";
    constant RSGN_INV : std_ulogic_vector(1 downto 0) := "01";
    constant RSGN_SUB : std_ulogic_vector(1 downto 0) := "10";
    constant RSGN_SEL : std_ulogic_vector(1 downto 0) := "11";

    signal  rcls_op      : std_ulogic_vector(1 downto 0);
    constant RCLS_NOP    : std_ulogic_vector(1 downto 0) := "00";
    constant RCLS_SEL    : std_ulogic_vector(1 downto 0) := "01";
    constant RCLS_TZERO  : std_ulogic_vector(1 downto 0) := "10";
    constant RCLS_TINF   : std_ulogic_vector(1 downto 0) := "11";

    constant CROP_NONE   : std_ulogic_vector(2 downto 0) := "000";
    constant CROP_FCMP   : std_ulogic_vector(2 downto 0) := "001";
    constant CROP_MCRFS  : std_ulogic_vector(2 downto 0) := "010";
    constant CROP_FTDIV  : std_ulogic_vector(2 downto 0) := "100";
    constant CROP_FTSQRT : std_ulogic_vector(2 downto 0) := "101";
    constant CROP_INTRES : std_ulogic_vector(2 downto 0) := "110";

    signal scinfo : specialcase_t;

    constant arith_decode : decode32 := (
        -- indexed by bits 5..1 of opcode
        2#01000# => DO_FRI,
        2#01100# => DO_FRSP,
        2#01110# => DO_FCTI,
        2#01111# => DO_FCTI,
        2#10010# => DO_FDIV,
        2#10100# => DO_FADD,
        2#10101# => DO_FADD,
        2#10110# => DO_FSQRT,
        2#11000# => DO_FRE,
        2#11001# => DO_FMUL,
        2#11010# => DO_FSQRT,
        2#11100# => DO_FMADD,
        2#11101# => DO_FMADD,
        2#11110# => DO_FMADD,
        2#11111# => DO_FMADD,
        others   => DO_ILLEGAL
        );

    constant cmp_decode : decode8 := (
        2#000# => DO_FCMP,
        2#001# => DO_FCMP,
        2#010# => DO_MCRFS,
        2#100# => DO_FTDIV,
        2#101# => DO_FTSQRT,
        others => DO_ILLEGAL
        );

    constant misc_decode : decode32 := (
        -- indexed by bits 10, 8, 4, 2, 1 of opcode
        2#00010# => DO_MTFSB,
        2#01010# => DO_MTFSFI,
        2#10010# => DO_FMRG,
        2#11010# => DO_FMRG,
        2#10011# => DO_MFFS,
        2#11011# => DO_MTFSF,
        2#10110# => DO_FCFID,
        2#11110# => DO_FCFID,
        others   => DO_ILLEGAL
        );

    -- Inverse lookup table, indexed by the top 8 fraction bits
    -- The first 256 entries are the reciprocal (1/x) lookup table,
    -- and the remaining 768 entries are the reciprocal square root table.
    -- Output range is [0.5, 1) in 0.19 format, though the top
    -- bit isn't stored since it is always 1.
    -- Each output value is the inverse of the center of the input
    -- range for the value, i.e. entry 0 is 1 / (1 + 1/512),
    -- entry 1 is 1 / (1 + 3/512), etc.
    constant inverse_table : lookup_table := (
        -- 1/x lookup table
        -- Unit bit is assumed to be 1, so input range is [1, 2)
        18x"3fc01", 18x"3f411", 18x"3ec31", 18x"3e460", 18x"3dc9f", 18x"3d4ec", 18x"3cd49", 18x"3c5b5",
        18x"3be2f", 18x"3b6b8", 18x"3af4f", 18x"3a7f4", 18x"3a0a7", 18x"39968", 18x"39237", 18x"38b14",
        18x"383fe", 18x"37cf5", 18x"375f9", 18x"36f0a", 18x"36828", 18x"36153", 18x"35a8a", 18x"353ce",
        18x"34d1e", 18x"3467a", 18x"33fe3", 18x"33957", 18x"332d7", 18x"32c62", 18x"325f9", 18x"31f9c",
        18x"3194a", 18x"31303", 18x"30cc7", 18x"30696", 18x"30070", 18x"2fa54", 18x"2f443", 18x"2ee3d",
        18x"2e841", 18x"2e250", 18x"2dc68", 18x"2d68b", 18x"2d0b8", 18x"2caee", 18x"2c52e", 18x"2bf79",
        18x"2b9cc", 18x"2b429", 18x"2ae90", 18x"2a900", 18x"2a379", 18x"29dfb", 18x"29887", 18x"2931b",
        18x"28db8", 18x"2885e", 18x"2830d", 18x"27dc4", 18x"27884", 18x"2734d", 18x"26e1d", 18x"268f6",
        18x"263d8", 18x"25ec1", 18x"259b3", 18x"254ac", 18x"24fad", 18x"24ab7", 18x"245c8", 18x"240e1",
        18x"23c01", 18x"23729", 18x"23259", 18x"22d90", 18x"228ce", 18x"22413", 18x"21f60", 18x"21ab4",
        18x"2160f", 18x"21172", 18x"20cdb", 18x"2084b", 18x"203c2", 18x"1ff40", 18x"1fac4", 18x"1f64f",
        18x"1f1e1", 18x"1ed79", 18x"1e918", 18x"1e4be", 18x"1e069", 18x"1dc1b", 18x"1d7d4", 18x"1d392",
        18x"1cf57", 18x"1cb22", 18x"1c6f3", 18x"1c2ca", 18x"1bea7", 18x"1ba8a", 18x"1b672", 18x"1b261",
        18x"1ae55", 18x"1aa50", 18x"1a64f", 18x"1a255", 18x"19e60", 18x"19a70", 18x"19686", 18x"192a2",
        18x"18ec3", 18x"18ae9", 18x"18715", 18x"18345", 18x"17f7c", 18x"17bb7", 18x"177f7", 18x"1743d",
        18x"17087", 18x"16cd7", 18x"1692c", 18x"16585", 18x"161e4", 18x"15e47", 18x"15ab0", 18x"1571d",
        18x"1538e", 18x"15005", 18x"14c80", 18x"14900", 18x"14584", 18x"1420d", 18x"13e9b", 18x"13b2d",
        18x"137c3", 18x"1345e", 18x"130fe", 18x"12da2", 18x"12a4a", 18x"126f6", 18x"123a7", 18x"1205c",
        18x"11d15", 18x"119d2", 18x"11694", 18x"11359", 18x"11023", 18x"10cf1", 18x"109c2", 18x"10698",
        18x"10372", 18x"10050", 18x"0fd31", 18x"0fa17", 18x"0f700", 18x"0f3ed", 18x"0f0de", 18x"0edd3",
        18x"0eacb", 18x"0e7c7", 18x"0e4c7", 18x"0e1ca", 18x"0ded2", 18x"0dbdc", 18x"0d8eb", 18x"0d5fc",
        18x"0d312", 18x"0d02b", 18x"0cd47", 18x"0ca67", 18x"0c78a", 18x"0c4b1", 18x"0c1db", 18x"0bf09",
        18x"0bc3a", 18x"0b96e", 18x"0b6a5", 18x"0b3e0", 18x"0b11e", 18x"0ae5f", 18x"0aba3", 18x"0a8eb",
        18x"0a636", 18x"0a383", 18x"0a0d4", 18x"09e28", 18x"09b80", 18x"098da", 18x"09637", 18x"09397",
        18x"090fb", 18x"08e61", 18x"08bca", 18x"08936", 18x"086a5", 18x"08417", 18x"0818c", 18x"07f04",
        18x"07c7e", 18x"079fc", 18x"0777c", 18x"074ff", 18x"07284", 18x"0700d", 18x"06d98", 18x"06b26",
        18x"068b6", 18x"0664a", 18x"063e0", 18x"06178", 18x"05f13", 18x"05cb1", 18x"05a52", 18x"057f5",
        18x"0559a", 18x"05342", 18x"050ed", 18x"04e9a", 18x"04c4a", 18x"049fc", 18x"047b0", 18x"04567",
        18x"04321", 18x"040dd", 18x"03e9b", 18x"03c5c", 18x"03a1f", 18x"037e4", 18x"035ac", 18x"03376",
        18x"03142", 18x"02f11", 18x"02ce2", 18x"02ab5", 18x"0288b", 18x"02663", 18x"0243d", 18x"02219",
        18x"01ff7", 18x"01dd8", 18x"01bbb", 18x"019a0", 18x"01787", 18x"01570", 18x"0135b", 18x"01149",
        18x"00f39", 18x"00d2a", 18x"00b1e", 18x"00914", 18x"0070c", 18x"00506", 18x"00302", 18x"00100",
        -- 1/sqrt(x) lookup table
        -- Input is in the range [1, 4), i.e. two bits to the left of the
        -- binary point.  Those 2 bits index the following 3 blocks of 256 values.
        -- 1.0 ... 1.9999
        18x"3fe00", 18x"3fa06", 18x"3f612", 18x"3f224", 18x"3ee3a", 18x"3ea58", 18x"3e67c", 18x"3e2a4",
        18x"3ded2", 18x"3db06", 18x"3d73e", 18x"3d37e", 18x"3cfc2", 18x"3cc0a", 18x"3c85a", 18x"3c4ae",
        18x"3c106", 18x"3bd64", 18x"3b9c8", 18x"3b630", 18x"3b29e", 18x"3af10", 18x"3ab86", 18x"3a802",
        18x"3a484", 18x"3a108", 18x"39d94", 18x"39a22", 18x"396b6", 18x"3934e", 18x"38fea", 18x"38c8c",
        18x"38932", 18x"385dc", 18x"3828a", 18x"37f3e", 18x"37bf6", 18x"378b2", 18x"37572", 18x"37236",
        18x"36efe", 18x"36bca", 18x"3689a", 18x"36570", 18x"36248", 18x"35f26", 18x"35c06", 18x"358ea",
        18x"355d4", 18x"352c0", 18x"34fb0", 18x"34ca4", 18x"3499c", 18x"34698", 18x"34398", 18x"3409c",
        18x"33da2", 18x"33aac", 18x"337bc", 18x"334cc", 18x"331e2", 18x"32efc", 18x"32c18", 18x"32938",
        18x"3265a", 18x"32382", 18x"320ac", 18x"31dd8", 18x"31b0a", 18x"3183e", 18x"31576", 18x"312b0",
        18x"30fee", 18x"30d2e", 18x"30a74", 18x"307ba", 18x"30506", 18x"30254", 18x"2ffa4", 18x"2fcf8",
        18x"2fa4e", 18x"2f7a8", 18x"2f506", 18x"2f266", 18x"2efca", 18x"2ed2e", 18x"2ea98", 18x"2e804",
        18x"2e572", 18x"2e2e4", 18x"2e058", 18x"2ddce", 18x"2db48", 18x"2d8c6", 18x"2d646", 18x"2d3c8",
        18x"2d14c", 18x"2ced4", 18x"2cc5e", 18x"2c9ea", 18x"2c77a", 18x"2c50c", 18x"2c2a2", 18x"2c038",
        18x"2bdd2", 18x"2bb70", 18x"2b90e", 18x"2b6b0", 18x"2b454", 18x"2b1fa", 18x"2afa4", 18x"2ad4e",
        18x"2aafc", 18x"2a8ac", 18x"2a660", 18x"2a414", 18x"2a1cc", 18x"29f86", 18x"29d42", 18x"29b00",
        18x"298c2", 18x"29684", 18x"2944a", 18x"29210", 18x"28fda", 18x"28da6", 18x"28b74", 18x"28946",
        18x"28718", 18x"284ec", 18x"282c4", 18x"2809c", 18x"27e78", 18x"27c56", 18x"27a34", 18x"27816",
        18x"275fa", 18x"273e0", 18x"271c8", 18x"26fb0", 18x"26d9c", 18x"26b8a", 18x"2697a", 18x"2676c",
        18x"26560", 18x"26356", 18x"2614c", 18x"25f46", 18x"25d42", 18x"25b40", 18x"2593e", 18x"25740",
        18x"25542", 18x"25348", 18x"2514e", 18x"24f58", 18x"24d62", 18x"24b6e", 18x"2497c", 18x"2478c",
        18x"2459e", 18x"243b0", 18x"241c6", 18x"23fde", 18x"23df6", 18x"23c10", 18x"23a2c", 18x"2384a",
        18x"2366a", 18x"2348c", 18x"232ae", 18x"230d2", 18x"22efa", 18x"22d20", 18x"22b4a", 18x"22976",
        18x"227a2", 18x"225d2", 18x"22402", 18x"22234", 18x"22066", 18x"21e9c", 18x"21cd2", 18x"21b0a",
        18x"21944", 18x"2177e", 18x"215ba", 18x"213fa", 18x"21238", 18x"2107a", 18x"20ebc", 18x"20d00",
        18x"20b46", 18x"2098e", 18x"207d6", 18x"20620", 18x"2046c", 18x"202b8", 18x"20108", 18x"1ff58",
        18x"1fda8", 18x"1fbfc", 18x"1fa50", 18x"1f8a4", 18x"1f6fc", 18x"1f554", 18x"1f3ae", 18x"1f208",
        18x"1f064", 18x"1eec2", 18x"1ed22", 18x"1eb82", 18x"1e9e4", 18x"1e846", 18x"1e6aa", 18x"1e510",
        18x"1e378", 18x"1e1e0", 18x"1e04a", 18x"1deb4", 18x"1dd20", 18x"1db8e", 18x"1d9fc", 18x"1d86c",
        18x"1d6de", 18x"1d550", 18x"1d3c4", 18x"1d238", 18x"1d0ae", 18x"1cf26", 18x"1cd9e", 18x"1cc18",
        18x"1ca94", 18x"1c910", 18x"1c78c", 18x"1c60a", 18x"1c48a", 18x"1c30c", 18x"1c18e", 18x"1c010",
        18x"1be94", 18x"1bd1a", 18x"1bba0", 18x"1ba28", 18x"1b8b2", 18x"1b73c", 18x"1b5c6", 18x"1b452",
        18x"1b2e0", 18x"1b16e", 18x"1affe", 18x"1ae8e", 18x"1ad20", 18x"1abb4", 18x"1aa46", 18x"1a8dc",
        -- 2.0 ... 2.9999
        18x"1a772", 18x"1a608", 18x"1a4a0", 18x"1a33a", 18x"1a1d4", 18x"1a070", 18x"19f0c", 18x"19da8",
        18x"19c48", 18x"19ae6", 18x"19986", 18x"19828", 18x"196ca", 18x"1956e", 18x"19412", 18x"192b8",
        18x"1915e", 18x"19004", 18x"18eae", 18x"18d56", 18x"18c00", 18x"18aac", 18x"18958", 18x"18804",
        18x"186b2", 18x"18562", 18x"18412", 18x"182c2", 18x"18174", 18x"18026", 18x"17eda", 18x"17d8e",
        18x"17c44", 18x"17afa", 18x"179b2", 18x"1786a", 18x"17724", 18x"175de", 18x"17498", 18x"17354",
        18x"17210", 18x"170ce", 18x"16f8c", 18x"16e4c", 18x"16d0c", 18x"16bcc", 18x"16a8e", 18x"16950",
        18x"16814", 18x"166d8", 18x"1659e", 18x"16464", 18x"1632a", 18x"161f2", 18x"160ba", 18x"15f84",
        18x"15e4e", 18x"15d1a", 18x"15be6", 18x"15ab2", 18x"15980", 18x"1584e", 18x"1571c", 18x"155ec",
        18x"154bc", 18x"1538e", 18x"15260", 18x"15134", 18x"15006", 18x"14edc", 18x"14db0", 18x"14c86",
        18x"14b5e", 18x"14a36", 18x"1490e", 18x"147e6", 18x"146c0", 18x"1459a", 18x"14476", 18x"14352",
        18x"14230", 18x"1410c", 18x"13fea", 18x"13eca", 18x"13daa", 18x"13c8a", 18x"13b6c", 18x"13a4e",
        18x"13930", 18x"13814", 18x"136f8", 18x"135dc", 18x"134c2", 18x"133a8", 18x"1328e", 18x"13176",
        18x"1305e", 18x"12f48", 18x"12e30", 18x"12d1a", 18x"12c06", 18x"12af2", 18x"129de", 18x"128ca",
        18x"127b8", 18x"126a6", 18x"12596", 18x"12486", 18x"12376", 18x"12266", 18x"12158", 18x"1204a",
        18x"11f3e", 18x"11e32", 18x"11d26", 18x"11c1a", 18x"11b10", 18x"11a06", 18x"118fc", 18x"117f4",
        18x"116ec", 18x"115e4", 18x"114de", 18x"113d8", 18x"112d2", 18x"111ce", 18x"110ca", 18x"10fc6",
        18x"10ec2", 18x"10dc0", 18x"10cbe", 18x"10bbc", 18x"10abc", 18x"109bc", 18x"108bc", 18x"107be",
        18x"106c0", 18x"105c2", 18x"104c4", 18x"103c8", 18x"102cc", 18x"101d0", 18x"100d6", 18x"0ffdc",
        18x"0fee2", 18x"0fdea", 18x"0fcf0", 18x"0fbf8", 18x"0fb02", 18x"0fa0a", 18x"0f914", 18x"0f81e",
        18x"0f72a", 18x"0f636", 18x"0f542", 18x"0f44e", 18x"0f35a", 18x"0f268", 18x"0f176", 18x"0f086",
        18x"0ef94", 18x"0eea4", 18x"0edb4", 18x"0ecc6", 18x"0ebd6", 18x"0eae8", 18x"0e9fa", 18x"0e90e",
        18x"0e822", 18x"0e736", 18x"0e64a", 18x"0e55e", 18x"0e474", 18x"0e38a", 18x"0e2a0", 18x"0e1b8",
        18x"0e0d0", 18x"0dfe8", 18x"0df00", 18x"0de1a", 18x"0dd32", 18x"0dc4c", 18x"0db68", 18x"0da82",
        18x"0d99e", 18x"0d8ba", 18x"0d7d6", 18x"0d6f4", 18x"0d612", 18x"0d530", 18x"0d44e", 18x"0d36c",
        18x"0d28c", 18x"0d1ac", 18x"0d0cc", 18x"0cfee", 18x"0cf0e", 18x"0ce30", 18x"0cd54", 18x"0cc76",
        18x"0cb9a", 18x"0cabc", 18x"0c9e0", 18x"0c906", 18x"0c82a", 18x"0c750", 18x"0c676", 18x"0c59c",
        18x"0c4c4", 18x"0c3ea", 18x"0c312", 18x"0c23a", 18x"0c164", 18x"0c08c", 18x"0bfb6", 18x"0bee0",
        18x"0be0a", 18x"0bd36", 18x"0bc62", 18x"0bb8c", 18x"0baba", 18x"0b9e6", 18x"0b912", 18x"0b840",
        18x"0b76e", 18x"0b69c", 18x"0b5cc", 18x"0b4fa", 18x"0b42a", 18x"0b35a", 18x"0b28a", 18x"0b1bc",
        18x"0b0ee", 18x"0b01e", 18x"0af50", 18x"0ae84", 18x"0adb6", 18x"0acea", 18x"0ac1e", 18x"0ab52",
        18x"0aa86", 18x"0a9bc", 18x"0a8f0", 18x"0a826", 18x"0a75c", 18x"0a694", 18x"0a5ca", 18x"0a502",
        18x"0a43a", 18x"0a372", 18x"0a2aa", 18x"0a1e4", 18x"0a11c", 18x"0a056", 18x"09f90", 18x"09ecc",
        -- 3.0 ... 3.9999
        18x"09e06", 18x"09d42", 18x"09c7e", 18x"09bba", 18x"09af6", 18x"09a32", 18x"09970", 18x"098ae",
        18x"097ec", 18x"0972a", 18x"09668", 18x"095a8", 18x"094e8", 18x"09426", 18x"09368", 18x"092a8",
        18x"091e8", 18x"0912a", 18x"0906c", 18x"08fae", 18x"08ef0", 18x"08e32", 18x"08d76", 18x"08cba",
        18x"08bfe", 18x"08b42", 18x"08a86", 18x"089ca", 18x"08910", 18x"08856", 18x"0879c", 18x"086e2",
        18x"08628", 18x"08570", 18x"084b6", 18x"083fe", 18x"08346", 18x"0828e", 18x"081d8", 18x"08120",
        18x"0806a", 18x"07fb4", 18x"07efe", 18x"07e48", 18x"07d92", 18x"07cde", 18x"07c2a", 18x"07b76",
        18x"07ac2", 18x"07a0e", 18x"0795a", 18x"078a8", 18x"077f4", 18x"07742", 18x"07690", 18x"075de",
        18x"0752e", 18x"0747c", 18x"073cc", 18x"0731c", 18x"0726c", 18x"071bc", 18x"0710c", 18x"0705e",
        18x"06fae", 18x"06f00", 18x"06e52", 18x"06da4", 18x"06cf6", 18x"06c4a", 18x"06b9c", 18x"06af0",
        18x"06a44", 18x"06998", 18x"068ec", 18x"06840", 18x"06796", 18x"066ea", 18x"06640", 18x"06596",
        18x"064ec", 18x"06442", 18x"0639a", 18x"062f0", 18x"06248", 18x"061a0", 18x"060f8", 18x"06050",
        18x"05fa8", 18x"05f00", 18x"05e5a", 18x"05db4", 18x"05d0e", 18x"05c68", 18x"05bc2", 18x"05b1c",
        18x"05a76", 18x"059d2", 18x"0592e", 18x"05888", 18x"057e4", 18x"05742", 18x"0569e", 18x"055fa",
        18x"05558", 18x"054b6", 18x"05412", 18x"05370", 18x"052ce", 18x"0522e", 18x"0518c", 18x"050ec",
        18x"0504a", 18x"04faa", 18x"04f0a", 18x"04e6a", 18x"04dca", 18x"04d2c", 18x"04c8c", 18x"04bee",
        18x"04b50", 18x"04ab0", 18x"04a12", 18x"04976", 18x"048d8", 18x"0483a", 18x"0479e", 18x"04700",
        18x"04664", 18x"045c8", 18x"0452c", 18x"04490", 18x"043f6", 18x"0435a", 18x"042c0", 18x"04226",
        18x"0418a", 18x"040f0", 18x"04056", 18x"03fbe", 18x"03f24", 18x"03e8c", 18x"03df2", 18x"03d5a",
        18x"03cc2", 18x"03c2a", 18x"03b92", 18x"03afa", 18x"03a62", 18x"039cc", 18x"03934", 18x"0389e",
        18x"03808", 18x"03772", 18x"036dc", 18x"03646", 18x"035b2", 18x"0351c", 18x"03488", 18x"033f2",
        18x"0335e", 18x"032ca", 18x"03236", 18x"031a2", 18x"03110", 18x"0307c", 18x"02fea", 18x"02f56",
        18x"02ec4", 18x"02e32", 18x"02da0", 18x"02d0e", 18x"02c7c", 18x"02bec", 18x"02b5a", 18x"02aca",
        18x"02a38", 18x"029a8", 18x"02918", 18x"02888", 18x"027f8", 18x"0276a", 18x"026da", 18x"0264a",
        18x"025bc", 18x"0252e", 18x"024a0", 18x"02410", 18x"02384", 18x"022f6", 18x"02268", 18x"021da",
        18x"0214e", 18x"020c0", 18x"02034", 18x"01fa8", 18x"01f1c", 18x"01e90", 18x"01e04", 18x"01d78",
        18x"01cee", 18x"01c62", 18x"01bd8", 18x"01b4c", 18x"01ac2", 18x"01a38", 18x"019ae", 18x"01924",
        18x"0189c", 18x"01812", 18x"01788", 18x"01700", 18x"01676", 18x"015ee", 18x"01566", 18x"014de",
        18x"01456", 18x"013ce", 18x"01346", 18x"012c0", 18x"01238", 18x"011b2", 18x"0112c", 18x"010a4",
        18x"0101e", 18x"00f98", 18x"00f12", 18x"00e8c", 18x"00e08", 18x"00d82", 18x"00cfe", 18x"00c78",
        18x"00bf4", 18x"00b70", 18x"00aec", 18x"00a68", 18x"009e4", 18x"00960", 18x"008dc", 18x"00858",
        18x"007d6", 18x"00752", 18x"006d0", 18x"0064e", 18x"005cc", 18x"0054a", 18x"004c8", 18x"00446",
        18x"003c4", 18x"00342", 18x"002c2", 18x"00240", 18x"001c0", 18x"00140", 18x"000c0", 18x"00040"
        );

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
        variable shift_result : std_ulogic_vector(63 downto 0);
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
                shift_result := s2(70 downto 7);
            when "001" =>
                shift_result := s2(69 downto 6);
            when "010" =>
                shift_result := s2(68 downto 5);
            when "011" =>
                shift_result := s2(67 downto 4);
            when "100" =>
                shift_result := s2(66 downto 3);
            when "101" =>
                shift_result := s2(65 downto 2);
            when "110" =>
                shift_result := s2(64 downto 1);
            when others =>
                shift_result := s2(63 downto 0);
        end case;
        return shift_result;
    end;

    -- Split a DP floating-point number into components and work out its class.
    -- If is_int = 1, the input is considered an integer
    function decode_dp(fpr: std_ulogic_vector(63 downto 0); is_fp: std_ulogic;
                       is_32bint: std_ulogic; is_signed: std_ulogic) return fpu_reg_type is
        variable reg     : fpu_reg_type;
        variable exp_nz  : std_ulogic;
        variable exp_ao  : std_ulogic;
        variable frac_nz : std_ulogic;
        variable low_nz  : std_ulogic;
        variable cls     : std_ulogic_vector(2 downto 0);
    begin
        reg.negative := fpr(63);
        reg.denorm := '0';
        reg.naninf := '0';
        reg.zeroexp := '0';
        exp_nz := or (fpr(62 downto 52));
        exp_ao := and (fpr(62 downto 52));
        frac_nz := or (fpr(51 downto 0));
        low_nz := or (fpr(31 downto 0));
        if is_fp = '1' then
            reg.naninf := exp_ao;
            reg.zeroexp := not exp_nz;
            reg.denorm := frac_nz and not exp_nz;
            reg.exponent := signed(resize(unsigned(fpr(62 downto 52)), EXP_BITS)) - to_signed(1023, EXP_BITS);
            if exp_nz = '0' then
                reg.exponent := to_signed(-1022, EXP_BITS);
            end if;
            reg.mantissa := std_ulogic_vector(shift_left(resize(unsigned(exp_nz & fpr(51 downto 0)), 64),
                                                         UNIT_BIT - 52));
            cls := exp_ao & exp_nz & frac_nz;
            case cls is
                when "000"  => reg.class := ZERO;
                when "001"  => reg.class := FINITE;    -- denormalized
                when "010"  => reg.class := FINITE;
                when "011"  => reg.class := FINITE;
                when "110"  => reg.class := INFINITY;
                when others => reg.class := NAN;
            end case;
        elsif is_32bint = '1' then
            reg.negative := fpr(31);
            reg.mantissa(31 downto 0) := fpr(31 downto 0);
            reg.mantissa(63 downto 32) := (others => (is_signed and fpr(31)));
            reg.exponent := (others => '0');
            if low_nz = '1' then
                reg.class := FINITE;
            else
                reg.class := ZERO;
            end if;
        else
            reg.mantissa := fpr;
            reg.exponent := (others => '0');
            if (fpr(63) or exp_nz or frac_nz) = '1' then
                reg.class := FINITE;
            else
                reg.class := ZERO;
            end if;
        end if;
        return reg;
    end;

    -- Construct a DP floating-point result from components
    function pack_dp(negative: std_ulogic; class: fp_number_class; exp: signed(EXP_BITS-1 downto 0);
                     mantissa: std_ulogic_vector; single_prec: std_ulogic; quieten_nan: std_ulogic)
        return std_ulogic_vector is
        variable dp_result : std_ulogic_vector(63 downto 0);
    begin
        dp_result := (others => '0');
        case class is
            when ZERO =>
            when FINITE =>
                if mantissa(UNIT_BIT) = '1' then
                    -- normalized number
                    dp_result(62 downto 52) := std_ulogic_vector(resize(exp, 11) + 1023);
                end if;
                dp_result(51 downto 29) := mantissa(UNIT_BIT - 1 downto SP_LSB);
                if single_prec = '0' then
                    dp_result(28 downto 0) := mantissa(SP_LSB - 1 downto DP_LSB);
                end if;
            when INFINITY =>
                dp_result(62 downto 52) := "11111111111";
            when NAN =>
                dp_result(62 downto 52) := "11111111111";
                dp_result(51) := quieten_nan or mantissa(QNAN_BIT);
                dp_result(50 downto 29) := mantissa(QNAN_BIT - 1 downto SP_LSB);
                if single_prec = '0' then
                    dp_result(28 downto 0) := mantissa(SP_LSB - 1 downto DP_LSB);
                end if;
        end case;
        dp_result(63) := negative;
        return dp_result;
    end;

    -- Determine whether to increment when rounding
    -- Returns rounding_inc & inexact
    -- If single_prec = 1, assumes x includes the bottom 31 (== SP_LSB - 2)
    -- bits of the mantissa already (usually arranged by setting set_x = 1 earlier).
    function fp_rounding(mantissa: std_ulogic_vector(63 downto 0); x: std_ulogic;
                         single_prec: std_ulogic; rn: std_ulogic_vector(2 downto 0);
                         sign: std_ulogic)
        return std_ulogic_vector is
        variable grx : std_ulogic_vector(2 downto 0);
        variable ret : std_ulogic_vector(1 downto 0);
        variable lsb : std_ulogic;
    begin
        if single_prec = '0' then
            grx := mantissa(DP_GBIT downto DP_RBIT) & (x or (or mantissa(DP_RBIT - 1 downto 0)));
            lsb := mantissa(DP_LSB);
        else
            grx := mantissa(SP_GBIT downto SP_RBIT) & x;
            lsb := mantissa(SP_LSB);
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
    fpu_multiply_0: entity work.multiply
        port map (
            clk => clk,
            m_in => f_to_multiply,
            m_out => multiply_to_f
            );

    fpu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_in = '1' then
                r.state <= IDLE;
                r.busy <= '0';
                r.f2stall <= '0';
                r.instr_done <= '0';
                r.complete <= '0';
                r.illegal <= '0';
                r.do_intr <= '0';
                r.writing_fpr <= '0';
                r.writing_cr <= '0';
                r.writing_xer <= '0';
                r.fpscr <= (others => '0');
                r.write_reg <= (others =>'0');
                r.complete_tag.valid <= '0';
                r.cr_mask <= (others =>'0');
                r.cr_result <= (others =>'0');
                r.instr_tag.valid <= '0';
                r.exec_state <= IDLE;
                if rst = '1' then
                    r.fpscr <= (others => '0');
                    r.comm_fpscr <= (others => '0');
                elsif r.do_intr = '0' then
                    -- flush_in = 1 and not due to us generating an interrupt,
                    -- roll back to committed fpscr
                    r.fpscr <= r.comm_fpscr;
                end if;
            else
                assert not (r.state /= IDLE and e_in.valid = '1') severity failure;
                r <= rin;
            end if;
        end if;
    end process;

    -- synchronous reads from lookup table
    lut_access: process(clk)
        variable addrhi : std_ulogic_vector(1 downto 0);
        variable addr   : std_ulogic_vector(9 downto 0);
    begin
        if rising_edge(clk) then
            if r.is_sqrt = '1' then
                addrhi := r.b.mantissa(UNIT_BIT + 1 downto UNIT_BIT);
            else
                addrhi := "00";
            end if;
            addr := addrhi & r.b.mantissa(UNIT_BIT - 1 downto UNIT_BIT - 8);
	    if is_X(addr) then
		inverse_est <= (others => 'X');
	    else
		inverse_est <= '1' & inverse_table(to_integer(unsigned(addr)));
	    end if;
        end if;
    end process;

    e_out.busy <= r.busy;
    e_out.f2stall <= r.f2stall;
    e_out.exception <= r.fpscr(FPSCR_FEX);

    -- Note that the cycle where r.complete = 1 for an instruction can be as
    -- late as the second cycle of the following instruction (i.e. in the state
    -- following IDLE state).  Hence it is important that none of the fields of
    -- r that are used below are modified in IDLE state.
    w_out.valid <= r.complete;
    w_out.instr_tag <= r.complete_tag;
    w_out.write_enable <= r.writing_fpr and r.complete;
    w_out.write_reg <= r.write_reg;
    w_out.write_data <= fp_result;
    w_out.write_cr_enable <= r.writing_cr and r.complete;
    w_out.write_cr_mask <= r.cr_mask;
    w_out.write_cr_data <= r.cr_result & r.cr_result & r.cr_result & r.cr_result &
                           r.cr_result & r.cr_result & r.cr_result & r.cr_result;
    w_out.write_xerc <= r.writing_xer and r.complete;
    w_out.xerc <= r.xerc_result;
    w_out.interrupt <= r.do_intr;
    w_out.intr_vec <= 16#700#;
    w_out.srr1 <= (47-44 => r.illegal, 47-43 => not r.illegal, others => '0');

    -- This is active in the second cycle of an instruction, and works out if
    -- we have a special case where one or more operand is NaN, infinity, or zero,
    -- meaning that an exception is generated or a specific value results
    -- immediately without further calculation.
    fpu_specialcases: process(all)
        variable e : specialcase_t;
        variable invalid_mul  : std_ulogic;
    begin
        e.invalid := '0';
        e.zero_divide := '0';
        e.new_fpscr := (others => '0');
        e.immed_result := '0';
        e.qnan_result := '0';
        e.result_sel := AIN_ZERO;
        e.result_class := FINITE;
        e.rsgn_op := RSGN_NOP;

        -- Check if any operand is a signalling NAN
        if (r.a.class = NAN and r.a.mantissa(QNAN_BIT) = '0') or
            (r.b.class = NAN and r.b.mantissa(QNAN_BIT) = '0') or
            (r.c.class = NAN and r.c.mantissa(QNAN_BIT) = '0') then
            e.new_fpscr(FPSCR_VXSNAN) := '1';
            e.invalid := '1';
        end if;

        -- Check for this case here since VXIMZ can be set along with VXSNAN
        invalid_mul := '0';
        if r.is_multiply = '1' and
            ((r.a.class = INFINITY and r.c.class = ZERO) or
             (r.a.class = ZERO and r.c.class = INFINITY)) then
            e.new_fpscr(FPSCR_VXIMZ) := '1';
            e.invalid := '1';
            invalid_mul := '1';
        end if;

        -- Note that any operand for which r.use_X is 0 will have class = ZERO
        if r.is_nan_inf = '1' then
            e.immed_result := '1';

            if r.int_result = '1' then
                e.qnan_result := '1';
                e.new_fpscr(FPSCR_VXCVI) := '1';

            elsif r.a.class = NAN or r.b.class = NAN or r.c.class = NAN then
                e.result_class := NAN;
                e.rsgn_op := RSGN_SEL;
                -- Select the first input that is a NaN
                if r.a.class = NAN then
                    e.result_sel := AIN_A;
                elsif r.b.class = NAN then
                    e.result_sel := AIN_B;
                elsif r.c.class = NAN then
                    e.result_sel := AIN_C;
                end if;

            else
                -- some operand is an infinity
                if invalid_mul = '1' then
                    e.qnan_result := '1';
                elsif (r.a.class = INFINITY or r.c.class = INFINITY) then
                    if r.is_multiply = '1' then
                        e.rsgn_op := RSGN_SUB;
                    end if;
                    if r.is_subtract = '1' and r.b.class = INFINITY then
                        e.new_fpscr(FPSCR_VXISI) := '1';
                        e.qnan_result := '1';
                    end if;
                end if;
                if r.is_inverse = '1' and r.a.class = INFINITY and r.b.class = INFINITY then
                    e.new_fpscr(FPSCR_VXIDI) := '1';
                    e.qnan_result := '1';
                end if;
                if r.b.class = INFINITY and r.is_sqrt = '1' and r.b.negative = '1' then
                    e.new_fpscr(FPSCR_VXSQRT) := '1';
                    e.qnan_result := '1';
                end if;
                if r.b.class = INFINITY and r.is_inverse = '1' then
                    -- fdiv, fre, frsqrte
                    e.result_class := ZERO;
                else
                    e.result_class := INFINITY;
                end if;
            end if;

        elsif r.use_a = '1' and r.a.class = ZERO then
            e.immed_result := '1';
            if r.is_addition = '1' then
                -- result is +/- B
                e.result_sel := AIN_B;
                e.result_class := r.b.class;
            else
                e.result_class := ZERO;
            end if;
            if r.is_inverse = '1' and r.b.class = ZERO then
                -- fdiv 0 / 0
                e.new_fpscr(FPSCR_VXZDZ) := '1';
                e.qnan_result := '1';
            end if;

        elsif r.use_c = '1' and r.c.class = ZERO then
            -- fmadd/sub A * 0 + B
            e.immed_result := '1';
            e.result_sel := AIN_B;
            e.result_class := r.b.class;

        elsif r.use_b = '1' and r.b.class = ZERO and r.is_multiply = '0' then
            -- B is zero, other operands are finite
            e.immed_result := '1';
            if r.is_inverse = '1' then
                -- fdiv, fre, frsqrte
                e.result_class := INFINITY;
                e.new_fpscr(FPSCR_ZX) := '1';
                e.zero_divide := '1';
            elsif r.is_addition = '1' then
                -- fadd, result is A
                e.result_sel := AIN_A;
            else
                -- other things, result is zero
                e.result_class := ZERO;
            end if;
        end if;
        if r.is_sqrt = '1' and r.b.class = FINITE and r.b.negative = '1' then
            e.immed_result := '1';
            e.new_fpscr(FPSCR_VXSQRT) := '1';
            e.qnan_result := '1';
        end if;

        if e.qnan_result = '1' then
            e.invalid := '1';
            e.result_class := NAN;
        end if;
        scinfo <= e;
    end process;

    fpu_1: process(all)
        variable v           : reg_type;
        variable adec        : fpu_reg_type;
        variable bdec        : fpu_reg_type;
        variable cdec        : fpu_reg_type;
        variable fpscr_mask  : std_ulogic_vector(31 downto 0);
        variable j, k        : integer;
        variable flm         : std_ulogic_vector(7 downto 0);
        variable fpin_a      : std_ulogic;
        variable fpin_b      : std_ulogic;
        variable fpin_c      : std_ulogic;
        variable is_32bint   : std_ulogic;
        variable mask        : std_ulogic_vector(63 downto 0);
        variable in_a0       : std_ulogic_vector(63 downto 0);
        variable in_b0       : std_ulogic_vector(63 downto 0);
        variable misc        : std_ulogic_vector(63 downto 0);
        variable shift_res   : std_ulogic_vector(63 downto 0);
        variable round       : std_ulogic_vector(1 downto 0);
        variable update_fx   : std_ulogic;
        variable arith_done  : std_ulogic;
        variable invalid     : std_ulogic;
        variable zero_divide : std_ulogic;
        variable min_exp     : signed(EXP_BITS-1 downto 0);
        variable max_exp     : signed(EXP_BITS-1 downto 0);
        variable bias_exp    : signed(EXP_BITS-1 downto 0);
        variable new_exp     : signed(EXP_BITS-1 downto 0);
        variable exp_tiny    : std_ulogic;
        variable exp_huge    : std_ulogic;
        variable clz         : std_ulogic_vector(5 downto 0);
        variable set_x       : std_ulogic;
        variable mshift      : signed(EXP_BITS-1 downto 0);
        variable need_check  : std_ulogic;
        variable msb         : std_ulogic;
        variable set_a       : std_ulogic;
        variable set_a_exp   : std_ulogic;
        variable set_a_mant  : std_ulogic;
        variable set_a_hi    : std_ulogic;
        variable set_a_lo    : std_ulogic;
        variable set_b       : std_ulogic;
        variable set_b_mant  : std_ulogic;
        variable set_c       : std_ulogic;
        variable set_y       : std_ulogic;
        variable set_r       : std_ulogic;
        variable set_s       : std_ulogic;
        variable qnan_result : std_ulogic;
        variable invalid_mul : std_ulogic;
        variable px_nz       : std_ulogic;
        variable pcmpb_eq    : std_ulogic;
        variable pcmpb_lt    : std_ulogic;
        variable pcmpc_eq    : std_ulogic;
        variable pcmpc_lt    : std_ulogic;
        variable pshift      : std_ulogic;
        variable renorm_sqrt : std_ulogic;
        variable sqrt_exp    : signed(EXP_BITS-1 downto 0);
        variable shiftin     : std_ulogic;
        variable shiftin0    : std_ulogic;
        variable mulexp      : signed(EXP_BITS-1 downto 0);
        variable maddend     : std_ulogic_vector(127 downto 0);
        variable sum         : std_ulogic_vector(63 downto 0);
        variable mult_mask   : std_ulogic;
        variable sign_bit    : std_ulogic;
        variable rexp_in1    : signed(EXP_BITS-1 downto 0);
        variable rexp_in2    : signed(EXP_BITS-1 downto 0);
        variable rexp_cin    : std_ulogic;
        variable rexp_sum    : signed(EXP_BITS-1 downto 0);
        variable rsh_in1     : signed(EXP_BITS-1 downto 0);
        variable rsh_in2     : signed(EXP_BITS-1 downto 0);
        variable exec_state  : state_t;
        variable opcbits     : std_ulogic_vector(4 downto 0);
        variable illegal     : std_ulogic;
        variable rsign       : std_ulogic;
        variable rsgn_op     : std_ulogic_vector(1 downto 0);
        variable is_nan_inf  : std_ulogic;
        variable is_zero_den : std_ulogic;
        variable set_reg_ind : std_ulogic;
        variable cr_op       : std_ulogic_vector(2 downto 0);
        variable cr_result   : std_ulogic_vector(3 downto 0);
        variable set_cr      : std_ulogic;
        variable set_fpcc    : std_ulogic;
        variable asign       : std_ulogic;
        variable bneg        : std_ulogic;
        variable ci          : std_ulogic;
        variable rormr       : std_ulogic_vector(63 downto 0);
    begin
        v := r;
        v.complete := '0';
        v.do_intr := '0';
        is_32bint := '0';
        exec_state := IDLE;
        is_nan_inf := '0';
        is_zero_den := '0';
        v.cycle_1 := e_in.valid;
        v.cycle_1_ar := '0';

        if r.complete = '1' or r.do_intr = '1' then
            v.instr_done := '0';
            v.writing_fpr := '0';
            v.writing_cr := '0';
            v.writing_xer := '0';
            v.comm_fpscr := r.fpscr;
            v.illegal := '0';
        end if;

        -- capture incoming instruction
        if e_in.valid = '1' then
            v.insn := e_in.insn;
            v.op := e_in.op;
            v.instr_tag := e_in.itag;
            v.fe_mode := or (e_in.fe_mode);
            v.dest_fpr := e_in.frt;
            v.single_prec := e_in.single;
            v.is_signed := e_in.is_signed;
            v.rc := e_in.rc;
            v.fp_rc := '0';
            v.is_cmp := e_in.out_cr;
            v.oe := e_in.oe;
            v.m32b := e_in.m32b;
            v.xerc := e_in.xerc;
            v.longmask := '0';
            v.integer_op := '0';
            v.divext := '0';
            v.divmod := '0';
            v.is_sqrt := '0';
            v.is_multiply := '0';
            v.is_addition := '0';
            v.is_subtract := '0';
            v.is_inverse := '0';
            fpin_a := '0';
            fpin_b := '0';
            fpin_c := '0';
            v.use_a := e_in.valid_a;
            v.use_b := e_in.valid_b;
            v.use_c := e_in.valid_c;
            v.round_mode := '0' & r.fpscr(FPSCR_RN+1 downto FPSCR_RN);
            v.result_sign := '0';
            v.negate := '0';
            v.quieten_nan := '1';
            v.int_result := '0';
            v.is_arith := '0';
            case e_in.op is
                when OP_FP_ARITH =>
                    fpin_a := e_in.valid_a;
                    fpin_b := e_in.valid_b;
                    fpin_c := e_in.valid_c;
                    v.longmask := e_in.single;
                    v.fp_rc := e_in.rc;
                    v.is_arith := '1';
                    v.cycle_1_ar := '1';
                    exec_state := arith_decode(to_integer(unsigned(e_in.insn(5 downto 1))));
                    if e_in.insn(5 downto 1) = "10110" or e_in.insn(5 downto 1) = "11010" then
                        v.is_sqrt := '1';
                    end if;
                    if e_in.insn(5 downto 1) = "01111" then   -- fcti*z
                        v.round_mode := "001";
                    elsif e_in.insn(5 downto 1) = "01000" then   -- fri*
                        v.round_mode := '1' & e_in.insn(7 downto 6);
                    end if;
                    case e_in.insn(5 downto 1) is
                        when "10100" | "10101" =>       -- fadd and fsub
                            v.is_addition := '1';
                            v.result_sign := e_in.fra(63);
                            if unsigned(e_in.fra(62 downto 52)) <= unsigned(e_in.frb(62 downto 52)) then
                                v.result_sign := e_in.frb(63) xnor e_in.insn(1);
                            end if;
                            v.is_subtract := not (e_in.fra(63) xor e_in.frb(63) xor e_in.insn(1));
                        when "11001" =>         -- fmul
                            v.is_multiply := '1';
                            v.result_sign := e_in.fra(63) xor e_in.frc(63);
                        when "11100" | "11101" | "11110" | "11111" =>   --fmadd family
                            v.is_multiply := '1';
                            v.is_addition := '1';
                            v.result_sign := e_in.frb(63) xnor e_in.insn(1);
                            v.is_subtract := not (e_in.fra(63) xor e_in.frb(63) xor
                                                  e_in.frc(63) xor e_in.insn(1));
                            v.negate := e_in.insn(2);
                        when "10010" =>         -- fdiv
                            v.is_inverse := '1';
                            v.result_sign := e_in.fra(63) xor e_in.frb(63);
                        when "11000" | "11010" =>       -- fre and frsqrte
                            v.is_inverse := '1';
                            v.result_sign := e_in.frb(63);
                        when "01110" | "01111" =>       -- fcti*
                            v.int_result := '1';
                            v.result_sign := e_in.frb(63);
                        when others =>                  -- fri* and frsp
                            v.result_sign := e_in.frb(63);
                    end case;
                when OP_FP_CMP =>
                    fpin_a := e_in.valid_a;
                    fpin_b := e_in.valid_b;
                    exec_state := cmp_decode(to_integer(unsigned(e_in.insn(8 downto 6))));
                when OP_FP_MISC =>
                    v.fp_rc := e_in.rc;
                    opcbits := e_in.insn(10) & e_in.insn(8) & e_in.insn(4) & e_in.insn(2) & e_in.insn(1);
                    exec_state := misc_decode(to_integer(unsigned(opcbits)));
                    case opcbits is
                        when "10010" | "11010" | "10011" =>
                            -- fmrg*, mffs
                            v.int_result := '1';
                            v.result_sign := '0';
                        when "10110" =>        -- fcfid
                            v.result_sign := e_in.frb(63);
                        when others =>
                            v.result_sign := '0';
                    end case;
                when OP_FP_MOVE =>
                    v.fp_rc := e_in.rc;
                    fpin_a := e_in.valid_a;
                    fpin_b := e_in.valid_b;
                    fpin_c := e_in.valid_c;
                    v.quieten_nan := '0';
                    if e_in.insn(5) = '0' then
                        exec_state := DO_FMR;
                        if e_in.insn(9) = '1' then
                            v.result_sign := '0';              -- fabs
                        elsif e_in.insn(8) = '1' then
                            v.result_sign := '1';              -- fnabs
                        elsif e_in.insn(7) = '1' then
                            v.result_sign := e_in.frb(63);     -- fmr
                        elsif e_in.insn(6) = '1' then
                            v.result_sign := not e_in.frb(63); -- fneg
                        else
                            v.result_sign := e_in.fra(63);     -- fcpsgn
                        end if;
                    else
                        exec_state := DO_FSEL;
                        v.result_sign := e_in.frb(63);
                    end if;
                when OP_DIV =>
                    v.integer_op := '1';
                    is_32bint := e_in.single;
                    if e_in.single = '0' then
                        v.result_sign := e_in.is_signed and (e_in.fra(63) xor e_in.frb(63));
                    else
                        v.result_sign := e_in.is_signed and (e_in.fra(31) xor e_in.frb(31));
                    end if;
                    exec_state := DO_IDIVMOD;
                when OP_DIVE =>
                    v.integer_op := '1';
                    v.divext := '1';
                    is_32bint := e_in.single;
                    if e_in.single = '0' then
                        v.result_sign := e_in.is_signed and (e_in.fra(63) xor e_in.frb(63));
                    else
                        v.result_sign := e_in.is_signed and (e_in.fra(31) xor e_in.frb(31));
                    end if;
                    exec_state := DO_IDIVMOD;
                when OP_MOD =>
                    v.integer_op := '1';
                    v.divmod := '1';
                    is_32bint := e_in.single;
                    if e_in.single = '0' then
                        v.result_sign := e_in.is_signed and e_in.fra(63);
                    else
                        v.result_sign := e_in.is_signed and e_in.fra(31);
                    end if;
                    exec_state := DO_IDIVMOD;
                when others =>
                    exec_state := DO_ILLEGAL;
            end case;
            v.tiny := '0';
            v.denorm := '0';
            v.add_bsmall := '0';
            v.int_ovf := '0';
            v.div_close := '0';

            adec := decode_dp(e_in.fra, fpin_a, is_32bint, e_in.is_signed);
            bdec := decode_dp(e_in.frb, fpin_b, is_32bint, e_in.is_signed);
            cdec := decode_dp(e_in.frc, fpin_c, '0', '0');
            v.a := adec;
            v.b := bdec;
            v.c := cdec;

            if e_in.op = OP_FP_ARITH then
                is_nan_inf := adec.naninf or bdec.naninf or cdec.naninf;
                is_zero_den := adec.zeroexp or bdec.zeroexp or cdec.zeroexp;
            end if;

            v.a_hi := 8x"0";
            v.a_lo := 56x"0";
        end if;

        r_hi_nz <= or (r.r(UNIT_BIT + 1 downto SP_LSB));
        r_lo_nz <= or (r.r(SP_LSB - 1 downto DP_LSB));
        r_gt_1 <= or (r.r(63 downto 1));
        s_nz <= or (r.s);

        if r.single_prec = '0' then
            if r.doing_ftdiv(1) = '0' then
                max_exp := to_signed(1023, EXP_BITS);
            else
                max_exp := to_signed(1020, EXP_BITS);
            end if;
            if r.doing_ftdiv(0) = '0' then
                min_exp := to_signed(-1022, EXP_BITS);
            else
                min_exp := to_signed(-1021, EXP_BITS);
            end if;
            bias_exp := to_signed(1536, EXP_BITS);
        else
            max_exp := to_signed(127, EXP_BITS);
            min_exp := to_signed(-126, EXP_BITS);
            bias_exp := to_signed(192, EXP_BITS);
        end if;
        new_exp := r.result_exp - r.shift;
        exp_tiny := '0';
        exp_huge := '0';
	if is_X(new_exp) or is_X(min_exp) then
	    exp_tiny := 'X';
        elsif new_exp < min_exp then
            exp_tiny := '1';
        end if;
	if is_X(new_exp) or is_X(max_exp) then
	    exp_huge := 'X';
	elsif new_exp > max_exp then
            exp_huge := '1';
        end if;

        -- Compare P with zero and with B
        px_nz := or (r.p(UNIT_BIT + 1 downto 4));
        pcmpb_eq := '0';
        if r.p(59 downto 4) = r.b.mantissa(UNIT_BIT + 1 downto DP_RBIT) then
            pcmpb_eq := '1';
        end if;
        pcmpb_lt := '0';
        if is_X(r.p(59 downto 4)) or is_X(r.b.mantissa(55 downto 0)) then
	    pcmpb_lt := 'X';
        elsif unsigned(r.p(59 downto 4)) < unsigned(r.b.mantissa(UNIT_BIT + 1 downto DP_RBIT)) then
            pcmpb_lt := '1';
        end if;
        pcmpc_eq := '0';
        if r.p = r.c.mantissa then
            pcmpc_eq := '1';
        end if;
        pcmpc_lt := '0';
        if is_X(r.p) or is_X(r.c.mantissa) then
	    pcmpc_lt := 'X';
        elsif unsigned(r.p) < unsigned(r.c.mantissa) then
            pcmpc_lt := '1';
        end if;

        v.update_fprf := '0';
        v.first := '0';
        v.doing_ftdiv := "00";
        opsel_a <= AIN_ZERO;
        opsel_aneg <= '0';
        opsel_aabs <= '0';
        opsel_mask <= '0';
        opsel_b <= BIN_R;
        opsel_c <= CIN_ZERO;
        opsel_r <= RES_SUM;
        opsel_s <= S_ZERO;
        misc_sel <= "000";
        opsel_sel <= AIN_ZERO;
        fpscr_mask := (others => '1');
        cr_op := CROP_NONE;
        update_fx := '0';
        arith_done := '0';
        invalid := '0';
        zero_divide := '0';
        set_x := '0';
        qnan_result := '0';
        set_a := '0';
        set_a_exp := '0';
        set_a_mant := '0';
        set_a_hi := '0';
        set_a_lo := '0';
        set_b := '0';
        set_b_mant := '0';
        set_c := '0';
        set_r := '1';
        set_s := '0';
        set_cr := '0';
        set_fpcc := '0';
        f_to_multiply.is_signed <= '0';
        f_to_multiply.valid <= '0';
        msel_1 <= MUL1_A;
        msel_2 <= MUL2_C;
        msel_add <= MULADD_ZERO;
        msel_inv <= '0';
        set_y := '0';
        pshift := '0';
        renorm_sqrt := '0';
        shiftin := '0';
        shiftin0 := '0';
        mult_mask := '0';
        illegal := '0';
        set_reg_ind := '0';

        re_sel1 <= REXP1_ZERO;
        re_sel2 <= REXP2_CON;
        re_con2 <= RECON2_ZERO;
        re_neg1 <= '0';
        re_neg2 <= '0';
        re_set_result <= '0';
        rs_sel1 <= RSH1_ZERO;
        rs_sel2 <= RSH2_CON;
        rs_con2 <= RSCON2_ZERO;
        rs_neg1 <= '0';
        rs_neg2 <= '0';
        rs_norm <= '0';

        rsgn_op := RSGN_NOP;
        rcls_op <= RCLS_NOP;

        if r.cycle_1_ar = '1' then
            v.fpscr(FPSCR_FR) := '0';
            v.fpscr(FPSCR_FI) := '0';
            v.result_class := FINITE;
        end if;

        case r.state is
            when IDLE =>
                v.invalid := '0';
                if e_in.valid = '1' then
                    v.busy := '1';
                    v.exec_state := exec_state;
                    v.is_nan_inf := is_nan_inf;
                    if is_nan_inf = '1' or is_zero_den = '1' then
                        v.state := DO_SPECIAL;
                    else
                        v.state := exec_state;
                    end if;
                end if;
                v.x := '0';
                v.old_exc := r.fpscr(FPSCR_VX downto FPSCR_XX);
                set_s := '1';
                v.regsel := AIN_ZERO;

            when DO_SPECIAL =>
                -- At least one floating point operand is NaN, infinity, zero or denormalized
                -- Most of the special cases are handled in the fpu_specialcases process
                -- and in the code below (the scinfo.immed_result = '1' block).
                if r.is_multiply = '1' and r.b.class = ZERO then
                    -- This will trigger for fmul as well as fmadd/sub, but
                    -- it doesn't matter since r.is_subtract = 0 for fmul.
                    rsgn_op := RSGN_SUB;
                end if;
                if r.a.denorm = '1' and (r.is_multiply = '1' or r.is_inverse = '1') then
                    v.state := RENORM_A;
                elsif r.c.denorm = '1' then
                    v.state := RENORM_C;
                elsif r.b.denorm = '1' and (r.is_inverse = '1' or r.is_sqrt = '1') then
                    v.state := RENORM_B;
                elsif r.is_multiply = '1' and r.b.class = ZERO then
                    v.state := DO_FMUL;
                else
                    v.state := r.exec_state;
                end if;

            when DO_ILLEGAL =>
                illegal := '1';
                v.instr_done := '1';

            when DO_MCRFS =>
                cr_op := CROP_MCRFS;
                set_cr := '1';
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

            when DO_FTDIV =>
                -- set result_exp to the exponent of B
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                cr_op := CROP_FTDIV;
                if (r.a.class = ZERO or r.a.class = FINITE) and r.b.class = FINITE then
                    v.doing_ftdiv := "11";
                    v.first := '1';
                    v.state := FTDIV_1;
                else
                    set_cr := '1';
                    v.instr_done := '1';
                end if;

            when DO_FTSQRT =>
                cr_op := CROP_FTSQRT;
                set_cr := '1';
                v.instr_done := '1';

            when DO_FCMP =>
                -- fcmp[uo]
                -- Prepare to subtract mantissas, put B in R
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                update_fx := '1';
                cr_op := CROP_FCMP;
                if r.a.class = NAN or r.b.class = NAN then
                    if (r.a.class = NAN and r.a.mantissa(QNAN_BIT) = '0') or
                        (r.b.class = NAN and r.b.mantissa(QNAN_BIT) = '0') then
                        -- Signalling NAN
                        v.fpscr(FPSCR_VXSNAN) := '1';
                        if r.insn(6) = '1' and r.fpscr(FPSCR_VE) = '0' then
                            v.fpscr(FPSCR_VXVC) := '1';
                        end if;
                        invalid := '1';
                    elsif r.insn(6) = '1' then
                        -- fcmpo
                        v.fpscr(FPSCR_VXVC) := '1';
                        invalid := '1';
                    end if;
                end if;
                if r.a.class = FINITE and r.b.class = FINITE and
                    r.a.negative = r.b.negative and
                    r.a.exponent = r.b.exponent then
                    v.state := CMP_1;
                else
                    set_cr := '1';
                    set_fpcc := '1';
                    v.instr_done := '1';
                end if;

            when DO_MTFSB =>
                -- mtfsb{0,1}
                j := to_integer(unsigned(insn_bt(r.insn)));
                for i in 0 to 31 loop
                    if i = j then
                        v.fpscr(31 - i) := r.insn(6);
                    end if;
                end loop;
                v.instr_done := '1';

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

            when DO_FMRG =>
                -- fmrgew, fmrgow
                set_r := '1';
                opsel_r <= RES_MISC;
                misc_sel <= "100";
                v.writing_fpr := '1';
                v.instr_done := '1';

            when DO_MFFS =>
                v.writing_fpr := '1';
                set_r := '1';
                opsel_r <= RES_MISC;
                misc_sel <= "011";
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
                        v.illegal := '1';
                        v.writing_fpr := '0';
                end case;
                v.instr_done := '1';

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

            when DO_FMR =>
                opsel_r <= RES_MISC;
                misc_sel <= "111";
                opsel_sel <= AIN_B;
                set_r := '1';
                rcls_op <= RCLS_SEL;
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                v.writing_fpr := '1';
                v.instr_done := '1';

            when DO_FRI =>    -- fri[nzpm]
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                -- set shift to exponent - 52
                rs_sel1 <= RSH1_B;
                rs_con2 <= RSCON2_52;
                rs_neg2 <= '1';
                if r.b.exponent >= to_signed(52, EXP_BITS) then
                    -- integer already, no rounding required
                    arith_done := '1';
                else
                    v.state := FRI_1;
                end if;

            when DO_FRSP =>
                -- r.shift = 0
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                v.state := DO_FRSP_2;

            when DO_FRSP_2 =>
                -- r.shift = 0
                -- set shift to exponent - -126 (for ROUND_UFLOW state)
                rs_sel1 <= RSH1_B;
                rs_con2 <= RSCON2_MINEXP;
                rs_neg2 <= '1';
                set_x := '1';   -- uses r.r and r.shift
                if r.b.exponent < to_signed(-126, EXP_BITS) then
                    v.state := ROUND_UFLOW;
                elsif r.b.exponent > to_signed(127, EXP_BITS) then
                    v.state := ROUND_OFLOW;
                else
                    v.state := ROUNDING;
                end if;

            when DO_FCTI =>
                -- instr bit 9: 1=dword 0=word
                -- instr bit 8: 1=unsigned 0=signed
                -- instr bit 1: 1=round to zero 0=use fpscr[RN]
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                rs_sel1 <= RSH1_B;
                rs_neg2 <= '1';

                if r.b.exponent >= to_signed(64, EXP_BITS) or
                    (r.insn(9) = '0' and r.b.exponent >= to_signed(32, EXP_BITS)) then
                    v.state := INT_OFLOW;
                elsif r.b.exponent >= to_signed(52, EXP_BITS) then
                    -- integer already, no rounding required,
                    -- shift into final position
                    -- set shift to exponent - 56
                    rs_con2 <= RSCON2_UNIT;
                    if r.insn(8) = '1' and r.b.negative = '1' then
                        v.state := INT_OFLOW;
                    else
                        v.state := INT_ISHIFT;
                    end if;
                else
                    -- set shift to exponent - 52
                    rs_con2 <= RSCON2_52;
                    v.state := INT_SHIFT;
                end if;

            when DO_FCFID =>
                opsel_a <= AIN_B;
                opsel_aabs <= '1';
                opsel_b <= BIN_ZERO;
                set_r := '1';
                opsel_sel <= AIN_B;
                rcls_op <= RCLS_SEL;
                re_con2 <= RECON2_UNIT;
                re_set_result <= '1';
                if r.b.class = ZERO then
                    arith_done := '1';
                else
                    v.state := FINISH;
                end if;

            when DO_FADD =>
                -- fadd[s] and fsub[s]
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel1 <= REXP1_A;
                re_set_result <= '1';
                -- set shift to a.exp - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                rs_sel2 <= RSH2_A;
                v.add_bsmall := '0';
                if r.a.exponent = r.b.exponent then
                    v.state := ADD_2B;
                elsif r.a.exponent < r.b.exponent then
                    v.longmask := '0';
                    v.state := ADD_SHIFT;
                else
                    v.add_bsmall := '1';
                    v.state := ADD_1;
                end if;

            when DO_FMUL =>
                -- fmul[s]
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel1 <= REXP1_A;
                re_sel2 <= REXP2_C;
                re_set_result <= '1';
                f_to_multiply.valid <= '1';
                v.state := MULT_1;

            when DO_FDIV =>
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel1 <= REXP1_A;
                re_sel2 <= REXP2_B;
                re_neg2 <= '1';
                re_set_result <= '1';
                v.count := "00";
                v.first := '1';
                v.state := DIV_2;

            when DO_FSEL =>
                rsgn_op := RSGN_SEL;
                rcls_op <= RCLS_SEL;
                if r.a.class = ZERO or (r.a.negative = '0' and r.a.class /= NAN) then
                    opsel_sel <= AIN_C;
                    re_sel2 <= REXP2_C;
                else
                    opsel_sel <= AIN_B;
                    re_sel2 <= REXP2_B;
                end if;
                opsel_r <= RES_MISC;
                misc_sel <= "111";
                set_r := '1';
                re_set_result <= '1';
                arith_done := '1';

            when DO_FSQRT =>
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                if r.b.exponent(0) = '1' then
                    v.state := SQRT_ODD;
                elsif r.is_inverse = '0' then
                    v.state := SQRT_1;
                else
                    v.state := RSQRT_1;
                end if;

            when DO_FRE =>
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                v.state := FRE_1;

            when DO_FMADD =>
                -- fmadd, fmsub, fnmadd, fnmsub
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                -- put a.exp + c.exp into result_exp
                re_sel1 <= REXP1_A;
                re_sel2 <= REXP2_C;
                re_set_result <= '1';
                -- put b.exp into shift
                rs_sel1 <= RSH1_B;
                if (r.a.exponent + r.c.exponent + 1) < r.b.exponent then
                    -- addend is bigger, do multiply first
                    -- if subtracting, sign is opposite to initial estimate
                    f_to_multiply.valid <= '1';
                    v.first := '1';
                    v.state := FMADD_0;
                else
                    -- product is bigger, shift B first
                    v.state := FMADD_1;
                end if;

            when RENORM_A =>
                -- Get A into R
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                v.regsel := AIN_A;
                re_sel1 <= REXP1_A;
                re_set_result <= '1';
                v.a.denorm := '0';
                v.state := RENORM_1;

            when RENORM_B =>
                -- Get B into R
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                v.regsel := AIN_B;
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                v.b.denorm := '0';
                v.state := RENORM_1;

            when RENORM_C =>
                -- Get C into R
                opsel_a <= AIN_C;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                v.regsel := AIN_C;
                re_sel2 <= REXP2_C;
                re_set_result <= '1';
                v.c.denorm := '0';
                v.state := RENORM_1;

            when RENORM_1 =>
                rs_norm <= '1';
                renorm_sqrt := r.is_sqrt;
                v.state := RENORM_2;

            when RENORM_2 =>
                set_reg_ind := '1';
                if r.c.denorm = '1' then
                    -- must be either fmul or fmadd/sub
                    v.state := RENORM_C;
                elsif r.b.denorm = '1' and r.is_addition = '0' then
                    v.state := RENORM_B;
                elsif r.is_multiply = '1' and r.b.class = ZERO then
                    v.state := DO_FMUL;
                else
                    v.state := r.exec_state;
                end if;

            when ADD_1 =>
                -- transferring B to R
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                -- set shift to b.exp - a.exp
                rs_sel1 <= RSH1_B;
                rs_sel2 <= RSH2_A;
                rs_neg2 <= '1';
                v.longmask := '0';
                v.state := ADD_SHIFT;

            when ADD_SHIFT =>
                -- r.shift = - exponent difference, r.longmask = 0
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.x := s_nz;
                set_x := '1';
                v.longmask := r.single_prec;
                if r.add_bsmall = '1' then
                    v.state := ADD_2;
                else
                    v.state := ADD_2B;
                end if;

            when ADD_2 =>
                opsel_a <= AIN_A;
                opsel_b <= BIN_ADDSUBR;
                opsel_c <= CIN_SUBEXT;
                set_r := '1';
                -- set shift to -1
                rs_con2 <= RSCON2_1;
                rs_neg2 <= '1';
                v.state := ADD_3;

            when ADD_2B =>
                opsel_a <= AIN_B;
                opsel_b <= BIN_ADDSUBR;
                opsel_c <= CIN_SUBEXT;
                set_r := '1';
                -- set shift to -1
                rs_con2 <= RSCON2_1;
                rs_neg2 <= '1';
                v.state := ADD_3;

            when ADD_3 =>
                -- check for overflow or negative result (can't get both)
                -- r.shift = -1
                re_sel2 <= REXP2_NE;
                rcls_op <= RCLS_TZERO;
                opsel_a <= AIN_ZERO;
                opsel_b <= BIN_ABSR;
                if r.r(63) = '1' then
                    -- result is opposite sign to expected
                    rsgn_op := RSGN_INV;
                    set_r := '1';
                    v.state := FINISH;
                elsif r.r(UNIT_BIT + 1) = '1' then
                    -- sum overflowed, shift right
                    opsel_r <= RES_SHIFT;
                    set_r := '1';
                    re_set_result <= '1';
                    set_x := '1';
                    if exp_huge = '1' then
                        v.state := ROUND_OFLOW;
                    else
                        v.state := ROUNDING;
                    end if;
                elsif r.r(UNIT_BIT) = '1' then
                    set_x := '1';
                    v.state := ROUNDING;
                else
                    rs_norm <= '1';
                    v.state := NORMALIZE;
                end if;

            when CMP_1 =>
                opsel_a <= AIN_A;
                opsel_b <= BIN_MINUSR;
                set_r := '1';
                v.state := CMP_2;

            when CMP_2 =>
                cr_op := CROP_FCMP;
                set_cr := '1';
                set_fpcc := '1';
                v.instr_done := '1';

            when MULT_1 =>
                f_to_multiply.valid <= r.first;
                opsel_r <= RES_MULT;
                set_r := '1';
                if multiply_to_f.valid = '1' then
                    v.state := FINISH;
                end if;

            when FMADD_0 =>
                -- r.shift is b.exp, so new_exp is a.exp + c.exp - b.exp
                -- (first time through; subsequent times we preserve v.shift)
                -- Addend is bigger here
                -- set shift to a.exp + c.exp - b.exp
                -- note v.shift is at most -2 here
                if r.first = '1' then
                    rs_sel1 <= RSH1_NE;
                else
                    rs_sel1 <= RSH1_S;
                end if;
                opsel_r <= RES_MULT;
                set_r := '1';
                opsel_s <= S_MULT;
                set_s := '1';
                if multiply_to_f.valid = '1' then
                    v.longmask := '0';
                    v.state := ADD_SHIFT;
                end if;

            when FMADD_1 =>
                -- shift is b.exp, so new_exp is a.exp + c.exp - b.exp
                -- product is bigger here
                -- shift B right and use it as the addend to the multiplier
                -- for subtract, multiplier does B - A * C
                re_sel2 <= REXP2_B;
                re_set_result <= '1';
                -- set shift to b.exp - result_exp + 64
                rs_sel1 <= RSH1_NE;
                rs_neg1 <= '1';
                rs_con2 <= RSCON2_64;
                v.state := FMADD_2;

            when FMADD_2 =>
                -- Product is potentially bigger here
                -- r.shift = addend exp - product exp + 64, r.r = r.b.mantissa
                set_s := '1';
                opsel_s <= S_SHIFT;
                -- set shift to r.shift - 64
                rs_sel1 <= RSH1_S;
                rs_con2 <= RSCON2_64;
                rs_neg2 <= '1';
                v.state := FMADD_3;

            when FMADD_3 =>
                -- r.shift = addend exp - product exp
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.first := '1';
                v.state := FMADD_4;

            when FMADD_4 =>
                msel_add <= MULADD_RS;
                set_r := '1';
                f_to_multiply.valid <= r.first;
                msel_inv <= r.is_subtract;
                opsel_r <= RES_MULT;
                opsel_s <= S_MULT;
                set_s := '1';
                if multiply_to_f.valid = '1' then
                    v.state := FMADD_5;
                end if;

            when FMADD_5 =>
                -- negate R:S:X if negative
                opsel_b <= BIN_ABSR;
                opsel_c <= CIN_ABSEXT;
                if r.r(63) = '1' then
                    rsgn_op := RSGN_INV;
                    set_r := '1';
                    opsel_s <= S_NEG;
                    set_s := '1';
                end if;
                -- set shift to UNIT_BIT
                rs_con2 <= RSCON2_UNIT;
                v.state := FMADD_6;

            when FMADD_6 =>
                -- r.shift = UNIT_BIT (or 0, but only if r is now nonzero)
                set_r := '0';
                opsel_r <= RES_SHIFT;
                re_sel2 <= REXP2_NE;
                rs_norm <= '1';
                rcls_op <= RCLS_TZERO;
                if (r.r(UNIT_BIT + 2) or r_hi_nz or r_lo_nz or (or (r.r(DP_LSB - 1 downto 0)))) = '0' then
                    -- S = 0 case is handled by RCLS_TZERO logic, otherwise...
                    -- R is all zeroes but there are non-zero bits in S
                    -- so shift them into R and set S to 0
                    set_r := '1';
                    re_set_result <= '1';
                    set_s := '1';
                    v.state := FINISH;
                elsif r.r(UNIT_BIT + 2 downto UNIT_BIT) = "001" then
                    v.state := FINISH;
                else
                    v.state := NORMALIZE;
                end if;

            when DIV_2 =>
                -- compute Y = inverse_table[B] (when count=0); P = 2 - B * Y
                msel_1 <= MUL1_B;
                msel_add <= MULADD_CONST;
                msel_inv <= '1';
                if r.count = 0 then
                    msel_2 <= MUL2_LUT;
                else
                    msel_2 <= MUL2_P;
                end if;
                set_y := r.first;
                pshift := '1';
                f_to_multiply.valid <= r.first;
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.count := r.count + 1;
                    v.state := DIV_3;
                end if;

            when DIV_3 =>
                -- compute Y = P = P * Y
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    if r.count = 3 then
                        v.state := DIV_4;
                    else
                        v.state := DIV_2;
                    end if;
                end if;

            when DIV_4 =>
                -- compute R = P = A * Y (quotient)
                msel_1 <= MUL1_A;
                msel_2 <= MUL2_P;
                set_y := r.first;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                mult_mask := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := DIV_5;
                end if;

            when DIV_5 =>
                -- compute P = A - B * R (remainder)
                msel_1 <= MUL1_B;
                msel_2 <= MUL2_R;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                if multiply_to_f.valid = '1' then
                    v.state := DIV_6;
                end if;

            when DIV_6 =>
                -- test if remainder is 0 or >= B
                opsel_a <= AIN_RND_RBIT;
                if pcmpb_lt = '1' then
                    -- quotient is correct, set X if remainder non-zero
                    set_r := '0';
                    v.x := r.p(UNIT_BIT + 2) or px_nz;
                else
                    -- quotient needs to be incremented by 1 in R-bit position
                    set_r := '1';
                    v.x := not pcmpb_eq;
                end if;
                v.state := FINISH;

            when FRE_1 =>
                re_sel1 <= REXP1_R;
                re_neg1 <= '1';
                re_set_result <= '1';
                opsel_r <= RES_MISC;
                set_r := '1';
                misc_sel <= "101";
                -- set shift to 1
                rs_con2 <= RSCON2_1;
                v.state := NORMALIZE;

            when FTDIV_1 =>
                -- We go through this state up to two times; the first sees if
                -- B.exponent is in the range [-1021,1020], and the second tests
                -- whether B.exp - A.exp is in the range [-1022,1020].
                rs_sel2 <= RSH2_A;                -- set shift to a.exp
                cr_op := CROP_FTDIV;
                if exp_tiny = '1' or exp_huge = '1' or r.a.class = ZERO or r.first = '0' then
                    set_cr := '1';
                    v.instr_done := '1';
                else
                    v.doing_ftdiv := "10";
                end if;

            when SQRT_ODD =>
                -- set shift to 1
                rs_con2 <= RSCON2_1;
                v.regsel := AIN_B;
                v.state := RENORM_2;

            when RSQRT_1 =>
                opsel_r <= RES_MISC;
                misc_sel <= "101";
                set_r := '1';
                re_sel1 <= REXP1_BHALF;
                re_neg1 <= '1';
                re_set_result <= '1';
                -- set shift to 1
                rs_con2 <= RSCON2_1;
                v.state := NORMALIZE;

            when SQRT_1 =>
                -- put invsqr[B] in R and compute P = invsqr[B] * B
                -- also transfer B (in R) to A
                set_a := '1';
                opsel_r <= RES_MISC;
                misc_sel <= "101";
                set_r := '1';
                msel_1 <= MUL1_B;
                msel_2 <= MUL2_LUT;
                f_to_multiply.valid <= '1';
                -- set shift to -1
                rs_con2 <= RSCON2_1;
                rs_neg2 <= '1';
                v.count := "00";
                v.state := SQRT_2;

            when SQRT_2 =>
                -- shift R right one place
                -- not expecting multiplier result yet
                -- r.shift = -1
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.first := '1';
                v.state := SQRT_3;

            when SQRT_3 =>
                -- put R into Y, wait for product from multiplier
                msel_2 <= MUL2_R;
                set_y := r.first;
                pshift := '1';
                mult_mask := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := SQRT_4;
                end if;

            when SQRT_4 =>
                -- compute 1.5 - Y * P
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                msel_add <= MULADD_CONST;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                pshift := '1';
                if multiply_to_f.valid = '1' then
                    v.state := SQRT_5;
                end if;

            when SQRT_5 =>
                -- compute Y = Y * P
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                f_to_multiply.valid <= '1';
                v.first := '1';
                v.state := SQRT_6;

            when SQRT_6 =>
                -- pipeline in R = R * P
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_P;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := SQRT_7;
                end if;

            when SQRT_7 =>
                -- first multiply is done, put result in Y
                msel_2 <= MUL2_P;
                set_y := r.first;
                -- wait for second multiply (should be here already)
                pshift := '1';
                mult_mask := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.count := r.count + 1;
                    if r.count < 2 then
                        v.state := SQRT_4;
                    else
                        v.first := '1';
                        v.state := SQRT_8;
                    end if;
                end if;

            when SQRT_8 =>
                -- compute P = A - R * R, which can be +ve or -ve
                -- we arranged for B to be put into A earlier
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_R;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                pshift := '1';
                f_to_multiply.valid <= r.first;
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := SQRT_9;
                end if;

            when SQRT_9 =>
                -- compute P = P * Y
                -- since Y is an estimate of 1/sqrt(B), this makes P an
                -- estimate of the adjustment needed to R.  Since the error
                -- could be negative and we have an unsigned multiplier, the
                -- upper bits can be wrong, but it turns out the lowest 8 bits
                -- are correct and are all we need (given 3 iterations through
                -- SQRT_4 to SQRT_7).
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                pshift := '1';
                f_to_multiply.valid <= r.first;
                if multiply_to_f.valid = '1' then
                    v.state := SQRT_10;
                end if;

            when SQRT_10 =>
                -- Add the bottom 8 bits of P, sign-extended, onto R.
                opsel_a <= AIN_PS8;
                set_r := '1';
                re_sel1 <= REXP1_BHALF;
                re_set_result <= '1';
                -- set shift to 1
                rs_con2 <= RSCON2_1;
                v.first := '1';
                v.state := SQRT_11;

            when SQRT_11 =>
                -- compute P = A - R * R (remainder)
                -- also put 2 * R + 1 into B for comparison with P
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_R;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                shiftin := '1';
                set_b := r.first;
                if multiply_to_f.valid = '1' then
                    v.state := SQRT_12;
                end if;

            when SQRT_12 =>
                -- test if remainder is 0 or >= B = 2*R + 1
                set_r := '0';
                opsel_c <= CIN_INC;
                if pcmpb_lt = '1' then
                    -- square root is correct, set X if remainder non-zero
                    v.x := r.p(UNIT_BIT + 2) or px_nz;
                else
                    -- square root needs to be incremented by 1
                    set_r := '1';
                    v.x := not pcmpb_eq;
                end if;
                v.state := FINISH;

            when INT_SHIFT =>
                -- r.shift = b.exponent - 52
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                set_x := '1';
                v.state := INT_ROUND;
                -- set shift to -4 (== 52 - UNIT_BIT)
                rs_con2 <= RSCON2_UNIT_52;
                rs_neg2 <= '1';

            when INT_ROUND =>
                -- r.shift = -4 (== 52 - UNIT_BIT)
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
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
                -- r.shift = b.exponent - UNIT_BIT;
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.state := INT_FINAL;

            when INT_FINAL =>
                -- Negate if necessary, and increment for rounding if needed
                opsel_b <= BIN_RSIGNR;
                opsel_c <= CIN_ROUND;
                set_r := '1';
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
                opsel_r <= RES_MISC;
                misc_sel <= "110";
                if (r.insn(8) = '0' and msb /= r.result_sign) or
                    (r.insn(8) = '1' and msb /= '1') then
                    set_r := '1';
                    v.fpscr(FPSCR_VXCVI) := '1';
                    invalid := '1';
                else
                    set_r := '0';
                    if r.fpscr(FPSCR_FI) = '1' then
                        v.fpscr(FPSCR_XX) := '1';
                    end if;
                end if;
                arith_done := '1';

            when INT_OFLOW =>
                opsel_r <= RES_MISC;
                misc_sel <= "110";
                set_r := '1';
                v.fpscr(FPSCR_VXCVI) := '1';
                invalid := '1';
                arith_done := '1';

            when FRI_1 =>
                -- r.shift = b.exponent - 52
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                set_x := '1';
                v.state := ROUNDING;

            when FINISH =>
                if r.is_multiply = '1' and px_nz = '1' then
                    v.x := '1';
                end if;
                -- set shift to new_exp - min_exp (N.B. rs_norm overrides this)
                rs_sel1 <= RSH1_NE;
                rs_con2 <= RSCON2_MINEXP;
                rs_neg2 <= '1';
                if r.r(63 downto UNIT_BIT) /= std_ulogic_vector(to_unsigned(1, 64 - UNIT_BIT)) then
                    rs_norm <= '1';
                    v.state := NORMALIZE;
                else
                    set_x := '1';
                    if exp_tiny = '1' then
                        v.state := ROUND_UFLOW;
                    elsif exp_huge = '1' then
                        v.state := ROUND_OFLOW;
                    else
                        v.state := ROUNDING;
                    end if;
                end if;

            when NORMALIZE =>
                -- Shift so we have 9 leading zeroes (we know R is non-zero)
                -- r.shift = clz(r.r) - 7
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                -- set shift to new_exp - min_exp
                rs_sel1 <= RSH1_NE;
                rs_con2 <= RSCON2_MINEXP;
                rs_neg2 <= '1';
                set_x := '1';
                if exp_tiny = '1' then
                    v.state := ROUND_UFLOW;
                elsif exp_huge = '1' then
                    v.state := ROUND_OFLOW;
                else
                    v.state := ROUNDING;
                end if;

            when ROUND_UFLOW =>
                -- r.shift = - amount by which exponent underflows
                v.tiny := '1';
                opsel_r <= RES_SHIFT;
                set_r := '0';
                if r.fpscr(FPSCR_UE) = '0' then
                    -- disabled underflow exception case
                    -- have to denormalize before rounding
                    set_r := '1';
                    re_sel2 <= REXP2_NE;
                    re_set_result <= '1';
                    set_x := '1';
                    v.state := ROUNDING;
                else
                    -- enabled underflow exception case
                    -- if denormalized, have to normalize before rounding
                    v.fpscr(FPSCR_UX) := '1';
                    re_sel1 <= REXP1_R;
                    re_con2 <= RECON2_BIAS;
                    re_set_result <= '1';
                    if r.r(UNIT_BIT) = '0' then
                        rs_norm <= '1';
                        v.state := NORMALIZE;
                    else
                        v.state := ROUNDING;
                    end if;
                end if;

            when ROUND_OFLOW =>
                rcls_op <= RCLS_TINF;
                v.fpscr(FPSCR_OX) := '1';
                opsel_r <= RES_MISC;
                misc_sel <= "010";
                set_r := '0';
                if r.fpscr(FPSCR_OE) = '0' then
                    -- disabled overflow exception
                    -- result depends on rounding mode
                    set_r := '1';
                    v.fpscr(FPSCR_XX) := '1';
                    v.fpscr(FPSCR_FI) := '1';
                    -- construct largest representable number
                    re_con2 <= RECON2_MAX;
                    re_set_result <= '1';
                    arith_done := '1';
                else
                    -- enabled overflow exception
                    re_sel1 <= REXP1_R;
                    re_con2 <= RECON2_BIAS;
                    re_neg2 <= '1';
                    re_set_result <= '1';
                    v.state := ROUNDING;
                end if;

            when ROUNDING =>
                opsel_mask <= '1';
                set_r := '1';
                round := fp_rounding(r.r, r.x, r.single_prec, r.round_mode, r.result_sign);
                v.fpscr(FPSCR_FR downto FPSCR_FI) := round;
                if round(1) = '1' then
                    -- increment the LSB for the precision
                    v.state := ROUND_INC;
                elsif r.r(UNIT_BIT) = '0' then
                    -- result after masking could be zero, or could be a
                    -- denormalized result that needs to be renormalized
                    rs_norm <= '1';
                    v.state := ROUNDING_3;
                else
                    arith_done := '1';
                end if;
                if round(0) = '1' then
                    v.fpscr(FPSCR_XX) := '1';
                    if r.tiny = '1' then
                        v.fpscr(FPSCR_UX) := '1';
                    end if;
                end if;

            when ROUND_INC =>
                set_r := '1';
                opsel_a <= AIN_RND;
                -- set shift to -1
                rs_con2 <= RSCON2_1;
                rs_neg2 <= '1';
                v.state := ROUNDING_2;

            when ROUNDING_2 =>
                -- Check for overflow during rounding
                -- r.shift = -1
                v.x := '0';
                re_sel2 <= REXP2_NE;
                opsel_r <= RES_SHIFT;
                set_r := '0';
                if r.r(UNIT_BIT + 1) = '1' then
                    set_r := '1';
                    re_set_result <= '1';
                    if exp_huge = '1' then
                        v.state := ROUND_OFLOW;
                    else
                        arith_done := '1';
                    end if;
                elsif r.r(UNIT_BIT) = '0' then
                    -- Do CLZ so we can renormalize the result
                    rs_norm <= '1';
                    v.state := ROUNDING_3;
                else
                    arith_done := '1';
                end if;

            when ROUNDING_3 =>
                -- r.shift = clz(r.r) - 9
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                -- set shift to new_exp - min_exp (== -1022)
                rs_sel1 <= RSH1_NE;
                rs_con2 <= RSCON2_MINEXP;
                rs_neg2 <= '1';
                rcls_op <= RCLS_TZERO;
                -- If the result is zero, that's handled below.
                -- Renormalize result after rounding
                re_set_result <= '1';
                v.denorm := exp_tiny;
                if new_exp < to_signed(-1022, EXP_BITS) then
                    v.state := DENORM;
                else
                    arith_done := '1';
                end if;

            when DENORM =>
                -- r.shift = result_exp - -1022
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                arith_done := '1';

            when DO_IDIVMOD =>
                opsel_a <= AIN_B;
                opsel_aabs <= '1';
                opsel_b <= BIN_ZERO;
                set_r := '1';
                -- normalize and round up B to 8.56 format, like fcfid[u]
                re_con2 <= RECON2_UNIT;
                re_set_result <= '1';
                if r.b.class = ZERO then
                    -- B is zero, signal overflow
                    v.int_ovf := '1';
                    v.state := IDIV_ZERO;
                elsif r.a.class = ZERO then
                    -- A is zero, result is zero (both for div and for mod)
                    v.state := IDIV_ZERO;
                else
                    v.state := IDIV_NORMB;
                end if;
            when IDIV_NORMB =>
                -- do count-leading-zeroes on B (now in R)
                rs_norm <= '1';
                -- save the original value of B or |B| in C
                set_c := '1';
                v.state := IDIV_NORMB2;
            when IDIV_NORMB2 =>
                -- get B into the range [1, 2) in 8.56 format
                set_x := '1';           -- record if any 1 bits shifted out
                opsel_r <= RES_SHIFT;
                set_r := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.state := IDIV_NORMB3;
            when IDIV_NORMB3 =>
                -- add the X bit onto R to round up B
                opsel_c <= CIN_RNDX;
                set_r := '1';
                -- prepare to do count-leading-zeroes on A
                v.state := IDIV_CLZA;
            when IDIV_CLZA =>
                set_b := '1';           -- put R back into B
                opsel_a <= AIN_A;
                opsel_aabs <= '1';
                opsel_b <= BIN_ZERO;
                set_r := '1';
                re_con2 <= RECON2_UNIT;
                re_set_result <= '1';
                v.state := IDIV_CLZA2;
            when IDIV_CLZA2 =>
                rs_norm <= '1';
                -- write the dividend back into A in case we negated it
                set_a_mant := '1';
                -- while doing the count-leading-zeroes on A,
                -- also compute A - B to tell us whether A >= B
                -- (using the original value of B, which is now in C)
                opsel_a <= AIN_C;
                opsel_b <= BIN_R;
                opsel_aneg <= '1';
                set_r := '1';
                v.state := IDIV_CLZA3;
            when IDIV_CLZA3 =>
                -- save the exponent of A (but don't overwrite the mantissa)
                set_a_exp := '1';
                re_sel2 <= REXP2_NE;
                re_set_result <= '1';
                v.div_close := '0';
                if new_exp = r.b.exponent then
                    v.div_close := '1';
                end if;
                v.state := IDIV_NR0;
                if new_exp > r.b.exponent or (v.div_close = '1' and r.r(63) = '0') then
                    -- A >= B, overflow if extended division
                    if r.divext = '1' then
                        v.int_ovf := '1';
                        -- return 0 in overflow cases
                        v.state := IDIV_ZERO;
                    end if;
                else
                    -- A < B, result is zero for normal division
                    if r.divmod = '0' and r.divext = '0' then
                        v.state := IDIV_ZERO;
                    end if;
                end if;
            when IDIV_NR0 =>
                -- reduce number of Newton-Raphson iterations for small A
                if r.divext = '1' or r.result_exp >= to_signed(32, EXP_BITS) then
                    v.count := "00";
                elsif r.result_exp >= to_signed(16, EXP_BITS) then
                    v.count := "01";
                else
                    v.count := "10";
                end if;
                -- first NR iteration does Y = LUT; P = 2 - B * LUT
                msel_1 <= MUL1_B;
                msel_add <= MULADD_CONST;
                msel_inv <= '1';
                msel_2 <= MUL2_LUT;
                set_y := '1';
                -- Get 0.5 into R in case the inverse estimate turns out to be
                -- less than 0.5, in which case we want to use 0.5, to avoid
                -- infinite loops in some cases.
                -- It turns out the generated QNaN mantissa is actually what we want
                opsel_r <= RES_MISC;
                misc_sel <= "001";
                set_r := '1';
                if r.b.mantissa(UNIT_BIT + 1) = '1' then
                    -- rounding up of the mantissa caused overflow, meaning the
                    -- normalized B is 2.0.  Since this is outside the range
                    -- of the LUT, just use 0.5 as the estimated inverse.
                    v.state := IDIV_USE0_5;
                else
                    -- start the first multiply now
                    f_to_multiply.valid <= '1';
                    -- note we don't set v.first, thus the following IDIV_NR1
                    -- state doesn't start a multiply (we already did that)
                    v.state := IDIV_NR1;
                end if;
            when IDIV_NR1 =>
                -- subsequent NR iterations do Y = P; P = 2 - B * P
                msel_1 <= MUL1_B;
                msel_add <= MULADD_CONST;
                msel_inv <= '1';
                msel_2 <= MUL2_P;
                set_y := r.first;
                pshift := '1';
                -- set shift to 64
                rs_con2 <= RSCON2_64;
                if r.first = '1' then
                    if r.count = "11" then
                        if r.p(UNIT_BIT) = '0' and r.p(UNIT_BIT - 1) = '0' then
                            -- inverse estimate is < 0.5, so use 0.5
                            v.state := IDIV_USE0_5;
                        else
                            v.state := IDIV_DODIV;
                        end if;
                    else
                        f_to_multiply.valid <= r.first;
                    end if;
                end if;
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := IDIV_NR2;
                end if;
            when IDIV_NR2 =>
                -- compute P = Y * P
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                if r.first = '1' then
                    v.count := r.count + 1;
                end if;
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := IDIV_NR1;
                end if;
            when IDIV_USE0_5 =>
                -- Put the 0.5 which is in R into Y as the inverse estimate
                set_y := '1';
                msel_2 <= MUL2_R;
                -- set shift to 64
                rs_con2 <= RSCON2_64;
                v.state := IDIV_DODIV;
            when IDIV_DODIV =>
                -- r.shift = 64
                -- inverse estimate is in Y
                -- put A (dividend) into R
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                -- shift_res is 0 because r.shift = 64;
                -- put that into B, which now holds the quotient
                set_b_mant := '1';
                if r.divext = '0' then
                    -- set shift to -56
                    rs_con2 <= RSCON2_UNIT;
                    rs_neg2 <= '1';
                    v.first := '1';
                    v.state := IDIV_DIV;
                elsif r.single_prec = '1' then
                    -- divwe[u][o], shift A left 32 bits
                    -- set shift to 32
                    rs_con2 <= RSCON2_32;
                    v.state := IDIV_SH32;
                elsif r.div_close = '0' then
                    -- set shift to 64 - UNIT_BIT (== 8)
                    rs_con2 <= RSCON2_64_UNIT;
                    v.state := IDIV_EXTDIV;
                else
                    -- handle top bit of quotient specially
                    -- for this we need the divisor left-justified in B
                    v.state := IDIV_EXT_TBH;
                end if;
            when IDIV_SH32 =>
                -- r.shift = 32, R contains the dividend
                opsel_r <= RES_SHIFT;
                set_r := '1';
                -- set shift to -UNIT_BIT (== -56)
                rs_con2 <= RSCON2_UNIT;
                rs_neg2 <= '1';
                v.first := '1';
                v.state := IDIV_DIV;
            when IDIV_DIV =>
                -- Dividing A by C, r.shift = -56; A is in R
                -- Put A into the bottom 64 bits of Ahi/A/Alo
                set_a_mant := r.first;
                set_a_lo := r.first;
                -- compute R = R * Y (quotient estimate)
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_R;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                -- set shift to - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                if multiply_to_f.valid = '1' then
                    v.state := IDIV_DIV2;
                end if;
            when IDIV_DIV2 =>
                -- r.shift = - b.exponent
                -- shift the quotient estimate right by b.exponent bits
                opsel_r <= RES_SHIFT;
                set_r := '1';
                v.first := '1';
                v.state := IDIV_DIV3;
            when IDIV_DIV3 =>
                -- quotient (so far) is in R; multiply by C and subtract from A
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_C;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                -- store the current quotient estimate in B
                set_b_mant := r.first;
                opsel_r <= RES_MULT;
                set_r := '1';
                opsel_s <= S_MULT;
                set_s := '1';
                if multiply_to_f.valid = '1' then
                    v.state := IDIV_DIV4;
                end if;
            when IDIV_DIV4 =>
                -- remainder is in R/S and P
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                v.inc_quot := not pcmpc_lt and not r.divmod;
                -- if dividing, get B into R for IDIV_DIVADJ state
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := not r.divmod;
                -- set shift to UNIT_BIT (== 56)
                rs_con2 <= RSCON2_UNIT;
                if pcmpc_lt = '1' or pcmpc_eq = '1' then
                    if r.divmod = '0' then
                        v.state := IDIV_DIVADJ;
                    elsif pcmpc_eq = '1' then
                        v.state := IDIV_ZERO;
                    else
                        v.state := IDIV_MODADJ;
                    end if;
                else
                    -- need to do another iteration, compute P * Y
                    f_to_multiply.valid <= '1';
                    v.state := IDIV_DIV5;
                end if;
            when IDIV_DIV5 =>
                pshift := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                -- set shift to - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                if multiply_to_f.valid = '1' then
                    v.state := IDIV_DIV6;
                end if;
            when IDIV_DIV6 =>
                -- r.shift = - b.exponent
                -- shift the quotient estimate right by b.exponent bits
                opsel_r <= RES_SHIFT;
                set_r := '1';
                v.first := '1';
                v.state := IDIV_DIV7;
            when IDIV_DIV7 =>
                -- add shifted quotient delta onto the total quotient
                opsel_a <= AIN_B;
                opsel_b <= BIN_R;
                set_r := '1';
                v.first := '1';
                v.state := IDIV_DIV8;
            when IDIV_DIV8 =>
                -- quotient (so far) is in R; multiply by C and subtract from A
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_C;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                -- store the current quotient estimate in B
                set_b_mant := r.first;
                opsel_r <= RES_MULT;
                set_r := '1';
                opsel_s <= S_MULT;
                set_s := '1';
                if multiply_to_f.valid = '1' then
                    v.state := IDIV_DIV9;
                end if;
            when IDIV_DIV9 =>
                -- remainder is in R/S and P
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_P;
                v.inc_quot := not pcmpc_lt and not r.divmod;
                -- set shift to UNIT_BIT (== 56)
                rs_con2 <= RSCON2_UNIT;
                -- if dividing, get B into R for IDIV_DIVADJ state
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := not r.divmod;
                if r.divmod = '0' then
                    v.state := IDIV_DIVADJ;
                elsif pcmpc_eq = '1' then
                    v.state := IDIV_ZERO;
                else
                    v.state := IDIV_MODADJ;
                end if;
            when IDIV_EXT_TBH =>
                -- get divisor into R and prepare to shift left
                -- set shift to 63 - b.exp
                opsel_a <= AIN_C;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                rs_con2 <= RSCON2_63;
                v.state := IDIV_EXT_TBH2;
            when IDIV_EXT_TBH2 =>
                -- divisor is in R
                -- r.shift = 63 - b.exponent; shift and put into B
                opsel_a <= AIN_A;
                opsel_b <= BIN_ZERO;
                set_r := '1';
                set_b_mant := '1';
                -- set shift to 64 - UNIT_BIT (== 8)
                rs_con2 <= RSCON2_64_UNIT;
                v.state := IDIV_EXT_TBH3;
            when IDIV_EXT_TBH3 =>
                -- Dividing (A << 64) by C
                -- r.shift = 8
                -- Put A in the top 64 bits of Ahi/A/Alo
                set_a_hi := '1';
                set_a_mant := '1';
                -- set shift to 64 - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                rs_con2 <= RSCON2_64;
                v.state := IDIV_EXT_TBH4;
            when IDIV_EXT_TBH4 =>
                -- dividend (A) is in R
                -- r.shift = 64 - B.exponent, so is at least 1
                opsel_r <= RES_SHIFT;
                set_r := '1';
                -- top bit of A gets lost in the shift, so handle it specially
                -- set shift to 63
                rs_con2 <= RSCON2_63;
                v.state := IDIV_EXT_TBH5;
            when IDIV_EXT_TBH5 =>
                -- r.shift = 63
                -- shifted dividend is in R, subtract left-justified divisor
                opsel_a <= AIN_B;
                opsel_b <= BIN_R;
                opsel_aneg <= '1';
                set_r := '1';
                -- and put 1<<63 into B as the divisor (S is still 0)
                shiftin0 := '1';
                set_b_mant := '1';
                v.first := '1';
                v.state := IDIV_EXTDIV2;
            when IDIV_EXTDIV =>
                -- Dividing (A << 64) by C
                -- r.shift = 8
                -- Put A in the top 64 bits of Ahi/A/Alo
                set_a_hi := '1';
                set_a_mant := '1';
                -- set shift to 64 - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                rs_con2 <= RSCON2_64;
                v.state := IDIV_EXTDIV1;
            when IDIV_EXTDIV1 =>
                -- dividend is in R
                -- r.shift = 64 - B.exponent
                opsel_r <= RES_SHIFT;
                set_r := '1';
                v.first := '1';
                v.state := IDIV_EXTDIV2;
            when IDIV_EXTDIV2 =>
                -- shifted remainder is in R; compute R = R * Y (quotient estimate)
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_R;
                f_to_multiply.valid <= r.first;
                pshift := '1';
                opsel_r <= RES_MULT;
                set_r := '1';
                if multiply_to_f.valid = '1' then
                    v.first := '1';
                    v.state := IDIV_EXTDIV3;
                end if;
            when IDIV_EXTDIV3 =>
                -- delta quotient is in R; add it to B
                opsel_a <= AIN_B;
                opsel_b <= BIN_R;
                set_r := '1';
                v.first := '1';
                v.state := IDIV_EXTDIV4;
            when IDIV_EXTDIV4 =>
                -- quotient is in R; put it in B and compute remainder
                set_b_mant := r.first;
                msel_1 <= MUL1_R;
                msel_2 <= MUL2_C;
                msel_add <= MULADD_A;
                msel_inv <= '1';
                f_to_multiply.valid <= r.first;
                opsel_r <= RES_MULT;
                set_r := '1';
                opsel_s <= S_MULT;
                set_s := '1';
                -- set shift to UNIT_BIT - b.exp
                rs_sel1 <= RSH1_B;
                rs_neg1 <= '1';
                rs_con2 <= RSCON2_UNIT;
                if multiply_to_f.valid = '1' then
                    v.state := IDIV_EXTDIV5;
                end if;
            when IDIV_EXTDIV5 =>
                -- r.shift = r.b.exponent - 56
                -- remainder is in R/S; shift it right r.b.exponent bits
                opsel_r <= RES_SHIFT;
                set_r := '1';
                -- test LS 64b of remainder in P against divisor in C
                v.inc_quot := not pcmpc_lt;
                v.state := IDIV_EXTDIV6;
            when IDIV_EXTDIV6 =>
                -- shifted remainder is in R, see if it is > 1
                -- and compute R = R * Y if so
                opsel_a <= AIN_B;
                opsel_b <= BIN_ZERO;
                set_r := '0';
                msel_1 <= MUL1_Y;
                msel_2 <= MUL2_R;
                pshift := '1';
                if r_gt_1 = '1' then
                    f_to_multiply.valid <= '1';
                    v.state := IDIV_EXTDIV2;
                else
                    -- Put B (quotient) into R for IDIV_DIVADJ state
                    set_r := '1';
                    v.state := IDIV_DIVADJ;
                end if;
            when IDIV_MODADJ =>
                -- r.shift = 56
                -- result is in R/S
                opsel_r <= RES_SHIFT;
                set_r := '1';
                if pcmpc_lt = '0' then
                    v.state := IDIV_MODSUB;
                elsif r.result_sign = '0' then
                    v.state := IDIV_DONE;
                else
                    v.state := IDIV_MODADJ_NEG;
                end if;
            when IDIV_MODADJ_NEG =>
                -- result (so far) is in R
                -- set carry to increment quotient if needed
                -- and also negate R since the answer is negative
                opsel_b <= BIN_MINUSR;
                set_r := '1';
                v.state := IDIV_OVFCHK;
            when IDIV_MODSUB =>
                -- Subtract divisor from remainder
                opsel_a <= AIN_C;
                opsel_aneg <= '1';
                opsel_b <= BIN_R;
                set_r := '1';
                if r.result_sign = '0' then
                    v.state := IDIV_DONE;
                else
                    v.state := IDIV_DIVADJ;
                end if;
            when IDIV_DIVADJ =>
                -- result (so far) is in R
                -- set carry to increment quotient if needed
                -- and also negate R if the answer is negative
                opsel_a <= AIN_RND_B32;
                opsel_b <= BIN_RSIGNR;
                opsel_c <= CIN_RNDQ;
                set_r := '1';
                if r.is_signed = '0' then
                    v.state := IDIV_DONE;
                else
                    v.state := IDIV_OVFCHK;
                end if;
            when IDIV_OVFCHK =>
                opsel_r <= RES_MISC;
                misc_sel <= "000";
                if r.single_prec = '0' then
                    sign_bit := r.r(63);
                else
                    sign_bit := r.r(31);
                end if;
                v.int_ovf := sign_bit xor r.result_sign;
                set_r := sign_bit xor r.result_sign;
                v.state := IDIV_DONE;
            when IDIV_DONE =>
                cr_op := CROP_INTRES;
                set_cr := '1';
                v.writing_fpr := '1';
                v.instr_done := '1';
            when IDIV_ZERO =>
                opsel_r <= RES_MISC;
                misc_sel <= "000";
                set_r := '1';
                v.state := IDIV_DONE;

        end case;

        -- Handle exceptions and special cases for arithmetic operations
        if r.cycle_1_ar = '1' then
            v.fpscr := r.fpscr or scinfo.new_fpscr;
            invalid := scinfo.invalid;
            zero_divide := scinfo.zero_divide;
            qnan_result := scinfo.qnan_result;
            if scinfo.immed_result = '1' then
                -- state machine is in the DO_SPECIAL or DO_FSQRT state here
                arith_done := '1';
                set_r := '1';
                opsel_r <= RES_MISC;
                opsel_sel <= scinfo.result_sel;
                if scinfo.qnan_result = '1' then
                    if r.int_result = '0' then
                        misc_sel <= "001";
                    else
                        misc_sel <= "110";
                    end if;
                else
                    misc_sel <= "111";
                end if;
                rsgn_op := scinfo.rsgn_op;
                v.result_class := scinfo.result_class;
                if scinfo.result_sel = AIN_B then
                    re_sel2 <= REXP2_B;
                else
                    re_sel1 <= REXP1_A;
                end if;
                re_set_result <= '1';
            end if;
        end if;

        rsign := r.result_sign;
        case rsgn_op is
            when RSGN_SEL =>
                case opsel_sel is
                    when AIN_A =>
                        rsign := r.a.negative;
                    when AIN_B =>
                        rsign := r.b.negative;
                    when AIN_C =>
                        rsign := r.c.negative;
                    when others =>
                end case;
                v.result_sign := rsign;
            when RSGN_SUB =>
                rsign := r.result_sign xor r.is_subtract;
                v.result_sign := rsign;
            when RSGN_INV =>
                rsign := not r.result_sign;
                v.result_sign := rsign;
            when others =>
        end case;

        case rcls_op is
            when RCLS_SEL =>
                case opsel_sel is
                    when AIN_A =>
                        v.result_class := r.a.class;
                    when AIN_B =>
                        v.result_class := r.b.class;
                    when AIN_C =>
                        v.result_class := r.c.class;
                    when others =>
                end case;
            when RCLS_TZERO =>
                if or (r.r(UNIT_BIT + 2 downto 0)) = '0' and s_nz = '0' then
                    v.result_class := ZERO;
                    arith_done := '1';
                end if;
            when RCLS_TINF =>
                if r.fpscr(FPSCR_OE) = '0' then
                    if r.round_mode(1 downto 0) = "00" or
                        (r.round_mode(1) = '1' and r.round_mode(0) = r.result_sign) then
                        v.result_class := INFINITY;
                        v.fpscr(FPSCR_FR) := '1';
                    else
                        v.fpscr(FPSCR_FR) := '0';
                    end if;
                end if;
            when others =>
        end case;

        if qnan_result = '1' then
            rsign := '0';
        end if;
        if invalid = '1' then
            v.invalid := '1';
        end if;
        if arith_done = '1' then
            -- Enabled invalid exception doesn't write result or FPRF
            -- Neither does enabled zero-divide exception
            if (v.invalid and r.fpscr(FPSCR_VE)) = '0' and
                (zero_divide and r.fpscr(FPSCR_ZE)) = '0' then
                v.writing_fpr := '1';
                v.update_fprf := '1';
            end if;
            if r.is_subtract = '1' and v.result_class = ZERO then
                rsign := r.round_mode(0) and r.round_mode(1);
            end if;
            if r.negate = '1' and v.result_class /= NAN then
                rsign := not rsign;
            end if;
            v.instr_done := '1';
            update_fx := '1';
        end if;

        -- Multiplier and divide/square root data path
        case msel_1 is
            when MUL1_A =>
                f_to_multiply.data1 <= r.a.mantissa;
            when MUL1_B =>
                f_to_multiply.data1 <= r.b.mantissa;
            when MUL1_Y =>
                f_to_multiply.data1 <= r.y;
            when others =>
                f_to_multiply.data1 <= r.r;
        end case;
        case msel_2 is
            when MUL2_C =>
                f_to_multiply.data2 <= r.c.mantissa;
            when MUL2_LUT =>
                f_to_multiply.data2 <= std_ulogic_vector(shift_left(resize(unsigned(inverse_est), 64),
                                                                    UNIT_BIT - 19));
            when MUL2_P =>
                f_to_multiply.data2 <= r.p;
            when others =>
                f_to_multiply.data2 <= r.r;
        end case;
        maddend := (others => '0');
        case msel_add is
            when MULADD_CONST =>
                -- addend is 2.0 or 1.5 in 16.112 format
                if r.is_sqrt = '0' then
                    maddend(2*UNIT_BIT + 1) := '1';                       -- 2.0
                else
                    maddend(2*UNIT_BIT downto 2*UNIT_BIT - 1) := "11";    -- 1.5
                end if;
            when MULADD_A =>
                -- addend is A in 16.112 format
                maddend(127 downto UNIT_BIT + 64) := r.a_hi;
                maddend(UNIT_BIT + 63 downto UNIT_BIT) := r.a.mantissa;
                maddend(UNIT_BIT - 1 downto 0) := r.a_lo;
            when MULADD_RS =>
                -- addend is concatenation of R and S in 16.112 format
                maddend(UNIT_BIT + 63 downto UNIT_BIT) := r.r;
                maddend(UNIT_BIT - 1 downto 0) := r.s;
            when others =>
        end case;
        f_to_multiply.addend <= maddend;
        f_to_multiply.subtract <= msel_inv;
        if set_y = '1' then
            v.y := f_to_multiply.data2;
        end if;
        if multiply_to_f.valid = '1' then
            if pshift = '0' then
                v.p := multiply_to_f.result(63 downto 0);
            else
                v.p := multiply_to_f.result(UNIT_BIT + 63 downto UNIT_BIT);
            end if;
        end if;

        -- Data path.
        -- This has A and B input multiplexers, an adder, a shifter,
        -- count-leading-zeroes logic, and a result mux.

        -- If shifting right, test if bits of R will be shifted out of significance
        if r.longmask = '1' then
            mshift := to_signed(28, EXP_BITS);
        else
            mshift := to_signed(-1, EXP_BITS);
        end if;
        mshift := mshift - r.shift;
        if set_x = '1' and not is_X(mshift) and mshift >= to_signed(0, EXP_BITS) then
            -- Instead of computing (R & right_mask(63-mshift)) != 0,
            -- we compute (R | -R), which has the form 111...10...0
            -- where the rightmost 1 is in the same position as the
            -- rightmost 1 in R.  Then if bit (mshift) of that value
            -- is 1, there must be a 1 in the rightmost (mshift + 1)
            -- bits of R.
            rormr := r.r or std_ulogic_vector(- signed(r.r));
            if mshift >= to_signed(64, EXP_BITS) then
                mshift := to_signed(63, EXP_BITS);
            end if;
            v.x := v.x or r.r(to_integer(unsigned(mshift(5 downto 0))));
        end if;
        asign := '0';
        case opsel_a is
            when AIN_A =>
                in_a0 := r.a.mantissa;
                asign := r.a.negative;
            when AIN_B =>
                in_a0 := r.b.mantissa;
                asign := r.b.negative;
            when AIN_C =>
                in_a0 := r.c.mantissa;
            when AIN_PS8 =>     -- 8 LSBs of P sign-extended to 64
                in_a0 := std_ulogic_vector(resize(signed(r.p(7 downto 0)), 64));
            when AIN_RND_B32 =>
                in_a0 := (32 => r.result_sign and r.single_prec, others => '0');
            when AIN_RND_RBIT =>
                in_a0 := (DP_RBIT => '1', others => '0');
            when AIN_RND =>
                in_a0 := (SP_LSB => r.single_prec, DP_LSB => not r.single_prec, others => '0');
            when others =>
                in_a0 := (others => '0');
        end case;
        ci := '0';
        case opsel_c is
            when CIN_SUBEXT =>
                ci := r.is_subtract and r.x;
            when CIN_ABSEXT =>
                ci := r.r(63) and (s_nz or r.x);
            when CIN_INC =>
                ci := '1';
            when CIN_ROUND =>
                ci := r.fpscr(FPSCR_FR);
            when CIN_RNDX =>
                ci := r.x;
            when CIN_RNDQ =>
                ci := r.inc_quot;
            when others =>
        end case;
        if opsel_aneg = '1' or (opsel_aabs = '1' and r.is_signed = '1' and asign = '1') then
            in_a0 := not in_a0;
            ci := not ci;
        end if;
        in_a <= in_a0;
        in_b0 := r.r;
        bneg := '0';
        case opsel_b is
            when BIN_R =>
            when BIN_MINUSR =>
                bneg := '1';
            when BIN_ABSR =>
                bneg := r.r(63);
            when BIN_ADDSUBR =>
                bneg := r.is_subtract;
            when BIN_RSIGNR =>
                bneg := r.result_sign;
            when others =>
                in_b0 := (others => '0');
        end case;
        if bneg = '1' then
            in_b0 := not in_b0;
            ci := not ci;
        end if;
        in_b <= in_b0;
	if is_X(r.shift) then
            shift_res := (others => 'X');
	elsif r.shift >= to_signed(-64, EXP_BITS) and r.shift <= to_signed(63, EXP_BITS) then
            shift_res := shifter_64(r.r(63 downto 1) & (shiftin0 or r.r(0)) &
                                    (shiftin or r.s(55)) & r.s(54 downto 0),
                                    std_ulogic_vector(r.shift(6 downto 0)));
        else
            shift_res := (others => '0');
        end if;
        sum := std_ulogic_vector(unsigned(in_a) + unsigned(in_b) + ci);
        if opsel_mask = '1' then
            sum(DP_LSB - 1 downto 0) := "0000";
            if r.single_prec = '1' then
                sum(SP_LSB - 1 downto DP_LSB) := (others => '0');
            end if;
        end if;
        case opsel_r is
            when RES_SUM =>
                result <= sum;
            when RES_SHIFT =>
                result <= shift_res;
            when RES_MULT =>
                result <= multiply_to_f.result(UNIT_BIT + 63 downto UNIT_BIT);
                if mult_mask = '1' then
                    -- trim to 54 fraction bits if mult_mask = 1, for quotient when dividing
                    result(UNIT_BIT - 55 downto 0) <= (others => '0');
                end if;
            when others =>
                misc := (others => '0');
                case misc_sel is
                    when "000" =>
                        -- zero result, used in idiv logic
                    when "001" =>
                        -- generated QNaN mantissa; also used for 0.5 in idiv logic
                        misc(QNAN_BIT) := '1';
                    when "010" =>
                        -- mantissa of max representable number, DP or SP
                        misc(UNIT_BIT downto SP_LSB) := (others => '1');
                        misc(SP_LSB-1 downto DP_LSB) := (others => not r.single_prec);
                    when "011" =>
                        -- read FPSCR
                        misc := x"00000000" & (r.fpscr and fpscr_mask);
                    when "100" =>
                        -- fmrgow/fmrgew result
                        if r.insn(8) = '0' then
                            misc := r.a.mantissa(31 downto 0) & r.b.mantissa(31 downto 0);
                        else
                            misc := r.a.mantissa(63 downto 32) & r.b.mantissa(63 downto 32);
                        end if;
                    when "101" =>
                        -- LUT value
                        misc := std_ulogic_vector(shift_left(resize(unsigned(inverse_est), 64),
                                                             UNIT_BIT - 19));
                    when "110" =>
                        -- max positive or negative result for fcti*
                        if r.result_sign = '0' and r.b.class /= NAN then
                            misc := x"000000007fffffff";
                            misc(31) := r.insn(8) or r.insn(9);  -- unsigned or dword
                            misc(62 downto 32) := (others => r.insn(9));  -- dword
                            misc(63) := r.insn(8) and r.insn(8);
                        elsif r.insn(8) = '0' then
                            misc(63) := '1';
                            if r.insn(9) = '0' then
                                misc(62 downto 31) := (others => '1');
                            end if;
                        end if;
                    when others =>
                        -- A, B or C, according to opsel_sel
                        case opsel_sel is
                            when AIN_A =>
                                misc := r.a.mantissa;
                            when AIN_B =>
                                misc := r.b.mantissa;
                            when AIN_C =>
                                misc := r.c.mantissa;
                            when others =>
                        end case;
                end case;
                result <= misc;
        end case;
        if set_r = '1' then
            v.r := result;
        end if;
        if set_s = '1' then
            case opsel_s is
                when S_NEG =>
                    v.s := std_ulogic_vector(unsigned(not r.s) + (not r.x));
                when S_MULT =>
                    v.s := multiply_to_f.result(55 downto 0);
                when S_SHIFT =>
                    v.s := shift_res(63 downto 8);
                    if shift_res(7 downto 0) /= x"00" then
                        v.x := '1';
                    end if;
                when others =>
                    v.s := (others => '0');
            end case;
        end if;

        if set_reg_ind = '1' then
            case r.regsel is
                when AIN_A =>
                    set_a := '1';
                when AIN_B =>
                    set_b := '1';
                when AIN_C =>
                    set_c := '1';
                when others =>
            end case;
        end if;
        if set_a = '1' or set_a_exp = '1' then
            v.a.exponent := new_exp;
        end if;
        if set_a = '1' or set_a_mant = '1' then
            v.a.mantissa := shift_res;
        end if;
        if e_in.valid = '1' then
            v.a_hi := (others => '0');
            v.a_lo := (others => '0');
        else
            if set_a_hi = '1' then
                v.a_hi := r.r(63 downto 56);
            end if;
            if set_a_lo = '1' then
                v.a_lo := r.r(55 downto 0);
            end if;
        end if;
        if set_b = '1' then
            v.b.exponent := new_exp;
        end if;
        if set_b = '1' or set_b_mant = '1' then
            v.b.mantissa := shift_res;
        end if;
        if set_c = '1' then
            v.c.exponent := new_exp;
            v.c.mantissa := shift_res;
        end if;

        -- exponent data path
        case re_sel1 is
            when REXP1_R =>
                rexp_in1 := r.result_exp;
            when REXP1_A =>
                rexp_in1 := r.a.exponent;
            when REXP1_BHALF =>
                rexp_in1 := r.b.exponent(EXP_BITS-1) & r.b.exponent(EXP_BITS-1 downto 1);
            when others =>
                rexp_in1 := to_signed(0, EXP_BITS);
        end case;
        if re_neg1 = '1' then
            rexp_in1 := not rexp_in1;
        end if;
        case re_sel2 is
            when REXP2_NE =>
                rexp_in2 := new_exp;
            when REXP2_C =>
                rexp_in2 := r.c.exponent;
            when REXP2_B =>
                rexp_in2 := r.b.exponent;
            when others =>
                case re_con2 is
                    when RECON2_UNIT =>
                        rexp_in2 := to_signed(UNIT_BIT, EXP_BITS);
                    when RECON2_MAX =>
                        rexp_in2 := max_exp;
                    when RECON2_BIAS =>
                        rexp_in2 := bias_exp;
                    when others =>
                        rexp_in2 := to_signed(0, EXP_BITS);
                end case;
        end case;
        if re_neg2 = '1' then
            rexp_in2 := not rexp_in2;
        end if;
        rexp_cin := re_neg1 or re_neg2;
        rexp_sum := rexp_in1 + rexp_in2 + rexp_cin;
        if re_set_result = '1' then
            v.result_exp := rexp_sum;
        end if;
        case rs_sel1 is
            when RSH1_B =>
                rsh_in1 := r.b.exponent;
            when RSH1_NE =>
                rsh_in1 := new_exp;
            when RSH1_S =>
                rsh_in1 := r.shift;
            when others =>
                rsh_in1 := to_signed(0, EXP_BITS);
        end case;
        if rs_neg1 = '1' then
            rsh_in1 := not rsh_in1;
        end if;
        case rs_sel2 is
            when RSH2_A =>
                rsh_in2 := r.a.exponent;
            when others =>
                case rs_con2 is
                    when RSCON2_1 =>
                        rsh_in2 := to_signed(1, EXP_BITS);
                    when RSCON2_UNIT_52 =>
                        rsh_in2 := to_signed(UNIT_BIT - 52, EXP_BITS);
                    when RSCON2_64_UNIT =>
                        rsh_in2 := to_signed(64 - UNIT_BIT, EXP_BITS);
                    when RSCON2_32 =>
                        rsh_in2 := to_signed(32, EXP_BITS);
                    when RSCON2_52 =>
                        rsh_in2 := to_signed(52, EXP_BITS);
                    when RSCON2_UNIT =>
                        rsh_in2 := to_signed(UNIT_BIT, EXP_BITS);
                    when RSCON2_63 =>
                        rsh_in2 := to_signed(63, EXP_BITS);
                    when RSCON2_64 =>
                        rsh_in2 := to_signed(64, EXP_BITS);
                    when RSCON2_MINEXP =>
                        rsh_in2 := min_exp;
                    when others =>
                        rsh_in2 := to_signed(0, EXP_BITS);
                end case;
        end case;
        if rs_neg2 = '1' then
            rsh_in2 := not rsh_in2;
        end if;
        if rs_norm = '1' then
            clz := count_left_zeroes(r.r);
            if renorm_sqrt = '1' then
                -- make denormalized value end up with even exponent
                clz(0) := '1';
            end if;
            -- do this as a separate dedicated 7-bit adder for timing reasons
            v.shift := resize(signed('0' & clz) - (63 - UNIT_BIT), EXP_BITS);
        else
            v.shift := rsh_in1 + rsh_in2 + (rs_neg1 or rs_neg2);
        end if;

        -- Condition register data path
        cr_result := "0000";
        case cr_op is
            when CROP_FCMP =>
                if r.a.class = NAN or r.b.class = NAN then
                    cr_result := "0001";          -- unordered
                elsif r.a.class = ZERO and r.b.class = ZERO then
                    cr_result := "0010";          -- equal
                elsif r.a.negative /= r.b.negative then
                    cr_result := r.a.negative & r.b.negative & "00";
                elsif r.a.class = INFINITY and r.b.class = INFINITY then
                    -- A and B are the same sign from here down
                    cr_result := "0010";
                elsif r.a.class = ZERO then
                    cr_result := not r.b.negative & r.b.negative & "00";
                elsif r.a.class = INFINITY then
                    cr_result := r.a.negative & not r.a.negative & "00";
                elsif r.b.class = ZERO then
                    -- A is finite from here down
                    cr_result := r.a.negative & not r.a.negative & "00";
                elsif r.b.class = INFINITY then
                    cr_result := not r.b.negative & r.b.negative & "00";
                elsif r.a.exponent > r.b.exponent then
                    -- A and B are both finite from here down
                    cr_result := r.a.negative & not r.a.negative & "00";
                elsif r.a.exponent /= r.b.exponent then
                    -- A exponent is smaller than B
                    cr_result := not r.a.negative & r.a.negative & "00";
                elsif r.r(63) = '1' then
                    -- A is smaller in magnitude
                    cr_result := not r.a.negative & r.a.negative & "00";
                elsif (r_hi_nz or r_lo_nz) = '0' then
                    cr_result := "0010";
                else
                    cr_result := r.a.negative & not r.a.negative & "00";
                end if;
            when CROP_MCRFS =>
                j := to_integer(unsigned(insn_bfa(r.insn)));
                for i in 0 to 7 loop
                    if i = j then
                        k := (7 - i) * 4;
                        cr_result := r.fpscr(k + 3 downto k);
                    end if;
                end loop;
            when CROP_FTDIV =>
                if r.a.class = INFINITY or r.b.class = ZERO or r.b.class = INFINITY or
                    (r.b.class = FINITE and r.b.denorm = '1') then
                    cr_result(2) := '1';
                end if;
                if r.a.class = NAN or r.a.class = INFINITY or
                    r.b.class = NAN or r.b.class = ZERO or r.b.class = INFINITY or
                    (r.a.class = FINITE and r.a.exponent <= to_signed(-970, EXP_BITS)) or
                    (r.doing_ftdiv(1) = '1' and (exp_tiny or exp_huge) = '1') then
                    cr_result(1) := '1';
                end if;
            when CROP_FTSQRT =>
                if r.b.class = ZERO or r.b.class = INFINITY or
                    (r.b.class = FINITE and r.b.denorm = '1') then
                    cr_result(2) := '1';
                end if;
                if r.b.class = NAN or r.b.class = INFINITY or r.b.class = ZERO
                    or r.b.negative = '1' or r.b.exponent <= to_signed(-970, EXP_BITS) then
                    cr_result(1) := '1';
                end if;
            when CROP_INTRES =>
                v.xerc_result := v.xerc;
                if r.oe = '1' then
                    v.xerc_result.ov := r.int_ovf;
                    v.xerc_result.ov32 := r.int_ovf;
                    v.xerc_result.so := r.xerc.so or r.int_ovf;
                    v.writing_xer := '1';
                end if;
                if r.m32b = '0' then
                    cr_result(3) := r.r(63);
                    if r.r = 64x"0" then
                        cr_result(1) := '1';
                    else
                        cr_result(2) := not r.r(63);
                    end if;
                else
                    cr_result(3) := r.r(31);
                    if r.r(31 downto 0) = 32x"0" then
                        cr_result(1) := '1';
                    else
                        cr_result(2) := not r.r(31);
                    end if;
                end if;
                cr_result(0) := v.xerc_result.so;
            when others =>
        end case;
        if set_cr = '1' then
            v.cr_result := cr_result;
        end if;
        if set_fpcc = '1' then
            v.fpscr(FPSCR_FL downto FPSCR_FU) := cr_result;
        end if;

        if r.update_fprf = '1' then
            v.fpscr(FPSCR_C downto FPSCR_FU) := result_flags(r.res_sign, r.result_class,
                                                             r.r(UNIT_BIT) and not r.denorm);
        end if;

        v.fpscr(FPSCR_VX) := (or (v.fpscr(FPSCR_VXSNAN downto FPSCR_VXVC))) or
                             (or (v.fpscr(FPSCR_VXSOFT downto FPSCR_VXCVI)));
        v.fpscr(FPSCR_FEX) := or (v.fpscr(FPSCR_VX downto FPSCR_XX) and
                                  v.fpscr(FPSCR_VE downto FPSCR_XE));
        if update_fx = '1' and
            (v.fpscr(FPSCR_VX downto FPSCR_XX) and not r.old_exc) /= "00000" then
            v.fpscr(FPSCR_FX) := '1';
        end if;

        if v.instr_done = '1' then
            if r.state /= IDLE then
                v.state := IDLE;
                v.busy := '0';
                v.f2stall := '0';
                if r.fp_rc = '1' then
                    v.cr_result := v.fpscr(FPSCR_FX downto FPSCR_OX);
                end if;
                v.sp_result := r.single_prec;
                v.res_int := r.int_result or r.integer_op;
                v.illegal := illegal;
                v.nsnan_result := r.quieten_nan;
                v.res_sign := rsign;
                if r.integer_op = '1' then
                    v.cr_mask := num_to_fxm(0);
                elsif r.is_cmp = '0' then
                    v.cr_mask := num_to_fxm(1);
                elsif is_X(insn_bf(r.insn)) then
		    v.cr_mask := (others => 'X');
		else
                    v.cr_mask := num_to_fxm(to_integer(unsigned(insn_bf(r.insn))));
                end if;
                v.writing_cr := r.is_cmp or r.rc;
                v.write_reg := r.dest_fpr;
                v.complete_tag := r.instr_tag;
            end if;
            if e_in.stall = '0' then
                v.complete := not v.illegal;
                v.do_intr := (v.fpscr(FPSCR_FEX) and r.fe_mode) or v.illegal;
            end if;
            -- N.B. We rely on execute1 to prevent any new instruction
            -- coming in while e_in.stall = 1, without us needing to
            -- have busy asserted.
        else
            if r.state /= IDLE and e_in.stall = '0' then
                v.f2stall := '1';
            end if;
        end if;

        -- This mustn't depend on any fields of r that are modified in IDLE state.
        if r.res_int = '1' then
            fp_result <= r.r;
        else
            fp_result <= pack_dp(r.res_sign, r.result_class, r.result_exp, r.r,
                                 r.sp_result, r.nsnan_result);
        end if;

        rin <= v;
    end process;

end architecture behaviour;
