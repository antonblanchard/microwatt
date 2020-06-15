library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;

entity decode1 is
    port (
        clk       : in std_ulogic;
        rst       : in std_ulogic;

        stall_in  : in  std_ulogic;
        flush_in  : in  std_ulogic;
        busy_out  : out std_ulogic;
        flush_out : out std_ulogic;

        f_in      : in IcacheToDecode1Type;
        f_out     : out Decode1ToFetch1Type;
        d_out     : out Decode1ToDecode2Type;
        log_out   : out std_ulogic_vector(12 downto 0)
	);
end entity decode1;

architecture behaviour of decode1 is
    signal r, rin : Decode1ToDecode2Type;
    signal s      : Decode1ToDecode2Type;

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
        12 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- addic
        13 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0'), -- addic.
        14 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- addi
        15 =>       (ALU,    OP_ADD,       RA_OR_ZERO, CONST_SI_HI, NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- addis
        28 =>       (ALU,    OP_AND,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0'), -- andi.
        29 =>       (ALU,    OP_AND,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0'), -- andis.
        0 =>       (ALU,    OP_ATTN,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- attn
        18 =>       (ALU,    OP_B,         NONE,       CONST_LI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0'), -- b
        16 =>       (ALU,    OP_BC,        SPR,        CONST_BD,    NONE, SPR , '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0'), -- bc
        11 =>       (ALU,    OP_CMP,       RA,         CONST_SI,    NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0'), -- cmpi
        10 =>       (ALU,    OP_CMP,       RA,         CONST_UI,    NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- cmpli
        34 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lbz
        35 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lbzu
        42 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0'), -- lha
        43 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0'), -- lhau
        40 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lhz
        41 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lhzu
        32 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lwz
        33 =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lwzu
        7 =>       (ALU,    OP_MUL_L64,   RA,         CONST_SI,    NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0'), -- mulli
        24 =>       (ALU,    OP_OR,        NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- ori
        25 =>       (ALU,    OP_OR,        NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- oris
        20 =>       (ALU,    OP_RLC,       RA,         CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- rlwimi
        21 =>       (ALU,    OP_RLC,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- rlwinm
        23 =>       (ALU,    OP_RLC,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- rlwnm
        17 =>       (ALU,    OP_SC,        NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- sc
        38 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stb
        39 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stbu
        44 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- sth
        45 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- sthu
        36 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stw
        37 =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stwu
        8 =>       (ALU,    OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- subfic
        2 =>       (ALU,    OP_TRAP,      RA,         CONST_SI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- tdi
        3 =>       (ALU,    OP_TRAP,      RA,         CONST_SI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '1'), -- twi
        26 =>       (ALU,    OP_XOR,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- xori
        27 =>       (ALU,    OP_XOR,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- xoris
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
        2#0100000001# => '1', -- crand
        2#0010000001# => '1', -- crandc
        2#0100100001# => '1', -- creqv
        2#0011100001# => '1', -- crnand
        2#0000100001# => '1', -- crnor
        2#0111000001# => '1', -- cror
        2#0110100001# => '1', -- crorc
        2#0011000001# => '1', -- crxor
        2#0010010110# => '1', -- isync
        2#0000000000# => '1', -- mcrf
        2#0000010010# => '1', -- rfid
        others => '0'
        );

    -- indexed by bits 5, 3, 2 of instruction word
    constant decode_op_19_array : op_19_subop_array_t := (
        --                 unit     internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                               op                                            in   out   A   out  in    out  len        ext                                 pipe
        -- mcrf; and cr logical ops
        2#000#    =>       (ALU,    OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'),
        -- addpcis
        2#001#    =>       (ALU,    OP_ADD,       CIA,        CONST_DXHI4, NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'),
        -- bclr, bcctr, bctar
        2#100#    =>       (ALU,    OP_BCREG,     SPR,        SPR,         NONE, SPR,  '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0'),
        -- isync
        2#111#    =>       (ALU,    OP_ISYNC,     NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'),
        -- rfid
        2#101#    =>       (ALU,    OP_RFID,      SPR,        SPR,         NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'),
        others   => illegal_inst
        );

    constant decode_op_30_array : op_30_subop_array_t := (
        --                 unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                               op                                           in   out   A   out  in    out  len        ext                                pipe
        2#0100#  =>       (ALU,    OP_RLC,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldic
        2#0101#  =>       (ALU,    OP_RLC,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldic
        2#0000#  =>       (ALU,    OP_RLCL,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldicl
        2#0001#  =>       (ALU,    OP_RLCL,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldicl
        2#0010#  =>       (ALU,    OP_RLCR,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldicr
        2#0011#  =>       (ALU,    OP_RLCR,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldicr
        2#0110#  =>       (ALU,    OP_RLC,       RA,         CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldimi
        2#0111#  =>       (ALU,    OP_RLC,       RA,         CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldimi
        2#1000#  =>       (ALU,    OP_RLCL,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldcl
        2#1001#  =>       (ALU,    OP_RLCR,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- rldcr
        others   => illegal_inst
        );

    -- Note: reformat with column -t -o ' '
    constant decode_op_31_array : op_31_subop_array_t := (
        --                       unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                                    op                                            in   out   A   out  in    out  len        ext                                 pipe
        2#0100001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- add
        2#1100001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addo
        2#0000001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addc
        2#1000001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addco
        2#0010001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- adde
        2#1010001010#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addeo
        2#0011101010#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addme
        2#1011101010#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addmeo
        2#0011001010#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addze
        2#1011001010#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- addzeo
        2#0000011100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- and
        2#0000111100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- andc
        -- 2#0011111100# bperm
        2#0000000000#  =>       (ALU,    OP_CMP,       RA,         RB,          NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0'), -- cmp
        2#0111111100#  =>       (ALU,    OP_CMPB,      NONE,       RB,          RS,   RA,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- cmpb
        -- 2#0011100000# cmpeqb
        2#0000100000#  =>       (ALU,    OP_CMP,       RA,         RB,          NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- cmpl
        -- 2#0011000000# cmprb
        2#0000111010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- cntlzd
        2#0000011010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- cntlzw
        2#1000111010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- cnttzd
        2#1000011010#  =>       (ALU,    OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- cnttzw
        -- 2#1011110011# darn
        2#0001010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbf
        2#0000110110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbst
        2#0100010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbt
        2#0011110110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- dcbtst
        2#1111110110#  =>       (LDST,   OP_DCBZ,      RA_OR_ZERO, RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- dcbz
        2#0110001001#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- divdeu
        2#1110001001#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- divdeuo
        2#0110001011#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- divweu
        2#1110001011#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- divweuo
        2#0110101001#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- divde
        2#1110101001#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- divdeo
        2#0110101011#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- divwe
        2#1110101011#  =>       (ALU,    OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- divweo
        2#0111001001#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- divdu
        2#1111001001#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- divduo
        2#0111001011#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- divwu
        2#1111001011#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- divwuo
        2#0111101001#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- divd
        2#1111101001#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- divdo
        2#0111101011#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- divw
        2#1111101011#  =>       (ALU,    OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- divwo
        2#1101010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- eieio
        2#0100011100#  =>       (ALU,    OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- eqv
        2#1110111010#  =>       (ALU,    OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- extsb
        2#1110011010#  =>       (ALU,    OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- extsh
        2#1111011010#  =>       (ALU,    OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- extsw
        2#1101111010#  =>       (ALU,    OP_EXTSWSLI,  NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- extswsli
        2#1101111011#  =>       (ALU,    OP_EXTSWSLI,  NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- extswsli
        2#1111010110#  =>       (ALU,    OP_ICBI,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- icbi
        2#0000010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- icbt
        2#0000001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- isel
        2#0000101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0001001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0001101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0010001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0010101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0011001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0011101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0100001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0100101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0101001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0101101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0110001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0110101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0111001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0111101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1000001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1000101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1001001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1001101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1010001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1010101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1011001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1011101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1100001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1100101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1101001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1101101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1110001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1110101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1111001111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#1111101111#  =>       (ALU,    OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- isel
        2#0000110100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '0'), -- lbarx
        2#1101010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lbzcix
        2#0001110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lbzux
        2#0001010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lbzx
        2#0001010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '0'), -- ldarx
        2#1000010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- ldbrx
        2#1101110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- ldcix
        2#0000110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- ldux
        2#0000010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- ldx
        2#0001110100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '0'), -- lharx
        2#0101110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0'), -- lhaux
        2#0101010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0'), -- lhax
        2#1100010110#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lhbrx
        2#1100110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lhzcix
        2#0100110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lhzux
        2#0100010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lhzx
        2#0000010100#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '0'), -- lwarx
        2#0101110101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '0'), -- lwaux
        2#0101010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0'), -- lwax
        2#1000010110#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lwbrx
        2#1100010101#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lwzcix
        2#0000110111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- lwzux
        2#0000010111#  =>       (LDST,   OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- lwzx
        -- 2#1000000000# mcrxr
        -- 2#1001000000# mcrxrx
        2#0000010011#  =>       (ALU,    OP_MFCR,      NONE,       NONE,        NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- mfcr/mfocrf
        2#0001010011#  =>       (ALU,    OP_MFMSR,     NONE,       NONE,        NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mfmsr
        2#0101010011#  =>       (ALU,    OP_MFSPR,     SPR,        NONE,        RS,   RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- mfspr
        2#0100001001#  =>       (ALU,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- modud
        2#0100001011#  =>       (ALU,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0'), -- moduw
        2#1100001001#  =>       (ALU,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0'), -- modsd
        2#1100001011#  =>       (ALU,    OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', NONE, '0', '0'), -- modsw
        2#0010010000#  =>       (ALU,    OP_MTCRF,     NONE,       NONE,        RS,   NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- mtcrf/mtocrf
        2#0010110010#  =>       (ALU,    OP_MTMSRD,    NONE,       NONE,        RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- mtmsrd # ignore top bits and d
        2#0111010011#  =>       (ALU,    OP_MTSPR,     NONE,       NONE,        RS,   SPR,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- mtspr
        2#0001001001#  =>       (ALU,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- mulhd
        2#0000001001#  =>       (ALU,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- mulhdu
        2#0001001011#  =>       (ALU,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- mulhw
        2#0000001011#  =>       (ALU,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- mulhwu
        -- next 4 have reserved bit set
        2#1001001001#  =>       (ALU,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- mulhd
        2#1000001001#  =>       (ALU,    OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- mulhdu
        2#1001001011#  =>       (ALU,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- mulhw
        2#1000001011#  =>       (ALU,    OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- mulhwu
        2#0011101001#  =>       (ALU,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- mulld
        2#1011101001#  =>       (ALU,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- mulldo
        2#0011101011#  =>       (ALU,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- mullw
        2#1011101011#  =>       (ALU,    OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- mullwo
        2#0111011100#  =>       (ALU,    OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- nand
        2#0001101000#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- neg
        2#1001101000#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- nego
        2#0001111100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- nor
        2#0110111100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- or
        2#0110011100#  =>       (ALU,    OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- orc
        2#0001111010#  =>       (ALU,    OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- popcntb
        2#0111111010#  =>       (ALU,    OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- popcntd
        2#0101111010#  =>       (ALU,    OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- popcntw
        2#0010111010#  =>       (ALU,    OP_PRTY,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- prtyd
        2#0010011010#  =>       (ALU,    OP_PRTY,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- prtyw
        -- 2#0010000000# setb
        2#0111110010#  =>       (LDST,   OP_TLBIE,     NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- slbia
        2#0000011011#  =>       (ALU,    OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- sld
        2#0000011000#  =>       (ALU,    OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- slw
        2#1100011010#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- srad
        2#1100111010#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- sradi
        2#1100111011#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0'), -- sradi
        2#1100011000#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- sraw
        2#1100111000#  =>       (ALU,    OP_SHR,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0'), -- srawi
        2#1000011011#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- srd
        2#1000011000#  =>       (ALU,    OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0'), -- srw
        2#1111010101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stbcix
        2#1010110110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0'), -- stbcx
        2#0011110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stbux
        2#0011010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stbx
        2#1010010100#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stdbrx
        2#1111110101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stdcix
        2#0011010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0'), -- stdcx
        2#0010110101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stdux
        2#0010010101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stdx
        2#1110010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- sthbrx
        2#1110110101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- sthcix
        2#1011010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0'), -- sthcx
        2#0110110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- sthux
        2#0110010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- sthx
        2#1010010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stwbrx
        2#1110010101#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stwcix
        2#0010010110#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0'), -- stwcx
        2#0010110111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stwux
        2#0010010111#  =>       (LDST,   OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- stwx
        2#0000101000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subf
        2#1000101000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfo
        2#0000001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfc
        2#1000001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfco
        2#0010001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfe
        2#1010001000#  =>       (ALU,    OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfeo
        2#0011101000#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfme
        2#1011101000#  =>       (ALU,    OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfmeo
        2#0011001000#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfze
        2#1011001000#  =>       (ALU,    OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- subfzeo
        2#1001010110#  =>       (ALU,    OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- sync
        2#0001000100#  =>       (ALU,    OP_TRAP,      RA,         RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1'), -- td
        2#0000000100#  =>       (ALU,    OP_TRAP,      RA,         RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '1'), -- tw
        2#0100110010#  =>       (LDST,   OP_TLBIE,     NONE,       RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- tlbie
        2#0100010010#  =>       (LDST,   OP_TLBIE,     NONE,       RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- tlbiel
        2#0100111100#  =>       (ALU,    OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0'), -- xor
        others => illegal_inst
	);

    constant decode_op_58_array : minor_rom_array_2_t := (
        --              unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                           op                                            in   out   A   out  in    out  len        ext                                 pipe
        0     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- ld
        1     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- ldu
        2     =>       (LDST,   OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0'), -- lwa
        others   => decode_rom_init
        );

    constant decode_op_62_array : minor_rom_array_2_t := (
        --              unit    internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
        --                            op                                           in   out   A   out  in    out  len        ext                                 pipe
        0     =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0'), -- std
        1     =>       (LDST,   OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0'), -- stdu
        others   => decode_rom_init
        );

    --                                        unit   internal         in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl
    --                                                     op                                              in   out   A   out  in    out  len        ext                                 pipe
    constant nop_instr      : decode_rom_t := (ALU,  OP_NOP,          NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0');
    constant fetch_fail_inst: decode_rom_t := (LDST, OP_FETCH_FAILED, NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0');

    signal log_data : std_ulogic_vector(12 downto 0);

begin
    decode1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r <= Decode1ToDecode2Init;
                s <= Decode1ToDecode2Init;
            elsif flush_in = '1' then
                r.valid <= '0';
                s.valid <= '0';
            elsif s.valid = '1' then
                if stall_in = '0' then
                    r <= s;
                    s.valid <= '0';
                end if;
            else
                s <= rin;
                s.valid <= rin.valid and r.valid and stall_in;
                if r.valid = '0' or stall_in = '0' then
                    r <= rin;
                end if;
            end if;
        end if;
    end process;
    busy_out <= s.valid;

    decode1_1: process(all)
        variable v : Decode1ToDecode2Type;
        variable f : Decode1ToFetch1Type;
        variable majorop : major_opcode_t;
        variable op_19_bits: std_ulogic_vector(2 downto 0);
        variable sprn : spr_num_t;
        variable br_nia    : std_ulogic_vector(61 downto 0);
        variable br_target : std_ulogic_vector(61 downto 0);
        variable br_offset : signed(23 downto 0);
    begin
        v := Decode1ToDecode2Init;

        v.valid := f_in.valid;
        v.nia  := f_in.nia;
        v.insn := f_in.insn;
        v.stop_mark := f_in.stop_mark;
        v.ispr1 := (others => '0');
        v.ispr2 := (others => '0');

        if f_in.valid = '1' then
            report "Decode insn " & to_hstring(f_in.insn) & " at " & to_hstring(f_in.nia);
        end if;

        majorop := unsigned(f_in.insn(31 downto 26));
        if f_in.fetch_failed = '1' then
            v.valid := '1';
            -- Only send down a single OP_FETCH_FAILED
            if r.decode.insn_type = OP_FETCH_FAILED then
                v.valid := '0';
            end if;
            v.decode := fetch_fail_inst;

        elsif majorop = "011111" then
            -- major opcode 31, lots of things
            v.decode := decode_op_31_array(to_integer(unsigned(f_in.insn(10 downto 1))));

            -- Work out ispr1/ispr2 independent of v.decode since they seem to be critical path
            sprn := decode_spr_num(f_in.insn);
            v.ispr1 := fast_spr_num(sprn);

            if std_match(f_in.insn(10 downto 1), "01-1010011") then
                -- mfspr or mtspr
                -- Make slow SPRs single issue
                if is_fast_spr(v.ispr1) = '0' then
                    v.decode.sgl_pipe := '1';
                    -- send MMU-related SPRs to loadstore1
                    case sprn is
                        when SPR_DAR | SPR_DSISR | SPR_PID | SPR_PRTBL =>
                            v.decode.unit := LDST;
                        when others =>
                    end case;
                end if;
            end if;

        elsif majorop = "010000" then
            -- CTR may be needed as input to bc
            v.decode := major_decode_rom_array(to_integer(majorop));
            if f_in.insn(23) = '0' then
                v.ispr1 := fast_spr_num(SPR_CTR);
            end if;

        elsif majorop = "010011" then
            if decode_op_19_valid(to_integer(unsigned(f_in.insn(10 downto 1)))) = '0' then
                report "op 19 illegal subcode";
                v.decode := illegal_inst;
            else
                op_19_bits := f_in.insn(5) & f_in.insn(3) & f_in.insn(2);
                v.decode := decode_op_19_array(to_integer(unsigned(op_19_bits)));
                report "op 19 sub " & to_hstring(op_19_bits);
            end if;

            -- Work out ispr1/ispr2 independent of v.decode since they seem to be critical path
            if f_in.insn(2) = '0' then
                -- Could be OP_BCREG: bclr, bcctr, bctar
                -- Branch uses CTR as condition when BO(2) is 0. This is
                -- also used to indicate that CTR is modified (they go
                -- together).
                if f_in.insn(23) = '0' then
                    v.ispr1 := fast_spr_num(SPR_CTR);
                end if;
                -- TODO: Add TAR
                if f_in.insn(10) = '0' then
                    v.ispr2 := fast_spr_num(SPR_LR);
                else
                    v.ispr2 := fast_spr_num(SPR_CTR);
                end if;
            else
                -- Could be OP_RFID
                v.ispr1 := fast_spr_num(SPR_SRR0);
                v.ispr2 := fast_spr_num(SPR_SRR1);
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

        else
            v.decode := major_decode_rom_array(to_integer(majorop));
        end if;

        -- Branch predictor
        -- Note bclr, bcctr and bctar are predicted not taken as we have no
        -- count cache or link stack.
        br_offset := (others => '0');
        if majorop = 18 then
            -- Unconditional branches are always taken
            v.br_pred := '1';
            br_offset := signed(f_in.insn(25 downto 2));
        elsif majorop = 16 then
            -- Predict backward branches as taken, forward as untaken
            v.br_pred := f_in.insn(15);
            br_offset := resize(signed(f_in.insn(15 downto 2)), 24);
        end if;
        br_nia := f_in.nia(63 downto 2);
        if f_in.insn(1) = '1' then
            br_nia := (others => '0');
        end if;
        br_target := std_ulogic_vector(signed(br_nia) + br_offset);
        f.redirect := v.br_pred and f_in.valid and not flush_in and not s.valid;
        f.redirect_nia := br_target & "00";

        -- Update registers
        rin <= v;

        -- Update outputs
        d_out <= r;
        f_out <= f;
        flush_out <= f.redirect;
    end process;

    dec1_log : process(clk)
    begin
        if rising_edge(clk) then
            log_data <= std_ulogic_vector(to_unsigned(insn_type_t'pos(r.decode.insn_type), 6)) &
                        r.nia(5 downto 2) &
                        std_ulogic_vector(to_unsigned(unit_t'pos(r.decode.unit), 2)) &
                        r.valid;
        end if;
    end process;
    log_out <= log_data;

end architecture behaviour;
