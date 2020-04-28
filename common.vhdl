library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;

package common is

    -- MSR bit numbers
    constant MSR_SF  : integer := (63 - 0);     -- Sixty-Four bit mode
    constant MSR_EE  : integer := (63 - 48);    -- External interrupt Enable
    constant MSR_PR  : integer := (63 - 49);    -- PRoblem state
    constant MSR_IR  : integer := (63 - 58);    -- Instruction Relocation
    constant MSR_DR  : integer := (63 - 59);    -- Data Relocation
    constant MSR_RI  : integer := (63 - 62);    -- Recoverable Interrupt
    constant MSR_LE  : integer := (63 - 63);    -- Little Endian

    -- SPR numbers
    subtype spr_num_t is integer range 0 to 1023;

    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t;

    constant SPR_XER    : spr_num_t := 1;
    constant SPR_LR     : spr_num_t := 8;
    constant SPR_CTR    : spr_num_t := 9;
    constant SPR_TB     : spr_num_t := 268;
    constant SPR_DEC    : spr_num_t := 22;
    constant SPR_SRR0   : spr_num_t := 26;
    constant SPR_SRR1   : spr_num_t := 27;
    constant SPR_HSRR0  : spr_num_t := 314;
    constant SPR_HSRR1  : spr_num_t := 315;
    constant SPR_SPRG0  : spr_num_t := 272;
    constant SPR_SPRG1  : spr_num_t := 273;
    constant SPR_SPRG2  : spr_num_t := 274;
    constant SPR_SPRG3  : spr_num_t := 275;
    constant SPR_SPRG3U : spr_num_t := 259;
    constant SPR_HSPRG0 : spr_num_t := 304;
    constant SPR_HSPRG1 : spr_num_t := 305;

    -- GPR indices in the register file (GPR only)
    subtype gpr_index_t is std_ulogic_vector(4 downto 0);

    -- Extended GPR indice (can hold an SPR)
    subtype gspr_index_t is std_ulogic_vector(5 downto 0);

    -- Some SPRs are stored in the register file, they use the magic
    -- GPR numbers above 31.
    --
    -- The function fast_spr_num() returns the corresponding fast
    -- pseudo-GPR number for a given SPR number. The result MSB
    -- indicates if this is indeed a fast SPR. If clear, then
    -- the SPR is not stored in the GPR file.
    --
    function fast_spr_num(spr: spr_num_t) return gspr_index_t;

    -- Indices conversion functions
    function gspr_to_gpr(i: gspr_index_t) return gpr_index_t;
    function gpr_to_gspr(i: gpr_index_t) return gspr_index_t;
    function gpr_or_spr_to_gspr(g: gpr_index_t; s: gspr_index_t) return gspr_index_t;
    function is_fast_spr(s: gspr_index_t) return std_ulogic;

    -- The XER is split: the common bits (CA, OV, SO, OV32 and CA32) are
    -- in the CR file as a kind of CR extension (with a separate write
    -- control). The rest is stored as a fast SPR.
    type xer_common_t is record
	ca : std_ulogic;
	ca32 : std_ulogic;
	ov : std_ulogic;
	ov32 : std_ulogic;
	so : std_ulogic;
    end record;
    constant xerc_init : xer_common_t := (others => '0');

    type irq_state_t is (WRITE_SRR0, WRITE_SRR1);

    -- This needs to die...
    type ctrl_t is record
	tb: std_ulogic_vector(63 downto 0);
	dec: std_ulogic_vector(63 downto 0);
	msr: std_ulogic_vector(63 downto 0);
	irq_state : irq_state_t;
	irq_nia: std_ulogic_vector(63 downto 0);
	srr1: std_ulogic_vector(63 downto 0);
    end record;

    type Fetch1ToIcacheType is record
	req: std_ulogic;
	stop_mark: std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
    end record;

    type IcacheToFetch2Type is record
	valid: std_ulogic;
	stop_mark: std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
	insn: std_ulogic_vector(31 downto 0);
    end record;

    type Fetch2ToDecode1Type is record
	valid: std_ulogic;
	stop_mark : std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
	insn: std_ulogic_vector(31 downto 0);
    end record;
    constant Fetch2ToDecode1Init : Fetch2ToDecode1Type := (valid => '0', stop_mark => '0', others => (others => '0'));

    type Decode1ToDecode2Type is record
	valid: std_ulogic;
	stop_mark : std_ulogic;
	nia: std_ulogic_vector(63 downto 0);
	insn: std_ulogic_vector(31 downto 0);
	ispr1: gspr_index_t; -- (G)SPR used for branch condition (CTR) or mfspr
	ispr2: gspr_index_t; -- (G)SPR used for branch target (CTR, LR, TAR)
	decode: decode_rom_t;
    end record;
    constant Decode1ToDecode2Init : Decode1ToDecode2Type := (valid => '0', stop_mark => '0', decode => decode_rom_init, others => (others => '0'));

    type Decode2ToExecute1Type is record
	valid: std_ulogic;
	insn_type: insn_type_t;
	nia: std_ulogic_vector(63 downto 0);
	write_reg: gspr_index_t;
	read_reg1: gspr_index_t;
	read_reg2: gspr_index_t;
	read_data1: std_ulogic_vector(63 downto 0);
	read_data2: std_ulogic_vector(63 downto 0);
	read_data3: std_ulogic_vector(63 downto 0);
        bypass_data1: std_ulogic;
        bypass_data2: std_ulogic;
        bypass_data3: std_ulogic;
	cr: std_ulogic_vector(31 downto 0);
	xerc: xer_common_t;
	lr: std_ulogic;
	rc: std_ulogic;
	oe: std_ulogic;
	invert_a: std_ulogic;
	invert_out: std_ulogic;
	input_carry: carry_in_t;
	output_carry: std_ulogic;
	input_cr: std_ulogic;
	output_cr: std_ulogic;
	is_32bit: std_ulogic;
	is_signed: std_ulogic;
	insn: std_ulogic_vector(31 downto 0);
	data_len: std_ulogic_vector(3 downto 0);
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;			-- do we need to sign extend?
	update : std_ulogic;				-- is this an update instruction?
        reserve : std_ulogic;                           -- set for larx/stcx
    end record;
    constant Decode2ToExecute1Init : Decode2ToExecute1Type :=
	(valid => '0', insn_type => OP_ILLEGAL, bypass_data1 => '0', bypass_data2 => '0', bypass_data3 => '0',
         lr => '0', rc => '0', oe => '0', invert_a => '0',
	 invert_out => '0', input_carry => ZERO, output_carry => '0', input_cr => '0', output_cr => '0',
	 is_32bit => '0', is_signed => '0', xerc => xerc_init, reserve => '0',
         byte_reverse => '0', sign_extend => '0', update => '0', others => (others => '0'));

    type Execute1ToMultiplyType is record
	valid: std_ulogic;
	insn_type: insn_type_t;
	data1: std_ulogic_vector(64 downto 0);
	data2: std_ulogic_vector(64 downto 0);
	is_32bit: std_ulogic;
    end record;
    constant Execute1ToMultiplyInit : Execute1ToMultiplyType := (valid => '0', insn_type => OP_ILLEGAL,
								 is_32bit => '0',
								 others => (others => '0'));

    type Execute1ToDividerType is record
	valid: std_ulogic;
	dividend: std_ulogic_vector(63 downto 0);
	divisor: std_ulogic_vector(63 downto 0);
	is_signed: std_ulogic;
	is_32bit: std_ulogic;
	is_extended: std_ulogic;
	is_modulus: std_ulogic;
        neg_result: std_ulogic;
    end record;
    constant Execute1ToDividerInit: Execute1ToDividerType := (valid => '0', is_signed => '0', is_32bit => '0',
                                                              is_extended => '0', is_modulus => '0',
                                                              neg_result => '0', others => (others => '0'));

    type Decode2ToRegisterFileType is record
	read1_enable : std_ulogic;
	read1_reg : gspr_index_t;
	read2_enable : std_ulogic;
	read2_reg : gspr_index_t;
	read3_enable : std_ulogic;
	read3_reg : gpr_index_t;
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

    type Execute1ToFetch1Type is record
	redirect: std_ulogic;
	redirect_nia: std_ulogic_vector(63 downto 0);
    end record;
    constant Execute1ToFetch1TypeInit : Execute1ToFetch1Type := (redirect => '0', others => (others => '0'));

    type Execute1ToLoadstore1Type is record
	valid : std_ulogic;
	load : std_ulogic;				-- is this a load or store
	addr1 : std_ulogic_vector(63 downto 0);
	addr2 : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);		-- data to write, unused for read
	write_reg : gpr_index_t;
	length : std_ulogic_vector(3 downto 0);
        ci : std_ulogic;                                -- cache-inhibited load/store
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;			-- do we need to sign extend?
	update : std_ulogic;				-- is this an update instruction?
	update_reg : gpr_index_t;                      	-- if so, the register to update
	xerc : xer_common_t;
        reserve : std_ulogic;                           -- set for larx/stcx.
        rc : std_ulogic;                                -- set for stcx.
    end record;
    constant Execute1ToLoadstore1Init : Execute1ToLoadstore1Type := (valid => '0', load => '0', ci => '0', byte_reverse => '0',
                                                                     sign_extend => '0', update => '0', xerc => xerc_init,
                                                                     reserve => '0', rc => '0', others => (others => '0'));

    type Loadstore1ToDcacheType is record
	valid : std_ulogic;
	load : std_ulogic;
	nc : std_ulogic;
        reserve : std_ulogic;
	addr : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);
        byte_sel : std_ulogic_vector(7 downto 0);
    end record;

    type DcacheToLoadstore1Type is record
	valid : std_ulogic;
	data : std_ulogic_vector(63 downto 0);
        store_done : std_ulogic;
        error : std_ulogic;
    end record;

    type Loadstore1ToWritebackType is record
	valid : std_ulogic;
	write_enable: std_ulogic;
	write_reg : gpr_index_t;
	write_data : std_ulogic_vector(63 downto 0);
	xerc : xer_common_t;
        rc : std_ulogic;
        store_done : std_ulogic;
    end record;
    constant Loadstore1ToWritebackInit : Loadstore1ToWritebackType := (valid => '0', write_enable => '0', xerc => xerc_init,
                                                                       rc => '0', store_done => '0', others => (others => '0'));

    type Execute1ToWritebackType is record
	valid: std_ulogic;
	rc : std_ulogic;
	write_enable : std_ulogic;
	write_reg: gspr_index_t;
	write_data: std_ulogic_vector(63 downto 0);
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
	write_xerc_enable : std_ulogic;
	xerc : xer_common_t;
        exc_write_enable : std_ulogic;
        exc_write_reg : gspr_index_t;
        exc_write_data : std_ulogic_vector(63 downto 0);
    end record;
    constant Execute1ToWritebackInit : Execute1ToWritebackType := (valid => '0', rc => '0', write_enable => '0',
								   write_cr_enable => '0', exc_write_enable => '0',
								   write_xerc_enable => '0', xerc => xerc_init,
								   others => (others => '0'));

    type MultiplyToExecute1Type is record
	valid: std_ulogic;
	write_reg_data: std_ulogic_vector(63 downto 0);
        overflow : std_ulogic;
    end record;
    constant MultiplyToExecute1Init : MultiplyToExecute1Type := (valid => '0', overflow => '0',
								 others => (others => '0'));

    type DividerToExecute1Type is record
	valid: std_ulogic;
	write_reg_data: std_ulogic_vector(63 downto 0);
        overflow : std_ulogic;
    end record;
    constant DividerToExecute1Init : DividerToExecute1Type := (valid => '0', overflow => '0',
                                                               others => (others => '0'));

    type WritebackToRegisterFileType is record
	write_reg : gspr_index_t;
	write_data : std_ulogic_vector(63 downto 0);
	write_enable : std_ulogic;
    end record;
    constant WritebackToRegisterFileInit : WritebackToRegisterFileType := (write_enable => '0', others => (others => '0'));

    type WritebackToCrFileType is record
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
	write_xerc_enable : std_ulogic;
	write_xerc_data : xer_common_t;
    end record;
    constant WritebackToCrFileInit : WritebackToCrFileType := (write_cr_enable => '0', write_xerc_enable => '0',
							       write_xerc_data => xerc_init,
							       others => (others => '0'));
