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
        br_target : signed(61 downto 0);
        predict   : std_ulogic;
    end record;

    signal br, br_in : br_predictor_t;

    signal decode_rom_addr : insn_code;
    signal decode : decode_rom_t;

    signal double : std_ulogic;

    type prefix_state_t is record
        prefixed : std_ulogic;
        prefix   : std_ulogic_vector(25 downto 0);
        pref_ia  : std_ulogic_vector(3 downto 0);
    end record;
    constant prefix_state_init : prefix_state_t := (prefixed => '0', prefix => (others => '0'),
                                                    pref_ia => (others => '0'));

    signal pr, pr_in : prefix_state_t;

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
        --                   unit   fac   internal      in1         in2  const        in3   out   res subres  CR   CR   inv  inv  cry   cry  ldst  BR   sgn  upd  rsrv 32b  sgn  rc    lk   priv sgl  rpt
        --                                                op                                                  in   out   A   out  in    out  len        ext                                      pipe
        INSN_illegal     =>  (ALU,  NONE, OP_ILLEGAL,   NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_fetch_fail  =>  (LDST, NONE, OP_FETCH_FAILED, CIA,     IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),

        INSN_add         =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_addc        =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_adde        =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_addex       =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', OV,   '1', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_addg6s      =>  (ALU,  NONE, OP_COMPUTE,   RA,         RB,  NONE,        NONE, RT,   MSC, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_addi        =>  (ALU,  NONE, OP_ADD,       RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_addic       =>  (ALU,  NONE, OP_ADD,       RA,         IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_addic_dot   =>  (ALU,  NONE, OP_ADD,       RA,         IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_addis       =>  (ALU,  NONE, OP_ADD,       RA_OR_ZERO, IMM, CONST_SI_HI, NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_addme       =>  (ALU,  NONE, OP_ADD,       RA,         IMM, CONST_M1,    NONE, RT,   ADD, "000", '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_addpcis     =>  (ALU,  NONE, OP_ADD,       CIA,        IMM, CONST_DXHI4, NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_addze       =>  (ALU,  NONE, OP_ADD,       RA,         IMM, NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_and         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_andc        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_andi_dot    =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI,    RS,   RA,   LOG, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_andis_dot   =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI_HI, RS,   RA,   LOG, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_attn        =>  (ALU,  NONE, OP_ATTN,      NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '1', NONE),
        INSN_brel        =>  (ALU,  NONE, OP_B,         CIA,        IMM, CONST_LI,    NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_babs        =>  (ALU,  NONE, OP_B,         NONE,       IMM, CONST_LI,    NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bcrel       =>  (ALU,  NONE, OP_BC,        CIA,        IMM, CONST_BD,    NONE, NONE, ADD, "000", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bcabs       =>  (ALU,  NONE, OP_BC,        NONE,       IMM, CONST_BD,    NONE, NONE, ADD, "000", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bcctr       =>  (ALU,  NONE, OP_BCREG,     NONE,       IMM, NONE,        NONE, NONE, SPR, "000", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bclr        =>  (ALU,  NONE, OP_BCREG,     NONE,       IMM, NONE,        NONE, NONE, SPR, "000", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bctar       =>  (ALU,  NONE, OP_BCREG,     NONE,       IMM, NONE,        NONE, NONE, SPR, "000", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '1', '0', '0', NONE),
        INSN_bperm       =>  (ALU,  NONE, OP_BPERM,     NONE,       RB,  NONE,        RS,   RA,   ADD, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_brh         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "010", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_brw         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "010", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_brd         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "010", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cbcdtd      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cdtbcd      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "110", '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cfuged      =>  (ALU,  NONE, OP_BSORT,     NONE,       RB,  NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cmp         =>  (ALU,  NONE, OP_CMP,       RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_cmpb        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cmpeqb      =>  (ALU,  NONE, OP_COMPUTE,   RA,         RB,  NONE,        NONE, NONE, ADD, "010", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cmpi        =>  (ALU,  NONE, OP_CMP,       RA,         IMM, CONST_SI,    NONE, NONE, ADD, "000", '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_cmpl        =>  (ALU,  NONE, OP_CMP,       RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cmpli       =>  (ALU,  NONE, OP_CMP,       RA,         IMM, CONST_UI,    NONE, NONE, ADD, "000", '0', '1', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cmprb       =>  (ALU,  NONE, OP_COMPUTE,   RA,         RB,  NONE,        NONE, NONE, ADD, "001", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cntlzd      =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_cntlzw      =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_cnttzd      =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_cnttzw      =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_crand       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_crandc      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_creqv       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_crnand      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_crnor       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_cror        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_crorc       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_crxor       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "011", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_darn        =>  (ALU,  NONE, OP_DARN,      NONE,       IMM, NONE,        NONE, RT,   MSC, "011", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_dcbf        =>  (LDST, NONE, OP_DCBF,      RA_OR_ZERO, RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_dcbst       =>  (ALU,  NONE, OP_DCBST,     NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_dcbt        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_dcbtst      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_dcbz        =>  (LDST, NONE, OP_DCBZ,      RA_OR_ZERO, RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_divd        =>  (DVU,  NONE, OP_DIV,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', '0', NONE),
        INSN_divde       =>  (DVU,  NONE, OP_DIVE,      RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', '0', NONE),
        INSN_divdeu      =>  (DVU,  NONE, OP_DIVE,      RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_divdu       =>  (DVU,  NONE, OP_DIV,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_divw        =>  (DVU,  NONE, OP_DIV,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', '0', NONE),
        INSN_divwe       =>  (DVU,  NONE, OP_DIVE,      RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', '0', NONE),
        INSN_divweu      =>  (DVU,  NONE, OP_DIVE,      RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RCOE, '0', '0', '0', NONE),
        INSN_divwu       =>  (DVU,  NONE, OP_DIV,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RCOE, '0', '0', '0', NONE),
        INSN_eieio       =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_eqv         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "001", '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_extsb       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "111", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_extsh       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "111", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_extsw       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "111", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_extswsli    =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH,    RS,   RA,   ROT, "010", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fabs        =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fadd        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fadds       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fcfid       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_fcfids      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', '0', NONE),
        INSN_fcfidu      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fcfidus     =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fcmpo       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB, NONE,        NONE, NONE, ADD, "000", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_fcmpu       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB, NONE,        NONE, NONE, ADD, "000", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_fcpsgn      =>  (FPU,  FPU,  OP_FP_MOVE,   FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctid       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctidu      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctiduz     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctidz      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctiw       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctiwu      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctiwuz     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fctiwz      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fdiv        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fdivs       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fmadd       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fmadds      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fmr         =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fmrgew      =>  (FPU,  FPU,  OP_FP_MISC,   FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_fmrgow      =>  (FPU,  FPU,  OP_FP_MISC,   FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_fmsub       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fmsubs      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fmul        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        IMM, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fmuls       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        IMM, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fnabs       =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fneg        =>  (FPU,  FPU,  OP_FP_MOVE,   NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fnmadd      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fnmadds     =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fnmsub      =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fnmsubs     =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fre         =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fres        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_frim        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_frin        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_frip        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_friz        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_frsp        =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_frsqrte     =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_frsqrtes    =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fsel        =>  (FPU,  FPU,  OP_FP_MOVE,   FRA,        FRB, NONE,        FRC,  FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fsqrt       =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fsqrts      =>  (FPU,  FPU,  OP_FP_ARITH,  NONE,       FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_fsub        =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_fsubs       =>  (FPU,  FPU,  OP_FP_ARITH,  FRA,        FRB, NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_ftdiv       =>  (FPU,  FPU,  OP_FP_CMP,    FRA,        FRB, NONE,        NONE, NONE, ADD, "000", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_ftsqrt      =>  (FPU,  FPU,  OP_FP_CMP,    NONE,       FRB, NONE,        NONE, NONE, ADD, "000", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_hashchk     =>  (LDST, NONE, OP_LOAD,      RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_hashchkp    =>  (LDST, NONE, OP_LOAD,      RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '1', NONE, '0', '1', '0', NONE),
        INSN_hashst      =>  (LDST, NONE, OP_STORE,     RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_hashstp     =>  (LDST, NONE, OP_STORE,     RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '1', NONE, '0', '1', '0', NONE),
        INSN_icbi        =>  (ALU,  NONE, OP_ICBI,      NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '1', NONE),
        INSN_icbt        =>  (ALU,  NONE, OP_ICBT,      NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_isel        =>  (ALU,  NONE, OP_COMPUTE,   RA_OR_ZERO, RB,  NONE,        NONE, RT,   MSC, "010", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_isync       =>  (ALU,  NONE, OP_ISYNC,     NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lbarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lbz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lbzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_lbzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lbzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lbzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_ld          =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_DS,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_ldarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_ldbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_ldcix       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_ldu         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_DS,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_ldux        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_ldx         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lfd         =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lfdu        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lfdux       =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lfdx        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lfiwax      =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lfiwzx      =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lfs         =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_lfsu        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', '0', DUPD),
        INSN_lfsux       =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', '0', DUPD),
        INSN_lfsx        =>  (LDST, FPU,  OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_lha         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lharx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lhau        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lhaux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lhax        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lhbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lhz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lhzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_lhzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lhzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lhzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lq          =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_DQ,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', DRTP),
        INSN_lqarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', '0', DRTP),
        INSN_lwa         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_DS,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lwarx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lwaux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lwax        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lwbrx       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lwz         =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_lwzcix      =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_lwzu        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lwzux       =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', DUPD),
        INSN_lwzx        =>  (LDST, NONE, OP_LOAD,      RA_OR_ZERO, RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_maddhd      =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,  NONE,        RCR,  RT,   ADD, "010", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_maddhdu     =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,  NONE,        RCR,  RT,   ADD, "010", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_maddld      =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,  NONE,        RCR,  RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_mcrf        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, NONE, ADD, "100", '1', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mcrfs       =>  (FPU,  FPU,  OP_FP_CMP,    NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mcrxrx      =>  (ALU,  NONE, OP_MCRXRX,    NONE,       IMM, NONE,        NONE, NONE, ADD, "101", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mfcr        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, RT,   MSC, "101", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mffs        =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB,  NONE,       NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_mfmsr       =>  (ALU,  NONE, OP_MFMSR,     NONE,       IMM, NONE,        NONE, RT,   MSC, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '1', NONE),
        INSN_mfspr       =>  (ALU,  NONE, OP_MFSPR,     NONE,       IMM, NONE,        RS,   RT,   SPR, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_modsd       =>  (DVU,  NONE, OP_MOD,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_modsw       =>  (DVU,  NONE, OP_MOD,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', NONE, '0', '0', '0', NONE),
        INSN_modud       =>  (DVU,  NONE, OP_MOD,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_moduw       =>  (DVU,  NONE, OP_MOD,       RA,         RB,  NONE,        NONE, RT,   ADD, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_msgclr      =>  (ALU,  NONE, OP_MSG,       NONE,       RB,  NONE,        NONE, NONE, ADD, "011", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_msgsnd      =>  (ALU,  NONE, OP_MSG,       NONE,       RB,  NONE,        NONE, NONE, ADD, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_msgsync     =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_mtcrf       =>  (ALU,  NONE, OP_MTCRF,     NONE,       IMM, NONE,        RS,   NONE, ADD, "101", '0', '1', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mtfsb       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_mtfsf       =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       FRB, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_mtfsfi      =>  (FPU,  FPU,  OP_FP_MISC,   NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_mtmsr       =>  (ALU,  NONE, OP_MTMSRD,    NONE,       IMM, NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '1', '0', NONE),
        INSN_mtmsrd      =>  (ALU,  NONE, OP_MTMSRD,    NONE,       IMM, NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_mtspr       =>  (ALU,  NONE, OP_MTSPR,     NONE,       IMM, NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_mulhd       =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,  NONE,        NONE, RT,   ADD, "010", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_mulhdu      =>  (ALU,  NONE, OP_MUL_H64,   RA,         RB,  NONE,        NONE, RT,   ADD, "010", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_mulhw       =>  (ALU,  NONE, OP_MUL_H32,   RA,         RB,  NONE,        NONE, RT,   ADD, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', '0', NONE),
        INSN_mulhwu      =>  (ALU,  NONE, OP_MUL_H32,   RA,         RB,  NONE,        NONE, RT,   ADD, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_mulld       =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RCOE, '0', '0', '0', NONE),
        INSN_mulli       =>  (ALU,  NONE, OP_MUL_L64,   RA,         IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_mullw       =>  (ALU,  NONE, OP_MUL_L64,   RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '1', RCOE, '0', '0', '0', NONE),
        INSN_nand        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_neg         =>  (ALU,  NONE, OP_ADD,       RA,         IMM, NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_nop         =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_nor         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_or          =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '1', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_orc         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "000", '0', '0', '0', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_ori         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI,    RS,   RA,   LOG, "000", '0', '0', '1', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_oris        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI_HI, RS,   RA,   LOG, "000", '0', '0', '1', '1', ZERO, '0', NONE, '0', '0', '0', '0', '0', '1', NONE, '0', '0', '0', NONE),
        INSN_paddi       =>  (ALU,  NONE, OP_ADD,       RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pdepd       =>  (ALU,  NONE, OP_BSORT,     NONE,       RB,  NONE,        RS,   RA,   ADD, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pextd       =>  (ALU,  NONE, OP_BSORT,     NONE,       RB,  NONE,        RS,   RA,   ADD, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plbz        =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pld         =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plfd        =>  (LDST, FPU,  OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plfs        =>  (LDST, FPU,  OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, FRT,  ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_plha        =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plhz        =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plq         =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', DRTP),
        INSN_plwa        =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '1', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_plwz        =>  (LDST, NONE, OP_LOAD,      RA0_OR_CIA, IMM, CONST_PSI,   NONE, RT,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pnop        =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pstb        =>  (LDST, NONE, OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pstd        =>  (LDST, NONE, OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pstfd       =>  (LDST, FPU,  OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pstfs       =>  (LDST, FPU,  OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_psth        =>  (LDST, NONE, OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_pstq        =>  (LDST, NONE, OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', DRSP),
        INSN_pstw        =>  (LDST, NONE, OP_STORE,     RA0_OR_CIA, IMM, CONST_PSI,   RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_popcntb     =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_popcntd     =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_popcntw     =>  (ALU,  NONE, OP_COUNTB,    NONE,       IMM, NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_prtyd       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "011", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_prtyw       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        RS,   RA,   LOG, "011", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_rfid        =>  (ALU,  NONE, OP_RFID,      NONE,       IMM, NONE,        NONE, NONE, SPR, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_rfscv       =>  (ALU,  NONE, OP_RFID,      NONE,       IMM, NONE,        NONE, NONE, SPR, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_rldcl       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rldcr       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rldic       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH,    RS,   RA,   ROT, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rldicl      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH,    RS,   RA,   ROT, "100", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rldicr      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH,    RS,   RA,   ROT, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rldimi      =>  (ALU,  NONE, OP_COMPUTE,   RA,         IMM, CONST_SH,    RS,   RA,   ROT, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_rlwimi      =>  (ALU,  NONE, OP_COMPUTE,   RA,         IMM, CONST_SH32,  RS,   RA,   ROT, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_rlwinm      =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH32,  RS,   RA,   ROT, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_rlwnm       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "101", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_rnop        =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_sc          =>  (ALU,  NONE, OP_SC,        NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_setb        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, NONE,        NONE, RT,   MSC, "110", '1', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_slbia       =>  (LDST, NONE, OP_TLBIE,     NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_sld         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_slw         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_srad        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_sradi       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH,    RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '1', NONE, '0', '0', '0', '0', '0', '1', RC,   '0', '0', '0', NONE),
        INSN_sraw        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', '0', NONE),
        INSN_srawi       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_SH32,  RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '1', NONE, '0', '0', '0', '0', '1', '1', RC,   '0', '0', '0', NONE),
        INSN_srd         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_srw         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   ROT, "000", '0', '0', '1', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', RC,   '0', '0', '0', NONE),
        INSN_stb         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stbcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '1', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_stbcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_stbu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stbux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stbx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is1B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_std         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_DS,    RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stdbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stdcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '1', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_stdcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_stdu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_DS,    RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stdux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stdx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfd        =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfdu       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    FRS,  RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfdux      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,  NONE,        FRS,  RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfdx       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,  NONE,        FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfiwx      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,  NONE,        FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stfs        =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_stfsu       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    FRS,  RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_stfsux      =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,  NONE,        FRS,  RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_stfsx       =>  (LDST, FPU,  OP_STORE,     RA_OR_ZERO, RB,  NONE,        FRS,  NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_sth         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_sthbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_sthcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '1', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_sthcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_sthu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_sthux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_sthx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is2B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stq         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_DS,    RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', DRSP),
        INSN_stqcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is8B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', '0', DRSP),
        INSN_stw         =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stwbrx      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '1', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stwcix      =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '1', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_stwcx       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '1', '0', '0', ONE,  '0', '0', '0', NONE),
        INSN_stwu        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, IMM, CONST_SI,    RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stwux       =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   RA,   ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '1', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_stwx        =>  (LDST, NONE, OP_STORE,     RA_OR_ZERO, RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', is4B, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_subf        =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ONE,  '0', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_subfc       =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_subfe       =>  (ALU,  NONE, OP_ADD,       RA,         RB,  NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_subfic      =>  (ALU,  NONE, OP_ADD,       RA,         IMM, CONST_SI,    NONE, RT,   ADD, "000", '0', '0', '1', '0', ONE,  '1', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_subfme      =>  (ALU,  NONE, OP_ADD,       RA,         IMM, CONST_M1,    NONE, RT,   ADD, "000", '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_subfze      =>  (ALU,  NONE, OP_ADD,       RA,         IMM, NONE,        NONE, RT,   ADD, "000", '0', '0', '1', '0', CA,   '1', NONE, '0', '0', '0', '0', '0', '0', RCOE, '0', '0', '0', NONE),
        INSN_sync        =>  (LDST, NONE, OP_SYNC,      NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '1', NONE),
        INSN_td          =>  (ALU,  NONE, OP_TRAP,      RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_tdi         =>  (ALU,  NONE, OP_TRAP,      RA,         IMM, CONST_SI,    NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_tlbie       =>  (LDST, NONE, OP_TLBIE,     NONE,       RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_tlbiel      =>  (LDST, NONE, OP_TLBIE,     NONE,       RB,  NONE,        RS,   NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_tlbsync     =>  (ALU,  NONE, OP_NOP,       NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '1', '0', NONE),
        INSN_tw          =>  (ALU,  NONE, OP_TRAP,      RA,         RB,  NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_twi         =>  (ALU,  NONE, OP_TRAP,      RA,         IMM, CONST_SI,    NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '1', '0', NONE, '0', '0', '0', NONE),
        INSN_wait        =>  (ALU,  NONE, OP_WAIT,      NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '1', NONE),
        INSN_xor         =>  (ALU,  NONE, OP_COMPUTE,   NONE,       RB,  NONE,        RS,   RA,   LOG, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', RC,   '0', '0', '0', NONE),
        INSN_xori        =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI,    RS,   RA,   LOG, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),
        INSN_xoris       =>  (ALU,  NONE, OP_COMPUTE,   NONE,       IMM, CONST_UI_HI, RS,   RA,   LOG, "001", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE),

        others           =>  (ALU,  NONE, OP_ILLEGAL,   NONE,       IMM, NONE,        NONE, NONE, ADD, "000", '0', '0', '0', '0', ZERO, '0', NONE, '0', '0', '0', '0', '0', '0', NONE, '0', '0', '0', NONE)
        );

    function decode_ram_spr(sprn : spr_num_t) return ram_spr_info is
        variable ret : ram_spr_info;
    begin
        ret := (index => (others => '0'), isodd => '0', is32b => '0', valid => '1');
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
            when SPR_VRSAVE =>
                ret.index := RAMSPR_VRSAVE;
                ret.is32b := '1';
            when SPR_HASHKEYR =>
                ret.index := RAMSPR_HASHKY;
                ret.isodd := '1';
            when SPR_HASHPKEYR =>
                ret.index := RAMSPR_HASHPK;
                ret.isodd := '1';
            when others =>
                ret.valid := '0';
        end case;
        return ret;
    end;

    function map_spr(sprn : spr_num_t) return spr_id is
        variable i : spr_id;
    begin
        i.sel := "0000";
        i.valid := '1';
        i.ispmu := '0';
        i.ronly := '0';
        i.wonly := '0';
        i.noop  := '0';
        case sprn is
            when SPR_TB =>
                i.sel := SPRSEL_TB;
                i.ronly := '1';
            when SPR_TBU =>
                i.sel := SPRSEL_TBU;
                i.ronly := '1';
            when SPR_TBLW =>
                i.sel := SPRSEL_TB;
                i.wonly := '1';
            when SPR_TBUW =>
                i.sel := SPRSEL_TB;
                i.wonly := '1';
            when SPR_DEC =>
                i.sel := SPRSEL_DEC;
            when SPR_PVR =>
                i.sel := SPRSEL_PVR;
            when 724 =>     -- LOG_ADDR SPR
                i.sel := SPRSEL_LOGR;
            when 725 =>     -- LOG_DATA SPR
                i.sel := SPRSEL_LOGR;
                i.ronly := '1';
            when SPR_UPMC1 | SPR_UPMC2 | SPR_UPMC3 | SPR_UPMC4 | SPR_UPMC5 | SPR_UPMC6 |
                SPR_UMMCR0 | SPR_UMMCR1 | SPR_UMMCR2 | SPR_UMMCRA | SPR_USIER | SPR_USIAR | SPR_USDAR |
                SPR_PMC1 | SPR_PMC2 | SPR_PMC3 | SPR_PMC4 | SPR_PMC5 | SPR_PMC6 |
                SPR_MMCR0 | SPR_MMCR1 | SPR_MMCR2 | SPR_MMCRA | SPR_SIER | SPR_SIAR | SPR_SDAR =>
                i.ispmu := '1';
            when SPR_USIER2 | SPR_USIER3 | SPR_UMMCR3 | SPR_SIER2 | SPR_SIER3 | SPR_MMCR3 =>
                i.sel := SPRSEL_ZERO;
            when SPR_CFAR =>
                i.sel := SPRSEL_CFAR;
            when SPR_XER =>
                i.sel := SPRSEL_XER;
            when SPR_FSCR =>
                i.sel := SPRSEL_FSCR;
            when SPR_LPCR =>
                i.sel := SPRSEL_LPCR;
            when SPR_HEIR =>
                i.sel := SPRSEL_HEIR;
            when SPR_CTRL =>
                i.sel := SPRSEL_CTRL;
                i.ronly := '1';
            when SPR_CTRLW =>
                i.sel := SPRSEL_CTRL;
                i.wonly := '1';
            when SPR_UDSCR =>
                i.sel := SPRSEL_DSCR;
            when SPR_DSCR =>
                i.sel := SPRSEL_DSCR;
            when SPR_PIR =>
                i.sel := SPRSEL_PIR;
            when SPR_CIABR =>
                i.sel := SPRSEL_CIABR;
            when SPR_DEXCR | SPR_HDEXCR =>
                i.sel := SPRSEL_DEXCR;
            when SPR_DEXCRU | SPR_HDEXCU =>
                i.sel := SPRSEL_DEXCR;
                i.ronly := '1';
            when SPR_NOOP0 | SPR_NOOP1 | SPR_NOOP2 | SPR_NOOP3 =>
                i.noop := '1';
            when SPR_HMER | SPR_HMEER | SPR_HRMOR =>
                i.sel := SPRSEL_ZERO;
            when others =>
                i.valid := '0';
        end case;
        return i;
    end;

begin
    double <= not r.second when (r.valid = '1' and decode.repeat /= NONE) else '0';

    decode1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r <= Decode1ToDecode2Init;
                fetch_failed <= '0';
                pr <= prefix_state_init;
            elsif flush_in = '1' then
                r.valid <= '0';
                fetch_failed <= '0';
                pr <= prefix_state_init;
            elsif stall_in = '0' then
                if double = '0' then
                    r <= rin;
                    fetch_failed <= f_in.fetch_failed;
                    if f_in.valid = '1' then
                        pr <= pr_in;
                    end if;
                else
                    r.second <= '1';
                    r.reg_c <= rin.reg_c;
                end if;
            end if;
            if rst = '1' then
                br.predict <= '0';
            else
                br <= br_in;
            end if;
        end if;
    end process;

    busy_out <= stall_in or double;

    decode1_rom: process(clk)
    begin
        if rising_edge(clk) then
            if stall_in = '0' and double = '0' then
                decode <= decode_rom(decode_rom_addr);
            end if;
        end if;
    end process;

    decode1_1: process(all)
        variable v : Decode1ToDecode2Type;
        variable vr : Decode1ToRegisterFileType;
        variable br_nia    : std_ulogic_vector(61 downto 0);
        variable br_offset : std_ulogic_vector(23 downto 0);
        variable bv : br_predictor_t;
        variable icode : insn_code;
        variable sprn : spr_num_t;
        variable maybe_rb : std_ulogic;
        variable pv : prefix_state_t;
        variable icode_bits : std_ulogic_vector(9 downto 0);
        variable valid_suffix : std_ulogic;
    begin
        v := Decode1ToDecode2Init;
        pv := pr;

        v.valid := f_in.valid;
        v.nia  := f_in.nia;
        v.insn := f_in.insn;
        v.prefix := pr.prefix;
        v.prefixed := pr.prefixed;
        v.stop_mark := f_in.stop_mark;
        v.big_endian := f_in.big_endian;

	if is_X(f_in.insn) then
	    v.spr_info := (sel => "XXXX", others => 'X');
	    v.ram_spr := (index => (others => 'X'), others => 'X');
	else
            sprn := decode_spr_num(f_in.insn);
            v.spr_info := map_spr(sprn);
            v.ram_spr := decode_ram_spr(sprn);
        end if;

        icode := f_in.icode;
        icode_bits := std_ulogic_vector(to_unsigned(insn_code'pos(icode), 10));

        if f_in.fetch_failed = '1' then
            icode_bits := std_ulogic_vector(to_unsigned(insn_code'pos(INSN_fetch_fail), 10));
            -- Only send down a single OP_FETCH_FAILED
            v.valid := not fetch_failed;
            pv := prefix_state_init;

        elsif pr.prefixed = '1' then
            -- Check suffix value and convert to the prefixed instruction code
            if pr.prefix(24) = '1' then
                -- either pnop or illegal
                icode_bits := std_ulogic_vector(to_unsigned(insn_code'pos(INSN_pnop), 10));
            else
                -- various load/store instructions
                icode_bits(0) := '1';
            end if;
            valid_suffix := '0';
            case pr.prefix(25 downto 23) is
                when "000" =>    -- 8LS
                    if icode >= INSN_first_8ls and icode < INSN_first_rb then
                        valid_suffix := '1';
                    end if;
                when "100" =>   -- MLS
                    if icode >= INSN_first_mls and icode < INSN_first_8ls then
                        valid_suffix := '1';
                    elsif icode >= INSN_first_fp_mls and icode < INSN_first_fp_nonmls then
                        valid_suffix := '1';
                    end if;
                when "110" =>   -- MRR, i.e. pnop
                    if pr.prefix(22 downto 20) = "000" then
                        valid_suffix := '1';
                    end if;
                when others =>
            end case;
            v.nia(5 downto 2) := pr.pref_ia;
            v.prefixed := '1';
            v.prefix := pr.prefix;
            v.illegal_suffix := not valid_suffix;
            pv := prefix_state_init;

        elsif icode = INSN_prefix then
            pv.prefixed := '1';
            pv.pref_ia := f_in.nia(5 downto 2);
            pv.prefix := f_in.insn(25 downto 0);
            -- Check if the address of the prefix mod 64 is 60;
            -- if so we need to arrange to generate an alignment interrupt
            if f_in.nia(5 downto 2) = "1111" then
                v.misaligned_prefix := '1';
            else
                v.valid := '0';
            end if;

        end if;
        decode_rom_addr <= insn_code'val(to_integer(unsigned(icode_bits)));

        if f_in.valid = '1' then
            report "Decode " & insn_code'image(insn_code'val(to_integer(unsigned(icode_bits)))) & " " &
                to_hstring(f_in.insn) & " at " & to_hstring(f_in.nia);
        end if;

        -- Branch predictor
        -- Note bclr, bcctr and bctar not predicted as we have no
        -- count cache or link stack.
        br_offset := f_in.insn(25 downto 2);
        case icode is
            when INSN_brel | INSN_babs =>
                -- Unconditional branches are always taken
                v.br_pred := '1';
            when INSN_bcrel =>
                -- Predict backward relative branches as taken, others as untaken
                v.br_pred := f_in.insn(15);
                br_offset(23 downto 14) := (others => '1');
            when others =>
        end case;
        br_nia := f_in.nia(63 downto 2);
        if f_in.insn(1) = '1' then
            br_nia := (others => '0');
        end if;
        bv.br_target := signed(br_nia) + signed(br_offset);
        if f_in.next_predicted = '1' then
            v.br_pred := '1';
        elsif f_in.next_pred_ntaken = '1' then
            v.br_pred := '0';
        end if;
        bv.predict := v.br_pred and f_in.valid and not flush_in and not busy_out and not f_in.next_predicted;

        -- Work out GPR/FPR read addresses
        -- Note that for prefixed instructions we are working this out based
        -- only on the suffix.
        if double = '0' then
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
            -- See if this is an instruction where repeat_t = DRSP and we need
            -- to read RS|1 followed by RS, i.e. stq or stqcx. in LE mode
            -- (note we don't have access to the decode for the current instruction)
            if (icode = INSN_stq or icode = INSN_stqcx) and f_in.big_endian = '0' then
                vr.reg_3_addr(0) := '1';
            end if;
            vr.read_1_enable := f_in.valid;
            vr.read_2_enable := f_in.valid and maybe_rb;
            vr.read_3_enable := f_in.valid;
        else
            -- second instance of a doubled instruction
            vr.reg_1_addr := r.reg_a;
            vr.reg_2_addr := r.reg_b;
            vr.reg_3_addr := r.reg_c;
            vr.read_1_enable := '0';            -- (not actually used)
            vr.read_2_enable := '0';
            vr.read_3_enable := '1';            -- (not actually used)
            -- For pstq, and for stq and stqcx in BE mode,
            -- we need to read register RS|1 in the cycle after we read RS;
            -- stq and stqcx in LE mode read RS.
            if decode.repeat = DRSP then
                vr.reg_3_addr(0) := r.prefixed or f_in.big_endian;
            end if;
        end if;

        v.reg_a := vr.reg_1_addr;
        v.reg_b := vr.reg_2_addr;
        v.reg_c := vr.reg_3_addr;

        -- Update registers
        rin <= v;
        br_in <= bv;
        pr_in <= pv;

        -- Update outputs
        d_out <= r;
        d_out.decode <= decode;
        r_out <= vr;
        f_out.redirect <= br.predict;
        f_out.redirect_nia <= std_ulogic_vector(br.br_target) & "00";
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
