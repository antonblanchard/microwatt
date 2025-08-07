library ieee;
use ieee.std_logic_1164.all;

package decode_types is
    type insn_type_t is (OP_ILLEGAL, OP_NOP, OP_ADD,
			 OP_ATTN, OP_B, OP_BC, OP_BCREG,
			 OP_BPERM, OP_BSORT, OP_CMP,
                         OP_COMPUTE,
			 OP_COUNTB,
			 OP_DARN, OP_DCBF, OP_DCBST, OP_DCBZ,
                         OP_ICBI, OP_ICBT,
                         OP_FP_CMP, OP_FP_ARITH, OP_FP_MOVE, OP_FP_MISC,
                         OP_DIV, OP_DIVE, OP_MOD,
                         OP_ISYNC,
			 OP_LOAD, OP_STORE,
			 OP_MCRXRX, OP_MFMSR, OP_MFSPR,
                         OP_MSG,
			 OP_MTCRF, OP_MTMSRD, OP_MTSPR, OP_MUL_L64,
			 OP_MUL_H64, OP_MUL_H32,
			 OP_RFID,
			 OP_SC,
			 OP_SYNC, OP_TLBIE, OP_TRAP,
                         OP_WAIT,
                         OP_FETCH_FAILED
			 );

    -- The following list is ordered in such a way that we can know some
    -- things about which registers are accessed by an instruction by its place
    -- in the list.  In other words we can decide whether an instruction
    -- accesses FPRs and whether it has an RB operand by doing simple
    -- comparisons of the insn_code for the instruction with a few constants.
    type insn_code is (
        -- The following instructions don't have an RB operand or access FPRs
        INSN_illegal, -- 0
        INSN_fetch_fail,
        INSN_prefix,
        INSN_pnop,
        INSN_addic,
        INSN_addic_dot,
        INSN_addis,
        INSN_addme,
        INSN_addpcis,
        INSN_addze,
        INSN_andi_dot, -- 10
        INSN_andis_dot,
        INSN_attn,
        INSN_brel,
        INSN_babs,
        INSN_bcrel,
        INSN_bcabs,
        INSN_bcctr,
        INSN_bclr,
        INSN_bctar,
        INSN_brh, -- 20
        INSN_brw,
        INSN_brd,
        INSN_cbcdtd,
        INSN_cdtbcd,
        INSN_cmpi,
        INSN_cmpli,
        INSN_cntlzw,
        INSN_cntlzd,
        INSN_cnttzw,
        INSN_cnttzd, -- 30
        INSN_crand,
        INSN_crandc,
        INSN_creqv,
        INSN_crnand,
        INSN_crnor,
        INSN_cror,
        INSN_crorc,
        INSN_crxor,
        INSN_darn,
        INSN_eieio, -- 40
        INSN_extsb,
        INSN_extsh,
        INSN_extsw,
        INSN_extswsli,
        INSN_isync,
        INSN_lbzu,
        INSN_ld,
        INSN_ldu,
        INSN_lhau,
        INSN_lwa, -- 50
        INSN_lwzu,
        INSN_mcrf,
        INSN_mcrxrx,
        INSN_mfcr,
        INSN_mfmsr,
        INSN_mfspr,
        INSN_msgsync,
        INSN_mtcrf,
        INSN_mtmsr,
        INSN_mtmsrd, -- 60
        INSN_mtspr,
        INSN_mulli,
        INSN_neg,
        INSN_nop,
        INSN_ori,
        INSN_oris,
        INSN_popcntb,
        INSN_popcntw,
        INSN_popcntd,
        INSN_prtyw, -- 70
        INSN_prtyd,
        INSN_rfid,
        INSN_rfscv,
        INSN_rldic,
        INSN_rldicl,
        INSN_rldicr,
        INSN_rldimi,
        INSN_rlwimi,
        INSN_rlwinm,
        INSN_rnop, -- 80
        INSN_sc,
        INSN_setb,
        INSN_slbia,
        INSN_sradi,
        INSN_srawi,
        INSN_stbu,
        INSN_std,
        INSN_stdu,
        INSN_sthu,
        INSN_stq, -- 90
        INSN_stwu,
        INSN_subfic,
        INSN_subfme,
        INSN_subfze,
        INSN_sync,
        INSN_tdi,
        INSN_tlbsync,
        INSN_twi,
        INSN_wait,
        INSN_xori, -- 100
        INSN_xoris,

        -- Non-prefixed instructions that have a MLS:D prefixed form and
        -- their corresponding prefixed instructions.
        -- The non-prefixed versions have even indexes so that we can
        -- convert them to the prefixed version by setting bit 0
        INSN_addi, -- 102
        INSN_paddi,
        INSN_lbz,
        INSN_plbz,
        INSN_lha,
        INSN_plha,
        INSN_lhz,
        INSN_plhz,
        INSN_lwz, -- 110
        INSN_plwz,
        INSN_stb,
        INSN_pstb,
        INSN_sth,
        INSN_psth,
        INSN_stw,
        INSN_pstw,

        -- Slots for non-prefixed opcodes that are 8LS:D when prefixed
        INSN_lhzu,
        INSN_plwa,
        INSN_lq, -- 120
        INSN_plq,
        INSN_op57,
        INSN_pld,
        INSN_op60,
        INSN_pstq,
        INSN_op61,
        INSN_pstd,

        -- pad to 128 to simplify comparison logic

        -- The following instructions have an RB operand but don't access FPRs
        INSN_add,
        INSN_addc,
        INSN_adde, -- 130
        INSN_addex,
        INSN_addg6s,
        INSN_and,
        INSN_andc,
        INSN_bperm,
        INSN_cfuged,
        INSN_cmp,
        INSN_cmpb,
        INSN_cmpeqb,
        INSN_cmpl, -- 140
        INSN_cmprb,
        INSN_dcbf,
        INSN_dcbst,
        INSN_dcbt,
        INSN_dcbtst,
        INSN_dcbz,
        INSN_divd,
        INSN_divdu,
        INSN_divde,
        INSN_divdeu, -- 150
        INSN_divw,
        INSN_divwu,
        INSN_divwe,
        INSN_divweu,
        INSN_eqv,
        INSN_hashchk,
        INSN_hashchkp,
        INSN_hashst,
        INSN_hashstp,
        INSN_icbi, -- 160
        INSN_icbt,
        INSN_isel,
        INSN_lbarx,
        INSN_lbzcix,
        INSN_lbzux,
        INSN_lbzx,
        INSN_ldarx,
        INSN_ldbrx,
        INSN_ldcix,
        INSN_ldx, -- 170
        INSN_ldux,
        INSN_lharx,
        INSN_lhax,
        INSN_lhaux,
        INSN_lhbrx,
        INSN_lhzcix,
        INSN_lhzx,
        INSN_lhzux,
        INSN_lqarx,
        INSN_lwarx, -- 180
        INSN_lwax,
        INSN_lwaux,
        INSN_lwbrx,
        INSN_lwzcix,
        INSN_lwzx,
        INSN_lwzux,
        INSN_modsd,
        INSN_modsw,
        INSN_moduw,
        INSN_modud, -- 190
        INSN_msgclr,
        INSN_msgsnd,
        INSN_mulhw,
        INSN_mulhwu,
        INSN_mulhd,
        INSN_mulhdu,
        INSN_mullw,
        INSN_mulld,
        INSN_nand,
        INSN_nor, -- 200
        INSN_or,
        INSN_orc,
        INSN_pdepd,
        INSN_pextd,
        INSN_rldcl,
        INSN_rldcr,
        INSN_rlwnm,
        INSN_slw,
        INSN_sld,
        INSN_sraw, -- 210
        INSN_srad,
        INSN_srw,
        INSN_srd,
        INSN_stbcix,
        INSN_stbcx,
        INSN_stbx,
        INSN_stbux,
        INSN_stdbrx,
        INSN_stdcix,
        INSN_stdcx, -- 220
        INSN_stdx,
        INSN_stdux,
        INSN_sthbrx,
        INSN_sthcix,
        INSN_sthcx,
        INSN_sthx,
        INSN_sthux,
        INSN_stqcx,
        INSN_stwbrx,
        INSN_stwcix, -- 230
        INSN_stwcx,
        INSN_stwx,
        INSN_stwux,
        INSN_subf,
        INSN_subfc,
        INSN_subfe,
        INSN_td,
        INSN_tlbie,
        INSN_tlbiel,
        INSN_tw, -- 240
        INSN_xor,

        -- pad to 248 to simplify comparison logic
        INSN_242, INSN_243, INSN_244, INSN_245, INSN_246, INSN_247,

        -- The following instructions have a third input addressed by RC
        INSN_maddld,
        INSN_maddhd,
        INSN_maddhdu,

        -- pad to 256 to simplify comparison logic
        INSN_251,
        INSN_252, INSN_253, INSN_254, INSN_255,

        -- The following instructions access floating-point registers
        -- They have an FRS operand, but RA/RB are GPRs

        -- Non-prefixed floating-point loads and stores that have a MLS:D
        -- prefixed form, and their corresponding prefixed instructions.
        INSN_stfd, -- 256
        INSN_pstfd,
        INSN_stfs,
        INSN_pstfs,
        INSN_lfd, -- 260
        INSN_plfd,
        INSN_lfs,
        INSN_plfs,

        -- opcodes that can't have a prefix
        INSN_stfdu, -- 264
        INSN_stfsu,
        INSN_stfdux,
        INSN_stfdx,
        INSN_stfiwx,
        INSN_stfsux,
        INSN_stfsx, -- 270
        -- These ones don't actually have an FRS operand (rather an FRT destination)
        -- but are here so that all FP instructions are >= INST_first_frs.
        INSN_lfdu,
        INSN_lfsu,
        INSN_lfdx,
        INSN_lfdux,
        INSN_lfiwax,
        INSN_lfiwzx,
        INSN_lfsx,
        INSN_lfsux,
        -- These are here in order to keep the FP instructions together
        INSN_mcrfs,
        INSN_mtfsb, -- 280
        INSN_mtfsfi,
        INSN_282, -- padding
        INSN_283,
        INSN_284,
        INSN_285,
        INSN_286,
        INSN_287,

        -- The following instructions access FRA and/or FRB operands
        INSN_fabs, -- 288
        INSN_fadd,
        INSN_fadds, -- 290
        INSN_fcfid,
        INSN_fcfids,
        INSN_fcfidu,
        INSN_fcfidus,
        INSN_fcmpo,
        INSN_fcmpu,
        INSN_fcpsgn,
        INSN_fctid,
        INSN_fctidz,
        INSN_fctidu, -- 300
        INSN_fctiduz,
        INSN_fctiw,
        INSN_fctiwz,
        INSN_fctiwu,
        INSN_fctiwuz,
        INSN_fdiv,
        INSN_fdivs,
        INSN_fmr,
        INSN_fmrgew,
        INSN_fmrgow, -- 310
        INSN_fnabs,
        INSN_fneg,
        INSN_fre,
        INSN_fres,
        INSN_frim,
        INSN_frin,
        INSN_frip,
        INSN_friz,
        INSN_frsp,
        INSN_frsqrte, -- 320
        INSN_frsqrtes,
        INSN_fsqrt,
        INSN_fsqrts,
        INSN_fsub,
        INSN_fsubs,
        INSN_ftdiv,
        INSN_ftsqrt,
        INSN_mffs,
        INSN_mtfsf,

        -- pad to 336
        INSN_330, INSN_331, INSN_332, INSN_333, INSN_334, INSN_335,

        -- The following instructions access FRA, FRB (possibly) and FRC operands
        INSN_fmul, -- 336
        INSN_fmuls,
        INSN_fmadd,
        INSN_fmadds,
        INSN_fmsub, -- 340
        INSN_fmsubs,
        INSN_fnmadd,
        INSN_fnmadds,
        INSN_fnmsub,
        INSN_fnmsubs,
        INSN_fsel
        );

    constant INSN_first_rb : insn_code := INSN_add;
    constant INSN_first_rc : insn_code := INSN_maddld;
    constant INSN_first_frs : insn_code := INSN_stfd;
    constant INSN_first_frab : insn_code := INSN_fabs;
    constant INSN_first_frabc : insn_code := INSN_fmul;
    constant INSN_first_mls : insn_code := INSN_addi;
    constant INSN_first_8ls : insn_code := INSN_lhzu;
    constant INSN_first_fp_mls : insn_code := INSN_stfd;
    constant INSN_first_fp_nonmls : insn_code := INSN_stfdu;

    type input_reg_a_t is (NONE, RA, RA_OR_ZERO, RA0_OR_CIA, CIA, FRA);
    type input_reg_b_t is (IMM, RB, FRB);
    type const_sel_t is   (NONE, CONST_UI, CONST_SI, CONST_SI_HI, CONST_UI_HI, CONST_LI, CONST_BD,
                           CONST_DXHI4, CONST_DS, CONST_DQ, CONST_M1, CONST_SH, CONST_SH32, CONST_PSI);
    type input_reg_c_t is (NONE, RS, RCR, FRC, FRS);
    type output_reg_a_t is (NONE, RT, RA, FRT);
    type rc_t is (NONE, ONE, RC, RCOE);
    type carry_in_t is (ZERO, CA, OV, ONE);

    constant SH_OFFSET : integer := 0;
    constant MB_OFFSET : integer := 1;
    constant ME_OFFSET : integer := 1;
    constant SH32_OFFSET : integer := 0;
    constant MB32_OFFSET : integer := 1;
    constant ME32_OFFSET : integer := 2;

    constant FXM_OFFSET : integer := 0;

    constant BO_OFFSET : integer := 0;
    constant BI_OFFSET : integer := 1;
    constant BH_OFFSET : integer := 2;

    constant BF_OFFSET : integer := 0;
    constant L_OFFSET  : integer := 1;

    constant TOO_OFFSET : integer := 0;

    type unit_t is (ALU, LDST, FPU);
    type facility_t is (NONE, FPU);
    type length_t is (NONE, is1B, is2B, is4B, is8B);

    type result_sel_t is (ADD, LOG, ROT, UN3, MCYC, SPR, UN6, MSC);
    subtype subresult_sel_t is std_ulogic_vector(2 downto 0);

    type repeat_t is (NONE,      -- instruction is not repeated
                      DUPD,      -- update-form load
                      DRSP,      -- double RS (RS, RS+1)
                      DRTP);     -- double RT (RT, RT+1, or RT+1, RT)

    type decode_rom_t is record
	unit         : unit_t;
        facility     : facility_t;
	insn_type    : insn_type_t;
	input_reg_a  : input_reg_a_t;
	input_reg_b  : input_reg_b_t;
        const_sel    : const_sel_t;
	input_reg_c  : input_reg_c_t;
	output_reg_a : output_reg_a_t;

        -- Result multiplexor control
        result       : result_sel_t;
        subresult    : subresult_sel_t;

	input_cr     : std_ulogic;
	output_cr    : std_ulogic;

	invert_a     : std_ulogic;
	invert_out   : std_ulogic;
	input_carry  : carry_in_t;
	output_carry : std_ulogic;

	-- load/store signals
	length       : length_t;
	byte_reverse : std_ulogic;
	sign_extend  : std_ulogic;
	update       : std_ulogic;
	reserve      : std_ulogic;

	-- multiplier and ALU signals
	is_32bit     : std_ulogic;
	is_signed    : std_ulogic;

	rc           : rc_t;
	lr           : std_ulogic;

        privileged   : std_ulogic;
	sgl_pipe     : std_ulogic;
        repeat       : repeat_t;
    end record;
    constant decode_rom_init : decode_rom_t := (unit => ALU, facility => NONE,
						insn_type => OP_ILLEGAL, input_reg_a => NONE,
						input_reg_b => IMM, const_sel => NONE, input_reg_c => NONE,
						output_reg_a => NONE, result => ADD, subresult => "000",
                                                input_cr => '0', output_cr => '0',
						invert_a => '0', invert_out => '0', input_carry => ZERO, output_carry => '0',
						length => NONE, byte_reverse => '0', sign_extend => '0',
						update => '0', reserve => '0', is_32bit => '0',
						is_signed => '0', rc => NONE, lr => '0',
                                                privileged => '0', sgl_pipe => '0', repeat => NONE);

    -- This function maps from insn_code values to primary opcode.
    -- With this, we don't have to store the primary opcode of each instruction
    -- in the icache if we are storing its insn_code.
    function recode_primary_opcode(icode: insn_code) return std_ulogic_vector;

