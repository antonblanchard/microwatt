library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;

entity decode1 is
	port (
		clk      : in std_ulogic;
		rst      : in std_ulogic;

		stall_in : in std_ulogic;
		flush_in : in std_ulogic;

		f_in     : in Fetch2ToDecode1Type;
		d_out    : out Decode1ToDecode2Type
	);
end entity decode1;

architecture behaviour of decode1 is
	signal r, rin : Decode1ToDecode2Type;

	type decode_rom_array_t is array(ppc_insn_t) of decode_rom_t;

	-- Note: reformat with column -t -o ' '
	constant decode_rom_array : decode_rom_array_t := (
		--                       unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                                      op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		PPC_ILLEGAL    =>       (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADD        =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADDC       =>       (ALU,    OP_ADDE,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADDE       =>       (ALU,    OP_ADDE,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_ADDEX
		PPC_ADDI       =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_ADDIC      =>       (ALU,    OP_ADDE,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_ADDIC_RC   =>       (ALU,    OP_ADDE,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'),
		PPC_ADDIS      =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI_HI, NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_ADDME
		--PPC_ADDPCIS
		PPC_ADDZE      =>       (ALU,    OP_ADDE,      RA,         NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_AND        =>       (ALU,    OP_AND,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ANDC       =>       (ALU,    OP_ANDC,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ANDI_RC    =>       (ALU,    OP_AND,       RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'),
		PPC_ANDIS_RC   =>       (ALU,    OP_AND,       RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'),
		PPC_ATTN       =>       (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_B          =>       (ALU,    OP_B,         NONE,       CONST_LI,    NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
		PPC_BC         =>       (ALU,    OP_BC,        NONE,       CONST_BD,    NONE, NONE, BO,   BI,   NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
		PPC_BCCTR      =>       (ALU,    OP_BCCTR,     NONE,       NONE,        NONE, NONE, BO,   BI,   BH,   '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
		PPC_BCLR       =>       (ALU,    OP_BCLR,      NONE,       NONE,        NONE, NONE, BO,   BI,   BH,   '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
		--PPC_BCTAR
		--PPC_BPERM
		PPC_CMP        =>       (ALU,    OP_CMP,       RA,         RB,          NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_CMPB       =>       (ALU,    OP_CMPB,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_CMPEQB
		PPC_CMPI       =>       (ALU,    OP_CMP,       RA,         CONST_SI,    NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_CMPL       =>       (ALU,    OP_CMPL,      RA,         RB,          NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_CMPLI      =>       (ALU,    OP_CMPL,      RA,         CONST_UI,    NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_CMPRB
		PPC_CNTLZD     =>       (ALU,    OP_CNTLZD,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTLZW     =>       (ALU,    OP_CNTLZW,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTTZD     =>       (ALU,    OP_CNTTZD,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTTZW     =>       (ALU,    OP_CNTTZW,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_CRAND
		--PPC_CRANDC
		--PPC_CREQV
		--PPC_CRNAND
		--PPC_CRNOR
		--PPC_CROR
		--PPC_CRORC
		--PPC_CRXOR
		--PPC_DARN
		PPC_DCBF       =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_DCBST      =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_DCBT       =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_DCBTST     =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_DCBZ
		PPC_DIV        =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_EQV        =>       (ALU,    OP_EQV,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_EXTSB      =>       (ALU,    OP_EXTSB,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_EXTSH      =>       (ALU,    OP_EXTSH,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_EXTSW      =>       (ALU,    OP_EXTSW,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_EXTSWSLI
		--PPC_ICBI
		PPC_ICBT       =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_ISEL       =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   BC,   NONE, NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_ISYNC      =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LBARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		--CONST_LI matches CONST_SI, so reuse it
		PPC_LBZ        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LBZU       =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LBZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LBZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LD         =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LDARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LDBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LDU        =>       (LDST,   OP_LOAD,      RA,         CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LDUX       =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LDX        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHA        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LHAU       =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHAUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHAX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZ        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZU       =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWA        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LWAUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LWAX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZ        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZU       =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_MADDHD
		--PPC_MADDHDU
		--PPC_MADDLD
		--PPC_MCRF
		--PPC_MCRXR
		--PPC_MCRXRX
		PPC_MFCR       =>       (ALU,    OP_MFCR,      NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFOCRF     =>       (ALU,    OP_MFOCRF,    NONE,       NONE,        NONE, RT,   FXM,  NONE, NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFCTR      =>       (ALU,    OP_MFCTR,     NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFLR       =>       (ALU,    OP_MFLR,      NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFTB       =>       (ALU,    OP_MFTB,      NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MTCTR      =>       (ALU,    OP_MTCTR,     RS,         NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MTLR       =>       (ALU,    OP_MTLR,      RS,         NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_MFSPR
		PPC_MOD        =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_MTCRF      =>       (ALU,    OP_MTCRF,     RS,         NONE,        NONE, NONE, FXM,  NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MTOCRF     =>       (ALU,    OP_MTOCRF,    RS,         NONE,        NONE, NONE, FXM,  NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_MTSPR
		PPC_MULHD      =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'),
		PPC_MULHDU     =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_MULHW      =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'),
		PPC_MULHWU     =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'),
		PPC_MULLD      =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'),
		PPC_MULLI      =>       (MUL,    OP_MUL_L64,   RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '1'),
		PPC_MULLW      =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'),
		PPC_NAND       =>       (ALU,    OP_NAND,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_NEG        =>       (ALU,    OP_NEG,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_NOP        =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_NOR        =>       (ALU,    OP_NOR,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_OR         =>       (ALU,    OP_OR,        RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ORC        =>       (ALU,    OP_ORC,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ORI        =>       (ALU,    OP_OR,        RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_ORIS       =>       (ALU,    OP_OR,        RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_POPCNTB    =>       (ALU,    OP_POPCNTB,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_POPCNTD    =>       (ALU,    OP_POPCNTD,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_POPCNTW    =>       (ALU,    OP_POPCNTW,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_PRTYD      =>       (ALU,    OP_PRTYD,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_PRTYW      =>       (ALU,    OP_PRTYW,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_RLDCL      =>       (ALU,    OP_RLDCL,     RS,         RB,          NONE, RA,   NONE, MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLDCR      =>       (ALU,    OP_RLDCR,     RS,         RB,          NONE, RA,   NONE, MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLDIC      =>       (ALU,    OP_RLDIC,     RS,         NONE,        NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLDICL     =>       (ALU,    OP_RLDICL,    RS,         NONE,        NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLDICR     =>       (ALU,    OP_RLDICR,    RS,         NONE,        NONE, RA,   SH,   ME,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLDIMI     =>       (ALU,    OP_RLDIMI,    RA,         RS,          NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLWIMI     =>       (ALU,    OP_RLWIMI,    RA,         RS,          NONE, RA,   SH32, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLWINM     =>       (ALU,    OP_RLWINM,    RS,         NONE,        NONE, RA,   SH32, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_RLWNM      =>       (ALU,    OP_RLWNM,     RS,         RB,          NONE, RA,   NONE, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_SETB
		PPC_SLD        =>       (ALU,    OP_SLD,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SLW        =>       (ALU,    OP_SLW,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAD       =>       (ALU,    OP_SRAD,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRADI      =>       (ALU,    OP_SRADI,     RS,         NONE,        NONE, RA,   SH,   NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAW       =>       (ALU,    OP_SRAW,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAWI      =>       (ALU,    OP_SRAWI,     RS,         NONE,        NONE, RA,   SH,   NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRD        =>       (ALU,    OP_SRD,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRW        =>       (ALU,    OP_SRW,       RS,         RB,          RS,   RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_STB        =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_STBCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '1', '0', '0', RC,   '0', '1'),
		PPC_STBU       =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'),
		PPC_STBUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'),
		PPC_STBX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_STD        =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STDBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STDCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STDU       =>       (LDST,   OP_STORE,     RA,         CONST_DS,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STDUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STDX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STH        =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STHBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STHCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STHU       =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STHUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STHX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STW        =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STWBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STWCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STWU       =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STWUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STWX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_SUBF       =>       (ALU,    OP_SUBF,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SUBFC      =>       (ALU,    OP_SUBFE,     RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SUBFE      =>       (ALU,    OP_SUBFE,     RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SUBFIC     =>       (ALU,    OP_SUBFE,     RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_SUBFME
		PPC_SUBFZE     =>       (ALU,    OP_SUBFE,     RA,         NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SYNC       =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_TD
		PPC_TDI        =>       (ALU,    OP_TDI,       RA,         CONST_SI,    NONE, NONE, TOO,  NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_TW         =>       (ALU,    OP_TW,        RA,         RB,          NONE, NONE, TOO,  NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_TWI
		PPC_XOR        =>       (ALU,    OP_XOR,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_XORI       =>       (ALU,    OP_XOR,       RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_XORIS      =>       (ALU,    OP_XOR,       RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_SIM_CONFIG =>       (ALU,    OP_SIM_CONFIG,NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),

		others => decode_rom_init
	);

begin
	decode1_0: process(clk)
	begin
		if rising_edge(clk) then
			-- Output state remains unchanged on stall, unless we are flushing
			if rst = '1' or flush_in = '1' or stall_in = '0' then
				r <= rin;
			end if;
		end if;
	end process;

	decode1_1: process(all)
		variable v : Decode1ToDecode2Type;
		variable ppc_insn: ppc_insn_t;
	begin
		v := r;

		v.valid := f_in.valid;
		v.nia  := f_in.nia;
		v.insn := f_in.insn;
		v.stop_mark := f_in.stop_mark;

		ppc_insn := PPC_ILLEGAL;

		if f_in.valid = '1' then
			report "Decode insn " & to_hstring(f_in.insn) & " at " & to_hstring(f_in.nia);

			if std_match(f_in.insn, "011111---------------0100001010-") then
				report "PPC_add";
				ppc_insn := PPC_ADD;
			elsif std_match(f_in.insn, "011111---------------0000001010-") then
				report "PPC_addc";
				ppc_insn := PPC_ADDC;
			elsif std_match(f_in.insn, "011111---------------0010001010-") then
				report "PPC_adde";
				ppc_insn := PPC_ADDE;
			elsif std_match(f_in.insn, "011111---------------0010101010-") then
				report "PPC_addex";
				ppc_insn := PPC_ADDEX;
			elsif std_match(f_in.insn, "001110--------------------------") then
				report "PPC_addi";
				ppc_insn := PPC_ADDI;
			elsif std_match(f_in.insn, "001100--------------------------") then
				report "PPC_addic";
				ppc_insn := PPC_ADDIC;
			elsif std_match(f_in.insn, "001101--------------------------") then
				report "PPC_addic.";
				ppc_insn := PPC_ADDIC_RC;
			elsif std_match(f_in.insn, "001111--------------------------") then
				report "PPC_addis";
				ppc_insn := PPC_ADDIS;
			elsif std_match(f_in.insn, "011111---------------0011101010-") then
				report "PPC_addme";
				ppc_insn := PPC_ADDME;
			elsif std_match(f_in.insn, "010011--------------------00010-") then
				report "PPC_addpcis";
				ppc_insn := PPC_ADDPCIS;
			elsif std_match(f_in.insn, "011111---------------0011001010-") then
				report "PPC_addze";
				ppc_insn := PPC_ADDZE;
			elsif std_match(f_in.insn, "011111---------------0000011100-") then
				report "PPC_and";
				ppc_insn := PPC_AND;
			elsif std_match(f_in.insn, "011111---------------0000111100-") then
				report "PPC_andc";
				ppc_insn := PPC_ANDC;
			elsif std_match(f_in.insn, "011100--------------------------") then
				report "PPC_andi.";
				ppc_insn := PPC_ANDI_RC;
			elsif std_match(f_in.insn, "011101--------------------------") then
				report "PPC_andis.";
				ppc_insn := PPC_ANDIS_RC;
			elsif std_match(f_in.insn, "000000---------------0100000000-") then
				report "PPC_attn";
				ppc_insn := PPC_ATTN;
			elsif std_match(f_in.insn, "010010--------------------------") then
				report "PPC_b";
				ppc_insn := PPC_B;
			elsif std_match(f_in.insn, "010000--------------------------") then
				report "PPC_bc";
				ppc_insn := PPC_BC;
			elsif std_match(f_in.insn, "010011---------------1000010000-") then
				report "PPC_bcctr";
				ppc_insn := PPC_BCCTR;
			elsif std_match(f_in.insn, "010011---------------0000010000-") then
				report "PPC_bclr";
				ppc_insn := PPC_BCLR;
			elsif std_match(f_in.insn, "010011---------------1000110000-") then
				report "PPC_bctar";
				ppc_insn := PPC_BCTAR;
			elsif std_match(f_in.insn, "011111---------------0011111100-") then
				report "PPC_bperm";
				ppc_insn := PPC_BPERM;
			elsif std_match(f_in.insn, "011111---------------0000000000-") then
				report "PPC_cmp";
				ppc_insn := PPC_CMP;
			elsif std_match(f_in.insn, "011111---------------0111111100-") then
				report "PPC_cmpb";
				ppc_insn := PPC_CMPB;
			elsif std_match(f_in.insn, "011111---------------0011100000-") then
				report "PPC_cmpeqb";
				ppc_insn := PPC_CMPEQB;
			elsif std_match(f_in.insn, "001011--------------------------") then
				report "PPC_cmpi";
				ppc_insn := PPC_CMPI;
			elsif std_match(f_in.insn, "011111---------------0000100000-") then
				report "PPC_cmpl";
				ppc_insn := PPC_CMPL;
			elsif std_match(f_in.insn, "001010--------------------------") then
				report "PPC_cmpli";
				ppc_insn := PPC_CMPLI;
			elsif std_match(f_in.insn, "011111---------------0011000000-") then
				report "PPC_cmprb";
				ppc_insn := PPC_CMPRB;
			elsif std_match(f_in.insn, "011111---------------0000111010-") then
				report "PPC_cntlzd";
				ppc_insn := PPC_CNTLZD;
			elsif std_match(f_in.insn, "011111---------------0000011010-") then
				report "PPC_cntlzw";
				ppc_insn := PPC_CNTLZW;
			elsif std_match(f_in.insn, "011111---------------1000111010-") then
				report "PPC_cnttzd";
				ppc_insn := PPC_CNTTZD;
			elsif std_match(f_in.insn, "011111---------------1000011010-") then
				report "PPC_cnttzw";
				ppc_insn := PPC_CNTTZW;
			elsif std_match(f_in.insn, "010011---------------0100000001-") then
				report "PPC_crand";
				ppc_insn := PPC_CRAND;
			elsif std_match(f_in.insn, "010011---------------0010000001-") then
				report "PPC_crandc";
				ppc_insn := PPC_CRANDC;
			elsif std_match(f_in.insn, "010011---------------0100100001-") then
				report "PPC_creqv";
				ppc_insn := PPC_CREQV;
			elsif std_match(f_in.insn, "010011---------------0011100001-") then
				report "PPC_crnand";
				ppc_insn := PPC_CRNAND;
			elsif std_match(f_in.insn, "010011---------------0000100001-") then
				report "PPC_crnor";
				ppc_insn := PPC_CRNOR;
			elsif std_match(f_in.insn, "010011---------------0111000001-") then
				report "PPC_cror";
				ppc_insn := PPC_CROR;
			elsif std_match(f_in.insn, "010011---------------0110100001-") then
				report "PPC_crorc";
				ppc_insn := PPC_CRORC;
			elsif std_match(f_in.insn, "010011---------------0011000001-") then
				report "PPC_crxor";
				ppc_insn := PPC_CRXOR;
			elsif std_match(f_in.insn, "011111---------------1011110011-") then
				report "PPC_darn";
				ppc_insn := PPC_DARN;
			elsif std_match(f_in.insn, "011111---------------0001010110-") then
				report "PPC_dcbf";
				ppc_insn := PPC_DCBF;
			elsif std_match(f_in.insn, "011111---------------0000110110-") then
				report "PPC_dcbst";
				ppc_insn := PPC_DCBST;
			elsif std_match(f_in.insn, "011111---------------0100010110-") then
				report "PPC_dcbt";
				ppc_insn := PPC_DCBT;
			elsif std_match(f_in.insn, "011111---------------0011110110-") then
				report "PPC_dcbtst";
				ppc_insn := PPC_DCBTST;
			elsif std_match(f_in.insn, "011111---------------1111110110-") then
				report "PPC_dcbz";
				ppc_insn := PPC_DCBZ;
			elsif std_match(f_in.insn, "011111----------------11--010-1-") then
				report "PPC_div";
				ppc_insn := PPC_DIV;
			elsif std_match(f_in.insn, "011111---------------0100011100-") then
				report "PPC_eqv";
				ppc_insn := PPC_EQV;
			elsif std_match(f_in.insn, "011111---------------1110111010-") then
				report "PPC_extsb";
				ppc_insn := PPC_EXTSB;
			elsif std_match(f_in.insn, "011111---------------1110011010-") then
				report "PPC_extsh";
				ppc_insn := PPC_EXTSH;
			elsif std_match(f_in.insn, "011111---------------1111011010-") then
				report "PPC_extsw";
				ppc_insn := PPC_EXTSW;
			elsif std_match(f_in.insn, "011111---------------110111101--") then
				report "PPC_extswsli";
				ppc_insn := PPC_EXTSWSLI;
			elsif std_match(f_in.insn, "011111---------------1111010110-") then
				report "PPC_icbi";
				ppc_insn := PPC_ICBI;
			elsif std_match(f_in.insn, "011111---------------0000010110-") then
				report "PPC_icbt";
				ppc_insn := PPC_ICBT;
			elsif std_match(f_in.insn, "011111--------------------01111-") then
				report "PPC_isel";
				ppc_insn := PPC_ISEL;
			elsif std_match(f_in.insn, "010011---------------0010010110-") then
				report "PPC_isync";
				ppc_insn := PPC_ISYNC;
			elsif std_match(f_in.insn, "011111---------------0000110100-") then
				report "PPC_lbarx";
				ppc_insn := PPC_LBARX;
			elsif std_match(f_in.insn, "100010--------------------------") then
				report "PPC_lbz";
				ppc_insn := PPC_LBZ;
			elsif std_match(f_in.insn, "100011--------------------------") then
				report "PPC_lbzu";
				ppc_insn := PPC_LBZU;
			elsif std_match(f_in.insn, "011111---------------0001110111-") then
				report "PPC_lbzux";
				ppc_insn := PPC_LBZUX;
			elsif std_match(f_in.insn, "011111---------------0001010111-") then
				report "PPC_lbzx";
				ppc_insn := PPC_LBZX;
			elsif std_match(f_in.insn, "111010------------------------00") then
				report "PPC_ld";
				ppc_insn := PPC_LD;
			elsif std_match(f_in.insn, "011111---------------0001010100-") then
				report "PPC_ldarx";
				ppc_insn := PPC_LDARX;
			elsif std_match(f_in.insn, "011111---------------1000010100-") then
				report "PPC_ldbrx";
				ppc_insn := PPC_LDBRX;
			elsif std_match(f_in.insn, "111010------------------------01") then
				report "PPC_ldu";
				ppc_insn := PPC_LDU;
			elsif std_match(f_in.insn, "011111---------------0000110101-") then
				report "PPC_ldux";
				ppc_insn := PPC_LDUX;
			elsif std_match(f_in.insn, "011111---------------0000010101-") then
				report "PPC_ldx";
				ppc_insn := PPC_LDX;
			elsif std_match(f_in.insn, "101010--------------------------") then
				report "PPC_lha";
				ppc_insn := PPC_LHA;
			elsif std_match(f_in.insn, "011111---------------0001110100-") then
				report "PPC_lharx";
				ppc_insn := PPC_LHARX;
			elsif std_match(f_in.insn, "101011--------------------------") then
				report "PPC_lhau";
				ppc_insn := PPC_LHAU;
			elsif std_match(f_in.insn, "011111---------------0101110111-") then
				report "PPC_lhaux";
				ppc_insn := PPC_LHAUX;
			elsif std_match(f_in.insn, "011111---------------0101010111-") then
				report "PPC_lhax";
				ppc_insn := PPC_LHAX;
			elsif std_match(f_in.insn, "011111---------------1100010110-") then
				report "PPC_lhbrx";
				ppc_insn := PPC_LHBRX;
			elsif std_match(f_in.insn, "101000--------------------------") then
				report "PPC_lhz";
				ppc_insn := PPC_LHZ;
			elsif std_match(f_in.insn, "101001--------------------------") then
				report "PPC_lhzu";
				ppc_insn := PPC_LHZU;
			elsif std_match(f_in.insn, "011111---------------0100110111-") then
				report "PPC_lhzux";
				ppc_insn := PPC_LHZUX;
			elsif std_match(f_in.insn, "011111---------------0100010111-") then
				report "PPC_lhzx";
				ppc_insn := PPC_LHZX;
			elsif std_match(f_in.insn, "111010------------------------10") then
				report "PPC_lwa";
				ppc_insn := PPC_LWA;
			elsif std_match(f_in.insn, "011111---------------0000010100-") then
				report "PPC_lwarx";
				ppc_insn := PPC_LWARX;
			elsif std_match(f_in.insn, "011111---------------0101110101-") then
				report "PPC_lwaux";
				ppc_insn := PPC_LWAUX;
			elsif std_match(f_in.insn, "011111---------------0101010101-") then
				report "PPC_lwax";
				ppc_insn := PPC_LWAX;
			elsif std_match(f_in.insn, "011111---------------1000010110-") then
				report "PPC_lwbrx";
				ppc_insn := PPC_LWBRX;
			elsif std_match(f_in.insn, "100000--------------------------") then
				report "PPC_lwz";
				ppc_insn := PPC_LWZ;
			elsif std_match(f_in.insn, "100001--------------------------") then
				report "PPC_lwzu";
				ppc_insn := PPC_LWZU;
			elsif std_match(f_in.insn, "011111---------------0000110111-") then
				report "PPC_lwzux";
				ppc_insn := PPC_LWZUX;
			elsif std_match(f_in.insn, "011111---------------0000010111-") then
				report "PPC_lwzx";
				ppc_insn := PPC_LWZX;
			elsif std_match(f_in.insn, "000100--------------------110000") then
				report "PPC_maddhd";
				ppc_insn := PPC_MADDHD;
			elsif std_match(f_in.insn, "000100--------------------110001") then
				report "PPC_maddhdu";
				ppc_insn := PPC_MADDHDU;
			elsif std_match(f_in.insn, "000100--------------------110011") then
				report "PPC_maddld";
				ppc_insn := PPC_MADDLD;
			elsif std_match(f_in.insn, "010011---------------0000000000-") then
				report "PPC_mcrf";
				ppc_insn := PPC_MCRF;
			elsif std_match(f_in.insn, "011111---------------1000000000-") then
				report "PPC_mcrxr";
				ppc_insn := PPC_MCRXR;
			elsif std_match(f_in.insn, "011111---------------1001000000-") then
				report "PPC_mcrxrx";
				ppc_insn := PPC_MCRXRX;
			elsif std_match(f_in.insn, "011111-----0---------0000010011-") then
				report "PPC_mfcr";
				ppc_insn := PPC_MFCR;
			elsif std_match(f_in.insn, "011111-----1---------0000010011-") then
				report "PPC_mfocrf";
				ppc_insn := PPC_MFOCRF;
			-- Specific MF/MT SPR encodings first
			elsif std_match(f_in.insn, "011111-----01001000000101010011-") then
				report "PPC_mfctr";
				ppc_insn := PPC_MFCTR;
			elsif std_match(f_in.insn, "011111-----01000000000101010011-") then
				report "PPC_mflr";
				ppc_insn := PPC_MFLR;
			elsif std_match(f_in.insn, "011111-----01100010000101010011-") then
				report "PPC_mftb";
				ppc_insn := PPC_MFTB;
			elsif std_match(f_in.insn, "011111-----01001000000111010011-") then
				report "PPC_mtctr";
				ppc_insn := PPC_MTCTR;
			elsif std_match(f_in.insn, "011111-----01000000000111010011-") then
				report "PPC_mtlr";
				ppc_insn := PPC_MTLR;
			elsif std_match(f_in.insn, "011111---------------0101010011-") then
				report "PPC_mfspr";
				ppc_insn := PPC_MFSPR;
			elsif std_match(f_in.insn, "011111----------------1000010-1-") then
				report "PPC_mod";
				ppc_insn := PPC_MOD;
			elsif std_match(f_in.insn, "011111-----0---------0010010000-") then
				report "PPC_mtcrf";
				ppc_insn := PPC_MTCRF;
			elsif std_match(f_in.insn, "011111-----1---------0010010000-") then
				report "PPC_mtocrf";
				ppc_insn := PPC_MTOCRF;
			elsif std_match(f_in.insn, "011111---------------0111010011-") then
				report "PPC_mtspr";
				ppc_insn := PPC_MTSPR;
			elsif std_match(f_in.insn, "011111----------------001001001-") then
				report "PPC_mulhd";
				ppc_insn := PPC_MULHD;
			elsif std_match(f_in.insn, "011111----------------000001001-") then
				report "PPC_mulhdu";
				ppc_insn := PPC_MULHDU;
			elsif std_match(f_in.insn, "011111----------------001001011-") then
				report "PPC_mulhw";
				ppc_insn := PPC_MULHW;
			elsif std_match(f_in.insn, "011111----------------000001011-") then
				report "PPC_mulhwu";
				ppc_insn := PPC_MULHWU;
			elsif std_match(f_in.insn, "011111---------------0011101001-") then
				report "PPC_mulld";
				ppc_insn := PPC_MULLD;
			elsif std_match(f_in.insn, "000111--------------------------") then
				report "PPC_mulli";
				ppc_insn := PPC_MULLI;
			elsif std_match(f_in.insn, "011111---------------0011101011-") then
				report "PPC_mullw";
				ppc_insn := PPC_MULLW;
			elsif std_match(f_in.insn, "011111---------------0111011100-") then
				report "PPC_nand";
				ppc_insn := PPC_NAND;
			elsif std_match(f_in.insn, "011111---------------0001101000-") then
				report "PPC_neg";
				ppc_insn := PPC_NEG;
			elsif std_match(f_in.insn, "011111---------------0001111100-") then
				report "PPC_nor";
				ppc_insn := PPC_NOR;
			elsif std_match(f_in.insn, "011111---------------0110111100-") then
				report "PPC_or";
				ppc_insn := PPC_OR;
			elsif std_match(f_in.insn, "011111---------------0110011100-") then
				report "PPC_orc";
				ppc_insn := PPC_ORC;
				-- Has to be before ori
			elsif std_match(f_in.insn, "01100000000000000000000000000000") then
				report "PPC_nop";
				ppc_insn := PPC_NOP;
			elsif std_match(f_in.insn, "011000--------------------------") then
				report "PPC_ori";
				ppc_insn := PPC_ORI;
			elsif std_match(f_in.insn, "011001--------------------------") then
				report "PPC_oris";
				ppc_insn := PPC_ORIS;
			elsif std_match(f_in.insn, "011111---------------0001111010-") then
				report "PPC_popcntb";
				ppc_insn := PPC_POPCNTB;
			elsif std_match(f_in.insn, "011111---------------0111111010-") then
				report "PPC_popcntd";
				ppc_insn := PPC_POPCNTD;
			elsif std_match(f_in.insn, "011111---------------0101111010-") then
				report "PPC_popcntw";
				ppc_insn := PPC_POPCNTW;
			elsif std_match(f_in.insn, "011111---------------0010111010-") then
				report "PPC_prtyd";
				ppc_insn := PPC_PRTYD;
			elsif std_match(f_in.insn, "011111---------------0010011010-") then
				report "PPC_prtyw";
				ppc_insn := PPC_PRTYW;
			elsif std_match(f_in.insn, "011110---------------------1000-") then
				report "PPC_rldcl";
				ppc_insn := PPC_RLDCL;
			elsif std_match(f_in.insn, "011110---------------------1001-") then
				report "PPC_rldcr";
				ppc_insn := PPC_RLDCR;
			elsif std_match(f_in.insn, "011110---------------------010--") then
				report "PPC_rldic";
				ppc_insn := PPC_RLDIC;
			elsif std_match(f_in.insn, "011110---------------------000--") then
				report "PPC_rldicl";
				ppc_insn := PPC_RLDICL;
			elsif std_match(f_in.insn, "011110---------------------001--") then
				report "PPC_rldicr";
				ppc_insn := PPC_RLDICR;
			elsif std_match(f_in.insn, "011110---------------------011--") then
				report "PPC_rldimi";
				ppc_insn := PPC_RLDIMI;
			elsif std_match(f_in.insn, "010100--------------------------") then
				report "PPC_rlwimi";
				ppc_insn := PPC_RLWIMI;
			elsif std_match(f_in.insn, "010101--------------------------") then
				report "PPC_rlwinm";
				ppc_insn := PPC_RLWINM;
			elsif std_match(f_in.insn, "010111--------------------------") then
				report "PPC_rlwnm";
				ppc_insn := PPC_RLWNM;
			elsif std_match(f_in.insn, "011111---------------0010000000-") then
				report "PPC_setb";
				ppc_insn := PPC_SETB;
			elsif std_match(f_in.insn, "011111---------------0000011011-") then
				report "PPC_sld";
				ppc_insn := PPC_SLD;
			elsif std_match(f_in.insn, "011111---------------0000011000-") then
				report "PPC_slw";
				ppc_insn := PPC_SLW;
			elsif std_match(f_in.insn, "011111---------------1100011010-") then
				report "PPC_srad";
				ppc_insn := PPC_SRAD;
			elsif std_match(f_in.insn, "011111---------------110011101--") then
				report "PPC_sradi";
				ppc_insn := PPC_SRADI;
			elsif std_match(f_in.insn, "011111---------------1100011000-") then
				report "PPC_sraw";
				ppc_insn := PPC_SRAW;
			elsif std_match(f_in.insn, "011111---------------1100111000-") then
				report "PPC_srawi";
				ppc_insn := PPC_SRAWI;
			elsif std_match(f_in.insn, "011111---------------1000011011-") then
				report "PPC_srd";
				ppc_insn := PPC_SRD;
			elsif std_match(f_in.insn, "011111---------------1000011000-") then
				report "PPC_srw";
				ppc_insn := PPC_SRW;
			elsif std_match(f_in.insn, "100110--------------------------") then
				report "PPC_stb";
				ppc_insn := PPC_STB;
			elsif std_match(f_in.insn, "011111---------------1010110110-") then
				report "PPC_stbcx";
				ppc_insn := PPC_STBCX;
			elsif std_match(f_in.insn, "100111--------------------------") then
				report "PPC_stbu";
				ppc_insn := PPC_STBU;
			elsif std_match(f_in.insn, "011111---------------0011110111-") then
				report "PPC_stbux";
				ppc_insn := PPC_STBUX;
			elsif std_match(f_in.insn, "011111---------------0011010111-") then
				report "PPC_stbx";
				ppc_insn := PPC_STBX;
			elsif std_match(f_in.insn, "111110------------------------00") then
				report "PPC_std";
				ppc_insn := PPC_STD;
			elsif std_match(f_in.insn, "011111---------------1010010100-") then
				report "PPC_stdbrx";
				ppc_insn := PPC_STDBRX;
			elsif std_match(f_in.insn, "011111---------------0011010110-") then
				report "PPC_stdcx";
				ppc_insn := PPC_STDCX;
			elsif std_match(f_in.insn, "111110------------------------01") then
				report "PPC_stdu";
				ppc_insn := PPC_STDU;
			elsif std_match(f_in.insn, "011111---------------0010110101-") then
				report "PPC_stdux";
				ppc_insn := PPC_STDUX;
			elsif std_match(f_in.insn, "011111---------------0010010101-") then
				report "PPC_stdx";
				ppc_insn := PPC_STDX;
			elsif std_match(f_in.insn, "101100--------------------------") then
				report "PPC_sth";
				ppc_insn := PPC_STH;
			elsif std_match(f_in.insn, "011111---------------1110010110-") then
				report "PPC_sthbrx";
				ppc_insn := PPC_STHBRX;
			elsif std_match(f_in.insn, "011111---------------1011010110-") then
				report "PPC_sthcx";
				ppc_insn := PPC_STHCX;
			elsif std_match(f_in.insn, "101101--------------------------") then
				report "PPC_sthu";
				ppc_insn := PPC_STHU;
			elsif std_match(f_in.insn, "011111---------------0110110111-") then
				report "PPC_sthux";
				ppc_insn := PPC_STHUX;
			elsif std_match(f_in.insn, "011111---------------0110010111-") then
				report "PPC_sthx";
				ppc_insn := PPC_STHX;
			elsif std_match(f_in.insn, "100100--------------------------") then
				report "PPC_stw";
				ppc_insn := PPC_STW;
			elsif std_match(f_in.insn, "011111---------------1010010110-") then
				report "PPC_stwbrx";
				ppc_insn := PPC_STWBRX;
			elsif std_match(f_in.insn, "011111---------------0010010110-") then
				report "PPC_stwcx";
				ppc_insn := PPC_STWCX;
			elsif std_match(f_in.insn, "100101--------------------------") then
				report "PPC_stwu";
				ppc_insn := PPC_STWU;
			elsif std_match(f_in.insn, "011111---------------0010110111-") then
				report "PPC_stwux";
				ppc_insn := PPC_STWUX;
			elsif std_match(f_in.insn, "011111---------------0010010111-") then
				report "PPC_stwx";
				ppc_insn := PPC_STWX;
			elsif std_match(f_in.insn, "011111---------------0000101000-") then
				report "PPC_subf";
				ppc_insn := PPC_SUBF;
			elsif std_match(f_in.insn, "011111---------------0000001000-") then
				report "PPC_subfc";
				ppc_insn := PPC_SUBFC;
			elsif std_match(f_in.insn, "011111---------------0010001000-") then
				report "PPC_subfe";
				ppc_insn := PPC_SUBFE;
			elsif std_match(f_in.insn, "001000--------------------------") then
				report "PPC_subfic";
				ppc_insn := PPC_SUBFIC;
			elsif std_match(f_in.insn, "011111---------------0011101000-") then
				report "PPC_subfme";
				ppc_insn := PPC_SUBFME;
			elsif std_match(f_in.insn, "011111---------------0011001000-") then
				report "PPC_subfze";
				ppc_insn := PPC_SUBFZE;
			elsif std_match(f_in.insn, "011111---------------1001010110-") then
				report "PPC_sync";
				ppc_insn := PPC_SYNC;
			elsif std_match(f_in.insn, "011111---------------0001000100-") then
				report "PPC_td";
				ppc_insn := PPC_TD;
			elsif std_match(f_in.insn, "000010--------------------------") then
				report "PPC_tdi";
				ppc_insn := PPC_TDI;
			elsif std_match(f_in.insn, "011111---------------0000000100-") then
				report "PPC_tw";
				ppc_insn := PPC_TW;
			elsif std_match(f_in.insn, "000011--------------------------") then
				report "PPC_twi";
				ppc_insn := PPC_TWI;
			elsif std_match(f_in.insn, "011111---------------0100111100-") then
				report "PPC_xor";
				ppc_insn := PPC_XOR;
			elsif std_match(f_in.insn, "011010--------------------------") then
				report "PPC_xori";
				ppc_insn := PPC_XORI;
			elsif std_match(f_in.insn, "011011--------------------------") then
				report "PPC_xoris";
				ppc_insn := PPC_XORIS;
			elsif std_match(f_in.insn, "000001---------------0000000011-") then
				report "PPC_SIM_CONFIG";
				ppc_insn := PPC_SIM_CONFIG;
			else
				report "PPC_illegal";
				ppc_insn := PPC_ILLEGAL;
			end if;

			v.decode := decode_rom_array(ppc_insn);
		end if;

		if flush_in = '1' then
			v.valid := '0';
		end if;

		if rst = '1' then
			v := Decode1ToDecode2Init;
		end if;

		-- Update registers
		rin <= v;

		-- Update outputs
		d_out <= r;
	end process;
end architecture behaviour;
