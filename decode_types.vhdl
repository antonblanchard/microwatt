library ieee;
use ieee.std_logic_1164.all;

package decode_types is
    type insn_type_t is (OP_ILLEGAL, OP_NOP, OP_ADD,
			 OP_AND, OP_ATTN, OP_B, OP_BC, OP_BCREG,
			 OP_BCD, OP_BPERM, OP_CMP, OP_CMPB, OP_CMPEQB, OP_CMPRB,
			 OP_CNTZ, OP_CROP,
			 OP_DARN, OP_DCBF, OP_DCBST, OP_DCBT, OP_DCBTST,
			 OP_DCBZ, OP_ICBI, OP_ICBT,
                         OP_FP_CMP, OP_FP_ARITH, OP_FP_MOVE, OP_FP_MISC,
                         OP_DIV, OP_DIVE, OP_MOD,
                         OP_EXTS, OP_EXTSWSLI,
                         OP_ISEL, OP_ISYNC,
			 OP_LOAD, OP_STORE,
			 OP_MCRXRX, OP_MFCR, OP_MFMSR, OP_MFSPR,
			 OP_MTCRF, OP_MTMSRD, OP_MTSPR, OP_MUL_L64,
			 OP_MUL_H64, OP_MUL_H32, OP_OR,
			 OP_POPCNT, OP_PRTY, OP_RFID,
			 OP_RLC, OP_RLCL, OP_RLCR, OP_SC, OP_SETB,
			 OP_SHL, OP_SHR,
			 OP_SYNC, OP_TLBIE, OP_TRAP,
			 OP_XOR,
                         OP_ADDG6S,
                         OP_FETCH_FAILED
			 );

    type insn_code is (
        INSN_illegal,
        INSN_fetch_fail,
        INSN_add,
        INSN_addc,
        INSN_adde,
        INSN_addex,
        INSN_addg6s,
        INSN_addi,
        INSN_addic,
        INSN_addic_dot,
        INSN_addis,
        INSN_addme,
        INSN_addpcis,
        INSN_addze,
        INSN_and,
        INSN_andc,
        INSN_andi_dot,
        INSN_andis_dot,
        INSN_attn,
        INSN_b,
        INSN_bc,
        INSN_bcctr,
        INSN_bclr,
        INSN_bctar,
        INSN_bperm,
        INSN_cbcdtd,
        INSN_cdtbcd,
        INSN_cmp,
        INSN_cmpb,
        INSN_cmpeqb,
        INSN_cmpi,
        INSN_cmpl,
        INSN_cmpli,
        INSN_cmprb,
        INSN_cntlzd,
        INSN_cntlzw,
        INSN_cnttzd,
        INSN_cnttzw,
        INSN_crand,
        INSN_crandc,
        INSN_creqv,
        INSN_crnand,
        INSN_crnor,
        INSN_cror,
        INSN_crorc,
        INSN_crxor,
        INSN_darn,
        INSN_dcbf,
        INSN_dcbst,
        INSN_dcbt,
        INSN_dcbtst,
        INSN_dcbz,
        INSN_divd,
        INSN_divde,
        INSN_divdeu,
        INSN_divdu,
        INSN_divw,
        INSN_divwe,
        INSN_divweu,
        INSN_divwu,
        INSN_eieio,
        INSN_eqv,
        INSN_extsb,
        INSN_extsh,
        INSN_extsw,
        INSN_extswsli,
        INSN_fabs,
        INSN_fadd,
        INSN_fadds,
        INSN_fcfid,
        INSN_fcfids,
        INSN_fcfidu,
        INSN_fcfidus,
        INSN_fcmpo,
        INSN_fcmpu,
        INSN_fcpsgn,
        INSN_fctid,
        INSN_fctidu,
        INSN_fctiduz,
        INSN_fctidz,
        INSN_fctiw,
        INSN_fctiwu,
        INSN_fctiwuz,
        INSN_fctiwz,
        INSN_fdiv,
        INSN_fdivs,
        INSN_fmadd,
        INSN_fmadds,
        INSN_fmr,
        INSN_fmrgew,
        INSN_fmrgow,
        INSN_fmsub,
        INSN_fmsubs,
        INSN_fmul,
        INSN_fmuls,
        INSN_fnabs,
        INSN_fneg,
        INSN_fnmadd,
        INSN_fnmadds,
        INSN_fnmsub,
        INSN_fnmsubs,
        INSN_fre,
        INSN_fres,
        INSN_frim,
        INSN_frin,
        INSN_frip,
        INSN_friz,
        INSN_frsp,
        INSN_frsqrte,
        INSN_frsqrtes,
        INSN_fsel,
        INSN_fsqrt,
        INSN_fsqrts,
        INSN_fsub,
        INSN_fsubs,
        INSN_ftdiv,
        INSN_ftsqrt,
        INSN_icbi,
        INSN_icbt,
        INSN_isel,
        INSN_isync,
        INSN_lbarx,
        INSN_lbz,
        INSN_lbzcix,
        INSN_lbzu,
        INSN_lbzux,
        INSN_lbzx,
        INSN_ld,
        INSN_ldarx,
        INSN_ldbrx,
        INSN_ldcix,
        INSN_ldu,
        INSN_ldux,
        INSN_ldx,
        INSN_lfd,
        INSN_lfdu,
        INSN_lfdux,
        INSN_lfdx,
        INSN_lfiwax,
        INSN_lfiwzx,
        INSN_lfs,
        INSN_lfsu,
        INSN_lfsux,
        INSN_lfsx,
        INSN_lha,
        INSN_lharx,
        INSN_lhau,
        INSN_lhaux,
        INSN_lhax,
        INSN_lhbrx,
        INSN_lhz,
        INSN_lhzcix,
        INSN_lhzu,
        INSN_lhzux,
        INSN_lhzx,
        INSN_lwa,
        INSN_lwarx,
        INSN_lwaux,
        INSN_lwax,
        INSN_lwbrx,
        INSN_lwz,
        INSN_lwzcix,
        INSN_lwzu,
        INSN_lwzux,
        INSN_lwzx,
        INSN_maddhd,
        INSN_maddhdu,
        INSN_maddld,
        INSN_mcrf,
        INSN_mcrfs,
        INSN_mcrxrx,
        INSN_mfcr,
        INSN_mffs,
        INSN_mfmsr,
        INSN_mfspr,
        INSN_modsd,
        INSN_modsw,
        INSN_modud,
        INSN_moduw,
        INSN_mtcrf,
        INSN_mtfsb,
        INSN_mtfsf,
        INSN_mtfsfi,
        INSN_mtmsr,
        INSN_mtmsrd,
        INSN_mtspr,
        INSN_mulhd,
        INSN_mulhdu,
        INSN_mulhw,
        INSN_mulhwu,
        INSN_mulld,
        INSN_mulli,
        INSN_mullw,
        INSN_nand,
        INSN_neg,
        INSN_nop,
        INSN_nor,
        INSN_or,
        INSN_orc,
        INSN_ori,
        INSN_oris,
        INSN_popcntb,
        INSN_popcntd,
        INSN_popcntw,
        INSN_prtyd,
        INSN_prtyw,
        INSN_rfid,
        INSN_rldcl,
        INSN_rldcr,
        INSN_rldic,
        INSN_rldicl,
        INSN_rldicr,
        INSN_rldimi,
        INSN_rlwimi,
        INSN_rlwinm,
        INSN_rlwnm,
        INSN_sc,
        INSN_setb,
        INSN_slbia,
        INSN_sld,
        INSN_slw,
        INSN_srad,
        INSN_sradi,
        INSN_sraw,
        INSN_srawi,
        INSN_srd,
        INSN_srw,
        INSN_stb,
        INSN_stbcix,
        INSN_stbcx,
        INSN_stbu,
        INSN_stbux,
        INSN_stbx,
        INSN_std,
        INSN_stdbrx,
        INSN_stdcix,
        INSN_stdcx,
        INSN_stdu,
        INSN_stdux,
        INSN_stdx,
        INSN_stfd,
        INSN_stfdu,
        INSN_stfdux,
        INSN_stfdx,
        INSN_stfiwx,
        INSN_stfs,
        INSN_stfsu,
        INSN_stfsux,
        INSN_stfsx,
        INSN_sth,
        INSN_sthbrx,
        INSN_sthcix,
        INSN_sthcx,
        INSN_sthu,
        INSN_sthux,
        INSN_sthx,
        INSN_stw,
        INSN_stwbrx,
        INSN_stwcix,
        INSN_stwcx,
        INSN_stwu,
        INSN_stwux,
        INSN_stwx,
        INSN_subf,
        INSN_subfc,
        INSN_subfe,
        INSN_subfic,
        INSN_subfme,
        INSN_subfze,
        INSN_sync,
        INSN_td,
        INSN_tdi,
        INSN_tlbie,
        INSN_tlbiel,
        INSN_tlbsync,
        INSN_tw,
        INSN_twi,
        INSN_wait,
        INSN_xor,
        INSN_xori,
        INSN_xoris
        );

    type input_reg_a_t is (NONE, RA, RA_OR_ZERO, CIA, FRA);
    type input_reg_b_t is (NONE, RB, CONST_UI, CONST_SI, CONST_SI_HI, CONST_UI_HI, CONST_LI, CONST_BD,
                           CONST_DXHI4, CONST_DS, CONST_DQ, CONST_M1, CONST_SH, CONST_SH32, FRB);
    type input_reg_c_t is (NONE, RS, RCR, FRC, FRS);
    type output_reg_a_t is (NONE, RT, RA, FRT);
    type rc_t is (NONE, ONE, RC);
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

    type unit_t is (NONE, ALU, LDST, FPU);
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
    constant decode_rom_init : decode_rom_t := (unit => NONE, facility => NONE,
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