end decode_types;

package body decode_types is

    function recode_primary_opcode(icode: insn_code) return std_ulogic_vector is
    begin
        case icode is
            when INSN_addic     => return "001100";
            when INSN_addic_dot => return "001101";
            when INSN_addi      => return "001110";
            when INSN_addis     => return "001111";
            when INSN_addpcis   => return "010011";
            when INSN_andi_dot  => return "011100";
            when INSN_andis_dot => return "011101";
            when INSN_attn      => return "000000";
            when INSN_brel      => return "010010";
            when INSN_babs      => return "010010";
            when INSN_bcrel     => return "010000";
            when INSN_bcabs     => return "010000";
            when INSN_brh       => return "011111";
            when INSN_brw       => return "011111";
            when INSN_brd       => return "011111";
            when INSN_cmpi      => return "001011";
            when INSN_cmpli     => return "001010";
            when INSN_lbz       => return "100010";
            when INSN_lbzu      => return "100011";
            when INSN_lfd       => return "110010";
            when INSN_lfdu      => return "110011";
            when INSN_lfs       => return "110000";
            when INSN_lfsu      => return "110001";
            when INSN_lha       => return "101010";
            when INSN_lhau      => return "101011";
            when INSN_lhz       => return "101000";
            when INSN_lhzu      => return "101001";
            when INSN_lq        => return "111000";
            when INSN_lwz       => return "100000";
            when INSN_lwzu      => return "100001";
            when INSN_mulli     => return "000111";
            when INSN_nop       => return "011000";
            when INSN_ori       => return "011000";
            when INSN_oris      => return "011001";
            when INSN_rlwimi    => return "010100";
            when INSN_rlwinm    => return "010101";
            when INSN_rlwnm     => return "010111";
            when INSN_sc        => return "010001";
            when INSN_stb       => return "100110";
            when INSN_stbu      => return "100111";
            when INSN_stfd      => return "110110";
            when INSN_stfdu     => return "110111";
            when INSN_stfs      => return "110100";
            when INSN_stfsu     => return "110101";
            when INSN_sth       => return "101100";
            when INSN_sthu      => return "101101";
            when INSN_stw       => return "100100";
            when INSN_stq       => return "111110";
            when INSN_stwu      => return "100101";
            when INSN_subfic    => return "001000";
            when INSN_tdi       => return "000010";
            when INSN_twi       => return "000011";
            when INSN_xori      => return "011010";
            when INSN_xoris     => return "011011";
            when INSN_maddhd    => return "000100";
            when INSN_maddhdu   => return "000100";
            when INSN_maddld    => return "000100";
            when INSN_rldic     => return "011110";
            when INSN_rldicl    => return "011110";
            when INSN_rldicr    => return "011110";
            when INSN_rldimi    => return "011110";
            when INSN_rldcl     => return "011110";
            when INSN_rldcr     => return "011110";
            when INSN_ld        => return "111010";
            when INSN_ldu       => return "111010";
            when INSN_lwa       => return "111010";
            when INSN_fdivs     => return "111011";
            when INSN_fsubs     => return "111011";
            when INSN_fadds     => return "111011";
            when INSN_fsqrts    => return "111011";
            when INSN_fres      => return "111011";
            when INSN_fmuls     => return "111011";
            when INSN_frsqrtes  => return "111011";
            when INSN_fmsubs    => return "111011";
            when INSN_fmadds    => return "111011";
            when INSN_fnmsubs   => return "111011";
            when INSN_fnmadds   => return "111011";
            when INSN_std       => return "111110";
            when INSN_stdu      => return "111110";
            when INSN_fdiv      => return "111111";
            when INSN_fsub      => return "111111";
            when INSN_fadd      => return "111111";
            when INSN_fsqrt     => return "111111";
            when INSN_fsel      => return "111111";
            when INSN_fre       => return "111111";
            when INSN_fmul      => return "111111";
            when INSN_frsqrte   => return "111111";
            when INSN_fmsub     => return "111111";
            when INSN_fmadd     => return "111111";
            when INSN_fnmsub    => return "111111";
            when INSN_fnmadd    => return "111111";
            when INSN_prefix    => return "000001";
            when INSN_op57      => return "111001";
            when INSN_op60      => return "111100";
            when INSN_op61      => return "111101";
            when INSN_add       => return "011111";
            when INSN_addc      => return "011111";
            when INSN_adde      => return "011111";
            when INSN_addex     => return "011111";
            when INSN_addg6s    => return "011111";
            when INSN_addme     => return "011111";
            when INSN_addze     => return "011111";
            when INSN_and       => return "011111";
            when INSN_andc      => return "011111";
            when INSN_bperm     => return "011111";
            when INSN_cbcdtd    => return "011111";
            when INSN_cdtbcd    => return "011111";
            when INSN_cmp       => return "011111";
            when INSN_cmpb      => return "011111";
            when INSN_cmpeqb    => return "011111";
            when INSN_cmpl      => return "011111";
            when INSN_cmprb     => return "011111";
            when INSN_cntlzd    => return "011111";
            when INSN_cntlzw    => return "011111";
            when INSN_cnttzd    => return "011111";
            when INSN_cnttzw    => return "011111";
            when INSN_darn      => return "011111";
            when INSN_dcbf      => return "011111";
            when INSN_dcbst     => return "011111";
            when INSN_dcbt      => return "011111";
            when INSN_dcbtst    => return "011111";
            when INSN_dcbz      => return "011111";
            when INSN_divdeu    => return "011111";
            when INSN_divweu    => return "011111";
            when INSN_divde     => return "011111";
            when INSN_divwe     => return "011111";
            when INSN_divdu     => return "011111";
            when INSN_divwu     => return "011111";
            when INSN_divd      => return "011111";
            when INSN_divw      => return "011111";
            when INSN_hashchk   => return "011111";
            when INSN_hashchkp  => return "011111";
            when INSN_hashst    => return "011111";
            when INSN_hashstp   => return "011111";
            when INSN_eieio     => return "011111";
            when INSN_eqv       => return "011111";
            when INSN_extsb     => return "011111";
            when INSN_extsh     => return "011111";
            when INSN_extsw     => return "011111";
            when INSN_extswsli  => return "011111";
            when INSN_icbi      => return "011111";
            when INSN_icbt      => return "011111";
            when INSN_isel      => return "011111";
            when INSN_lbarx     => return "011111";
            when INSN_lbzcix    => return "011111";
            when INSN_lbzux     => return "011111";
            when INSN_lbzx      => return "011111";
            when INSN_ldarx     => return "011111";
            when INSN_ldbrx     => return "011111";
            when INSN_ldcix     => return "011111";
            when INSN_ldux      => return "011111";
            when INSN_ldx       => return "011111";
            when INSN_lfdx      => return "011111";
            when INSN_lfdux     => return "011111";
            when INSN_lfiwax    => return "011111";
            when INSN_lfiwzx    => return "011111";
            when INSN_lfsx      => return "011111";
            when INSN_lfsux     => return "011111";
            when INSN_lharx     => return "011111";
            when INSN_lhaux     => return "011111";
            when INSN_lhax      => return "011111";
            when INSN_lhbrx     => return "011111";
            when INSN_lhzcix    => return "011111";
            when INSN_lhzux     => return "011111";
            when INSN_lhzx      => return "011111";
            when INSN_lqarx     => return "011111";
            when INSN_lwarx     => return "011111";
            when INSN_lwaux     => return "011111";
            when INSN_lwax      => return "011111";
            when INSN_lwbrx     => return "011111";
            when INSN_lwzcix    => return "011111";
            when INSN_lwzux     => return "011111";
            when INSN_lwzx      => return "011111";
            when INSN_mcrxrx    => return "011111";
            when INSN_mfcr      => return "011111";
            when INSN_mfmsr     => return "011111";
            when INSN_mfspr     => return "011111";
            when INSN_modud     => return "011111";
            when INSN_moduw     => return "011111";
            when INSN_modsd     => return "011111";
            when INSN_modsw     => return "011111";
            when INSN_msgclr    => return "011111";
            when INSN_msgsnd    => return "011111";
            when INSN_msgsync   => return "011111";
            when INSN_mtcrf     => return "011111";
            when INSN_mtmsr     => return "011111";
            when INSN_mtmsrd    => return "011111";
            when INSN_mtspr     => return "011111";
            when INSN_mulhd     => return "011111";
            when INSN_mulhdu    => return "011111";
            when INSN_mulhw     => return "011111";
            when INSN_mulhwu    => return "011111";
            when INSN_mulld     => return "011111";
            when INSN_mullw     => return "011111";
            when INSN_nand      => return "011111";
            when INSN_neg       => return "011111";
            when INSN_rnop      => return "011111";
            when INSN_nor       => return "011111";
            when INSN_or        => return "011111";
            when INSN_orc       => return "011111";
            when INSN_popcntb   => return "011111";
            when INSN_popcntd   => return "011111";
            when INSN_popcntw   => return "011111";
            when INSN_prtyd     => return "011111";
            when INSN_prtyw     => return "011111";
            when INSN_setb      => return "011111";
            when INSN_slbia     => return "011111";
            when INSN_sld       => return "011111";
            when INSN_slw       => return "011111";
            when INSN_srad      => return "011111";
            when INSN_sradi     => return "011111";
            when INSN_sraw      => return "011111";
            when INSN_srawi     => return "011111";
            when INSN_srd       => return "011111";
            when INSN_srw       => return "011111";
            when INSN_stbcix    => return "011111";
            when INSN_stbcx     => return "011111";
            when INSN_stbux     => return "011111";
            when INSN_stbx      => return "011111";
            when INSN_stdbrx    => return "011111";
            when INSN_stdcix    => return "011111";
            when INSN_stdcx     => return "011111";
            when INSN_stdux     => return "011111";
            when INSN_stdx      => return "011111";
            when INSN_stfdx     => return "011111";
            when INSN_stfdux    => return "011111";
            when INSN_stfiwx    => return "011111";
            when INSN_stfsx     => return "011111";
            when INSN_stfsux    => return "011111";
            when INSN_sthbrx    => return "011111";
            when INSN_sthcix    => return "011111";
            when INSN_sthcx     => return "011111";
            when INSN_sthux     => return "011111";
            when INSN_sthx      => return "011111";
            when INSN_stqcx     => return "011111";
            when INSN_stwbrx    => return "011111";
            when INSN_stwcix    => return "011111";
            when INSN_stwcx     => return "011111";
            when INSN_stwux     => return "011111";
            when INSN_stwx      => return "011111";
            when INSN_subf      => return "011111";
            when INSN_subfc     => return "011111";
            when INSN_subfe     => return "011111";
            when INSN_subfme    => return "011111";
            when INSN_subfze    => return "011111";
            when INSN_sync      => return "011111";
            when INSN_td        => return "011111";
            when INSN_tw        => return "011111";
            when INSN_tlbie     => return "011111";
            when INSN_tlbiel    => return "011111";
            when INSN_tlbsync   => return "011111";
            when INSN_wait      => return "011111";
            when INSN_xor       => return "011111";
            when INSN_bcctr     => return "010011";
            when INSN_bclr      => return "010011";
            when INSN_bctar     => return "010011";
            when INSN_crand     => return "010011";
            when INSN_crandc    => return "010011";
            when INSN_creqv     => return "010011";
            when INSN_crnand    => return "010011";
            when INSN_crnor     => return "010011";
            when INSN_cror      => return "010011";
            when INSN_crorc     => return "010011";
            when INSN_crxor     => return "010011";
            when INSN_isync     => return "010011";
            when INSN_mcrf      => return "010011";
            when INSN_rfid      => return "010011";
            when INSN_fcfids    => return "111011";
            when INSN_fcfidus   => return "111011";
            when INSN_fcmpu     => return "111111";
            when INSN_fcmpo     => return "111111";
            when INSN_mcrfs     => return "111111";
            when INSN_ftdiv     => return "111111";
            when INSN_ftsqrt    => return "111111";
            when INSN_mtfsb     => return "111111";
            when INSN_mtfsfi    => return "111111";
            when INSN_fmrgow    => return "111111";
            when INSN_fmrgew    => return "111111";
            when INSN_mffs      => return "111111";
            when INSN_mtfsf     => return "111111";
            when INSN_fcpsgn    => return "111111";
            when INSN_fneg      => return "111111";
            when INSN_fmr       => return "111111";
            when INSN_fnabs     => return "111111";
            when INSN_fabs      => return "111111";
            when INSN_frin      => return "111111";
            when INSN_friz      => return "111111";
            when INSN_frip      => return "111111";
            when INSN_frim      => return "111111";
            when INSN_frsp      => return "111111";
            when INSN_fctiw     => return "111111";
            when INSN_fctiwu    => return "111111";
            when INSN_fctid     => return "111111";
            when INSN_fcfid     => return "111111";
            when INSN_fctidu    => return "111111";
            when INSN_fcfidu    => return "111111";
            when INSN_fctiwz    => return "111111";
            when INSN_fctiwuz   => return "111111";
            when INSN_fctidz    => return "111111";
            when INSN_fctiduz   => return "111111";
            when others         => return "XXXXXX";
        end case;
    end;

end decode_types;