end common;

package body common is
    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t is
    begin
	return to_integer(unsigned(insn(15 downto 11) & insn(20 downto 16)));
    end;
    function fast_spr_num(spr: spr_num_t) return gspr_index_t is
       variable n : integer range 0 to 31;
    begin
       case spr is
       when SPR_LR =>
           n := 0;
       when SPR_CTR =>
           n:= 1;
       when SPR_SRR0 =>
           n := 2;
       when SPR_SRR1 =>
           n := 3;
       when SPR_HSRR0 =>
           n := 4;
       when SPR_HSRR1 =>
           n := 5;
       when SPR_SPRG0 =>
           n := 6;
       when SPR_SPRG1 =>
           n := 7;
       when SPR_SPRG2 =>
           n := 8;
       when SPR_SPRG3 | SPR_SPRG3U =>
           n := 9;
       when SPR_HSPRG0 =>
           n := 10;
       when SPR_HSPRG1 =>
           n := 11;
       when SPR_XER =>
           n := 12;
       when others =>
           n := 0;
           return "000000";
       end case;
       return "1" & std_ulogic_vector(to_unsigned(n, 5));
    end;

    function gspr_to_gpr(i: gspr_index_t) return gpr_index_t is
    begin
	return i(4 downto 0);
    end;

    function gpr_to_gspr(i: gpr_index_t) return gspr_index_t is
    begin
	return "0" & i;
    end;

    function gpr_or_spr_to_gspr(g: gpr_index_t; s: gspr_index_t) return gspr_index_t is
    begin
	if s(5) = '1' then
	    return s;
	else
	    return gpr_to_gspr(g);
	end if;
    end;

    function is_fast_spr(s: gspr_index_t) return std_ulogic is
    begin
	return s(5);
    end;
end common;
