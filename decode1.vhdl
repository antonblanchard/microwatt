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
        type op_30_subop_array_t is array(0 to 15) of decode_rom_t;
        type op_31_subop_array_t is array(0 to 1023) of decode_rom_t;
        type minor_rom_array_2_t is array(0 to 3) of decode_rom_t;

        constant illegal_inst : decode_rom_t :=
                            (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1');

        constant major_decode_rom_array : major_rom_array_t := (
		--          unit     internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                        op                                            in   out   A   out  in    out  len        ext                                 pipe
		12 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addic
		13 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- addic.
                14 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addi
		15 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI_HI, NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- addis
		28 =>       (ALU,    OP_AND,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- andi.
		29 =>       (ALU,    OP_AND,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '1'), -- andis.
		18 =>       (ALU,    OP_B,         NONE,       CONST_LI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'), -- b
		16 =>       (ALU,    OP_BC,        NONE,       CONST_BD,    NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'), -- bc
		11 =>       (ALU,    OP_CMP,       RA,         CONST_SI,    NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpi
		10 =>       (ALU,    OP_CMPL,      RA,         CONST_UI,    NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpli
		34 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lbz
		35 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lbzu
		42 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lha
		43 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'), -- lhau
		40 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lhz
		41 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lhzu
		32 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lwz
                33 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lwzu
		 7 =>       (MUL,    OP_MUL_L64,   RA,         CONST_SI,    NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '1'), -- mulli
		24 =>       (ALU,    OP_OR,        NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ori
		25 =>       (ALU,    OP_OR,        NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- oris
		20 =>       (ALU,    OP_RLC,       RA,         CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- rlwimi
		21 =>       (ALU,    OP_RLC,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- rlwinm
		23 =>       (ALU,    OP_RLC,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- rlwnm
		38 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- stb
		39 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'), -- stbu
		44 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sth
		45 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- sthu
		36 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stw
		37 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stwu
		 8 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- subfic
		 2 =>       (ALU,    OP_TDI,       RA,         CONST_SI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- tdi
		--PPC_TWI 3
		26 =>       (ALU,    OP_XOR,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- xori
		27 =>       (ALU,    OP_XOR,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- xoris
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
		--                 unit     internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                               op                                            in   out   A   out  in    out  len        ext                                 pipe
                -- mcrf; cr logical ops not implemented yet
		2#000#    =>       (ALU,    OP_MCRF,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		-- addpcis not implemented yet
		2#001#    =>       (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'),
                -- bclr, bcctr, bctar
		2#100#    =>       (ALU,    OP_BCREG,     NONE,       NONE,        NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '1'),
                -- isync
		2#111#    =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
		others   => illegal_inst
        );

	constant decode_op_30_array : op_30_subop_array_t := (
		--                 unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                               op                                           in   out   A   out  in    out  len        ext                                pipe
		2#0100#  =>       (ALU,    OP_RLC,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldic
		2#0101#  =>       (ALU,    OP_RLC,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldic
		2#0000#  =>       (ALU,    OP_RLCL,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldicl
		2#0001#  =>       (ALU,    OP_RLCL,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldicl
		2#0010#  =>       (ALU,    OP_RLCR,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldicr
		2#0011#  =>       (ALU,    OP_RLCR,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldicr
		2#0110#  =>       (ALU,    OP_RLC,       RA,         CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldimi
		2#0111#  =>       (ALU,    OP_RLC,       RA,         CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldimi
		2#1000#  =>       (ALU,    OP_RLCL,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldcl
		2#1001#  =>       (ALU,    OP_RLCR,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- rldcr
		others   => illegal_inst
        );

	-- Note: reformat with column -t -o ' '
	constant decode_op_31_array : op_31_subop_array_t := (
		--                       unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                                    op                                            in   out   A   out  in    out  len        ext                                 pipe
		2#0100001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- add
		2#0000001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- addc
		2#0010001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- adde
		2#0011101010#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- addme
		2#0011001010#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- addze
		2#0000011100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- and
		2#0000111100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- andc
		-- 2#0011111100# bperm
		2#0000000000#  =>       (ALU,    OP_CMP,       RA,         RB,          NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmp
		2#0111111100#  =>       (ALU,    OP_CMPB,      NONE,       RB,          RS,   RA,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpb
		-- 2#0011100000# cmpeqb
		2#0000100000#  =>       (ALU,    OP_CMPL,      RA,         RB,          NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- cmpl
		-- 2#0011000000# cmprb
		2#0000111010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- cntlzd
		2#0000011010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- cntlzw
		2#1000111010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- cnttzd
		2#1000011010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- cnttzw
		-- 2#1011110011# darn
		2#0001010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbf
		2#0000110110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbst
		2#0100010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbt
		2#0011110110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbtst
		-- 2#1111110110# dcbz
		2#0110001001#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divdeu
		2#0110001011#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divweu
		2#0110101001#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divde
		2#0110101011#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divwe
		2#0111001001#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divdu
		2#0111001011#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divwu
		2#0111101001#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divd
		2#0111101011#  =>       (DIV,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- divw
		2#0100011100#  =>       (ALU,    OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- eqv
		2#1110111010#  =>       (ALU,    OP_EXTSB,     NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- extsb
		2#1110011010#  =>       (ALU,    OP_EXTSH,     NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- extsh
		2#1111011010#  =>       (ALU,    OP_EXTSW,     NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- extsw
		-- 2#110111101-# extswsli
		2#1111010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- icbi
		2#0000010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- icbt
		2#0000001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0000101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0001001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0001101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0010001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0010101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0011001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0011101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0100001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0100101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0101001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0101101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0110001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0110101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0111001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0111101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1000001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1000101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1001001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1001101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1010001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1010101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1011001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1011101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1100001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1100101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1101001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1101101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1110001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1110101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1111001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#1111101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
		2#0000110100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- lbarx
		2#0001110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lbzux
		2#0001010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lbzx
		2#0001010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- ldarx
		2#1000010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ldbrx
		2#0000110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- ldux
		2#0000010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ldx
		2#0001110100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- lharx
		2#0101110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'), -- lhaux
		2#0101010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lhax
		2#1100010110#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lhbrx
		2#0100110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lhzux
		2#0100010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lhzx
		2#0000010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- lwarx
		2#0101110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '1'), -- lwaux
		2#0101010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lwax
		2#1000010110#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lwbrx
		2#0000110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- lwzux
		2#0000010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- lwzx
		-- 2#1000000000# mcrxr
		-- 2#1001000000# mcrxrx
		2#0000010011#  =>       (ALU,    OP_MFCR,      NONE,       NONE,        NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mfcr/mfocrf
		2#0101010011#  =>       (ALU,    OP_MFSPR,     NONE,       NONE,        NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mfspr
		2#0100001001#  =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- modud
		2#0100001011#  =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- moduw
		2#1100001001#  =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- modsd
		2#1100001011#  =>       (DIV,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- modsw
		2#0010010000#  =>       (ALU,    OP_MTCRF,     NONE,       NONE,        RS,   NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mtcrf/mtocrf
		2#0111010011#  =>       (ALU,    OP_MTSPR,     NONE,       NONE,        RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mtspr
		2#0001001001#  =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- mulhd
		2#0000001001#  =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- mulhdu
		2#0001001011#  =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'), -- mulhw
		2#0000001011#  =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- mulhwu
                -- next 4 have reserved bit set
		2#1001001001#  =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- mulhd
		2#1000001001#  =>       (MUL,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- mulhdu
		2#1001001011#  =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'), -- mulhw
		2#1000001011#  =>       (MUL,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- mulhwu
		2#0011101001#  =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- mulld
		2#0011101011#  =>       (MUL,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'), -- mullw
		2#0111011100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- nand
		2#0001101000#  =>       (ALU,    OP_NEG,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- neg
		2#0001111100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- nor
		2#0110111100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- or
		2#0110011100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- orc
		2#0001111010#  =>       (ALU,    OP_POPCNTB,   NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- popcntb
		2#0111111010#  =>       (ALU,    OP_POPCNTD,   NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- popcntd
		2#0101111010#  =>       (ALU,    OP_POPCNTW,   NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- popcntw
		2#0010111010#  =>       (ALU,    OP_PRTYD,     NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- prtyd
		2#0010011010#  =>       (ALU,    OP_PRTYW,     NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- prtyw
		-- 2#0010000000# setb
		2#0000011011#  =>       (ALU,    OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- sld
		2#0000011000#  =>       (ALU,    OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- slw
		2#1100011010#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- srad
		2#1100111010#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- sradi
		2#1100111011#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '1'), -- sradi
		2#1100011000#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'), -- sraw
		2#1100111000#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '1'), -- srawi
		2#1000011011#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- srd
		2#1000011000#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '1'), -- srw
		2#1010110110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', RC,   '0', '1'), -- stbcx
		2#0011110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', RC,   '0', '1'), -- stbux
		2#0011010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- stbx
		2#1010010100#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stdbrx
		2#0011010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- stdcx
		2#0010110101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stdux
		2#0010010101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stdx
		2#1110010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sthbrx
		2#1011010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- sthcx
		2#0110110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- sthux
		2#0110010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sthx
		2#1010010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stwbrx
		2#0010010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '1'), -- stwcx
		2#0010110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stwux
		2#0010010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- stwx
		2#0000101000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- subf
		2#0000001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- subfc
		2#0010001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- subfe
		2#0011101000#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- subfme
		2#0011001000#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- subfze
		2#1001010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sync
		-- 2#0001000100# td
		2#0000000100#  =>       (ALU,    OP_TW,        RA,         RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- tw
		2#0100111100#  =>       (ALU,    OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1'), -- xor
		others => illegal_inst
	);

        constant decode_op_58_array : minor_rom_array_2_t := (
		--              unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                           op                                            in   out   A   out  in    out  len        ext                                 pipe
		0     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- ld
                1     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- ldu
                2     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '1'), -- lwa
		others   => decode_rom_init
        );

        constant decode_op_62_array : minor_rom_array_2_t := (
		--              unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
		--                            op                                           in   out   A   out  in    out  len        ext                                 pipe
		0     =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- std
		1     =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '1'), -- stdu
		others   => decode_rom_init
        );

        --                                       unit     internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                                                      op                                           in   out   A   out  in    out  len        ext                                 pipe
        constant attn_instr    : decode_rom_t := (ALU,    OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '1');
	constant nop_instr     : decode_rom_t := (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1');
        constant sim_cfg_instr : decode_rom_t := (ALU,    OP_SIM_CONFIG,NONE,       NONE,        NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1');

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
                variable majorop : major_opcode_t;
                variable op_19_bits: std_ulogic_vector(2 downto 0);
	begin
		v := r;

		v.valid := f_in.valid;
		v.nia  := f_in.nia;
		v.insn := f_in.insn;
		v.stop_mark := f_in.stop_mark;

		if f_in.valid = '1' then
			report "Decode insn " & to_hstring(f_in.insn) & " at " & to_hstring(f_in.nia);
                end if;

                majorop := unsigned(f_in.insn(31 downto 26));
                if majorop = "011111" then
                        -- major opcode 31, lots of things
                        v.decode := decode_op_31_array(to_integer(unsigned(f_in.insn(10 downto 1))));

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
                        v.decode := decode_op_30_array(to_integer(unsigned(f_in.insn(4 downto 1))));

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
