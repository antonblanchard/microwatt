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

        subtype major_opcode_t is unsigned(5 downto 0);
        type major_rom_array_t is array(0 to 63) of decode_rom_t;
        type minor_valid_array_t is array(0 to 1023) of std_ulogic;
        type op_19_subop_array_t is array(0 to 7) of decode_rom_t;
        type op_30_subop_array_t is array(0 to 7) of decode_rom_t;
        type minor_rom_array_2_t is array(0 to 3) of decode_rom_t;

	type decode_rom_array_t is array(ppc_insn_t) of decode_rom_t;

        constant illegal_inst : decode_rom_t :=
                            (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1');

        constant major_decode_rom_array : major_rom_array_t := (
		--          unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                         op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		12 =>       (ALU,    OP_ADDE,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addic
		13 =>       (ALU,    OP_ADDE,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- addic.
                14 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addi
		15 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI_HI, NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addis
		28 =>       (ALU,    OP_AND,       RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- andi.
		29 =>       (ALU,    OP_AND,       RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- andis.
		18 =>       (ALU,    OP_B,         NONE,       CONST_LI,    NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'), -- b
		16 =>       (ALU,    OP_BC,        NONE,       CONST_BD,    NONE, NONE, BO,   BI,   NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'), -- bc
		11 =>       (ALU,    OP_CMP,       RA,         CONST_SI,    NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpi
		10 =>       (ALU,    OP_CMPL,      RA,         CONST_UI,    NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpli
		34 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lbz
		35 =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lbzu
		42 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lha
		43 =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'), -- lhau
		40 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lhz
		41 =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lhzu
		32 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lwz
                33 =>       (LDST,   OP_LOAD,      RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lwz
		 7 =>       (MUL,    OP_MUL_L64,   RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '1'), -- mulli
		24 =>       (ALU,    OP_OR,        RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ori
		25 =>       (ALU,    OP_OR,        RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- oris
		20 =>       (ALU,    OP_RLWIMI,    RA,         RS,          NONE, RA,   SH32, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rlwimi
		21 =>       (ALU,    OP_RLWINM,    RS,         NONE,        NONE, RA,   SH32, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rlwinm
		23 =>       (ALU,    OP_RLWNM,     RS,         RB,          NONE, RA,   NONE, MB32, ME32, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rlwnm
		38 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- stb
		39 =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'), -- stbu
		44 =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sth
		45 =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- sthu
		36 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stw
		37 =>       (LDST,   OP_STORE,     RA,         CONST_SI,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stwu
		 8 =>       (ALU,    OP_SUBFE,     RA,         CONST_SI,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- subfic
		 2 =>       (ALU,    OP_TDI,       RA,         CONST_SI,    NONE, NONE, TOO,  NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- tdi
		--PPC_TWI 3
		26 =>       (ALU,    OP_XOR,       RS,         CONST_UI,    NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- xori
		27 =>       (ALU,    OP_XOR,       RS,         CONST_UI_HI, NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- xoris
		others   => illegal_inst
        );

        -- indexed by bits 10..1 of instruction word
        constant decode_op_19_valid : minor_valid_array_t := (
                -- addpcis, 5 upper bits are part of constant
                2#0000000010# => '1', 2#0000100010# => '1', 2#0001000010# => '1', 2#0001100010# => '1', 2#0010000010# => '1', 2#0010100010# => '1', 2#0011000010# => '1', 2#0011100010# => '1',
                2#0100000010# => '1', 2#0100100010# => '1', 2#0101000010# => '1', 2#0101100010# => '1', 2#0110000010# => '1', 2#0110100010# => '1', 2#0111000010# => '1', 2#0111100010# => '1',
                2#1000000010# => '1', 2#1000100010# => '1', 2#1001000010# => '1', 2#1001100010# => '1', 2#1010000010# => '1', 2#1010100010# => '1', 2#1011000010# => '1', 2#1011100010# => '1',
                2#1100000010# => '1', 2#1100100010# => '1', 2#1101000010# => '1', 2#1101100010# => '1', 2#1110000010# => '1', 2#1110100010# => '1', 2#1111000010# => '1', 2#1111100010# => '1',
                2#1000010000# => '1', -- bcctr
                2#0000010000# => '1', -- bclr
                2#1000110000# => '0', -- bctar
                2#0100000001# => '0', -- crand
                2#0010000001# => '0', -- crandc
                2#0100100001# => '0', -- creqv
                2#0011100001# => '0', -- crnand
                2#0000100001# => '0', -- crnor
                2#0111000001# => '0', -- cror
                2#0011000001# => '0', -- crorc
                2#0110100001# => '0', -- crxor
                2#0010010110# => '1', -- isync
                2#0000000000# => '1', -- mcrf
                others => '0'
        );

        -- indexed by bits 5, 3, 2 of instruction word
	constant decode_op_19_array : op_19_subop_array_t := (
		--                unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                               op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
                -- mcrf; cr logical ops not implemented yet
		2#000#    =>       (ALU,    OP_MCRF,      NONE,       NONE,        NONE, NONE, BF,   BFA,  NONE, '1', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		-- addpcis not implemented yet
		2#001#    =>       (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
                -- bclr, bcctr, bctar
		2#100#    =>       (ALU,    OP_BCREG,     NONE,       NONE,        NONE, NONE, BO,   BI,   BH,   '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
                -- isync
		2#111#    =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		others   => illegal_inst
        );

	constant decode_op_30_array : op_30_subop_array_t := (
		--                unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                               op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		2#010#   =>       (ALU,    OP_RLDIC,     RS,         NONE,        NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		2#000#   =>       (ALU,    OP_RLDICL,    RS,         NONE,        NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		2#001#   =>       (ALU,    OP_RLDICR,    RS,         NONE,        NONE, RA,   SH,   ME,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		2#011#   =>       (ALU,    OP_RLDIMI,    RA,         RS,          NONE, RA,   SH,   MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
                -- rldcl, rldcr
		2#100#   =>       (ALU,    OP_RLDCX,     RS,         RB,          NONE, RA,   NONE, MB,   NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		others   => illegal_inst
        );

	-- Note: reformat with column -t -o ' '
	constant decode_op_31_array : decode_rom_array_t := (
		--                       unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                                      op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		PPC_ILLEGAL    =>       (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADD        =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADDC       =>       (ALU,    OP_ADDE,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ADDE       =>       (ALU,    OP_ADDE,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_ADDEX
		--PPC_ADDME
		PPC_ADDZE      =>       (ALU,    OP_ADDE,      RA,         NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_AND        =>       (ALU,    OP_AND,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ANDC       =>       (ALU,    OP_ANDC,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_BPERM
		PPC_CMP        =>       (ALU,    OP_CMP,       RA,         RB,          NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_CMPB       =>       (ALU,    OP_CMPB,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_CMPEQB
		PPC_CMPL       =>       (ALU,    OP_CMPL,      RA,         RB,          NONE, NONE, BF,   L,    NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_CMPRB
		PPC_CNTLZD     =>       (ALU,    OP_CNTLZD,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTLZW     =>       (ALU,    OP_CNTLZW,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTTZD     =>       (ALU,    OP_CNTTZD,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_CNTTZW     =>       (ALU,    OP_CNTTZW,    RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
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
		PPC_LBARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LBZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LBZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LDARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LDBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LDUX       =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LDX        =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LHAUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHAX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LHZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWARX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_LWAUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LWAX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWBRX      =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZUX      =>       (LDST,   OP_LOAD,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_LWZX       =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_MCRXR
		--PPC_MCRXRX
		PPC_MFCR       =>       (ALU,    OP_MFCR,      NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFOCRF     =>       (ALU,    OP_MFOCRF,    NONE,       NONE,        NONE, RT,   FXM,  NONE, NONE, '1', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MFSPR      =>       (ALU,    OP_MFSPR,     NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MOD        =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_MTCRF      =>       (ALU,    OP_MTCRF,     RS,         NONE,        NONE, NONE, FXM,  NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MTOCRF     =>       (ALU,    OP_MTOCRF,    RS,         NONE,        NONE, NONE, FXM,  NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MTSPR      =>       (ALU,    OP_MTSPR,     RS,         NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_MULHD      =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'),
		PPC_MULHDU     =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_MULHW      =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'),
		PPC_MULHWU     =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'),
		PPC_MULLD      =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'),
		PPC_MULLW      =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '1', '0', '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'),
		PPC_NAND       =>       (ALU,    OP_NAND,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_NEG        =>       (ALU,    OP_NEG,       RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_NOR        =>       (ALU,    OP_NOR,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_OR         =>       (ALU,    OP_OR,        RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_ORC        =>       (ALU,    OP_ORC,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_POPCNTB    =>       (ALU,    OP_POPCNTB,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_POPCNTD    =>       (ALU,    OP_POPCNTD,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_POPCNTW    =>       (ALU,    OP_POPCNTW,   RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_PRTYD      =>       (ALU,    OP_PRTYD,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_PRTYW      =>       (ALU,    OP_PRTYW,     RS,         NONE,        NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_SETB
		PPC_SLD        =>       (ALU,    OP_SLD,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SLW        =>       (ALU,    OP_SLW,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAD       =>       (ALU,    OP_SRAD,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRADI      =>       (ALU,    OP_SRADI,     RS,         NONE,        NONE, RA,   SH,   NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAW       =>       (ALU,    OP_SRAW,      RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRAWI      =>       (ALU,    OP_SRAWI,     RS,         NONE,        NONE, RA,   SH,   NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRD        =>       (ALU,    OP_SRD,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SRW        =>       (ALU,    OP_SRW,       RS,         RB,          RS,   RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_STBCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '1', '0', '0', RC,   '0', '1'),
		PPC_STBUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'),
		PPC_STBX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_STDBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STDCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STDUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STDX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STHBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STHCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STHUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STHX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STWBRX     =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_STWCX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'),
		PPC_STWUX      =>       (LDST,   OP_STORE,     RA,         RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'),
		PPC_STWX       =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_SUBF       =>       (ALU,    OP_SUBF,      RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SUBFC      =>       (ALU,    OP_SUBFE,     RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SUBFE      =>       (ALU,    OP_SUBFE,     RA,         RB,          NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		--PPC_SUBFME
		PPC_SUBFZE     =>       (ALU,    OP_SUBFE,     RA,         NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '1', '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		PPC_SYNC       =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		--PPC_TD
		PPC_TW         =>       (ALU,    OP_TW,        RA,         RB,          NONE, NONE, TOO,  NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		PPC_XOR        =>       (ALU,    OP_XOR,       RS,         RB,          NONE, RA,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
		others => decode_rom_init
	);

        constant decode_op_58_array : minor_rom_array_2_t := (
		--                 unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                                op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		0     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ld
                1     =>       (LDST,   OP_LOAD,      RA,         CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- ldu
                2     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lwa
		others   => decode_rom_init
        );

        constant decode_op_62_array : minor_rom_array_2_t := (
		--                 unit     internal     in1         in2          in3   out   const const const CR   CR   cry  cry  ldst  BR   sgn  upd  rsrv mul  mul  rc    lk   sgl
		--                                op                                          1     2     3     in   out  in   out  len        ext             32  sgn             pipe
		0     =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- std
		1     =>       (LDST,   OP_STORE,     RA,         CONST_DS,    RS,   NONE, NONE, NONE, NONE, '0', '0', '0', '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stdu
		others   => decode_rom_init
        );

        constant attn_instr    : decode_rom_t := (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1');
	constant nop_instr     : decode_rom_t := (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1');
        constant sim_cfg_instr : decode_rom_t := (ALU,    OP_SIM_CONFIG,NONE,       NONE,        NONE, RT,   NONE, NONE, NONE, '0', '0', '0', '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1');

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
                variable majorop : major_opcode_t;
                variable op_19_bits: std_ulogic_vector(2 downto 0);
                variable op_30_bits: std_ulogic_vector(2 downto 0);
	begin
		v := r;

		v.valid := f_in.valid;
		v.nia  := f_in.nia;
		v.insn := f_in.insn;
		v.stop_mark := f_in.stop_mark;

		ppc_insn := PPC_ILLEGAL;

		if f_in.valid = '1' then
			report "Decode insn " & to_hstring(f_in.insn) & " at " & to_hstring(f_in.nia);
                end if;

                majorop := unsigned(f_in.insn(31 downto 26));
                if majorop = "011111" then
                        -- major opcode 31, lots of things
			if std_match(f_in.insn, "---------------------0100001010-") then
				report "PPC_add";
				ppc_insn := PPC_ADD;
			elsif std_match(f_in.insn, "---------------------0000001010-") then
				report "PPC_addc";
				ppc_insn := PPC_ADDC;
			elsif std_match(f_in.insn, "---------------------0010001010-") then
				report "PPC_adde";
				ppc_insn := PPC_ADDE;
			elsif std_match(f_in.insn, "---------------------0010101010-") then
				report "PPC_addex";
				ppc_insn := PPC_ADDEX;
			elsif std_match(f_in.insn, "---------------------0011101010-") then
				report "PPC_addme";
				ppc_insn := PPC_ADDME;
			elsif std_match(f_in.insn, "---------------------0011001010-") then
				report "PPC_addze";
				ppc_insn := PPC_ADDZE;
			elsif std_match(f_in.insn, "---------------------0000011100-") then
				report "PPC_and";
				ppc_insn := PPC_AND;
			elsif std_match(f_in.insn, "---------------------0000111100-") then
				report "PPC_andc";
				ppc_insn := PPC_ANDC;
			elsif std_match(f_in.insn, "---------------------0011111100-") then
				report "PPC_bperm";
				ppc_insn := PPC_BPERM;
			elsif std_match(f_in.insn, "---------------------0000000000-") then
				report "PPC_cmp";
				ppc_insn := PPC_CMP;
			elsif std_match(f_in.insn, "---------------------0111111100-") then
				report "PPC_cmpb";
				ppc_insn := PPC_CMPB;
			elsif std_match(f_in.insn, "---------------------0011100000-") then
				report "PPC_cmpeqb";
				ppc_insn := PPC_CMPEQB;
			elsif std_match(f_in.insn, "---------------------0000100000-") then
				report "PPC_cmpl";
				ppc_insn := PPC_CMPL;
			elsif std_match(f_in.insn, "---------------------0011000000-") then
				report "PPC_cmprb";
				ppc_insn := PPC_CMPRB;
			elsif std_match(f_in.insn, "---------------------0000111010-") then
				report "PPC_cntlzd";
				ppc_insn := PPC_CNTLZD;
			elsif std_match(f_in.insn, "---------------------0000011010-") then
				report "PPC_cntlzw";
				ppc_insn := PPC_CNTLZW;
			elsif std_match(f_in.insn, "---------------------1000111010-") then
				report "PPC_cnttzd";
				ppc_insn := PPC_CNTTZD;
			elsif std_match(f_in.insn, "---------------------1000011010-") then
				report "PPC_cnttzw";
				ppc_insn := PPC_CNTTZW;
			elsif std_match(f_in.insn, "---------------------1011110011-") then
				report "PPC_darn";
				ppc_insn := PPC_DARN;
			elsif std_match(f_in.insn, "---------------------0001010110-") then
				report "PPC_dcbf";
				ppc_insn := PPC_DCBF;
			elsif std_match(f_in.insn, "---------------------0000110110-") then
				report "PPC_dcbst";
				ppc_insn := PPC_DCBST;
			elsif std_match(f_in.insn, "---------------------0100010110-") then
				report "PPC_dcbt";
				ppc_insn := PPC_DCBT;
			elsif std_match(f_in.insn, "---------------------0011110110-") then
				report "PPC_dcbtst";
				ppc_insn := PPC_DCBTST;
			elsif std_match(f_in.insn, "---------------------1111110110-") then
				report "PPC_dcbz";
				ppc_insn := PPC_DCBZ;
			elsif std_match(f_in.insn, "----------------------11--010-1-") then
				report "PPC_div";
				ppc_insn := PPC_DIV;
			elsif std_match(f_in.insn, "---------------------0100011100-") then
				report "PPC_eqv";
				ppc_insn := PPC_EQV;
			elsif std_match(f_in.insn, "---------------------1110111010-") then
				report "PPC_extsb";
				ppc_insn := PPC_EXTSB;
			elsif std_match(f_in.insn, "---------------------1110011010-") then
				report "PPC_extsh";
				ppc_insn := PPC_EXTSH;
			elsif std_match(f_in.insn, "---------------------1111011010-") then
				report "PPC_extsw";
				ppc_insn := PPC_EXTSW;
			elsif std_match(f_in.insn, "---------------------110111101--") then
				report "PPC_extswsli";
				ppc_insn := PPC_EXTSWSLI;
			elsif std_match(f_in.insn, "---------------------1111010110-") then
				report "PPC_icbi";
				ppc_insn := PPC_ICBI;
			elsif std_match(f_in.insn, "---------------------0000010110-") then
				report "PPC_icbt";
				ppc_insn := PPC_ICBT;
			elsif std_match(f_in.insn, "--------------------------01111-") then
				report "PPC_isel";
				ppc_insn := PPC_ISEL;
			elsif std_match(f_in.insn, "---------------------0000110100-") then
				report "PPC_lbarx";
				ppc_insn := PPC_LBARX;
			elsif std_match(f_in.insn, "---------------------0001110111-") then
				report "PPC_lbzux";
				ppc_insn := PPC_LBZUX;
			elsif std_match(f_in.insn, "---------------------0001010111-") then
				report "PPC_lbzx";
				ppc_insn := PPC_LBZX;
			elsif std_match(f_in.insn, "---------------------0001010100-") then
				report "PPC_ldarx";
				ppc_insn := PPC_LDARX;
			elsif std_match(f_in.insn, "---------------------1000010100-") then
				report "PPC_ldbrx";
				ppc_insn := PPC_LDBRX;
			elsif std_match(f_in.insn, "---------------------0000110101-") then
				report "PPC_ldux";
				ppc_insn := PPC_LDUX;
			elsif std_match(f_in.insn, "---------------------0000010101-") then
				report "PPC_ldx";
				ppc_insn := PPC_LDX;
			elsif std_match(f_in.insn, "---------------------0001110100-") then
				report "PPC_lharx";
				ppc_insn := PPC_LHARX;
			elsif std_match(f_in.insn, "---------------------0101110111-") then
				report "PPC_lhaux";
				ppc_insn := PPC_LHAUX;
			elsif std_match(f_in.insn, "---------------------0101010111-") then
				report "PPC_lhax";
				ppc_insn := PPC_LHAX;
			elsif std_match(f_in.insn, "---------------------1100010110-") then
				report "PPC_lhbrx";
				ppc_insn := PPC_LHBRX;
			elsif std_match(f_in.insn, "---------------------0100110111-") then
				report "PPC_lhzux";
				ppc_insn := PPC_LHZUX;
			elsif std_match(f_in.insn, "---------------------0100010111-") then
				report "PPC_lhzx";
				ppc_insn := PPC_LHZX;
			elsif std_match(f_in.insn, "---------------------0000010100-") then
				report "PPC_lwarx";
				ppc_insn := PPC_LWARX;
			elsif std_match(f_in.insn, "---------------------0101110101-") then
				report "PPC_lwaux";
				ppc_insn := PPC_LWAUX;
			elsif std_match(f_in.insn, "---------------------0101010101-") then
				report "PPC_lwax";
				ppc_insn := PPC_LWAX;
			elsif std_match(f_in.insn, "---------------------1000010110-") then
				report "PPC_lwbrx";
				ppc_insn := PPC_LWBRX;
			elsif std_match(f_in.insn, "---------------------0000110111-") then
				report "PPC_lwzux";
				ppc_insn := PPC_LWZUX;
			elsif std_match(f_in.insn, "---------------------0000010111-") then
				report "PPC_lwzx";
				ppc_insn := PPC_LWZX;
			elsif std_match(f_in.insn, "---------------------1000000000-") then
				report "PPC_mcrxr";
				ppc_insn := PPC_MCRXR;
			elsif std_match(f_in.insn, "---------------------1001000000-") then
				report "PPC_mcrxrx";
				ppc_insn := PPC_MCRXRX;
			elsif std_match(f_in.insn, "-----------0---------0000010011-") then
				report "PPC_mfcr";
				ppc_insn := PPC_MFCR;
			elsif std_match(f_in.insn, "-----------1---------0000010011-") then
				report "PPC_mfocrf";
				ppc_insn := PPC_MFOCRF;
			elsif std_match(f_in.insn, "---------------------0101010011-") then
				report "PPC_mfspr";
				ppc_insn := PPC_MFSPR;
			elsif std_match(f_in.insn, "----------------------1000010-1-") then
				report "PPC_mod";
				ppc_insn := PPC_MOD;
			elsif std_match(f_in.insn, "-----------0---------0010010000-") then
				report "PPC_mtcrf";
				ppc_insn := PPC_MTCRF;
			elsif std_match(f_in.insn, "-----------1---------0010010000-") then
				report "PPC_mtocrf";
				ppc_insn := PPC_MTOCRF;
			elsif std_match(f_in.insn, "---------------------0111010011-") then
				report "PPC_mtspr";
				ppc_insn := PPC_MTSPR;
			elsif std_match(f_in.insn, "----------------------001001001-") then
				report "PPC_mulhd";
				ppc_insn := PPC_MULHD;
			elsif std_match(f_in.insn, "----------------------000001001-") then
				report "PPC_mulhdu";
				ppc_insn := PPC_MULHDU;
			elsif std_match(f_in.insn, "----------------------001001011-") then
				report "PPC_mulhw";
				ppc_insn := PPC_MULHW;
			elsif std_match(f_in.insn, "----------------------000001011-") then
				report "PPC_mulhwu";
				ppc_insn := PPC_MULHWU;
			elsif std_match(f_in.insn, "---------------------0011101001-") then
				report "PPC_mulld";
				ppc_insn := PPC_MULLD;
			elsif std_match(f_in.insn, "---------------------0011101011-") then
				report "PPC_mullw";
				ppc_insn := PPC_MULLW;
			elsif std_match(f_in.insn, "---------------------0111011100-") then
				report "PPC_nand";
				ppc_insn := PPC_NAND;
			elsif std_match(f_in.insn, "---------------------0001101000-") then
				report "PPC_neg";
				ppc_insn := PPC_NEG;
			elsif std_match(f_in.insn, "---------------------0001111100-") then
				report "PPC_nor";
				ppc_insn := PPC_NOR;
			elsif std_match(f_in.insn, "---------------------0110111100-") then
				report "PPC_or";
				ppc_insn := PPC_OR;
			elsif std_match(f_in.insn, "---------------------0110011100-") then
				report "PPC_orc";
				ppc_insn := PPC_ORC;
				-- Has to be before ori
			elsif std_match(f_in.insn, "---------------------0001111010-") then
				report "PPC_popcntb";
				ppc_insn := PPC_POPCNTB;
			elsif std_match(f_in.insn, "---------------------0111111010-") then
				report "PPC_popcntd";
				ppc_insn := PPC_POPCNTD;
			elsif std_match(f_in.insn, "---------------------0101111010-") then
				report "PPC_popcntw";
				ppc_insn := PPC_POPCNTW;
			elsif std_match(f_in.insn, "---------------------0010111010-") then
				report "PPC_prtyd";
				ppc_insn := PPC_PRTYD;
			elsif std_match(f_in.insn, "---------------------0010011010-") then
				report "PPC_prtyw";
				ppc_insn := PPC_PRTYW;
			elsif std_match(f_in.insn, "---------------------0010000000-") then
				report "PPC_setb";
				ppc_insn := PPC_SETB;
			elsif std_match(f_in.insn, "---------------------0000011011-") then
				report "PPC_sld";
				ppc_insn := PPC_SLD;
			elsif std_match(f_in.insn, "---------------------0000011000-") then
				report "PPC_slw";
				ppc_insn := PPC_SLW;
			elsif std_match(f_in.insn, "---------------------1100011010-") then
				report "PPC_srad";
				ppc_insn := PPC_SRAD;
			elsif std_match(f_in.insn, "---------------------110011101--") then
				report "PPC_sradi";
				ppc_insn := PPC_SRADI;
			elsif std_match(f_in.insn, "---------------------1100011000-") then
				report "PPC_sraw";
				ppc_insn := PPC_SRAW;
			elsif std_match(f_in.insn, "---------------------1100111000-") then
				report "PPC_srawi";
				ppc_insn := PPC_SRAWI;
			elsif std_match(f_in.insn, "---------------------1000011011-") then
				report "PPC_srd";
				ppc_insn := PPC_SRD;
			elsif std_match(f_in.insn, "---------------------1000011000-") then
				report "PPC_srw";
				ppc_insn := PPC_SRW;
			elsif std_match(f_in.insn, "---------------------1010110110-") then
				report "PPC_stbcx";
				ppc_insn := PPC_STBCX;
			elsif std_match(f_in.insn, "---------------------0011110111-") then
				report "PPC_stbux";
				ppc_insn := PPC_STBUX;
			elsif std_match(f_in.insn, "---------------------0011010111-") then
				report "PPC_stbx";
				ppc_insn := PPC_STBX;
			elsif std_match(f_in.insn, "---------------------1010010100-") then
				report "PPC_stdbrx";
				ppc_insn := PPC_STDBRX;
			elsif std_match(f_in.insn, "---------------------0011010110-") then
				report "PPC_stdcx";
				ppc_insn := PPC_STDCX;
			elsif std_match(f_in.insn, "---------------------0010110101-") then
				report "PPC_stdux";
				ppc_insn := PPC_STDUX;
			elsif std_match(f_in.insn, "---------------------0010010101-") then
				report "PPC_stdx";
				ppc_insn := PPC_STDX;
			elsif std_match(f_in.insn, "---------------------1110010110-") then
				report "PPC_sthbrx";
				ppc_insn := PPC_STHBRX;
			elsif std_match(f_in.insn, "---------------------1011010110-") then
				report "PPC_sthcx";
				ppc_insn := PPC_STHCX;
			elsif std_match(f_in.insn, "---------------------0110110111-") then
				report "PPC_sthux";
				ppc_insn := PPC_STHUX;
			elsif std_match(f_in.insn, "---------------------0110010111-") then
				report "PPC_sthx";
				ppc_insn := PPC_STHX;
			elsif std_match(f_in.insn, "---------------------1010010110-") then
				report "PPC_stwbrx";
				ppc_insn := PPC_STWBRX;
			elsif std_match(f_in.insn, "---------------------0010010110-") then
				report "PPC_stwcx";
				ppc_insn := PPC_STWCX;
			elsif std_match(f_in.insn, "---------------------0010110111-") then
				report "PPC_stwux";
				ppc_insn := PPC_STWUX;
			elsif std_match(f_in.insn, "---------------------0010010111-") then
				report "PPC_stwx";
				ppc_insn := PPC_STWX;
			elsif std_match(f_in.insn, "---------------------0000101000-") then
				report "PPC_subf";
				ppc_insn := PPC_SUBF;
			elsif std_match(f_in.insn, "---------------------0000001000-") then
				report "PPC_subfc";
				ppc_insn := PPC_SUBFC;
			elsif std_match(f_in.insn, "---------------------0010001000-") then
				report "PPC_subfe";
				ppc_insn := PPC_SUBFE;
			elsif std_match(f_in.insn, "---------------------0011101000-") then
				report "PPC_subfme";
				ppc_insn := PPC_SUBFME;
			elsif std_match(f_in.insn, "---------------------0011001000-") then
				report "PPC_subfze";
				ppc_insn := PPC_SUBFZE;
			elsif std_match(f_in.insn, "---------------------1001010110-") then
				report "PPC_sync";
				ppc_insn := PPC_SYNC;
			elsif std_match(f_in.insn, "---------------------0001000100-") then
				report "PPC_td";
				ppc_insn := PPC_TD;
			elsif std_match(f_in.insn, "---------------------0000000100-") then
				report "PPC_tw";
				ppc_insn := PPC_TW;
			elsif std_match(f_in.insn, "---------------------0100111100-") then
				report "PPC_xor";
				ppc_insn := PPC_XOR;
			else
				report "PPC_illegal";
				ppc_insn := PPC_ILLEGAL;
			end if;
			v.decode := decode_op_31_array(ppc_insn);

                elsif majorop = "010011" then
                        if decode_op_19_valid(to_integer(unsigned(f_in.insn(10 downto 1)))) = '0' then
                                report "op 19 illegal subcode";
                                v.decode := illegal_inst;
                        else
                                op_19_bits := f_in.insn(5) & f_in.insn(3) & f_in.insn(2);
                                v.decode := decode_op_19_array(to_integer(unsigned(op_19_bits)));
                                report "op 19 sub " & to_hstring(op_19_bits);
                        end if;

                elsif majorop = "011110" then
                        v.decode := decode_op_30_array(to_integer(unsigned(f_in.insn(4 downto 2))));

                elsif majorop = "111010" then
                        v.decode := decode_op_58_array(to_integer(unsigned(f_in.insn(1 downto 0))));

                elsif majorop = "111110" then
                        v.decode := decode_op_62_array(to_integer(unsigned(f_in.insn(1 downto 0))));

                elsif std_match(f_in.insn, "01100000000000000000000000000000") then
                        report "PPC_nop";
                        v.decode := nop_instr;
                elsif std_match(f_in.insn, "000001---------------0000000011-") then
                        report "PPC_SIM_CONFIG";
                        v.decode := sim_cfg_instr;
                elsif std_match(f_in.insn, "000000---------------0100000000-") then
                        report "PPC_attn";
                        v.decode := attn_instr;

                else
                        v.decode := major_decode_rom_array(to_integer(majorop));
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
