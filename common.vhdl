library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;

package common is

    -- SPR numbers
    subtype spr_num_t is integer range 0 to 1023;

    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t;

    constant SPR_LR    : spr_num_t := 8;
    constant SPR_CTR   : spr_num_t := 9;
    constant SPR_TB    : spr_num_t := 268;

    type ctrl_t is record
	lr: std_ulogic_vector(63 downto 0);
	ctr: std_ulogic_vector(63 downto 0);
	tb: std_ulogic_vector(63 downto 0);
	carry: std_ulogic;
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
	decode: decode_rom_t;
    end record;
    constant Decode1ToDecode2Init : Decode1ToDecode2Type := (valid => '0', stop_mark => '0', decode => decode_rom_init, others => (others => '0'));

    type Decode2ToExecute1Type is record
	valid: std_ulogic;
	insn_type: insn_type_t;
	nia: std_ulogic_vector(63 downto 0);
	write_reg: std_ulogic_vector(4 downto 0);
	read_reg1: std_ulogic_vector(4 downto 0);
	read_reg2: std_ulogic_vector(4 downto 0);
	read_data1: std_ulogic_vector(63 downto 0);
	read_data2: std_ulogic_vector(63 downto 0);
	read_data3: std_ulogic_vector(63 downto 0);
	cr: std_ulogic_vector(31 downto 0);
	lr: std_ulogic;
	rc: std_ulogic;
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
    end record;
    constant Decode2ToExecute1Init : Decode2ToExecute1Type :=
	(valid => '0', insn_type => OP_ILLEGAL, lr => '0', rc => '0', invert_a => '0',
	 invert_out => '0', input_carry => ZERO, output_carry => '0', input_cr => '0', output_cr => '0',
	 is_32bit => '0', is_signed => '0', others => (others => '0'));

    type Decode2ToMultiplyType is record
	valid: std_ulogic;
	insn_type: insn_type_t;
	write_reg: std_ulogic_vector(4 downto 0);
	data1: std_ulogic_vector(63 downto 0);
	data2: std_ulogic_vector(63 downto 0);
	rc: std_ulogic;
	is_32bit: std_ulogic;
	is_signed: std_ulogic;
    end record;
    constant Decode2ToMultiplyInit : Decode2ToMultiplyType :=
	    (valid => '0', insn_type => OP_ILLEGAL, rc => '0', is_32bit => '0', is_signed => '0',
	     others => (others => '0'));

    type Decode2ToDividerType is record
	valid: std_ulogic;
	write_reg: std_ulogic_vector(4 downto 0);
	dividend: std_ulogic_vector(63 downto 0);
	divisor: std_ulogic_vector(63 downto 0);
	is_signed: std_ulogic;
	is_32bit: std_ulogic;
	is_extended: std_ulogic;
	is_modulus: std_ulogic;
	rc: std_ulogic;
    end record;
    constant Decode2ToDividerInit: Decode2ToDividerType := (valid => '0', is_signed => '0', is_32bit => '0', is_extended => '0', is_modulus => '0', rc => '0', others => (others => '0'));

    type Decode2ToRegisterFileType is record
	read1_enable : std_ulogic;
	read1_reg : std_ulogic_vector(4 downto 0);
	read2_enable : std_ulogic;
	read2_reg : std_ulogic_vector(4 downto 0);
	read3_enable : std_ulogic;
	read3_reg : std_ulogic_vector(4 downto 0);
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
    end record;

    type Execute1ToFetch1Type is record
	redirect: std_ulogic;
	redirect_nia: std_ulogic_vector(63 downto 0);
    end record;
    constant Execute1ToFetch1TypeInit : Execute1ToFetch1Type := (redirect => '0', others => (others => '0'));

    type Decode2ToLoadstore1Type is record
	valid : std_ulogic;
	load : std_ulogic;				-- is this a load or store
	addr1 : std_ulogic_vector(63 downto 0);
	addr2 : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);		-- data to write, unused for read
	write_reg : std_ulogic_vector(4 downto 0);	-- read data goes to this register
	length : std_ulogic_vector(3 downto 0);
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;			-- do we need to sign extend?
	update : std_ulogic;				-- is this an update instruction?
	update_reg : std_ulogic_vector(4 downto 0);	-- if so, the register to update
    end record;
    constant Decode2ToLoadstore1Init : Decode2ToLoadstore1Type := (valid => '0', load => '0', byte_reverse => '0', sign_extend => '0', update => '0', others => (others => '0'));

    type Loadstore1ToDcacheType is record
	valid : std_ulogic;
	load : std_ulogic;
	nc : std_ulogic;
	addr : std_ulogic_vector(63 downto 0);
	data : std_ulogic_vector(63 downto 0);
	write_reg : std_ulogic_vector(4 downto 0);
	length : std_ulogic_vector(3 downto 0);
	byte_reverse : std_ulogic;
	sign_extend : std_ulogic;
	update : std_ulogic;
	update_reg : std_ulogic_vector(4 downto 0);
    end record;

    type DcacheToWritebackType is record
	valid : std_ulogic;
	write_enable: std_ulogic;
	write_reg : std_ulogic_vector(4 downto 0);
	write_data : std_ulogic_vector(63 downto 0);
	write_len : std_ulogic_vector(3 downto 0);
	write_shift : std_ulogic_vector(2 downto 0);
	sign_extend : std_ulogic;
	byte_reverse : std_ulogic;
	second_word : std_ulogic;
    end record;
    constant DcacheToWritebackInit : DcacheToWritebackType := (valid => '0', write_enable => '0', sign_extend => '0', byte_reverse => '0', second_word => '0', others => (others => '0'));

    type Execute1ToWritebackType is record
	valid: std_ulogic;
	rc : std_ulogic;
	write_enable : std_ulogic;
	write_reg: std_ulogic_vector(4 downto 0);
	write_data: std_ulogic_vector(63 downto 0);
	write_len : std_ulogic_vector(3 downto 0);
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
	sign_extend: std_ulogic;
    end record;
    constant Execute1ToWritebackInit : Execute1ToWritebackType := (valid => '0', rc => '0', write_enable => '0', write_cr_enable => '0', sign_extend => '0', others => (others => '0'));

    type MultiplyToWritebackType is record
	valid: std_ulogic;

	write_reg_enable : std_ulogic;
	write_reg_nr: std_ulogic_vector(4 downto 0);
	write_reg_data: std_ulogic_vector(63 downto 0);
	rc: std_ulogic;
    end record;
    constant MultiplyToWritebackInit : MultiplyToWritebackType := (valid => '0', write_reg_enable => '0', rc => '0', others => (others => '0'));

    type DividerToWritebackType is record
	valid: std_ulogic;

	write_reg_enable : std_ulogic;
	write_reg_nr: std_ulogic_vector(4 downto 0);
	write_reg_data: std_ulogic_vector(63 downto 0);
	rc: std_ulogic;
    end record;
    constant DividerToWritebackInit : DividerToWritebackType := (valid => '0', write_reg_enable => '0', rc => '0', others => (others => '0'));

    type WritebackToRegisterFileType is record
	write_reg : std_ulogic_vector(4 downto 0);
	write_data : std_ulogic_vector(63 downto 0);
	write_enable : std_ulogic;
    end record;
    constant WritebackToRegisterFileInit : WritebackToRegisterFileType := (write_enable => '0', others => (others => '0'));

    type WritebackToCrFileType is record
	write_cr_enable : std_ulogic;
	write_cr_mask : std_ulogic_vector(7 downto 0);
	write_cr_data : std_ulogic_vector(31 downto 0);
    end record;
    constant WritebackToCrFileInit : WritebackToCrFileType := (write_cr_enable => '0', others => (others => '0'));

end common;

package body common is
    function decode_spr_num(insn: std_ulogic_vector(31 downto 0)) return spr_num_t is
    begin
	return to_integer(unsigned(insn(15 downto 11) & insn(20 downto 16)));
    end;
end common;
