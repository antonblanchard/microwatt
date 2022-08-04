-- Instruction pre-decoder for microwatt
-- One cycle latency.  Does 'WIDTH' instructions in parallel.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;
use work.insn_helpers.all;

entity predecoder is
    generic (
        HAS_FPU   : boolean := true;
        WIDTH     : natural := 2;
        ICODE_LEN : natural := 10;
        IMAGE_LEN : natural := 26
        );
    port (
        clk        : in  std_ulogic;
        valid_in   : in  std_ulogic;
        insns_in   : in  std_ulogic_vector(WIDTH * 32 - 1 downto 0);
        icodes_out : out std_ulogic_vector(WIDTH * (ICODE_LEN + IMAGE_LEN) - 1 downto 0)
        );
end entity predecoder;

architecture behaviour of predecoder is

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
        -- Columns 16-17 here are opcode 19 columns 0-1
        -- Columns 24-31 here are opcode 19 columns 16-23
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
        -- Address bits are 1, insn(10..6), 1, 0, insn(3..1)
        -- Only column 14 is valid here; columns 16-31 are handled in the major table
        -- Column 14 is mapped to column 22.
        -- Columns 20-23 here are opcode 59 columns 12-15
        2#1_11010_10110#  =>  INSN_fcfids,
        2#1_11110_10110#  =>  INSN_fcfidus,

        -- Major opcode 63
        -- Columns 0-15 are mapped here; columns 16-31 are in the major table.
        -- Address bits are 1, insn(10:6), 0, insn(4:1)
        -- Columns 0-15 here are opcode 63 columns 0-15
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

    constant IOUT_LEN : natural := ICODE_LEN + IMAGE_LEN;

    type predec_t is record
        image         : std_ulogic_vector(31 downto 0);
        maj_predecode : unsigned(ICODE_LEN - 1 downto 0);
        row_predecode : unsigned(ICODE_LEN - 1 downto 0);
    end record;

    subtype index_t is integer range 0 to WIDTH-1;
    type predec_array is array(index_t) of predec_t;

    signal pred : predec_array;
    signal valid : std_ulogic;

begin
    predecode_0: process(clk)
        variable majaddr  : std_ulogic_vector(10 downto 0);
        variable rowaddr  : std_ulogic_vector(10 downto 0);
        variable iword    : std_ulogic_vector(31 downto 0);
        variable majcode  : insn_code;
        variable rowcode  : insn_code;
    begin
        if rising_edge(clk) then
            valid <= valid_in;
            for i in index_t loop
                iword := insns_in(i * 32 + 31 downto i * 32);
                pred(i).image <= iword;

                if is_X(iword) then
                    pred(i).maj_predecode <= (others => 'X');
                    pred(i).row_predecode <= (others => 'X');
                else
                    majaddr := iword(31 downto 26) & iword(4 downto 0);

                    -- row_predecode_rom is used for op 19, 31, 59, 63
                    -- addr bit 10 is 0 for op 31, 1 for 19, 59, 63
                    rowaddr(10) := iword(31) or not iword(29);
                    rowaddr(9 downto 5) := iword(10 downto 6);
                    if iword(28) = '0' then
                        -- op 19 and op 59
                        rowaddr(4 downto 3) := '1' & iword(5);
                    else
                        -- op 31 and 63; for 63 we only use this when iword(5) = '0'
                        rowaddr(4 downto 3) := iword(5 downto 4);
                    end if;
                    rowaddr(2 downto 0) := iword(3 downto 1);

                    majcode := major_predecode_rom(to_integer(unsigned(majaddr)));
                    pred(i).maj_predecode <= to_unsigned(insn_code'pos(majcode), ICODE_LEN);
                    rowcode := row_predecode_rom(to_integer(unsigned(rowaddr)));
                    pred(i).row_predecode <= to_unsigned(insn_code'pos(rowcode), ICODE_LEN);
                end if;
            end loop;
        end if;
    end process;

    predecode_1: process(all)
        variable iword    : std_ulogic_vector(31 downto 0);
        variable use_row  : std_ulogic;
        variable illegal  : std_ulogic;
        variable ici      : std_ulogic_vector(IOUT_LEN - 1 downto 0);
        variable icode    : unsigned(ICODE_LEN - 1 downto 0);
    begin
        for i in index_t loop
            iword := pred(i).image;
            icode := pred(i).maj_predecode;
            use_row := '0';
            illegal := '0';

            case iword(31 downto 26) is
                when "000100" => -- 4
                    -- major opcode 4, mostly VMX/VSX stuff but also some integer ops (madd*)
                    illegal := not iword(5);

                when "010011" => -- 19
                    -- Columns 8-15 and 24-31 don't have any valid instructions
                    -- (where insn(5..1) is the column number).
                    -- addpcis (column 2) is in the major table
                    -- Other valid columns are mapped to columns in the second
                    -- half of the row table: columns 0-1 are mapped to 16-17
                    -- and 16-23 are mapped to 24-31.
                    illegal := iword(4);
                    use_row := iword(5) or (not iword(3) and not iword(2));

                when "011000" => -- 24
                    -- ori, special-case the standard NOP
                    if std_match(iword, "01100000000000000000000000000000") then
                        icode := to_unsigned(insn_code'pos(INSN_nop), ICODE_LEN);
                    end if;

                when "011111" => -- 31
                    -- major opcode 31, lots of things
                    -- Use the first half of the row table for all columns
                    use_row := '1';

                when "111011" => -- 59
                    -- floating point operations, mostly single-precision
                    -- Columns 0-11 are illegal; columns 12-15 are mapped
                    -- to columns 20-23 in the second half of the row table,
                    -- and columns 16-31 are in the major table.
                    illegal := not iword(5) and (not iword(4) or not iword(3));
                    use_row := not iword(5);

                when "111111" => -- 63
                    -- floating point operations, general and double-precision
                    -- Use columns 0-15 of the second half of the row table
                    -- for columns 0-15, and the major table for columns 16-31.
                    use_row := not iword(5);

                when others =>
            end case;
            if use_row = '1' then
                icode := pred(i).row_predecode;
            end if;

            -- Mark FP instructions as illegal if we don't have an FPU
            if not HAS_FPU and not is_X(icode) and
                to_integer(icode) >= insn_code'pos(INSN_first_frs) then
                illegal := '1';
            end if;

            ici(31 downto 0) := iword;
            ici(IOUT_LEN - 1 downto 32) := (others => '0');
            if valid = '0' or illegal = '1' or is_X(icode) or
                icode = to_unsigned(insn_code'pos(INSN_illegal), ICODE_LEN) then
                -- Since an insn_code currently fits in 9 bits, use just
                -- the most significant bit of ici to indicate illegal insns.
                ici(IOUT_LEN - 1) := '1';
            else
                ici(IOUT_LEN - 1 downto IMAGE_LEN) := std_ulogic_vector(icode);
            end if;
            icodes_out(i * IOUT_LEN + IOUT_LEN - 1 downto i * IOUT_LEN) <= ici;
        end loop;
    end process;

end architecture behaviour;
