library ieee;
use ieee.std_logic_1164.all;

package decode_types is
	type ppc_insn_t is (PPC_ILLEGAL, PPC_ADD, PPC_ADDC, PPC_ADDE,
		PPC_ADDEX, PPC_ADDI, PPC_ADDIC, PPC_ADDIC_RC, PPC_ADDIS,
		PPC_ADDME, PPC_ADDPCIS, PPC_ADDZE, PPC_AND, PPC_ANDC,
		PPC_ANDI_RC, PPC_ANDIS_RC, PPC_ATTN, PPC_B, PPC_BC,
		PPC_BCCTR, PPC_BCLR, PPC_BCTAR, PPC_BPERM,
		PPC_CMP, PPC_CMPB, PPC_CMPEQB, PPC_CMPI, PPC_CMPL, PPC_CMPLI,
		PPC_CMPRB, PPC_CNTLZD, PPC_CNTLZW, PPC_CNTTZD, PPC_CNTTZW,
		PPC_CRAND, PPC_CRANDC, PPC_CREQV, PPC_CRNAND, PPC_CRNOR,
		PPC_CROR, PPC_CRORC, PPC_CRXOR, PPC_DARN, PPC_DCBF, PPC_DCBST,
		PPC_DCBT, PPC_DCBTST, PPC_DCBZ, PPC_DIV,
		PPC_EQV, PPC_EXTSB, PPC_EXTSH, PPC_EXTSW,
		PPC_EXTSWSLI, PPC_ICBI, PPC_ICBT, PPC_ISEL, PPC_ISYNC,
		PPC_LBARX, PPC_LBZ, PPC_LBZU, PPC_LBZUX, PPC_LBZX, PPC_LD,
		PPC_LDARX, PPC_LDBRX, PPC_LDU, PPC_LDUX, PPC_LDX, PPC_LHA,
		PPC_LHARX, PPC_LHAU, PPC_LHAUX, PPC_LHAX, PPC_LHBRX, PPC_LHZ,
		PPC_LHZU, PPC_LHZUX, PPC_LHZX, PPC_LWA, PPC_LWARX, PPC_LWAUX,
		PPC_LWAX, PPC_LWBRX, PPC_LWZ, PPC_LWZU, PPC_LWZUX, PPC_LWZX,
		PPC_MADDHD, PPC_MADDHDU, PPC_MADDLD, PPC_MCRF, PPC_MCRXR,
		PPC_MCRXRX, PPC_MFCR, PPC_MFOCRF, PPC_MFSPR, PPC_MFTB,
		PPC_MOD, PPC_MTCRF,
		PPC_MFCTR, PPC_MTCTR, PPC_MFLR, PPC_MTLR, PPC_MTOCRF,
		PPC_MTSPR, PPC_MULHD, PPC_MULHDU, PPC_MULHW, PPC_MULHWU,
		PPC_MULLD, PPC_MULLI, PPC_MULLW, PPC_NAND, PPC_NEG, PPC_NOR, PPC_NOP,
		PPC_OR, PPC_ORC, PPC_ORI, PPC_ORIS, PPC_POPCNTB, PPC_POPCNTD,
		PPC_POPCNTW, PPC_PRTYD, PPC_PRTYW, PPC_RLDCL, PPC_RLDCR,
		PPC_RLDIC, PPC_RLDICL, PPC_RLDICR, PPC_RLDIMI, PPC_RLWIMI,
		PPC_RLWINM, PPC_RLWNM, PPC_SETB, PPC_SLD, PPC_SLW, PPC_SRAD,
		PPC_SRADI, PPC_SRAW, PPC_SRAWI, PPC_SRD, PPC_SRW, PPC_STB,
		PPC_STBCX, PPC_STBU, PPC_STBUX, PPC_STBX, PPC_STD, PPC_STDBRX,
		PPC_STDCX, PPC_STDU, PPC_STDUX, PPC_STDX, PPC_STH, PPC_STHBRX,
		PPC_STHCX, PPC_STHU, PPC_STHUX, PPC_STHX, PPC_STW, PPC_STWBRX,
		PPC_STWCX, PPC_STWU, PPC_STWUX, PPC_STWX, PPC_SUBF, PPC_SUBFC,
		PPC_SUBFE, PPC_SUBFIC, PPC_SUBFME, PPC_SUBFZE, PPC_SYNC, PPC_TD,
		PPC_TDI, PPC_TW, PPC_TWI, PPC_XOR, PPC_XORI, PPC_XORIS,
		PPC_SIM_CONFIG);

	type insn_type_t is (OP_ILLEGAL, OP_NOP, OP_ADD, OP_ADDE, OP_ADDEX, OP_ADDME,
		OP_ADDPCIS, OP_AND, OP_ANDC, OP_ATTN, OP_B, OP_BC,
		OP_BCCTR, OP_BCLR, OP_BCTAR, OP_BPERM, OP_CMP,
		OP_CMPB, OP_CMPEQB, OP_CMPL, OP_CMPRB,
		OP_CNTLZD, OP_CNTLZW, OP_CNTTZD, OP_CNTTZW, OP_CRAND,
		OP_CRANDC, OP_CREQV, OP_CRNAND, OP_CRNOR, OP_CROR, OP_CRORC,
		OP_CRXOR, OP_DARN, OP_DCBF, OP_DCBST, OP_DCBT, OP_DCBTST,
		OP_DCBZ, OP_DIV, OP_EQV, OP_EXTSB, OP_EXTSH,
		OP_EXTSW, OP_EXTSWSLI, OP_ICBI, OP_ICBT, OP_ISEL, OP_ISYNC,
		OP_LOAD, OP_STORE, OP_MADDHD, OP_MADDHDU, OP_MADDLD, OP_MCRF,
		OP_MCRXR, OP_MCRXRX, OP_MFCR, OP_MFOCRF, OP_MFCTR, OP_MFLR,
		OP_MFTB, OP_MFSPR, OP_MOD,
		OP_MTCRF, OP_MTOCRF, OP_MTCTR, OP_MTLR, OP_MTSPR, OP_MUL_L64,
		OP_MUL_H64, OP_MUL_H32, OP_NAND, OP_NEG, OP_NOR, OP_OR,
		OP_ORC, OP_POPCNTB, OP_POPCNTD, OP_POPCNTW, OP_PRTYD,
		OP_PRTYW, OP_RLDCL, OP_RLDCR, OP_RLDIC, OP_RLDICL, OP_RLDICR,
		OP_RLDIMI, OP_RLWIMI, OP_RLWINM, OP_RLWNM, OP_SETB, OP_SLD,
		OP_SLW, OP_SRAD, OP_SRADI, OP_SRAW, OP_SRAWI, OP_SRD, OP_SRW,
		OP_SUBF, OP_SUBFE, OP_SUBFME, OP_SYNC, OP_TD, OP_TDI, OP_TW,
		OP_TWI, OP_XOR, OP_SIM_CONFIG);

	type input_reg_a_t is (NONE, RA, RA_OR_ZERO, RS);
	type input_reg_b_t is (NONE, RB, RS, CONST_UI, CONST_SI, CONST_SI_HI, CONST_UI_HI, CONST_LI, CONST_BD, CONST_DS);
	type input_reg_c_t is (NONE, RS);
	type output_reg_a_t is (NONE, RT, RA);
	type constant_a_t is (NONE, SH, SH32, FXM, BO, BF, TOO, BC);
	type constant_b_t is (NONE, MB, ME, MB32, BI, L, BFA);
	type constant_c_t is (NONE, ME32, BH);
	type rc_t is (NONE, ONE, RC);

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

	type unit_t is (NONE, ALU, LDST, MUL, DIV);
	type length_t is (NONE, is1B, is2B, is4B, is8B);

	type decode_rom_t is record
		unit         : unit_t;
		insn_type    : insn_type_t;
		input_reg_a  : input_reg_a_t;
		input_reg_b  : input_reg_b_t;
		input_reg_c  : input_reg_c_t;
		output_reg_a : output_reg_a_t;

		const_a      : constant_a_t;
		const_b      : constant_b_t;
		const_c      : constant_c_t;

		input_cr     : std_ulogic;
		output_cr    : std_ulogic;

		input_carry  : std_ulogic;
		output_carry : std_ulogic;

		-- load/store signals
		length       : length_t;
		byte_reverse : std_ulogic;
		sign_extend  : std_ulogic;
		update       : std_ulogic;
		reserve      : std_ulogic;

		-- multiplier signals
		mul_32bit     : std_ulogic;
		mul_signed    : std_ulogic;

		rc           : rc_t;
		lr           : std_ulogic;

		sgl_pipe     : std_ulogic;
	end record;
	constant decode_rom_init : decode_rom_t := (unit => NONE,
		insn_type => OP_ILLEGAL, input_reg_a => NONE,
		input_reg_b => NONE, input_reg_c => NONE,
		output_reg_a => NONE, const_a => NONE, const_b => NONE,
		const_c => NONE, input_cr => '0', output_cr => '0',
		input_carry => '0', output_carry => '0',
		length => NONE, byte_reverse => '0', sign_extend => '0',
		update => '0', reserve => '0', mul_32bit => '0',
		mul_signed => '0', rc => NONE, lr => '0', sgl_pipe => '0');

end decode_types;

package body decode_types is
end decode_types;
