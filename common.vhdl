library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils.all;
use work.decode_types.all;

package common is
    -- Processor Version Number
    constant PVR_MICROWATT  : std_ulogic_vector(31 downto 0) := x"00630000";

    -- MSR bit numbers
    constant MSR_SF  : integer := (63 - 0);     -- Sixty-Four bit mode
    constant MSR_HV  : integer := (63 - 3);     -- Hypervisor mode (always 1)
    constant MSR_EE  : integer := (63 - 48);    -- External interrupt Enable
    constant MSR_PR  : integer := (63 - 49);    -- PRoblem state
    constant MSR_FP  : integer := (63 - 50);    -- Floating Point available
    constant MSR_FE0 : integer := (63 - 52);    -- Floating Exception mode
    constant MSR_SE  : integer := (63 - 53);    -- Single-step bit of TE field
    constant MSR_BE  : integer := (63 - 54);    -- Branch trace bit of TE field
    constant MSR_FE1 : integer := (63 - 55);    -- Floating Exception mode
    constant MSR_IR  : integer := (63 - 58);    -- Instruction Relocation
    constant MSR_DR  : integer := (63 - 59);    -- Data Relocation
    constant MSR_PMM : integer := (63 - 61);    -- Performance Monitor Mark
    constant MSR_RI  : integer := (63 - 62);    -- Recoverable Interrupt
    constant MSR_LE  : integer := (63 - 63);    -- Little Endian

    -- SPR numbers
    subtype spr_num_t is integer range 0 to 1023;

    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t;

    constant SPR_XER    : spr_num_t := 1;
    constant SPR_LR     : spr_num_t := 8;
    constant SPR_CTR    : spr_num_t := 9;
    constant SPR_TAR    : spr_num_t := 815;
    constant SPR_DSISR  : spr_num_t := 18;
    constant SPR_DAR    : spr_num_t := 19;
    constant SPR_TB     : spr_num_t := 268;
    constant SPR_TBU    : spr_num_t := 269;
    constant SPR_TBLW   : spr_num_t := 284;
    constant SPR_TBUW   : spr_num_t := 285;
    constant SPR_DEC    : spr_num_t := 22;
    constant SPR_SRR0   : spr_num_t := 26;
    constant SPR_SRR1   : spr_num_t := 27;
    constant SPR_CFAR   : spr_num_t := 28;
    constant SPR_HSRR0  : spr_num_t := 314;
    constant SPR_HSRR1  : spr_num_t := 315;
    constant SPR_SPRG0  : spr_num_t := 272;
    constant SPR_SPRG1  : spr_num_t := 273;
    constant SPR_SPRG2  : spr_num_t := 274;
    constant SPR_SPRG3  : spr_num_t := 275;
    constant SPR_SPRG3U : spr_num_t := 259;
    constant SPR_HSPRG0 : spr_num_t := 304;
    constant SPR_HSPRG1 : spr_num_t := 305;
    constant SPR_PID    : spr_num_t := 48;
    constant SPR_PTCR   : spr_num_t := 464;
    constant SPR_LPCR   : spr_num_t := 318;
    constant SPR_PVR	: spr_num_t := 287;
    constant SPR_FSCR   : spr_num_t := 153;
    constant SPR_HFSCR  : spr_num_t := 190;
    constant SPR_HEIR   : spr_num_t := 339;
    constant SPR_CTRL   : spr_num_t := 136;
    constant SPR_CTRLW  : spr_num_t := 152;
    constant SPR_UDSCR  : spr_num_t := 3;
    constant SPR_DSCR   : spr_num_t := 17;
    constant SPR_VRSAVE : spr_num_t := 256;
    constant SPR_PIR    : spr_num_t := 1023;
    constant SPR_CIABR  : spr_num_t := 187;
    constant SPR_DAWR0  : spr_num_t := 180;
    constant SPR_DAWR1  : spr_num_t := 181;
    constant SPR_DAWRX0 : spr_num_t := 188;
    constant SPR_DAWRX1 : spr_num_t := 189;
    constant SPR_HASHKEYR  : spr_num_t := 468;
    constant SPR_HASHPKEYR : spr_num_t := 469;
    constant SPR_DEXCR  : spr_num_t := 828;
    constant SPR_DEXCRU : spr_num_t := 812;
    constant SPR_HDEXCR : spr_num_t := 471;
    constant SPR_HDEXCU : spr_num_t := 455;
    constant SPR_NOOP0  : spr_num_t := 808;
    constant SPR_NOOP1  : spr_num_t := 809;
    constant SPR_NOOP2  : spr_num_t := 810;
    constant SPR_NOOP3  : spr_num_t := 811;
    constant SPR_HMER   : spr_num_t := 336;
    constant SPR_HMEER  : spr_num_t := 337;
    constant SPR_HRMOR  : spr_num_t := 313;

    -- PMU registers
    constant SPR_UPMC1  : spr_num_t := 771;
    constant SPR_UPMC2  : spr_num_t := 772;
    constant SPR_UPMC3  : spr_num_t := 773;
    constant SPR_UPMC4  : spr_num_t := 774;
    constant SPR_UPMC5  : spr_num_t := 775;
    constant SPR_UPMC6  : spr_num_t := 776;
    constant SPR_UMMCR0 : spr_num_t := 779;
    constant SPR_UMMCR1 : spr_num_t := 782;
    constant SPR_UMMCR2 : spr_num_t := 769;
    constant SPR_UMMCRA : spr_num_t := 770;
    constant SPR_USIER  : spr_num_t := 768;
    constant SPR_USIAR  : spr_num_t := 780;
    constant SPR_USDAR  : spr_num_t := 781;
    constant SPR_USIER2 : spr_num_t := 736;
    constant SPR_USIER3 : spr_num_t := 737;
    constant SPR_UMMCR3 : spr_num_t := 738;
    constant SPR_PMC1   : spr_num_t := 787;
    constant SPR_PMC2   : spr_num_t := 788;
    constant SPR_PMC3   : spr_num_t := 789;
    constant SPR_PMC4   : spr_num_t := 790;
    constant SPR_PMC5   : spr_num_t := 791;
    constant SPR_PMC6   : spr_num_t := 792;
    constant SPR_MMCR0  : spr_num_t := 795;
    constant SPR_MMCR1  : spr_num_t := 798;
    constant SPR_MMCR2  : spr_num_t := 785;
    constant SPR_MMCRA  : spr_num_t := 786;
    constant SPR_SIER   : spr_num_t := 784;
    constant SPR_SIAR   : spr_num_t := 796;
    constant SPR_SDAR   : spr_num_t := 797;
    constant SPR_SIER2  : spr_num_t := 752;
    constant SPR_SIER3  : spr_num_t := 753;
    constant SPR_MMCR3  : spr_num_t := 754;

    -- GPR indices in the register file (GPR only)
    subtype gpr_index_t is std_ulogic_vector(4 downto 0);

    -- Extended GPR index (can hold a GPR or a FPR)
    subtype gspr_index_t is std_ulogic_vector(5 downto 0);

    -- FPR indices
    subtype fpr_index_t is std_ulogic_vector(4 downto 0);

    -- FPRs are stored in the register file, using GSPR
    -- numbers from 32 to 63.
    --

    -- Indices conversion functions
    function gspr_to_gpr(i: gspr_index_t) return gpr_index_t;
    function gpr_to_gspr(i: gpr_index_t) return gspr_index_t;
    function fpr_to_gspr(f: fpr_index_t) return gspr_index_t;

    -- The XER is split: the common bits (CA, OV, SO, OV32 and CA32) are
    -- in the CR file as a kind of CR extension (with a separate write
    -- control). The rest is stored in ctrl_t (effectively in execute1).
    type xer_common_t is record
	ca : std_ulogic;
	ca32 : std_ulogic;
	ov : std_ulogic;
	ov32 : std_ulogic;
	so : std_ulogic;
    end record;
    constant xerc_init : xer_common_t := (others => '0');

    -- Some SPRs are stored in a pair of small RAMs in execute1
    -- Even half:
    subtype ramspr_index_range is natural range 0 to 7;
    subtype ramspr_index is unsigned(2 downto 0);
    constant RAMSPR_SRR0   : ramspr_index := to_unsigned(0,3);
    constant RAMSPR_HSRR0  : ramspr_index := to_unsigned(1,3);
    constant RAMSPR_SPRG0  : ramspr_index := to_unsigned(2,3);
    constant RAMSPR_SPRG2  : ramspr_index := to_unsigned(3,3);
    constant RAMSPR_HSPRG0 : ramspr_index := to_unsigned(4,3);
    constant RAMSPR_LR     : ramspr_index := to_unsigned(5,3);         -- must equal RAMSPR_CTR
    constant RAMSPR_TAR    : ramspr_index := to_unsigned(6,3);
    constant RAMSPR_VRSAVE : ramspr_index := to_unsigned(7,3);
    -- Odd half:
    constant RAMSPR_SRR1   : ramspr_index := to_unsigned(0,3);
    constant RAMSPR_HSRR1  : ramspr_index := to_unsigned(1,3);
    constant RAMSPR_SPRG1  : ramspr_index := to_unsigned(2,3);
    constant RAMSPR_SPRG3  : ramspr_index := to_unsigned(3,3);
    constant RAMSPR_HSPRG1 : ramspr_index := to_unsigned(4,3);
    constant RAMSPR_CTR    : ramspr_index := to_unsigned(5,3);         -- must equal RAMSPR_LR
    constant RAMSPR_HASHKY : ramspr_index := to_unsigned(6,3);
    constant RAMSPR_HASHPK : ramspr_index := to_unsigned(7,3);

    type ram_spr_info is record
        index : ramspr_index;
        isodd : std_ulogic;
        is32b : std_ulogic;
        valid : std_ulogic;
    end record;
    constant ram_spr_info_init: ram_spr_info := (index => to_unsigned(0,3), others => '0');

    subtype spr_selector is std_ulogic_vector(3 downto 0);
    type spr_id is record
        sel   : spr_selector;
        valid : std_ulogic;
        ispmu : std_ulogic;
        ronly : std_ulogic;
        wonly : std_ulogic;
        noop  : std_ulogic;
    end record;
    constant spr_id_init : spr_id := (sel => "0000", others => '0');

    constant SPRSEL_ZERO  : spr_selector := 4x"0";
    constant SPRSEL_TB    : spr_selector := 4x"1";
    constant SPRSEL_TBU   : spr_selector := 4x"2";
    constant SPRSEL_DEC   : spr_selector := 4x"3";
    constant SPRSEL_PVR   : spr_selector := 4x"4";
    constant SPRSEL_LOGR  : spr_selector := 4x"5";
    constant SPRSEL_CFAR  : spr_selector := 4x"6";
    constant SPRSEL_FSCR  : spr_selector := 4x"7";
    constant SPRSEL_LPCR  : spr_selector := 4x"8";
    constant SPRSEL_HEIR  : spr_selector := 4x"9";
    constant SPRSEL_CTRL  : spr_selector := 4x"a";
    constant SPRSEL_DSCR  : spr_selector := 4x"b";
    constant SPRSEL_PIR   : spr_selector := 4x"c";
    constant SPRSEL_CIABR : spr_selector := 4x"d";
    constant SPRSEL_DEXCR : spr_selector := 4x"e";
    constant SPRSEL_XER   : spr_selector := 4x"f";

    -- FSCR bit numbers
    constant FSCR_PREFIX   : integer := 63 - 50;
    constant FSCR_SCV      : integer := 63 - 51;
    constant FSCR_TAR      : integer := 63 - 55;
    constant FSCR_DSCR     : integer := 63 - 61;

    -- FPSCR bit numbers
    constant FPSCR_FX     : integer := 63 - 32;
    constant FPSCR_FEX    : integer := 63 - 33;
    constant FPSCR_VX     : integer := 63 - 34;
    constant FPSCR_OX     : integer := 63 - 35;
    constant FPSCR_UX     : integer := 63 - 36;
    constant FPSCR_ZX     : integer := 63 - 37;
    constant FPSCR_XX     : integer := 63 - 38;
    constant FPSCR_VXSNAN : integer := 63 - 39;
    constant FPSCR_VXISI  : integer := 63 - 40;
    constant FPSCR_VXIDI  : integer := 63 - 41;
    constant FPSCR_VXZDZ  : integer := 63 - 42;
    constant FPSCR_VXIMZ  : integer := 63 - 43;
    constant FPSCR_VXVC   : integer := 63 - 44;
    constant FPSCR_FR     : integer := 63 - 45;
    constant FPSCR_FI     : integer := 63 - 46;
    constant FPSCR_C      : integer := 63 - 47;
    constant FPSCR_FL     : integer := 63 - 48;
    constant FPSCR_FG     : integer := 63 - 49;
    constant FPSCR_FE     : integer := 63 - 50;
    constant FPSCR_FU     : integer := 63 - 51;
    constant FPSCR_VXSOFT : integer := 63 - 53;
    constant FPSCR_VXSQRT : integer := 63 - 54;
    constant FPSCR_VXCVI  : integer := 63 - 55;
    constant FPSCR_VE     : integer := 63 - 56;
    constant FPSCR_OE     : integer := 63 - 57;
    constant FPSCR_UE     : integer := 63 - 58;
    constant FPSCR_ZE     : integer := 63 - 59;
    constant FPSCR_XE     : integer := 63 - 60;
    constant FPSCR_NI     : integer := 63 - 61;
    constant FPSCR_RN     : integer := 63 - 63;

    -- LPCR bit numbers
    constant LPCR_HAIL    : integer := 63 - 37;
    constant LPCR_UPRT    : integer := 63 - 41;
    constant LPCR_HR      : integer := 63 - 43;
    constant LPCR_LD      : integer := 63 - 46;
    constant LPCR_HEIC    : integer := 63 - 59;
    constant LPCR_LPES    : integer := 63 - 60;
    constant LPCR_HVICE   : integer := 63 - 62;

    -- Real addresses
    -- REAL_ADDR_BITS is the number of real address bits that we store
    constant REAL_ADDR_BITS : positive := 56;
    subtype real_addr_t is std_ulogic_vector(REAL_ADDR_BITS - 1 downto 0);
    function addr_to_real(addr: std_ulogic_vector(63 downto 0)) return real_addr_t;

    -- Minimum page size
    constant MIN_LG_PGSZ : positive := 12;
    constant MIN_PAGESZ  : positive := 2 ** MIN_LG_PGSZ;

    -- Used for tracking instruction completion and pending register writes
    constant TAG_COUNT : positive := 4;
    constant TAG_NUMBER_BITS : natural := log2(TAG_COUNT);
    subtype tag_number_t is integer range 0 to TAG_COUNT - 1;
    subtype tag_index_t is unsigned(TAG_NUMBER_BITS - 1 downto 0);
    type instr_tag_t is record
        tag   : tag_number_t;
        valid : std_ulogic;
    end record;
    constant instr_tag_init : instr_tag_t := (tag => 0, valid => '0');
    function tag_match(tag1 : instr_tag_t; tag2 : instr_tag_t) return boolean;

    subtype intr_vector_t is integer range 0 to 16#fff#;

    -- For now, fixed 16 sources, make this either a parametric
    -- package of some sort or an unconstrainted array.
    -- We don't know NCPUS or SRC_NUM here, so make this
    -- large enough for 4 cpus and 16 interrupt sources for now.
    type ics_to_icp_t is record
        -- Level interrupts only, ICS just keeps prsenting the
        -- highest priority interrupt. Once handling edge, something
        -- smarter involving handshake & reject support will be needed
        src : std_ulogic_vector(15 downto 0);   -- 4 bits each for 4 cpus
        pri : std_ulogic_vector(31 downto 0);   -- 8 bits each for 4 cpus
    end record;

    -- Bits in each half of DEXCR and HDEXCR
    subtype aspect_bits_t is std_ulogic_vector(4 downto 0);
    constant aspect_bits_init : aspect_bits_t := (others => '1');
    -- Bit numbers in aspect_bits_t
    constant DEXCR_SBHE   : integer := 4;       -- speculative branch hint enable
    constant DEXCR_IBRTPD : integer := 3;       -- indirect branch recurrent target prediction disable
    constant DEXCR_SRAPD  : integer := 2;       -- subroutine return address prediction disable
    constant DEXCR_NPHIE  : integer := 1;       -- non-privileged hash instruction enable
    constant DEXCR_PHIE   : integer := 0;       -- privileged hash instruction enable

    -- This needs to die...
    type ctrl_t is record
        wait_state: std_ulogic;
        run: std_ulogic;
	dec: std_ulogic_vector(63 downto 0);
	msr: std_ulogic_vector(63 downto 0);
        cfar: std_ulogic_vector(63 downto 0);
        xer_low: std_ulogic_vector(17 downto 0);
        fscr_ic: std_ulogic_vector(3 downto 0);
        fscr_pref: std_ulogic;
        fscr_scv: std_ulogic;
        fscr_tar: std_ulogic;
        fscr_dscr: std_ulogic;
        heir: std_ulogic_vector(63 downto 0);
        dscr: std_ulogic_vector(24 downto 0);
        ciabr: std_ulogic_vector(63 downto 0);
        dexcr_pnh: aspect_bits_t;
        dexcr_pro: aspect_bits_t;
        hdexcr_hyp: aspect_bits_t;
        hdexcr_enf: aspect_bits_t;
        lpcr_hail: std_ulogic;
        lpcr_ld: std_ulogic;
        lpcr_heic: std_ulogic;
        lpcr_lpes: std_ulogic;
        lpcr_hvice: std_ulogic;
    end record;
    constant ctrl_t_init : ctrl_t :=
        (wait_state => '0', run => '1', xer_low => 18x"0",
         fscr_ic => x"0", fscr_pref => '1', fscr_scv => '1', fscr_tar => '1', fscr_dscr => '1',
         dscr => (others => '0'),
         dexcr_pnh => aspect_bits_init, dexcr_pro => aspect_bits_init,
         hdexcr_hyp => aspect_bits_init, hdexcr_enf => aspect_bits_init,
         lpcr_hail => '0', lpcr_ld => '1', lpcr_heic => '0',
         lpcr_lpes => '0', lpcr_hvice => '0',
         others => (others => '0'));

    type timebase_ctrl is record
        reset   : std_ulogic;
        rd_prot : std_ulogic;           -- read-protect => userspace can't read TB
        freeze  : std_ulogic;
    end record;

    type Fetch1ToIcacheType is record
	req: std_ulogic;
        fetch_fail : std_ulogic;
        virt_mode : std_ulogic;
        priv_mode : std_ulogic;
        big_endian : std_ulogic;
	stop_mark: std_ulogic;
        predicted : std_ulogic;
        pred_ntaken : std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
        next_nia: std_ulogic_vector(63 downto 0);
        rpn: std_ulogic_vector(REAL_ADDR_BITS - MIN_LG_PGSZ - 1 downto 0);
        next_rpn: std_ulogic_vector(REAL_ADDR_BITS - MIN_LG_PGSZ - 1 downto 0);
    end record;

    type IcacheToDecode1Type is record
	valid: std_ulogic;
	stop_mark: std_ulogic;
        fetch_failed: std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
	insn: std_ulogic_vector(31 downto 0);
        icode: insn_code;
        big_endian: std_ulogic;
        next_predicted: std_ulogic;
        next_pred_ntaken: std_ulogic;
    end record;
    constant IcacheToDecode1Init : IcacheToDecode1Type :=
        (nia => (others => '0'), insn => (others => '0'), icode => INSN_illegal, others => '0');

    type IcacheEventType is record
        icache_miss : std_ulogic;
        itlb_miss_resolved : std_ulogic;
    end record;

    type Decode1ToDecode2Type is record
	valid: std_ulogic;
	stop_mark : std_ulogic;
        second : std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
        prefixed: std_ulogic;
        prefix: std_ulogic_vector(25 downto 0);
        illegal_suffix: std_ulogic;
        misaligned_prefix: std_ulogic;
	insn: std_ulogic_vector(31 downto 0);
	decode: decode_rom_t;
        br_pred: std_ulogic; -- Branch was predicted to be taken
        big_endian: std_ulogic;
        spr_info : spr_id;
        ram_spr : ram_spr_info;
        reg_a : gspr_index_t;
        reg_b : gspr_index_t;
        reg_c : gspr_index_t;
    end record;
    constant Decode1ToDecode2Init : Decode1ToDecode2Type :=
        (valid => '0', stop_mark => '0', second => '0', nia => (others => '0'),
         prefixed => '0', prefix => (others => '0'), insn => (others => '0'),
         illegal_suffix => '0', misaligned_prefix => '0',
         decode => decode_rom_init, br_pred => '0', big_endian => '0',
         spr_info => spr_id_init, ram_spr => ram_spr_info_init,
         reg_a => (others => '0'), reg_b => (others => '0'), reg_c => (others => '0'));

    type Decode1ToFetch1Type is record
        redirect     : std_ulogic;
        redirect_nia : std_ulogic_vector(63 downto 0);
    end record;

    type Decode1ToRegisterFileType is record
        reg_1_addr : gspr_index_t;
        reg_2_addr : gspr_index_t;
        reg_3_addr : gspr_index_t;
        read_1_enable : std_ulogic;
        read_2_enable : std_ulogic;
        read_3_enable : std_ulogic;
    end record;

    type bypass_data_t is record
        tag  : instr_tag_t;
        data : std_ulogic_vector(63 downto 0);
    end record;
    constant bypass_data_init : bypass_data_t := (tag => instr_tag_init, data => (others => '0'));

    type cr_bypass_data_t is record
        tag  : instr_tag_t;
        data : std_ulogic_vector(31 downto 0);
    end record;
    constant cr_bypass_data_init : cr_bypass_data_t := (tag => instr_tag_init, data => (others => '0'));

    type Decode2ToExecute1Type is record
	valid: std_ulogic;
        unit : unit_t;
        fac : facility_t;
	insn_type: insn_type_t;
	nia: std_ulogic_vector(63 downto 0);
        instr_tag : instr_tag_t;
	write_reg: gspr_index_t;
        write_reg_enable: std_ulogic;
	read_reg1: gspr_index_t;
	read_reg2: gspr_index_t;
	read_reg3: gspr_index_t;
	read_data1: std_ulogic_vector(63 downto 0);
	read_data2: std_ulogic_vector(63 downto 0);
	read_data3: std_ulogic_vector(63 downto 0);
        reg_valid1: std_ulogic;
        reg_valid2: std_ulogic;
        reg_valid3: std_ulogic;
	cr: std_ulogic_vector(31 downto 0);
	xerc: xer_common_t;
	lr: std_ulogic;
        br_abs: std_ulogic;
	rc: std_ulogic;
	oe: std_ulogic;
	invert_a: std_ulogic;
	invert_out: std_ulogic;
	input_carry: carry_in_t;
	output_carry: std_ulogic;
	input_cr: std_ulogic;
	output_cr: std_ulogic;
        output_xer: std_ulogic;
	is_32bit: std_ulogic;
	is_signed: std_ulogic;
	insn: std_ulogic_vector(31 downto 0);
	data_len: std_ulogic_vector(3 downto 0);
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;			-- do we need to sign extend?
	update : std_ulogic;				-- is this an update instruction?
        reserve : std_ulogic;                           -- set for larx/stcx
        br_pred : std_ulogic;
        result_sel : result_sel_t;                      -- select source of result
        sub_select : subresult_sel_t;                   -- sub-result selection
        repeat : std_ulogic;                            -- set if instruction is cracked into two ops
        second : std_ulogic;                            -- set if this is the second op
        spr_select : spr_id;
        spr_is_ram : std_ulogic;
        ramspr_even_rdaddr : ramspr_index;
        ramspr_odd_rdaddr  : ramspr_index;
        ramspr_rd_odd      : std_ulogic;
        ramspr_wraddr      : ramspr_index;
        ramspr_write_even  : std_ulogic;
        ramspr_write_odd   : std_ulogic;
        ramspr_32bit       : std_ulogic;
        dbg_spr_access : std_ulogic;
        dec_ctr : std_ulogic;
        privileged : std_ulogic;
        prefixed : std_ulogic;
        prefix : std_ulogic_vector(25 downto 0);
        illegal_suffix : std_ulogic;
        misaligned_prefix : std_ulogic;
        illegal_form : std_ulogic;
        uses_tar : std_ulogic;
        uses_dscr : std_ulogic;
        right_shift : std_ulogic;
        rot_clear_left : std_ulogic;
        rot_clear_right : std_ulogic;
        rot_sign_ext : std_ulogic;
        do_popcnt : std_ulogic;
    end record;
    constant Decode2ToExecute1Init : Decode2ToExecute1Type :=
	(valid => '0', unit => ALU, fac => NONE, insn_type => OP_ILLEGAL, instr_tag => instr_tag_init,
         write_reg_enable => '0',
         lr => '0', br_abs => '0', rc => '0', oe => '0', invert_a => '0',
	 invert_out => '0', input_carry => ZERO, output_carry => '0', input_cr => '0',
         output_cr => '0', output_xer => '0',
	 is_32bit => '0', is_signed => '0', xerc => xerc_init, reserve => '0', br_pred => '0',
         byte_reverse => '0', sign_extend => '0', update => '0', nia => (others => '0'),
         read_data1 => (others => '0'), read_data2 => (others => '0'), read_data3 => (others => '0'),
         reg_valid1 => '0', reg_valid2 => '0', reg_valid3 => '0',
         cr => (others => '0'), insn => (others => '0'), data_len => (others => '0'),
         result_sel => ADD, sub_select => "000",
         repeat => '0', second => '0', spr_select => spr_id_init,
         spr_is_ram => '0',
         ramspr_even_rdaddr => (others => '0'), ramspr_odd_rdaddr => (others => '0'), ramspr_rd_odd => '0',
         ramspr_wraddr => (others => '0'), ramspr_write_even => '0', ramspr_write_odd => '0',
         ramspr_32bit => '0',
         dbg_spr_access => '0',
         dec_ctr => '0',
         privileged => '0', prefixed => '0', prefix => (others => '0'), illegal_suffix => '0',
         misaligned_prefix => '0', illegal_form => '0', uses_tar => '0', uses_dscr => '0',
         right_shift => '0', rot_clear_left => '0', rot_clear_right => '0', rot_sign_ext => '0',
         do_popcnt => '0',
         others => (others => '0'));

    type MultiplyInputType is record
	valid: std_ulogic;
	data1: std_ulogic_vector(63 downto 0);
	data2: std_ulogic_vector(63 downto 0);
        addend: std_ulogic_vector(127 downto 0);
        is_signed: std_ulogic;
        subtract: std_ulogic;   -- 0 => addend + data1 * data2, 1 => addend - data1 * data2
    end record;
    constant MultiplyInputInit : MultiplyInputType := (data1 => 64x"0", data2 => 64x"0",
                                                       addend => 128x"0", others => '0');

    type MultiplyOutputType is record
	valid: std_ulogic;
	result: std_ulogic_vector(127 downto 0);
        overflow : std_ulogic;
    end record;
    constant MultiplyOutputInit : MultiplyOutputType := (valid => '0', overflow => '0',
                                                         others => (others => '0'));

    type Execute1ToDividerType is record
	valid: std_ulogic;
        flush: std_ulogic;
	dividend: std_ulogic_vector(63 downto 0);
	divisor: std_ulogic_vector(63 downto 0);
	is_signed: std_ulogic;
	is_32bit: std_ulogic;
	is_extended: std_ulogic;
	is_modulus: std_ulogic;
        neg_result: std_ulogic;
    end record;
    constant Execute1ToDividerInit: Execute1ToDividerType := (
        dividend => 64x"0", divisor => 64x"0", others => '0');

    type PMUEventType is record
        no_instr_avail      : std_ulogic;
        dispatch            : std_ulogic;
        ext_interrupt       : std_ulogic;
        instr_complete      : std_ulogic;
        fp_complete         : std_ulogic;
        ld_complete         : std_ulogic;
        st_complete         : std_ulogic;
        br_taken_complete   : std_ulogic;
        br_mispredict       : std_ulogic;
        ipref_discard       : std_ulogic;
        itlb_miss           : std_ulogic;
        itlb_miss_resolved  : std_ulogic;
        icache_miss         : std_ulogic;
        dc_miss_resolved    : std_ulogic;
        dc_load_miss        : std_ulogic;
        dc_ld_miss_resolved : std_ulogic;
        dc_store_miss       : std_ulogic;
        dtlb_miss           : std_ulogic;
        dtlb_miss_resolved  : std_ulogic;
        ld_miss_nocache     : std_ulogic;
        ld_fill_nocache     : std_ulogic;
    end record;
    constant PMUEventInit : PMUEventType := (others => '0');

    type Execute1ToPMUType is record
        mfspr   : std_ulogic;
        mtspr   : std_ulogic;
        spr_num : std_ulogic_vector(4 downto 0);
        spr_val : std_ulogic_vector(63 downto 0);
        tbbits  : std_ulogic_vector(3 downto 0);        -- event bits from timebase
        pmm_msr : std_ulogic;                           -- PMM bit from MSR
        pr_msr  : std_ulogic;                           -- PR bit from MSR
        run     : std_ulogic;
        nia     : std_ulogic_vector(63 downto 0);
        addr    : std_ulogic_vector(63 downto 0);
        addr_v  : std_ulogic;
        trace   : std_ulogic;
        occur   : PMUEventType;
    end record;

    type PMUToExecute1Type is record
        spr_val : std_ulogic_vector(63 downto 0);
        intr    : std_ulogic;
    end record;

    type Decode2ToRegisterFileType is record
	read1_enable : std_ulogic;
	read2_enable : std_ulogic;
	read3_enable : std_ulogic;
    end record;

    type RegisterFileToDecode2Type is record
        read1_data : std_ulogic_vector(63 downto 0);
        read2_data : std_ulogic_vector(63 downto 0);
        read3_data : std_ulogic_vector(63 downto 0);
    end record;

    type Decode2ToCrFileType is record
	read : std_ulogic;
    end record;

    type CrFileToDecode2Type is record
	read_cr_data   : std_ulogic_vector(31 downto 0);
	read_xerc_data : xer_common_t;
    end record;

    type Execute1ToLoadstore1Type is record
	valid : std_ulogic;
        op : insn_type_t;                               -- what ld/st or m[tf]spr or TLB op to do
        insn : std_ulogic_vector(31 downto 0);
        instr_tag : instr_tag_t;
	addr1 : std_ulogic_vector(63 downto 0);
	addr2 : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);		-- data to write, unused for read
	write_reg : gspr_index_t;
	length : std_ulogic_vector(3 downto 0);
        ci : std_ulogic;                                -- cache-inhibited load/store
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;			-- do we need to sign extend?
	update : std_ulogic;				-- is this an update instruction?
        hash : std_ulogic;
	xerc : xer_common_t;
        reserve : std_ulogic;                           -- set for larx/stcx.
        rc : std_ulogic;                                -- set for stcx.
        virt_mode : std_ulogic;                         -- do translation through TLB
        priv_mode : std_ulogic;                         -- privileged mode (MSR[PR] = 0)
        mode_32bit : std_ulogic;                        -- trim addresses to 32 bits
        is_32bit : std_ulogic;
        prefixed : std_ulogic;
        repeat : std_ulogic;
        second : std_ulogic;
        e2stall : std_ulogic;
        msr : std_ulogic_vector(63 downto 0);
        hashkey : std_ulogic_vector(63 downto 0);
        hash_enable : std_ulogic;
    end record;
    constant Execute1ToLoadstore1Init : Execute1ToLoadstore1Type :=
        (valid => '0', op => OP_ILLEGAL, ci => '0', byte_reverse => '0',
         sign_extend => '0', update => '0', hash => '0', xerc => xerc_init,
         reserve => '0', rc => '0', virt_mode => '0', priv_mode => '0',
         insn => (others => '0'),
         instr_tag => instr_tag_init,
         addr1 => (others => '0'), addr2 => (others => '0'), data => (others => '0'),
         write_reg => (others => '0'),
         length => (others => '0'),
         mode_32bit => '0', is_32bit => '0', prefixed => '0',
         repeat => '0', second => '0', e2stall => '0',
         msr => (others => '0'), hashkey => (others => '0'), hash_enable => '0');

    type Loadstore1ToExecute1Type is record
        busy : std_ulogic;
        l2stall : std_ulogic;
        ea_for_pmu : std_ulogic_vector(63 downto 0);
        ea_valid : std_ulogic;
    end record;

    type Loadstore1ToDcacheType is record
	valid : std_ulogic;
        hold : std_ulogic;
	load : std_ulogic;				-- is this a load
        dcbz : std_ulogic;
        flush : std_ulogic;
        touch : std_ulogic;
        sync : std_ulogic;
	nc : std_ulogic;
        reserve : std_ulogic;
        atomic_qw : std_ulogic;                         -- part of a quadword atomic op
        atomic_first : std_ulogic;
        atomic_last : std_ulogic;
        virt_mode : std_ulogic;
        priv_mode : std_ulogic;
        tlb_probe : std_ulogic;
	addr : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);          -- valid the cycle after .valid = 1
        byte_sel : std_ulogic_vector(7 downto 0);
        dawr_match : std_ulogic;                        -- valid the cycle after .valid = 1
    end record;
    constant Loadstore1ToDcacheInit : Loadstore1ToDcacheType :=
        (addr => (others => '0'), data => (others => '0'), byte_sel => x"00",
         others => '0');

    type DcacheToLoadstore1Type is record
	valid : std_ulogic;
	data : std_ulogic_vector(63 downto 0);
        store_done : std_ulogic;
        error : std_ulogic;
        cache_paradox : std_ulogic;
        reserve_nc : std_ulogic;
    end record;

    type DcacheEventType is record
        load_miss          : std_ulogic;
        store_miss         : std_ulogic;
        dcache_refill      : std_ulogic;
        dtlb_miss          : std_ulogic;
        dtlb_miss_resolved : std_ulogic;
    end record;

    type Loadstore1ToMmuType is record
        valid : std_ulogic;
        tlbie : std_ulogic;
        slbia : std_ulogic;
        mtspr : std_ulogic;
        iside : std_ulogic;
        load  : std_ulogic;
        priv  : std_ulogic;
        ric   : std_ulogic_vector(1 downto 0);
        sprnf : std_ulogic;
        sprnt : std_ulogic;
        addr  : std_ulogic_vector(63 downto 0);
        rs    : std_ulogic_vector(63 downto 0);
    end record;

    type MmuToLoadstore1Type is record
        done       : std_ulogic;
        err        : std_ulogic;
        invalid    : std_ulogic;
        badtree    : std_ulogic;
        segerr     : std_ulogic;
        perm_error : std_ulogic;
        rc_error   : std_ulogic;
        sprval     : std_ulogic_vector(63 downto 0);
    end record;

    type MmuToDcacheType is record
        valid : std_ulogic;
        tlbie : std_ulogic;
        doall : std_ulogic;
        tlbld : std_ulogic;
        addr  : std_ulogic_vector(63 downto 0);
        pte   : std_ulogic_vector(63 downto 0);
    end record;

    type DcacheToMmuType is record
        stall : std_ulogic;
        done  : std_ulogic;
        err   : std_ulogic;
        data  : std_ulogic_vector(63 downto 0);
    end record;

    type MmuToITLBType is record
        tlbld : std_ulogic;
        tlbie : std_ulogic;
        doall : std_ulogic;
        addr  : std_ulogic_vector(63 downto 0);
        pte   : std_ulogic_vector(63 downto 0);
    end record;

    type Loadstore1ToWritebackType is record
	valid : std_ulogic;
        instr_tag : instr_tag_t;
	write_enable: std_ulogic;
	write_reg : gspr_index_t;
	write_data : std_ulogic_vector(63 downto 0);
	xerc : xer_common_t;
        rc : std_ulogic;
        store_done : std_ulogic;
        interrupt : std_ulogic;
        intr_vec : intr_vector_t;
        srr1: std_ulogic_vector(15 downto 0);
    end record;
    constant Loadstore1ToWritebackInit : Loadstore1ToWritebackType :=
        (valid => '0', instr_tag => instr_tag_init, write_enable => '0',
         write_reg => (others => '0'), write_data => (others => '0'),
         xerc => xerc_init, rc => '0', store_done => '0',
         interrupt => '0', intr_vec => 0,
         srr1 => (others => '0'));

    type Loadstore1EventType is record
        load_complete  : std_ulogic;
        store_complete : std_ulogic;
        itlb_miss      : std_ulogic;
    end record;

    type Execute1ToWritebackType is record
	valid: std_ulogic;
        instr_tag : instr_tag_t;
	rc : std_ulogic;
        mode_32bit : std_ulogic;
	write_enable : std_ulogic;
	write_reg: gspr_index_t;
	write_data: std_ulogic_vector(63 downto 0);
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
	write_xerc_enable : std_ulogic;
	xerc : xer_common_t;
        interrupt : std_ulogic;
        alt_intr : std_ulogic;
        hv_intr : std_ulogic;
        is_scv : std_ulogic;
        intr_vec : intr_vector_t;
	redirect: std_ulogic;
        redir_mode: std_ulogic_vector(3 downto 0);
        last_nia: std_ulogic_vector(63 downto 0);
        br_last: std_ulogic;
        br_taken: std_ulogic;
        abs_br: std_ulogic;
        srr1: std_ulogic_vector(15 downto 0);
    end record;
    constant Execute1ToWritebackInit : Execute1ToWritebackType :=
        (valid => '0', instr_tag => instr_tag_init, rc => '0', mode_32bit => '0',
         write_enable => '0', write_cr_enable => '0',
         write_xerc_enable => '0', xerc => xerc_init,
         write_data => (others => '0'), write_cr_mask => (others => '0'),
         write_cr_data => (others => '0'), write_reg => (others => '0'),
         interrupt => '0', alt_intr => '0', hv_intr => '0', is_scv => '0', intr_vec => 0,
         redirect => '0', redir_mode => "0000",
         last_nia => (others => '0'),
         br_last => '0', br_taken => '0', abs_br => '0',
         srr1 => (others => '0'));

    type Execute1ToFPUType is record
        valid     : std_ulogic;
        op        : insn_type_t;
        nia       : std_ulogic_vector(63 downto 0);
        itag      : instr_tag_t;
        insn      : std_ulogic_vector(31 downto 0);
        single    : std_ulogic;
        is_signed : std_ulogic;
        fe_mode   : std_ulogic_vector(1 downto 0);
        fra       : std_ulogic_vector(63 downto 0);
        frb       : std_ulogic_vector(63 downto 0);
        frc       : std_ulogic_vector(63 downto 0);
        valid_a   : std_ulogic;
        valid_b   : std_ulogic;
        valid_c   : std_ulogic;
        frt       : gspr_index_t;
        rc        : std_ulogic;
        m32b      : std_ulogic;
        out_cr    : std_ulogic;
        oe        : std_ulogic;
        xerc      : xer_common_t;
        stall     : std_ulogic;
    end record;
    constant Execute1ToFPUInit : Execute1ToFPUType := (valid => '0', op => OP_ILLEGAL, nia => (others => '0'),
                                                       itag => instr_tag_init,
                                                       insn => (others => '0'), fe_mode => "00", rc => '0',
                                                       fra => (others => '0'), frb => (others => '0'),
                                                       frc => (others => '0'), frt => (others => '0'),
                                                       valid_a => '0', valid_b => '0', valid_c => '0',
                                                       single => '0', is_signed => '0', out_cr => '0',
                                                       m32b => '0', oe => '0', xerc => xerc_init,
                                                       stall => '0');

    type FPUToExecute1Type is record
        busy      : std_ulogic;
        f2stall   : std_ulogic;
        exception : std_ulogic;
    end record;
    constant FPUToExecute1Init : FPUToExecute1Type := (others => '0');

    type FPUToWritebackType is record
        valid           : std_ulogic;
        interrupt       : std_ulogic;
        instr_tag       : instr_tag_t;
        write_enable    : std_ulogic;
        write_reg       : gspr_index_t;
        write_data      : std_ulogic_vector(63 downto 0);
        write_cr_enable : std_ulogic;
        write_cr_mask   : std_ulogic_vector(7 downto 0);
        write_cr_data   : std_ulogic_vector(31 downto 0);
        write_xerc      : std_ulogic;
        xerc            : xer_common_t;
        intr_vec        : intr_vector_t;
        srr1            : std_ulogic_vector(15 downto 0);
    end record;
    constant FPUToWritebackInit : FPUToWritebackType :=
        (valid => '0', interrupt => '0', instr_tag => instr_tag_init,
         write_enable => '0', write_reg => (others => '0'),
         write_cr_enable => '0', write_cr_mask => (others => '0'),
         write_cr_data => (others => '0'),
         write_xerc => '0', xerc => xerc_init,
         intr_vec => 0, srr1 => (others => '0'),
         others => (others => '0'));

    type DividerToExecute1Type is record
	valid: std_ulogic;
	write_reg_data: std_ulogic_vector(63 downto 0);
        overflow : std_ulogic;
    end record;
    constant DividerToExecute1Init : DividerToExecute1Type := (valid => '0', overflow => '0',
                                                               others => (others => '0'));

    type WritebackToFetch1Type is record
	redirect: std_ulogic;
        virt_mode: std_ulogic;
        priv_mode: std_ulogic;
        big_endian: std_ulogic;
        mode_32bit: std_ulogic;
	redirect_nia: std_ulogic_vector(63 downto 0);
        br_nia : std_ulogic_vector(63 downto 0);
        br_last : std_ulogic;
        br_taken : std_ulogic;
        interrupt : std_ulogic;
        alt_intr : std_ulogic;
        intr_vec : std_ulogic_vector(63 downto 0);
    end record;
    constant WritebackToFetch1Init : WritebackToFetch1Type :=
        (redirect => '0', virt_mode => '0', priv_mode => '0', big_endian => '0',
         mode_32bit => '0', redirect_nia => (others => '0'),
         br_last => '0', br_taken => '0', br_nia => (others => '0'),
         interrupt => '0', alt_intr => '0', intr_vec => 64x"0");

    type WritebackToRegisterFileType is record
	write_reg : gspr_index_t;
	write_data : std_ulogic_vector(63 downto 0);
	write_enable : std_ulogic;
    end record;
    constant WritebackToRegisterFileInit : WritebackToRegisterFileType :=
        (write_enable => '0', write_data => (others => '0'), others => (others => '0'));

    type WritebackToCrFileType is record
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
	write_xerc_enable : std_ulogic;
	write_xerc_data : xer_common_t;
    end record;
    constant WritebackToCrFileInit : WritebackToCrFileType := (write_cr_enable => '0', write_xerc_enable => '0',
							       write_xerc_data => xerc_init,
							       write_cr_mask => (others => '0'),
							       write_cr_data => (others => '0'));

    type WritebackToExecute1Type is record
        intr    : std_ulogic;
        hv_intr : std_ulogic;
        scv_int : std_ulogic;
        alt_int : std_ulogic;
        srr1    : std_ulogic_vector(15 downto 0);
    end record;

    type WritebackEventType is record
        instr_complete : std_ulogic;
        fp_complete    : std_ulogic;
    end record;

end common;

package body common is
    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t is
    begin
	return to_integer(unsigned(insn(15 downto 11) & insn(20 downto 16)));
    end;

    function gspr_to_gpr(i: gspr_index_t) return gpr_index_t is
    begin
	return i(4 downto 0);
    end;

    function gpr_to_gspr(i: gpr_index_t) return gspr_index_t is
    begin
	return "0" & i;
    end;

    function fpr_to_gspr(f: fpr_index_t) return gspr_index_t is
    begin
        return "1" & f;
    end;

    function tag_match(tag1 : instr_tag_t; tag2 : instr_tag_t) return boolean is
    begin
        return tag1.valid = '1' and tag2.valid = '1' and tag1.tag = tag2.tag;
    end;

    function addr_to_real(addr: std_ulogic_vector(63 downto 0)) return real_addr_t is
    begin
        return addr(real_addr_t'range);
    end;
end common;
