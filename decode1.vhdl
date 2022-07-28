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
    type dc0_t is record
        f_in     : IcacheToDecode1Type;
        use_row  : std_ulogic;
        br_pred  : std_ulogic;
        override : std_ulogic;
        ov_insn  : insn_code;
        spr_info : spr_id;
        ram_spr  : ram_spr_info;
    end record;
    constant dc0_t_init : dc0_t :=
        (f_in => IcacheToDecode1Init, ov_insn => INSN_illegal,
         spr_info => spr_id_init, ram_spr => ram_spr_info_init,
         others => '0');

    signal dc0, dc0in : dc0_t;

    signal r, rin : Decode1ToDecode2Type;
    signal f, fin : Decode1ToFetch1Type;

    type br_predictor_t is record
        br_nia    : std_ulogic_vector(61 downto 0);
        br_offset : signed(23 downto 0);
        predict   : std_ulogic;
    end record;

    signal br, br_in : br_predictor_t;

    signal maj_rom_addr : std_ulogic_vector(10 downto 0);
    signal row_rom_addr : std_ulogic_vector(10 downto 0);
    signal major_predecode : insn_code;
    signal row_predecode   : insn_code;

    signal decode_rom_addr : insn_code;
    signal decode : decode_rom_t;
    signal rom_ce : std_ulogic;

    type predecoder_rom_t is array(0 to 2047) of insn_code;

    constant major_predecode_rom : predecoder_rom_t := (
        2#001100_00000# to 2#001100_11111# =>  INSN_addic,
        2#001101_00000# to 2#001101_11111# =>  INSN_addic_dot,
        2#001110_00000# to 2#001110_11111# =>  INSN_addi,
        2#001111_00000# to 2#001111_11111# =>  INSN_addis,
        2#010011_00100# to 2#010011_00101# =>  INSN_addpcis,
        2#011100_00000# to 2#011100_11111# =>  INSN_andi_dot,
        2#011101_00000# to 2#011101_11111# =>  INSN_andis_dot,
        2#000000_00000#                    =>  INSN_attn,
        2#010010_00000# to 2#010010_11111# =>  INSN_b,
        2#010000_00000# to 2#010000_11111# =>  INSN_bc,
        2#001011_00000# to 2#001011_11111# =>  INSN_cmpi,
        2#001010_00000# to 2#001010_11111# =>  INSN_cmpli,
        2#100010_00000# to 2#100010_11111# =>  INSN_lbz,
        2#100011_00000# to 2#100011_11111# =>  INSN_lbzu,
        2#110010_00000# to 2#110010_11111# =>  INSN_lfd,
        2#110011_00000# to 2#110011_11111# =>  INSN_lfdu,
        2#110000_00000# to 2#110000_11111# =>  INSN_lfs,
        2#110001_00000# to 2#110001_11111# =>  INSN_lfsu,
        2#101010_00000# to 2#101010_11111# =>  INSN_lha,
        2#101011_00000# to 2#101011_11111# =>  INSN_lhau,
        2#101000_00000# to 2#101000_11111# =>  INSN_lhz,
        2#101001_00000# to 2#101001_11111# =>  INSN_lhzu,
        2#100000_00000# to 2#100000_11111# =>  INSN_lwz,
        2#100001_00000# to 2#100001_11111# =>  INSN_lwzu,
        2#000111_00000# to 2#000111_11111# =>  INSN_mulli,
        2#011000_00000# to 2#011000_11111# =>  INSN_ori,
        2#011001_00000# to 2#011001_11111# =>  INSN_oris,
        2#010100_00000# to 2#010100_11111# =>  INSN_rlwimi,
        2#010101_00000# to 2#010101_11111# =>  INSN_rlwinm,
        2#010111_00000# to 2#010111_11111# =>  INSN_rlwnm,
        2#010001_00000# to 2#010001_11111# =>  INSN_sc,
        2#100110_00000# to 2#100110_11111# =>  INSN_stb,
        2#100111_00000# to 2#100111_11111# =>  INSN_stbu,
        2#110110_00000# to 2#110110_11111# =>  INSN_stfd,
        2#110111_00000# to 2#110111_11111# =>  INSN_stfdu,
        2#110100_00000# to 2#110100_11111# =>  INSN_stfs,
        2#110101_00000# to 2#110101_11111# =>  INSN_stfsu,
        2#101100_00000# to 2#101100_11111# =>  INSN_sth,
        2#101101_00000# to 2#101101_11111# =>  INSN_sthu,
        2#100100_00000# to 2#100100_11111# =>  INSN_stw,
        2#100101_00000# to 2#100101_11111# =>  INSN_stwu,
        2#001000_00000# to 2#001000_11111# =>  INSN_subfic,
        2#000010_00000# to 2#000010_11111# =>  INSN_tdi,
        2#000011_00000# to 2#000011_11111# =>  INSN_twi,
        2#011010_00000# to 2#011010_11111# =>  INSN_xori,
        2#011011_00000# to 2#011011_11111# =>  INSN_xoris,
        -- major opcode 4
        2#000100_10000#                    =>  INSN_maddhd,
        2#000100_10001#                    =>  INSN_maddhdu,
        2#000100_10011#                    =>  INSN_maddld,
        -- major opcode 30
        2#011110_01000# to 2#011110_01001# =>  INSN_rldic,
        2#011110_01010# to 2#011110_01011# =>  INSN_rldic,
        2#011110_00000# to 2#011110_00001# =>  INSN_rldicl,
        2#011110_00010# to 2#011110_00011# =>  INSN_rldicl,
        2#011110_00100# to 2#011110_00101# =>  INSN_rldicr,
        2#011110_00110# to 2#011110_00111# =>  INSN_rldicr,
        2#011110_01100# to 2#011110_01101# =>  INSN_rldimi,
        2#011110_01110# to 2#011110_01111# =>  INSN_rldimi,
        2#011110_10000# to 2#011110_10001# =>  INSN_rldcl,
        2#011110_10010# to 2#011110_10011# =>  INSN_rldcr,
        -- major opcode 58
        2#111010_00000#                    =>  INSN_ld,
        2#111010_00001#                    =>  INSN_ldu,
        2#111010_00010#                    =>  INSN_lwa,
        2#111010_00100#                    =>  INSN_ld,
        2#111010_00101#                    =>  INSN_ldu,
        2#111010_00110#                    =>  INSN_lwa,
        2#111010_01000#                    =>  INSN_ld,
        2#111010_01001#                    =>  INSN_ldu,
        2#111010_01010#                    =>  INSN_lwa,
        2#111010_01100#                    =>  INSN_ld,
        2#111010_01101#                    =>  INSN_ldu,
        2#111010_01110#                    =>  INSN_lwa,
        2#111010_10000#                    =>  INSN_ld,
        2#111010_10001#                    =>  INSN_ldu,
        2#111010_10010#                    =>  INSN_lwa,
        2#111010_10100#                    =>  INSN_ld,
        2#111010_10101#                    =>  INSN_ldu,
        2#111010_10110#                    =>  INSN_lwa,
        2#111010_11000#                    =>  INSN_ld,
        2#111010_11001#                    =>  INSN_ldu,
        2#111010_11010#                    =>  INSN_lwa,
        2#111010_11100#                    =>  INSN_ld,
        2#111010_11101#                    =>  INSN_ldu,
        2#111010_11110#                    =>  INSN_lwa,
        -- major opcode 59
        2#111011_00100# to 2#111011_00101# =>  INSN_fdivs,
        2#111011_01000# to 2#111011_01001# =>  INSN_fsubs,
        2#111011_01010# to 2#111011_01011# =>  INSN_fadds,
        2#111011_01100# to 2#111011_01101# =>  INSN_fsqrts,
        2#111011_10000# to 2#111011_10001# =>  INSN_fres,
        2#111011_10010# to 2#111011_10011# =>  INSN_fmuls,
        2#111011_10100# to 2#111011_10101# =>  INSN_frsqrtes,
        2#111011_11000# to 2#111011_11001# =>  INSN_fmsubs,
        2#111011_11010# to 2#111011_11011# =>  INSN_fmadds,
        2#111011_11100# to 2#111011_11101# =>  INSN_fnmsubs,
        2#111011_11110# to 2#111011_11111# =>  INSN_fnmadds,
        -- major opcode 62
        2#111110_00000#                    =>  INSN_std,
        2#111110_00001#                    =>  INSN_stdu,
        2#111110_00100#                    =>  INSN_std,
        2#111110_00101#                    =>  INSN_stdu,
        2#111110_01000#                    =>  INSN_std,
        2#111110_01001#                    =>  INSN_stdu,
        2#111110_01100#                    =>  INSN_std,
        2#111110_01101#                    =>  INSN_stdu,
        2#111110_10000#                    =>  INSN_std,
        2#111110_10001#                    =>  INSN_stdu,
        2#111110_10100#                    =>  INSN_std,
        2#111110_10101#                    =>  INSN_stdu,
        2#111110_11000#                    =>  INSN_std,
        2#111110_11001#                    =>  INSN_stdu,
        2#111110_11100#                    =>  INSN_std,
        2#111110_11101#                    =>  INSN_stdu,
        -- major opcode 63
        2#111111_00100# to 2#111111_00101# =>  INSN_fdiv,
        2#111111_01000# to 2#111111_01001# =>  INSN_fsub,
        2#111111_01010# to 2#111111_01011# =>  INSN_fadd,
        2#111111_01100# to 2#111111_01101# =>  INSN_fsqrt,
        2#111111_01110# to 2#111111_01111# =>  INSN_fsel,
        2#111111_10000# to 2#111111_10001# =>  INSN_fre,
        2#111111_10010# to 2#111111_10011# =>  INSN_fmul,
        2#111111_10100# to 2#111111_10101# =>  INSN_frsqrte,
        2#111111_11000# to 2#111111_11001# =>  INSN_fmsub,
        2#111111_11010# to 2#111111_11011# =>  INSN_fmadd,
        2#111111_11100# to 2#111111_11101# =>  INSN_fnmsub,
        2#111111_11110# to 2#111111_11111# =>  INSN_fnmadd,
        others                             =>  INSN_illegal
        );

    constant row_predecode_rom : predecoder_rom_t := (
        -- Major opcode 31
        -- Address bits are 0, insn(10:1)
        2#0_01000_01010#  =>  INSN_add,
        2#0_11000_01010#  =>  INSN_add, -- addo
        2#0_00000_01010#  =>  INSN_addc,
        2#0_10000_01010#  =>  INSN_addc, -- addco
        2#0_00100_01010#  =>  INSN_adde,
        2#0_10100_01010#  =>  INSN_adde, -- addeo
        2#0_00101_01010#  =>  INSN_addex,
        2#0_00010_01010#  =>  INSN_addg6s,
        2#0_00111_01010#  =>  INSN_addme,
        2#0_10111_01010#  =>  INSN_addme, -- addmeo
        2#0_00110_01010#  =>  INSN_addze,
        2#0_10110_01010#  =>  INSN_addze, -- addzeo
        2#0_00000_11100#  =>  INSN_and,
        2#0_00001_11100#  =>  INSN_andc,
        2#0_00111_11100#  =>  INSN_bperm,
        2#0_01001_11010#  =>  INSN_cbcdtd,
        2#0_01000_11010#  =>  INSN_cdtbcd,
        2#0_00000_00000#  =>  INSN_cmp,
        2#0_01111_11100#  =>  INSN_cmpb,
        2#0_00111_00000#  =>  INSN_cmpeqb,
        2#0_00001_00000#  =>  INSN_cmpl,
        2#0_00110_00000#  =>  INSN_cmprb,
        2#0_00001_11010#  =>  INSN_cntlzd,
        2#0_00000_11010#  =>  INSN_cntlzw,
        2#0_10001_11010#  =>  INSN_cnttzd,
        2#0_10000_11010#  =>  INSN_cnttzw,
        2#0_10111_10011#  =>  INSN_darn,
        2#0_00010_10110#  =>  INSN_dcbf,
        2#0_00001_10110#  =>  INSN_dcbst,
        2#0_01000_10110#  =>  INSN_dcbt,
        2#0_00111_10110#  =>  INSN_dcbtst,
        2#0_11111_10110#  =>  INSN_dcbz,
        2#0_01100_01001#  =>  INSN_divdeu,
        2#0_11100_01001#  =>  INSN_divdeu, -- divdeuo
        2#0_01100_01011#  =>  INSN_divweu,
        2#0_11100_01011#  =>  INSN_divweu, -- divweuo
        2#0_01101_01001#  =>  INSN_divde,
        2#0_11101_01001#  =>  INSN_divde, -- divdeo
        2#0_01101_01011#  =>  INSN_divwe,
        2#0_11101_01011#  =>  INSN_divwe, -- divweo
        2#0_01110_01001#  =>  INSN_divdu,
        2#0_11110_01001#  =>  INSN_divdu, -- divduo
        2#0_01110_01011#  =>  INSN_divwu,
        2#0_11110_01011#  =>  INSN_divwu, -- divwuo
        2#0_01111_01001#  =>  INSN_divd,
        2#0_11111_01001#  =>  INSN_divd, -- divdo
        2#0_01111_01011#  =>  INSN_divw,
        2#0_11111_01011#  =>  INSN_divw, -- divwo
        2#0_11001_10110#  =>  INSN_nop, -- dss
        2#0_01010_10110#  =>  INSN_nop, -- dst
        2#0_01011_10110#  =>  INSN_nop, -- dstst
        2#0_11010_10110#  =>  INSN_eieio,
        2#0_01000_11100#  =>  INSN_eqv,
        2#0_11101_11010#  =>  INSN_extsb,
        2#0_11100_11010#  =>  INSN_extsh,
        2#0_11110_11010#  =>  INSN_extsw,
        2#0_11011_11010#  =>  INSN_extswsli,
        2#0_11011_11011#  =>  INSN_extswsli,
        2#0_11110_10110#  =>  INSN_icbi,
        2#0_00000_10110#  =>  INSN_icbt,
        2#0_00000_01111#  =>  INSN_isel,
        2#0_00001_01111#  =>  INSN_isel,
        2#0_00010_01111#  =>  INSN_isel,
        2#0_00011_01111#  =>  INSN_isel,
        2#0_00100_01111#  =>  INSN_isel,
        2#0_00101_01111#  =>  INSN_isel,
        2#0_00110_01111#  =>  INSN_isel,
        2#0_00111_01111#  =>  INSN_isel,
        2#0_01000_01111#  =>  INSN_isel,
        2#0_01001_01111#  =>  INSN_isel,
        2#0_01010_01111#  =>  INSN_isel,
        2#0_01011_01111#  =>  INSN_isel,
        2#0_01100_01111#  =>  INSN_isel,
        2#0_01101_01111#  =>  INSN_isel,
        2#0_01110_01111#  =>  INSN_isel,
        2#0_01111_01111#  =>  INSN_isel,
        2#0_10000_01111#  =>  INSN_isel,
        2#0_10001_01111#  =>  INSN_isel,
        2#0_10010_01111#  =>  INSN_isel,
        2#0_10011_01111#  =>  INSN_isel,
        2#0_10100_01111#  =>  INSN_isel,
        2#0_10101_01111#  =>  INSN_isel,
        2#0_10110_01111#  =>  INSN_isel,
        2#0_10111_01111#  =>  INSN_isel,
        2#0_11000_01111#  =>  INSN_isel,
        2#0_11001_01111#  =>  INSN_isel,
        2#0_11010_01111#  =>  INSN_isel,
        2#0_11011_01111#  =>  INSN_isel,
        2#0_11100_01111#  =>  INSN_isel,
        2#0_11101_01111#  =>  INSN_isel,
        2#0_11110_01111#  =>  INSN_isel,
        2#0_11111_01111#  =>  INSN_isel,
        2#0_00001_10100#  =>  INSN_lbarx,
        2#0_11010_10101#  =>  INSN_lbzcix,
        2#0_00011_10111#  =>  INSN_lbzux,
        2#0_00010_10111#  =>  INSN_lbzx,
        2#0_00010_10100#  =>  INSN_ldarx,
        2#0_10000_10100#  =>  INSN_ldbrx,
        2#0_11011_10101#  =>  INSN_ldcix,
        2#0_00001_10101#  =>  INSN_ldux,
        2#0_00000_10101#  =>  INSN_ldx,
        2#0_10010_10111#  =>  INSN_lfdx,
        2#0_10011_10111#  =>  INSN_lfdux,
        2#0_11010_10111#  =>  INSN_lfiwax,
        2#0_11011_10111#  =>  INSN_lfiwzx,
        2#0_10000_10111#  =>  INSN_lfsx,
        2#0_10001_10111#  =>  INSN_lfsux,
        2#0_00011_10100#  =>  INSN_lharx,
        2#0_01011_10111#  =>  INSN_lhaux,
        2#0_01010_10111#  =>  INSN_lhax,
        2#0_11000_10110#  =>  INSN_lhbrx,
        2#0_11001_10101#  =>  INSN_lhzcix,
        2#0_01001_10111#  =>  INSN_lhzux,
        2#0_01000_10111#  =>  INSN_lhzx,
        2#0_00000_10100#  =>  INSN_lwarx,
        2#0_01011_10101#  =>  INSN_lwaux,
        2#0_01010_10101#  =>  INSN_lwax,
        2#0_10000_10110#  =>  INSN_lwbrx,
        2#0_11000_10101#  =>  INSN_lwzcix,
        2#0_00001_10111#  =>  INSN_lwzux,
        2#0_00000_10111#  =>  INSN_lwzx,
        2#0_10010_00000#  =>  INSN_mcrxrx,
        2#0_00000_10011#  =>  INSN_mfcr,
        2#0_00010_10011#  =>  INSN_mfmsr,
        2#0_01010_10011#  =>  INSN_mfspr,
        2#0_01000_01001#  =>  INSN_modud,
        2#0_01000_01011#  =>  INSN_moduw,
        2#0_11000_01001#  =>  INSN_modsd,
        2#0_11000_01011#  =>  INSN_modsw,
        2#0_00100_10000#  =>  INSN_mtcrf,
        2#0_00100_10010#  =>  INSN_mtmsr,
        2#0_00101_10010#  =>  INSN_mtmsrd,
        2#0_01110_10011#  =>  INSN_mtspr,
        2#0_00010_01001#  =>  INSN_mulhd,
        2#0_00000_01001#  =>  INSN_mulhdu,
        2#0_00010_01011#  =>  INSN_mulhw,
        2#0_00000_01011#  =>  INSN_mulhwu,
        -- next 4 have reserved bit set
        2#0_10010_01001#  =>  INSN_mulhd,
        2#0_10000_01001#  =>  INSN_mulhdu,
        2#0_10010_01011#  =>  INSN_mulhw,
        2#0_10000_01011#  =>  INSN_mulhwu,
        2#0_00111_01001#  =>  INSN_mulld,
        2#0_10111_01001#  =>  INSN_mulld, -- mulldo
        2#0_00111_01011#  =>  INSN_mullw,
        2#0_10111_01011#  =>  INSN_mullw, -- mullwo
        2#0_01110_11100#  =>  INSN_nand,
        2#0_00011_01000#  =>  INSN_neg,
        2#0_10011_01000#  =>  INSN_neg, -- nego
        -- next 8 are reserved no-op instructions
        2#0_10000_10010#  =>  INSN_nop,
        2#0_10001_10010#  =>  INSN_nop,
        2#0_10010_10010#  =>  INSN_nop,
        2#0_10011_10010#  =>  INSN_nop,
        2#0_10100_10010#  =>  INSN_nop,
        2#0_10101_10010#  =>  INSN_nop,
        2#0_10110_10010#  =>  INSN_nop,
        2#0_10111_10010#  =>  INSN_nop,
        2#0_00011_11100#  =>  INSN_nor,
        2#0_01101_11100#  =>  INSN_or,
        2#0_01100_11100#  =>  INSN_orc,
        2#0_00011_11010#  =>  INSN_popcntb,
        2#0_01111_11010#  =>  INSN_popcntd,
        2#0_01011_11010#  =>  INSN_popcntw,
        2#0_00101_11010#  =>  INSN_prtyd,
        2#0_00100_11010#  =>  INSN_prtyw,
        2#0_00100_00000#  =>  INSN_setb,
        2#0_01111_10010#  =>  INSN_slbia,
        2#0_00000_11011#  =>  INSN_sld,
        2#0_00000_11000#  =>  INSN_slw,
        2#0_11000_11010#  =>  INSN_srad,
        2#0_11001_11010#  =>  INSN_sradi,
        2#0_11001_11011#  =>  INSN_sradi,
        2#0_11000_11000#  =>  INSN_sraw,
        2#0_11001_11000#  =>  INSN_srawi,
        2#0_10000_11011#  =>  INSN_srd,
        2#0_10000_11000#  =>  INSN_srw,
        2#0_11110_10101#  =>  INSN_stbcix,
        2#0_10101_10110#  =>  INSN_stbcx,
        2#0_00111_10111#  =>  INSN_stbux,
        2#0_00110_10111#  =>  INSN_stbx,
        2#0_10100_10100#  =>  INSN_stdbrx,
        2#0_11111_10101#  =>  INSN_stdcix,
        2#0_00110_10110#  =>  INSN_stdcx,
        2#0_00101_10101#  =>  INSN_stdux,
        2#0_00100_10101#  =>  INSN_stdx,
        2#0_10110_10111#  =>  INSN_stfdx,
        2#0_10111_10111#  =>  INSN_stfdux,
        2#0_11110_10111#  =>  INSN_stfiwx,
        2#0_10100_10111#  =>  INSN_stfsx,
        2#0_10101_10111#  =>  INSN_stfsux,
        2#0_11100_10110#  =>  INSN_sthbrx,
        2#0_11101_10101#  =>  INSN_sthcix,
        2#0_10110_10110#  =>  INSN_sthcx,
        2#0_01101_10111#  =>  INSN_sthux,
        2#0_01100_10111#  =>  INSN_sthx,
        2#0_10100_10110#  =>  INSN_stwbrx,
        2#0_11100_10101#  =>  INSN_stwcix,
        2#0_00100_10110#  =>  INSN_stwcx,
        2#0_00101_10111#  =>  INSN_stwux,
        2#0_00100_10111#  =>  INSN_stwx,
        2#0_00001_01000#  =>  INSN_subf,
        2#0_10001_01000#  =>  INSN_subf, -- subfo
        2#0_00000_01000#  =>  INSN_subfc,
        2#0_10000_01000#  =>  INSN_subfc, -- subfco
        2#0_00100_01000#  =>  INSN_subfe,
        2#0_10100_01000#  =>  INSN_subfe, -- subfeo
        2#0_00111_01000#  =>  INSN_subfme,
        2#0_10111_01000#  =>  INSN_subfme, -- subfmeo
        2#0_00110_01000#  =>  INSN_subfze,
        2#0_10110_01000#  =>  INSN_subfze, -- subfzeo
        2#0_10010_10110#  =>  INSN_sync,
        2#0_00010_00100#  =>  INSN_td,
        2#0_00000_00100#  =>  INSN_tw,
        2#0_01001_10010#  =>  INSN_tlbie,
        2#0_01000_10010#  =>  INSN_tlbiel,
        2#0_10001_10110#  =>  INSN_tlbsync,
        2#0_00000_11110#  =>  INSN_wait,
        2#0_01001_11100#  =>  INSN_xor,

        -- Major opcode 19
        -- Columns with insn(4) = '1' are all illegal and not mapped here; to
        -- fit into 2048 entries, the columns are remapped so that 16-24 are
        -- stored here as 8-15; in other words the address bits are
        -- 1, insn(10..6), 1, insn(5), insn(3..1)
        2#1_10000_11000#  =>  INSN_bcctr,
        2#1_00000_11000#  =>  INSN_bclr,
        2#1_10001_11000#  =>  INSN_bctar,
        2#1_01000_10001#  =>  INSN_crand,
        2#1_00100_10001#  =>  INSN_crandc,
        2#1_01001_10001#  =>  INSN_creqv,
        2#1_00111_10001#  =>  INSN_crnand,
        2#1_00001_10001#  =>  INSN_crnor,
        2#1_01110_10001#  =>  INSN_cror,
        2#1_01101_10001#  =>  INSN_crorc,
        2#1_00110_10001#  =>  INSN_crxor,
        2#1_00100_11110#  =>  INSN_isync,
        2#1_00000_10000#  =>  INSN_mcrf,
        2#1_00000_11010#  =>  INSN_rfid,

        -- Major opcode 59
        -- Only column 14 is valid here; columns 16-31 are handled in the major table
        -- Column 14 is mapped to column 6 of the space which is
        -- mostly used for opcode 19.
        2#1_11010_10110#  =>  INSN_fcfids,
        2#1_11110_10110#  =>  INSN_fcfidus,

        -- Major opcode 63
        -- Columns 0-15 are mapped here; columns 16-31 are in the major table.
        -- Address bits are 1, insn(10:6), 0, insn(4:1)
        2#1_00000_00000#  =>  INSN_fcmpu,
        2#1_00001_00000#  =>  INSN_fcmpo,
        2#1_00010_00000#  =>  INSN_mcrfs,
        2#1_00100_00000#  =>  INSN_ftdiv,
        2#1_00101_00000#  =>  INSN_ftsqrt,
        2#1_00001_00110#  =>  INSN_mtfsb,
        2#1_00010_00110#  =>  INSN_mtfsb,
        2#1_00100_00110#  =>  INSN_mtfsfi,
        2#1_11010_00110#  =>  INSN_fmrgow,
        2#1_11110_00110#  =>  INSN_fmrgew,
        2#1_10010_00111#  =>  INSN_mffs,
        2#1_10110_00111#  =>  INSN_mtfsf,
        2#1_00000_01000#  =>  INSN_fcpsgn,
        2#1_00001_01000#  =>  INSN_fneg,
        2#1_00010_01000#  =>  INSN_fmr,
        2#1_00100_01000#  =>  INSN_fnabs,
        2#1_01000_01000#  =>  INSN_fabs,
        2#1_01100_01000#  =>  INSN_frin,
        2#1_01101_01000#  =>  INSN_friz,
        2#1_01110_01000#  =>  INSN_frip,
        2#1_01111_01000#  =>  INSN_frim,
        2#1_00000_01100#  =>  INSN_frsp,
        2#1_00000_01110#  =>  INSN_fctiw,
        2#1_00100_01110#  =>  INSN_fctiwu,
        2#1_11001_01110#  =>  INSN_fctid,
        2#1_11010_01110#  =>  INSN_fcfid,
        2#1_11101_01110#  =>  INSN_fctidu,
        2#1_11110_01110#  =>  INSN_fcfidu,
        2#1_00000_01111#  =>  INSN_fctiwz,
        2#1_00100_01111#  =>  INSN_fctiwuz,
        2#1_11001_01111#  =>  INSN_fctidz,
        2#1_11101_01111#  =>  INSN_fctiduz,

        others            =>  INSN_illegal
        );

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
    decode0_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                dc0 <= dc0_t_init;
            elsif flush_in = '1' then
                dc0.f_in.valid <= '0';
                dc0.f_in.fetch_failed <= '0';
            elsif stall_in = '0' then
                dc0 <= dc0in;
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

    decode0_roms: process(clk)
    begin
        if rising_edge(clk) then
            if stall_in = '0' then
                if is_X(maj_rom_addr) then
                    major_predecode <= INSN_illegal;
                else
                    major_predecode <= major_predecode_rom(to_integer(unsigned(maj_rom_addr)));
                end if;
                if is_X(row_rom_addr) then
                    row_predecode   <= INSN_illegal;
                else
                    row_predecode   <= row_predecode_rom(to_integer(unsigned(row_rom_addr)));
                end if;
            end if;
        end if;
    end process;

    decode0_1: process(all)
        variable v : dc0_t;
        variable majorop : std_ulogic_vector(5 downto 0);
        variable majaddr : std_ulogic_vector(10 downto 0);
        variable rowaddr : std_ulogic_vector(10 downto 0);
        variable sprn : spr_num_t;
        variable br_target : std_ulogic_vector(61 downto 0);
        variable br_offset : signed(23 downto 0);
        variable bv : br_predictor_t;
    begin
        v := dc0_t_init;
        v.f_in := f_in;

        br_offset := (others => '0');

        majorop := f_in.insn(31 downto 26);
        majaddr := majorop & f_in.insn(4 downto 0);

        -- row_predecode_rom is used for op 19, 31, 59, 63
        -- addr bit 10 is 0 for op 31, 1 for 19, 59, 63
        rowaddr(10) := f_in.insn(31) or not f_in.insn(29);
        rowaddr(9 downto 5) := f_in.insn(10 downto 6);
        if f_in.insn(28) = '0' then
            -- op 19 and op 59
            rowaddr(4 downto 3) := '1' & f_in.insn(5);
        else
            -- op 31 and 63; for 63 we only use this when f_in.insn(5) = '0'
            rowaddr(4 downto 3) := f_in.insn(5 downto 4);
        end if;
        rowaddr(2 downto 0) := f_in.insn(3 downto 1);

        maj_rom_addr <= majaddr;
        row_rom_addr <= rowaddr;

	if is_X(f_in.insn) then
	    v.spr_info := (sel => "XXX", others => 'X');
	    v.ram_spr := (index => (others => 'X'), others => 'X');
	else
	    sprn := decode_spr_num(f_in.insn);
	    v.spr_info := map_spr(sprn);
	    v.ram_spr := decode_ram_spr(sprn);
	end if;

        case unsigned(majorop) is
        when "000100" => -- 4
            -- major opcode 4, mostly VMX/VSX stuff but also some integer ops (madd*)
            v.override := not f_in.insn(5);

        when "011111" => -- 31
            -- major opcode 31, lots of things
            -- Use the first half of the row table for all columns
            v.use_row := '1';

        when "010000" => -- 16
            -- Predict backward branches as taken, forward as untaken
            v.br_pred := f_in.insn(15);
            br_offset := resize(signed(f_in.insn(15 downto 2)), 24);

        when "010010" => -- 18
            -- Unconditional branches are always taken
            v.br_pred := '1';
            br_offset := signed(f_in.insn(25 downto 2));

        when "010011" => -- 19
            -- Columns 8-15 and 24-31 don't have any valid instructions
            -- (where insn(5..1) is the column number).
            -- addpcis (column 2) is in the major table
            -- Other valid columns are mapped to columns in the second
            -- half of the row table: columns 0-1 are mapped to 16-17
            -- and 16-23 are mapped to 24-31.
            v.override := f_in.insn(4);
            v.use_row := f_in.insn(5) or (not f_in.insn(3) and not f_in.insn(2));

        when "011000" => -- 24
            -- ori, special-case the standard NOP
            if std_match(f_in.insn, "01100000000000000000000000000000") then
                v.override := '1';
                v.ov_insn := INSN_nop;
            end if;

        when "111011" => -- 59
            if HAS_FPU then
                -- floating point operations, mostly single-precision
                -- Columns 0-11 are illegal; columns 12-15 are mapped
                -- to columns 20-23 in the second half of the row table,
                -- and columns 16-31 are in the major table.
                v.override := not f_in.insn(5) and (not f_in.insn(4) or not f_in.insn(3));
                v.use_row := not f_in.insn(5);
            else
                v.override := '1';
            end if;

        when "111111" => -- 63
            if HAS_FPU then
                -- floating point operations, general and double-precision
                -- Use columns 0-15 of the second half of the row table
                -- for columns 0-15, and the major table for columns 16-31.
                v.use_row := not f_in.insn(5);
            else
                v.override := '1';
            end if;

        when others =>
        end case;

        if f_in.fetch_failed = '1' then
            v.override := '1';
            v.ov_insn := INSN_fetch_fail;
            -- Only send down a single OP_FETCH_FAILED
            v.f_in.valid := not dc0.f_in.fetch_failed;
        end if;

        -- Branch predictor
        -- Note bclr, bcctr and bctar are predicted not taken as we have no
        -- count cache or link stack.
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

        dc0in <= v;
        br_in <= bv;

        f_out.redirect <= br.predict;
        f_out.redirect_nia <= br_target & "00";
        flush_out <= bv.predict or br.predict;
    end process;

    decode1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r <= Decode1ToDecode2Init;
            elsif flush_in = '1' then
                r.valid <= '0';
            elsif stall_in = '0' then
                r <= rin;
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
        variable icode : insn_code;
        variable sprn : spr_num_t;
        variable maybe_rb : std_ulogic;
    begin
        v := Decode1ToDecode2Init;

        v.valid := dc0.f_in.valid;
        v.nia  := dc0.f_in.nia;
        v.insn := dc0.f_in.insn;
        v.stop_mark := dc0.f_in.stop_mark;
        v.big_endian := dc0.f_in.big_endian;
        v.br_pred := dc0.br_pred;
        v.spr_info := dc0.spr_info;
        v.ram_spr := dc0.ram_spr;

        if dc0.override = '1' then
            icode := dc0.ov_insn;
        elsif dc0.use_row = '0' then
            icode := major_predecode;
        else
            icode := row_predecode;
        end if;
        decode_rom_addr <= icode;

        if dc0.f_in.valid = '1' then
            report "Decode insn " & to_hstring(dc0.f_in.insn) & " at " & to_hstring(dc0.f_in.nia) &
                " code " & insn_code'image(icode);
        end if;

        -- Work out GPR/FPR read addresses
        maybe_rb := '0';
        vr.reg_1_addr := '0' & insn_ra(dc0.f_in.insn);
        vr.reg_2_addr := '0' & insn_rb(dc0.f_in.insn);
        vr.reg_3_addr := '0' & insn_rs(dc0.f_in.insn);
        if icode >= INSN_first_rb then
            maybe_rb := '1';
            if icode < INSN_first_frs then
                if icode >= INSN_first_rc then
                    vr.reg_3_addr := '0' & insn_rcreg(dc0.f_in.insn);
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
                    vr.reg_3_addr := '1' & insn_rcreg(dc0.f_in.insn);
                end if;
            end if;
        end if;
        vr.read_1_enable := dc0.f_in.valid and not dc0.f_in.fetch_failed;
        vr.read_2_enable := dc0.f_in.valid and not dc0.f_in.fetch_failed and maybe_rb;
        vr.read_3_enable := dc0.f_in.valid and not dc0.f_in.fetch_failed;

        v.reg_a := vr.reg_1_addr;
        v.reg_b := vr.reg_2_addr;
        v.reg_c := vr.reg_3_addr;

        -- Update registers
        rin <= v;

        -- Update outputs
        d_out <= r;
        d_out.decode <= decode;
        r_out <= vr;
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
