library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;
use work.insn_helpers.all;

entity decode1 is
    generic (
        HAS_FPU : boolean := true;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
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
        r_out     : out Decode1ToRegisterFileType;
        log_out   : out std_ulogic_vector(12 downto 0)
	);
end entity decode1;

architecture behaviour of decode1 is
    signal r, rin : Decode1ToDecode2Type;
    signal f, fin : Decode1ToFetch1Type;

    type br_predictor_t is record
        br_nia    : std_ulogic_vector(61 downto 0);
        br_offset : signed(23 downto 0);
        predict   : std_ulogic;
    end record;

    signal br, br_in : br_predictor_t;

    signal decode_rom_addr : insn_code;
    signal decode : decode_rom_t;

    signal fetch_failed : std_ulogic;

    -- If we have an FPU, then it is used for integer divisions,
    -- otherwise a dedicated divider in the ALU is used.
    function divider_unit(hf : boolean) return unit_t is
    begin
        if hf then
            return FPU;
        else
            return ALU;
        end if;
    end;
    constant DVU : unit_t := divider_unit(HAS_FPU);

    type decoder_rom_t is array(insn_code) of decode_rom_t;

    constant decode_rom : decoder_rom_t := (
        --                   unit   fac   internal      in1         in2          in3   out   CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   sgl  rpt
        --                                     op                                            in   out   A   out  in    out  len        ext                                 pipe
        INSN_illegal     =>  (NONE, NONE, OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_fetch_fail  =>  (LDST, NONE, OP_FETCH_FAILED, CIA,     NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),

        INSN_add         =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_addc        =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_adde        =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_addex       =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', OV,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_addg6s      =>  (ALU,  NONE, OP_ADDG6S,    RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_addi        =>  (ALU,  NONE, OP_ADD,       RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_addic       =>  (ALU,  NONE, OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_addic_dot   =>  (ALU,  NONE, OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', NONE),
        INSN_addis       =>  (ALU,  NONE, OP_ADD,       RA_OR_ZERO, CONST_SI_HI, NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_addme       =>  (ALU,  NONE, OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_addpcis     =>  (ALU,  NONE, OP_ADD,       CIA,        CONST_DXHI4, NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_addze       =>  (ALU,  NONE, OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_and         =>  (ALU,  NONE, OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_andc        =>  (ALU,  NONE, OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_andi_dot    =>  (ALU,  NONE, OP_AND,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', NONE),
        INSN_andis_dot   =>  (ALU,  NONE, OP_AND,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', NONE),
        INSN_attn        =>  (ALU,  NONE, OP_ATTN,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', NONE),
        INSN_b           =>  (ALU,  NONE, OP_B,         NONE,       CONST_LI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', NONE),
        INSN_bc          =>  (ALU,  NONE, OP_BC,        NONE,       CONST_BD,    NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', NONE),
        INSN_bcctr       =>  (ALU,  NONE, OP_BCREG,     NONE,       NONE,        NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', NONE),
        INSN_bclr        =>  (ALU,  NONE, OP_BCREG,     NONE,       NONE,        NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', NONE),
        INSN_bctar       =>  (ALU,  NONE, OP_BCREG,     NONE,       NONE,        NONE, NONE, '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', NONE),
        INSN_bperm       =>  (ALU,  NONE, OP_BPERM,     NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cbcdtd      =>  (ALU,  NONE, OP_BCD,       NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cdtbcd      =>  (ALU,  NONE, OP_BCD,       NONE,       NONE,        RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cmp         =>  (ALU,  NONE, OP_CMP,       RA,         RB,          NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_cmpb        =>  (ALU,  NONE, OP_CMPB,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cmpeqb      =>  (ALU,  NONE, OP_CMPEQB,    RA,         RB,          NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cmpi        =>  (ALU,  NONE, OP_CMP,       RA,         CONST_SI,    NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_cmpl        =>  (ALU,  NONE, OP_CMP,       RA,         RB,          NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cmpli       =>  (ALU,  NONE, OP_CMP,       RA,         CONST_UI,    NONE, NONE, '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cmprb       =>  (ALU,  NONE, OP_CMPRB,     RA,         RB,          NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cntlzd      =>  (ALU,  NONE, OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_cntlzw      =>  (ALU,  NONE, OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_cnttzd      =>  (ALU,  NONE, OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_cnttzw      =>  (ALU,  NONE, OP_CNTZ,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_crand       =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_crandc      =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_creqv       =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_crnand      =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_crnor       =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_cror        =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_crorc       =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_crxor       =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_darn        =>  (ALU,  NONE, OP_DARN,      NONE,       NONE,        NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_dcbf        =>  (ALU,  NONE, OP_DCBF,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_dcbst       =>  (ALU,  NONE, OP_DCBST,     NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_dcbt        =>  (ALU,  NONE, OP_DCBT,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_dcbtst      =>  (ALU,  NONE, OP_DCBTST,    NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_dcbz        =>  (LDST, NONE, OP_DCBZ,      RA_OR_ZERO, RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_divd        =>  (DVU,  NONE, OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', NONE),
        INSN_divde       =>  (DVU,  NONE, OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', NONE),
        INSN_divdeu      =>  (DVU,  NONE, OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_divdu       =>  (DVU,  NONE, OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_divw        =>  (DVU,  NONE, OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', NONE),
        INSN_divwe       =>  (DVU,  NONE, OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', NONE),
        INSN_divweu      =>  (DVU,  NONE, OP_DIVE,      RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RCOE, '0', '0', NONE),
        INSN_divwu       =>  (DVU,  NONE, OP_DIV,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RCOE, '0', '0', NONE),
        INSN_eieio       =>  (ALU,  NONE, OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_eqv         =>  (ALU,  NONE, OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_extsb       =>  (ALU,  NONE, OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_extsh       =>  (ALU,  NONE, OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_extsw       =>  (ALU,  NONE, OP_EXTS,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_extswsli    =>  (ALU,  NONE, OP_EXTSWSLI,  NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fabs        =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fadd        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fadds       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fcfid       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fcfids      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fcfidu      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fcfidus     =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fcmpo       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB,         NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_fcmpu       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB,         NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_fcpsgn      =>  (FPU,  FPU,  OP_FP_MOVE,   FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctid       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctidu      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctiduz     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctidz      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctiw       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctiwu      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctiwuz     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fctiwz      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fdiv        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fdivs       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fmadd       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fmadds      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fmr         =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fmrgew      =>  (FPU,  FPU,  OP_FP_MISC,   FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_fmrgow      =>  (FPU,  FPU,  OP_FP_MISC,   FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_fmsub       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fmsubs      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fmul        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        NONE,        FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fmuls       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        NONE,        FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fnabs       =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fneg        =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fnmadd      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fnmadds     =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fnmsub      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fnmsubs     =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fre         =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fres        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_frim        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_frin        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_frip        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_friz        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_frsp        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_frsqrte     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_frsqrtes    =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fsel        =>  (FPU,  FPU,  OP_FP_MOVE,   FRA,        FRB,         FRC,  FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fsqrt       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fsqrts      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_fsub        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_fsubs       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_ftdiv       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB,         NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_ftsqrt      =>  (FPU,  FPU,  OP_FP_CMP,    NONE,       FRB,         NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_icbi        =>  (ALU,  NONE, OP_ICBI,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', NONE),
        INSN_icbt        =>  (ALU,  NONE, OP_ICBT,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', NONE),
        INSN_isel        =>  (ALU,  NONE, OP_ISEL,      RA_OR_ZERO, RB,          NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_isync       =>  (ALU,  NONE, OP_ISYNC,     NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lbarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', NONE),
        INSN_lbz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lbzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '1', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lbzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lbzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lbzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_ld          =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_ldarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', NONE),
        INSN_ldbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_ldcix       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '1', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_ldu         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_ldux        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_ldx         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lfd         =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lfdu        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lfdux       =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lfdx        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lfiwax      =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lfiwzx      =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lfs         =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_lfsu        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', DUPD),
        INSN_lfsux       =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', DUPD),
        INSN_lfsx        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,          NONE, FRT,  '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_lha         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lharx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', NONE),
        INSN_lhau        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lhaux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lhax        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lhbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lhz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lhzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '1', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lhzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lhzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lhzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwa         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_DS,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', NONE),
        INSN_lwaux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lwax        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '1', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_lwzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lwzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', DUPD),
        INSN_lwzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_maddhd      =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,          RCR,  RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_maddhdu     =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,          RCR,  RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_maddld      =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,          RCR,  RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_mcrf        =>  (ALU,  NONE, OP_CROP,      NONE,       NONE,        NONE, NONE, '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mcrfs       =>  (FPU,  FPU,  OP_FP_CMP,    NONE,       NONE,        NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mcrxrx      =>  (ALU,  NONE, OP_MCRXRX,    NONE,       NONE,        NONE, NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mfcr        =>  (ALU,  NONE, OP_MFCR,      NONE,       NONE,        NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mffs        =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, FRT,  '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_mfmsr       =>  (ALU,  NONE, OP_MFMSR,     NONE,       NONE,        NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', NONE),
        INSN_mfspr       =>  (ALU,  NONE, OP_MFSPR,     NONE,       NONE,        RS,   RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_modsd       =>  (DVU,  NONE, OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_modsw       =>  (DVU,  NONE, OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', NONE, '0', '0', NONE),
        INSN_modud       =>  (DVU,  NONE, OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_moduw       =>  (DVU,  NONE, OP_MOD,       RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_mtcrf       =>  (ALU,  NONE, OP_MTCRF,     NONE,       NONE,        RS,   NONE, '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mtfsb       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_mtfsf       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,         NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_mtfsfi      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_mtmsr       =>  (ALU,  NONE, OP_MTMSRD,    NONE,       NONE,        RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_mtmsrd      =>  (ALU,  NONE, OP_MTMSRD,    NONE,       NONE,        RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mtspr       =>  (ALU,  NONE, OP_MTSPR,     NONE,       NONE,        RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_mulhd       =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', NONE),
        INSN_mulhdu      =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_mulhw       =>  (ALU,  NONE, OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', NONE),
        INSN_mulhwu      =>  (ALU,  NONE, OP_MUL_H32,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_mulld       =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', NONE),
        INSN_mulli       =>  (ALU,  NONE, OP_MUL_L64,   RA,         CONST_SI,    NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', NONE),
        INSN_mullw       =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,          NONE, RT,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', NONE),
        INSN_nand        =>  (ALU,  NONE, OP_AND,       NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_neg         =>  (ALU,  NONE, OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_nop         =>  (ALU,  NONE, OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_nor         =>  (ALU,  NONE, OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_or          =>  (ALU,  NONE, OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_orc         =>  (ALU,  NONE, OP_OR,        NONE,       RB,          RS,   RA,   '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_ori         =>  (ALU,  NONE, OP_OR,        NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_oris        =>  (ALU,  NONE, OP_OR,        NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_popcntb     =>  (ALU,  NONE, OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_popcntd     =>  (ALU,  NONE, OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_popcntw     =>  (ALU,  NONE, OP_POPCNT,    NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_prtyd       =>  (ALU,  NONE, OP_PRTY,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_prtyw       =>  (ALU,  NONE, OP_PRTY,      NONE,       NONE,        RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_rfid        =>  (ALU,  NONE, OP_RFID,      NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_rldcl       =>  (ALU,  NONE, OP_RLCL,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rldcr       =>  (ALU,  NONE, OP_RLCR,      NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rldic       =>  (ALU,  NONE, OP_RLC,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rldicl      =>  (ALU,  NONE, OP_RLCL,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rldicr      =>  (ALU,  NONE, OP_RLCR,      NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rldimi      =>  (ALU,  NONE, OP_RLC,       RA,         CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_rlwimi      =>  (ALU,  NONE, OP_RLC,       RA,         CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_rlwinm      =>  (ALU,  NONE, OP_RLC,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_rlwnm       =>  (ALU,  NONE, OP_RLC,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_sc          =>  (ALU,  NONE, OP_SC,        NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_setb        =>  (ALU,  NONE, OP_SETB,      NONE,       NONE,        NONE, RT,   '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_slbia       =>  (LDST, NONE, OP_TLBIE,     NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sld         =>  (ALU,  NONE, OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_slw         =>  (ALU,  NONE, OP_SHL,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_srad        =>  (ALU,  NONE, OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', NONE),
        INSN_sradi       =>  (ALU,  NONE, OP_SHR,       NONE,       CONST_SH,    RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', NONE),
        INSN_sraw        =>  (ALU,  NONE, OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', NONE),
        INSN_srawi       =>  (ALU,  NONE, OP_SHR,       NONE,       CONST_SH32,  RS,   RA,   '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', NONE),
        INSN_srd         =>  (ALU,  NONE, OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_srw         =>  (ALU,  NONE, OP_SHR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', NONE),
        INSN_stb         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stbcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '1', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stbcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', NONE),
        INSN_stbu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stbux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stbx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_std         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stdbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stdcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '1', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stdcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', NONE),
        INSN_stdu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_DS,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stdux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stdx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfd        =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, CONST_SI,    FRS,  NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfdu       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, CONST_SI,    FRS,  RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfdux      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,          FRS,  RA,   '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfdx       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,          FRS,  NONE, '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfiwx      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,          FRS,  NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stfs        =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, CONST_SI,    FRS,  NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_stfsu       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, CONST_SI,    FRS,  RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_stfsux      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,          FRS,  RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_stfsx       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,          FRS,  NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_sth         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sthbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sthcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '1', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sthcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', NONE),
        INSN_sthu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sthux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_sthx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stw         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stwbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stwcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '1', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stwcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', NONE),
        INSN_stwu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, CONST_SI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stwux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_stwx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_subf        =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_subfc       =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_subfe       =>  (ALU,  NONE, OP_ADD,       RA,         RB,          NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_subfic      =>  (ALU,  NONE, OP_ADD,       RA,         CONST_SI,    NONE, RT,   '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_subfme      =>  (ALU,  NONE, OP_ADD,       RA,         CONST_M1,    NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_subfze      =>  (ALU,  NONE, OP_ADD,       RA,         NONE,        NONE, RT,   '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', NONE),
        INSN_sync        =>  (ALU,  NONE, OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_td          =>  (ALU,  NONE, OP_TRAP,      RA,         RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_tdi         =>  (ALU,  NONE, OP_TRAP,      RA,         CONST_SI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_tlbie       =>  (LDST, NONE, OP_TLBIE,     NONE,       RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_tlbiel      =>  (LDST, NONE, OP_TLBIE,     NONE,       RB,          RS,   NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_tlbsync     =>  (ALU,  NONE, OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_tw          =>  (ALU,  NONE, OP_TRAP,      RA,         RB,          NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_twi         =>  (ALU,  NONE, OP_TRAP,      RA,         CONST_SI,    NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', NONE),
        INSN_wait        =>  (ALU,  NONE, OP_NOP,       NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_xor         =>  (ALU,  NONE, OP_XOR,       NONE,       RB,          RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', NONE),
        INSN_xori        =>  (ALU,  NONE, OP_XOR,       NONE,       CONST_UI,    RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),
        INSN_xoris       =>  (ALU,  NONE, OP_XOR,       NONE,       CONST_UI_HI, RS,   RA,   '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE),

        others           =>  (NONE, NONE, OP_ILLEGAL,   NONE,       NONE,        NONE, NONE, '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', NONE)
        );

    function decode_ram_spr(sprn : spr_num_t) return ram_spr_info is
        variable ret : ram_spr_info;
    begin
        ret := (index => (others => '0'), isodd => '0', valid => '1');
        case sprn is
            when SPR_LR =>
                ret.index := RAMSPR_LR;
            when SPR_CTR =>
                ret.index := RAMSPR_CTR;
                ret.isodd := '1';
            when SPR_TAR =>
                ret.index := RAMSPR_TAR;
            when SPR_SRR0 =>
                ret.index := RAMSPR_SRR0;
            when SPR_SRR1 =>
                ret.index := RAMSPR_SRR1;
                ret.isodd := '1';
            when SPR_HSRR0 =>
                ret.index := RAMSPR_HSRR0;
            when SPR_HSRR1 =>
                ret.index := RAMSPR_HSRR1;
                ret.isodd := '1';
            when SPR_SPRG0 =>
                ret.index := RAMSPR_SPRG0;
            when SPR_SPRG1 =>
                ret.index := RAMSPR_SPRG1;
                ret.isodd := '1';
            when SPR_SPRG2 =>
                ret.index := RAMSPR_SPRG2;
            when SPR_SPRG3 | SPR_SPRG3U =>
                ret.index := RAMSPR_SPRG3;
                ret.isodd := '1';
            when SPR_HSPRG0 =>
                ret.index := RAMSPR_HSPRG0;
            when SPR_HSPRG1 =>
                ret.index := RAMSPR_HSPRG1;
                ret.isodd := '1';
            when others =>
                ret.valid := '0';
        end case;
        return ret;
    end;

    function map_spr(sprn : spr_num_t) return spr_id is
        variable i : spr_id;
    begin
        i.sel := "000";
        i.valid := '1';
        i.ispmu := '0';
        case sprn is
            when SPR_TB =>
                i.sel := SPRSEL_TB;
            when SPR_TBU =>
                i.sel := SPRSEL_TBU;
            when SPR_DEC =>
                i.sel := SPRSEL_DEC;
            when SPR_PVR =>
                i.sel := SPRSEL_PVR;
            when 724 =>     -- LOG_ADDR SPR
                i.sel := SPRSEL_LOGA;
            when 725 =>     -- LOG_DATA SPR
                i.sel := SPRSEL_LOGD;
            when SPR_UPMC1 | SPR_UPMC2 | SPR_UPMC3 | SPR_UPMC4 | SPR_UPMC5 | SPR_UPMC6 |
                SPR_UMMCR0 | SPR_UMMCR1 | SPR_UMMCR2 | SPR_UMMCRA | SPR_USIER | SPR_USIAR | SPR_USDAR |
                SPR_PMC1 | SPR_PMC2 | SPR_PMC3 | SPR_PMC4 | SPR_PMC5 | SPR_PMC6 |
                SPR_MMCR0 | SPR_MMCR1 | SPR_MMCR2 | SPR_MMCRA | SPR_SIER | SPR_SIAR | SPR_SDAR =>
                i.ispmu := '1';
            when SPR_CFAR =>
                i.sel := SPRSEL_CFAR;
            when SPR_XER =>
                i.sel := SPRSEL_XER;
            when others =>
                i.valid := '0';
        end case;
        return i;
    end;

begin
    decode1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r <= Decode1ToDecode2Init;
                fetch_failed <= '0';
            elsif flush_in = '1' then
                r.valid <= '0';
                fetch_failed <= '0';
            elsif stall_in = '0' then
                r <= rin;
                fetch_failed <= f_in.fetch_failed;
            end if;
            if rst = '1' then
                br.br_nia <= (others => '0');
                br.br_offset <= (others => '0');
                br.predict <= '0';
            else
                br <= br_in;
            end if;
        end if;
    end process;

    busy_out <= stall_in;

    decode1_rom: process(clk)
    begin
        if rising_edge(clk) then
            if stall_in = '0' then
                decode <= decode_rom(decode_rom_addr);
            end if;
        end if;
    end process;

    decode1_1: process(all)
        variable v : Decode1ToDecode2Type;
        variable vr : Decode1ToRegisterFileType;
        variable br_target : std_ulogic_vector(61 downto 0);
        variable br_offset : signed(23 downto 0);
        variable bv : br_predictor_t;
        variable icode : insn_code;
        variable sprn : spr_num_t;
        variable maybe_rb : std_ulogic;
    begin
        v := Decode1ToDecode2Init;

        v.valid := f_in.valid;
        v.nia  := f_in.nia;
        v.insn := f_in.insn;
        v.stop_mark := f_in.stop_mark;
        v.big_endian := f_in.big_endian;

	if is_X(f_in.insn) then
	    v.spr_info := (sel => "XXX", others => 'X');
	    v.ram_spr := (index => (others => 'X'), others => 'X');
	else
            sprn := decode_spr_num(f_in.insn);
            v.spr_info := map_spr(sprn);
            v.ram_spr := decode_ram_spr(sprn);
        end if;

        icode := f_in.icode;

        if f_in.fetch_failed = '1' then
            icode := INSN_fetch_fail;
            -- Only send down a single OP_FETCH_FAILED
            v.valid := not fetch_failed;
        end if;
        decode_rom_addr <= icode;

        if f_in.valid = '1' then
            report "Decode " & insn_code'image(icode) & " " & to_hstring(f_in.insn) &
                " at " & to_hstring(f_in.nia);
        end if;

        -- Branch predictor
        -- Note bclr, bcctr and bctar not predicted as we have no
        -- count cache or link stack.
        br_offset := (others => '0');
        case icode is
            when INSN_b =>
                -- Unconditional branches are always taken
                v.br_pred := '1';
                br_offset := signed(f_in.insn(25 downto 2));
            when INSN_bc =>
                -- Predict backward branches as taken, forward as untaken
                v.br_pred := f_in.insn(15);
                br_offset := resize(signed(f_in.insn(15 downto 2)), 24);
            when others =>
        end case;
        bv.br_nia := f_in.nia(63 downto 2);
        if f_in.insn(1) = '1' then
            bv.br_nia := (others => '0');
        end if;
        bv.br_offset := br_offset;
        if f_in.next_predicted = '1' then
            v.br_pred := '1';
        elsif f_in.next_pred_ntaken = '1' then
            v.br_pred := '0';
        end if;
        bv.predict := v.br_pred and f_in.valid and not flush_in and not busy_out and not f_in.next_predicted;
        -- after a clock edge...
        br_target := std_ulogic_vector(signed(br.br_nia) + br.br_offset);

        -- Work out GPR/FPR read addresses
        maybe_rb := '0';
        vr.reg_1_addr := '0' & insn_ra(f_in.insn);
        vr.reg_2_addr := '0' & insn_rb(f_in.insn);
        vr.reg_3_addr := '0' & insn_rs(f_in.insn);
        if icode >= INSN_first_rb then
            maybe_rb := '1';
            if icode < INSN_first_frs then
                if icode >= INSN_first_rc then
                    vr.reg_3_addr := '0' & insn_rcreg(f_in.insn);
                end if;
            else
                -- access FRS operand
                vr.reg_3_addr(5) := '1';
                if icode >= INSN_first_frab then
                    -- access FRA and/or FRB operands
                    vr.reg_1_addr(5) := '1';
                    vr.reg_2_addr(5) := '1';
                end if;
                if icode >= INSN_first_frabc then
                    -- access FRC operand
                    vr.reg_3_addr := '1' & insn_rcreg(f_in.insn);
                end if;
            end if;
        end if;
        vr.read_1_enable := f_in.valid;
        vr.read_2_enable := f_in.valid and maybe_rb;
        vr.read_3_enable := f_in.valid;

        v.reg_a := vr.reg_1_addr;
        v.reg_b := vr.reg_2_addr;
        v.reg_c := vr.reg_3_addr;

        -- Update registers
        rin <= v;
        br_in <= bv;

        -- Update outputs
        d_out <= r;
        d_out.decode <= decode;
        r_out <= vr;
        f_out.redirect <= br.predict;
        f_out.redirect_nia <= br_target & "00";
        flush_out <= bv.predict or br.predict;
    end process;

    d1_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(12 downto 0);
    begin
        dec1_log : process(clk)
        begin
            if rising_edge(clk) then
                log_data <= std_ulogic_vector(to_unsigned(insn_type_t'pos(d_out.decode.insn_type), 6)) &
                            r.nia(5 downto 2) &
                            std_ulogic_vector(to_unsigned(unit_t'pos(d_out.decode.unit), 2)) &
                            r.valid;
            end if;
        end process;
        log_out <= log_data;
    end generate;

end architecture behaviour;
