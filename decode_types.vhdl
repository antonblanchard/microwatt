library ieee;
use ieee.std_logic_1164.all;

package decode_types is
    type insn_type_t is (OP_ILLEGAL, OP_NOP, OP_ADD,
			 OP_ATTN, OP_B, OP_BC, OP_BCREG,
			 OP_BCD, OP_BPERM, OP_BREV,
                         OP_CMP, OP_CMPB, OP_CMPEQB, OP_CMPRB,
			 OP_CNTZ, OP_CROP,
			 OP_DARN, OP_DCBF, OP_DCBST, OP_DCBT, OP_DCBTST,
			 OP_DCBZ, OP_ICBI, OP_ICBT,
                         OP_FP_CMP, OP_FP_ARITH, OP_FP_MOVE, OP_FP_MISC,
                         OP_DIV, OP_DIVE, OP_MOD,
                         OP_EXTS, OP_EXTSWSLI,
                         OP_ISEL, OP_ISYNC,
                         OP_LOGIC,
			 OP_LOAD, OP_STORE,
			 OP_MCRXRX, OP_MFCR, OP_MFMSR, OP_MFSPR,
			 OP_MTCRF, OP_MTMSRD, OP_MTSPR, OP_MUL_L64,
			 OP_MUL_H64, OP_MUL_H32,
			 OP_POPCNT, OP_PRTY, OP_RFID,
			 OP_RLC, OP_RLCL, OP_RLCR, OP_SC, OP_SETB,
			 OP_SHL, OP_SHR,
			 OP_SYNC, OP_TLBIE, OP_TRAP,
			 OP_XOR,
                         OP_ADDG6S,
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
        INSN_b,
        INSN_bc,
        INSN_bcctr,
        INSN_bclr,
        INSN_bctar,
        INSN_brh,
        INSN_brw,
        INSN_brd, -- 20
        INSN_cbcdtd,
        INSN_cdtbcd,
        INSN_cmpi,
        INSN_cmpli,
        INSN_cntlzw,
        INSN_cntlzd,
        INSN_cnttzw,
        INSN_cnttzd,
        INSN_crand,
        INSN_crandc, -- 30
        INSN_creqv,
        INSN_crnand,
        INSN_crnor,
        INSN_cror,
        INSN_crorc,
        INSN_crxor,
        INSN_darn,
        INSN_eieio,
        INSN_extsb,
        INSN_extsh, -- 40
        INSN_extsw,
        INSN_extswsli,
        INSN_isync,
        INSN_lbzu,
        INSN_ld,
        INSN_ldu,
        INSN_lhau,
        INSN_lwa,
        INSN_lwzu,
        INSN_mcrf, -- 50
        INSN_mcrxrx,
        INSN_mfcr,
        INSN_mfmsr,
        INSN_mfspr,
        INSN_mtcrf,
        INSN_mtmsr,
        INSN_mtmsrd,
        INSN_mtspr,
        INSN_mulli,
        INSN_neg, -- 60
        INSN_nop,
        INSN_ori,
        INSN_oris,
        INSN_popcntb,
        INSN_popcntw,
        INSN_popcntd,
        INSN_prtyw,
        INSN_prtyd,
        INSN_rfid,
        INSN_rldic, -- 70
        INSN_rldicl,
        INSN_rldicr,
        INSN_rldimi,
        INSN_rlwimi,
        INSN_rlwinm,
        INSN_sc,
        INSN_setb,
        INSN_slbia,
        INSN_sradi,
        INSN_srawi, -- 80
        INSN_stbu,
        INSN_std,
        INSN_stdu,
        INSN_sthu,
        INSN_stwu,
        INSN_subfic,
        INSN_subfme,
        INSN_subfze,
        INSN_sync,
        INSN_tdi, -- 90
        INSN_tlbsync,
        INSN_twi,
        INSN_wait,
        INSN_xori,
        INSN_xoris,

        -- Non-prefixed instructions that have a MLS:D prefixed form and
        -- their corresponding prefixed instructions.
        -- The non-prefixed versions have even indexes so that we can
        -- convert them to the prefixed version by setting bit 0
        INSN_addi, -- 96
        INSN_paddi,
        INSN_lbz,
        INSN_plbz,
        INSN_lha, -- 100
        INSN_plha,
        INSN_lhz,
        INSN_plhz,
        INSN_lwz,
        INSN_plwz,
        INSN_stb,
        INSN_pstb,
        INSN_sth,
        INSN_psth,
        INSN_stw, -- 110
        INSN_pstw,

        -- Slots for non-prefixed opcodes that are 8LS:D when prefixed
        INSN_lhzu, -- 112
        INSN_plwa,
        INSN_op57,
        INSN_pld,
        INSN_op61,
        INSN_pstd,

        -- pad to 128 to simplify comparison logic
        INSN_076, INSN_077,
        INSN_078, INSN_079, INSN_07a, INSN_07b, INSN_07c, INSN_07d, INSN_07e, INSN_07f,

        -- The following instructions have an RB operand but don't access FPRs
        INSN_add,
        INSN_addc,
        INSN_adde, -- 130
        INSN_addex,
        INSN_addg6s,
        INSN_and,
        INSN_andc,
        INSN_bperm,
        INSN_cmp,
        INSN_cmpb,
        INSN_cmpeqb,
        INSN_cmpl,
        INSN_cmprb, -- 140
        INSN_dcbf,
        INSN_dcbst,
        INSN_dcbt,
        INSN_dcbtst,
        INSN_dcbz,
        INSN_divd,
        INSN_divdu,
        INSN_divde,
        INSN_divdeu,
        INSN_divw, -- 150
        INSN_divwu,
        INSN_divwe,
        INSN_divweu,
        INSN_eqv,
        INSN_icbi,
        INSN_icbt,
        INSN_isel,
        INSN_lbarx,
        INSN_lbzcix,
        INSN_lbzux, -- 160
        INSN_lbzx,
        INSN_ldarx,
        INSN_ldbrx,
        INSN_ldcix,
        INSN_ldx,
        INSN_ldux,
        INSN_lharx,
        INSN_lhax,
        INSN_lhaux,
        INSN_lhbrx, -- 170
        INSN_lhzcix,
        INSN_lhzx,
        INSN_lhzux,
        INSN_lwarx,
        INSN_lwax,
        INSN_lwaux,
        INSN_lwbrx,
        INSN_lwzcix,
        INSN_lwzx,
        INSN_lwzux, -- 180
        INSN_modsd,
        INSN_modsw,
        INSN_moduw,
        INSN_modud,
        INSN_mulhw,
        INSN_mulhwu,
        INSN_mulhd,
        INSN_mulhdu,
        INSN_mullw,
        INSN_mulld, -- 190
        INSN_nand,
        INSN_nor,
        INSN_or,
        INSN_orc,
        INSN_rldcl,
        INSN_rldcr,
        INSN_rlwnm,
        INSN_slw,
        INSN_sld,
        INSN_sraw, -- 200
        INSN_srad,
        INSN_srw,
        INSN_srd,
        INSN_stbcix,
        INSN_stbcx,
        INSN_stbx,
        INSN_stbux,
        INSN_stdbrx,
        INSN_stdcix,
        INSN_stdcx, -- 210
        INSN_stdx,
        INSN_stdux,
        INSN_sthbrx,
        INSN_sthcix,
        INSN_sthcx,
        INSN_sthx,
        INSN_sthux,
        INSN_stwbrx,
        INSN_stwcix,
        INSN_stwcx, -- 220
        INSN_stwx,
        INSN_stwux,
        INSN_subf,
        INSN_subfc,
        INSN_subfe,
        INSN_td,
        INSN_tlbie,
        INSN_tlbiel,
        INSN_tw,
        INSN_xor, -- 230

        -- pad to 232 to simplify comparison logic
        INSN_231,

        -- The following instructions have a third input addressed by RC
        INSN_maddld,
        INSN_maddhd,
        INSN_maddhdu,

        -- pad to 256 to simplify comparison logic
        INSN_235,
        INSN_236, INSN_237, INSN_238, INSN_239,
        INSN_240, INSN_241, INSN_242, INSN_243,
        INSN_244, INSN_245, INSN_246, INSN_247,
        INSN_248, INSN_249, INSN_250, INSN_251,
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
    type input_reg_b_t is (NONE, RB, CONST_UI, CONST_SI, CONST_SI_HI, CONST_UI_HI, CONST_LI, CONST_BD,
                           CONST_DXHI4, CONST_DS, CONST_DQ, CONST_M1, CONST_SH, CONST_SH32, CONST_PSI, FRB);
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

    type repeat_t is (NONE,      -- instruction is not repeated
                      DUPD);     -- update-form load

    type decode_rom_t is record
	unit         : unit_t;
        facility     : facility_t;
	insn_type    : insn_type_t;
	input_reg_a  : input_reg_a_t;
	input_reg_b  : input_reg_b_t;
	input_reg_c  : input_reg_c_t;
	output_reg_a : output_reg_a_t;

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

	sgl_pipe     : std_ulogic;
        repeat       : repeat_t;
    end record;
    constant decode_rom_init : decode_rom_t := (unit => ALU, facility => NONE,
						insn_type => OP_ILLEGAL, input_reg_a => NONE,
						input_reg_b => NONE, input_reg_c => NONE,
						output_reg_a => NONE, input_cr => '0', output_cr => '0',
						invert_a => '0', invert_out => '0', input_carry => ZERO, output_carry => '0',
						length => NONE, byte_reverse => '0', sign_extend => '0',
						update => '0', reserve => '0', is_32bit => '0',
						is_signed => '0', rc => NONE, lr => '0', sgl_pipe => '0', repeat => NONE);

end decode_types;

package body decode_types is
end decode_types;
