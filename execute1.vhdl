library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.crhelpers.all;
use work.insn_helpers.all;
use work.ppc_fx_insns.all;

entity execute1 is
    generic (
	SIM   : boolean := false
	);
    port (
	clk   : in std_logic;

	-- asynchronous
	flush_out : out std_ulogic;

	e_in  : in Decode2ToExecute1Type;

	-- asynchronous
	f_out : out Execute1ToFetch1Type;

	e_out : out Execute1ToWritebackType;

	terminate_out : out std_ulogic
	);
end entity execute1;

architecture behaviour of execute1 is
    type reg_type is record
	--f : Execute1ToFetch1Type;
	e : Execute1ToWritebackType;
    end record;

    signal r, rin : reg_type;

    signal ctrl: ctrl_t := (carry => '0', others => (others => '0'));
    signal ctrl_tmp: ctrl_t := (carry => '0', others => (others => '0'));

    signal right_shift, rot_clear_left, rot_clear_right: std_ulogic;
    signal rotator_result: std_ulogic_vector(63 downto 0);
    signal rotator_carry: std_ulogic;
    signal logical_result: std_ulogic_vector(63 downto 0);
    signal countzero_result: std_ulogic_vector(63 downto 0);

    function decode_input_carry (carry_sel : carry_in_t; ca_in : std_ulogic) return std_ulogic is
    begin
	case carry_sel is
	when ZERO =>
	    return '0';
	when CA =>
	    return ca_in;
	when ONE =>
	    return '1';
	end case;
    end;
begin

    rotator_0: entity work.rotator
	port map (
	    rs => e_in.read_data3,
	    ra => e_in.read_data1,
	    shift => e_in.read_data2(6 downto 0),
	    insn => e_in.insn,
	    is_32bit => e_in.is_32bit,
	    right_shift => right_shift,
	    arith => e_in.is_signed,
	    clear_left => rot_clear_left,
	    clear_right => rot_clear_right,
	    result => rotator_result,
	    carry_out => rotator_carry
	    );

    logical_0: entity work.logical
	port map (
	    rs => e_in.read_data3,
	    rb => e_in.read_data2,
	    op => e_in.insn_type,
	    invert_in => e_in.invert_a,
	    invert_out => e_in.invert_out,
	    result => logical_result
	    );

    countzero_0: entity work.zero_counter
	port map (
	    rs => e_in.read_data3,
	    count_right => e_in.insn(10),
	    is_32bit => e_in.is_32bit,
	    result => countzero_result
	    );

    execute1_0: process(clk)
    begin
	if rising_edge(clk) then
	    r <= rin;
	    ctrl <= ctrl_tmp;
	end if;
    end process;

    execute1_1: process(all)
	variable v : reg_type;
	variable a_inv : std_ulogic_vector(63 downto 0);
	variable result : std_ulogic_vector(63 downto 0);
	variable newcrf : std_ulogic_vector(3 downto 0);
	variable result_with_carry : std_ulogic_vector(64 downto 0);
	variable result_en : std_ulogic;
	variable crnum : crnum_t;
	variable crbit : integer range 0 to 31;
	variable scrnum : crnum_t;
	variable lo, hi : integer;
	variable sh, mb, me : std_ulogic_vector(5 downto 0);
	variable sh32, mb32, me32 : std_ulogic_vector(4 downto 0);
	variable bo, bi : std_ulogic_vector(4 downto 0);
	variable bf, bfa : std_ulogic_vector(2 downto 0);
	variable l : std_ulogic;
    begin
	result := (others => '0');
	result_with_carry := (others => '0');
	result_en := '0';
	newcrf := (others => '0');

	v := r;
	v.e := Execute1ToWritebackInit;
	--v.f := Execute1ToFetch1TypeInit;

	ctrl_tmp <= ctrl;
	-- FIXME: run at 512MHz not core freq
	ctrl_tmp.tb <= std_ulogic_vector(unsigned(ctrl.tb) + 1);

	terminate_out <= '0';
	f_out <= Execute1ToFetch1TypeInit;

	-- rotator control signals
	right_shift <= '1' when e_in.insn_type = OP_SHR else '0';
	rot_clear_left <= '1' when e_in.insn_type = OP_RLC or e_in.insn_type = OP_RLCL else '0';
	rot_clear_right <= '1' when e_in.insn_type = OP_RLC or e_in.insn_type = OP_RLCR else '0';

	if e_in.valid = '1' then

	    v.e.valid := '1';
	    v.e.write_reg := e_in.write_reg;
	    v.e.write_len := x"8";
	    v.e.sign_extend := '0';

	    case_0: case e_in.insn_type is

	    when OP_ILLEGAL =>
		terminate_out <= '1';
		report "illegal";
	    when OP_NOP =>
		-- Do nothing
	    when OP_ADD =>
		if e_in.invert_a = '0' then
		    a_inv := e_in.read_data1;
		else
		    a_inv := not e_in.read_data1;
		end if;
		result_with_carry := ppc_adde(a_inv, e_in.read_data2, decode_input_carry(e_in.input_carry, ctrl.carry));
		result := result_with_carry(63 downto 0);
		if e_in.output_carry then
		    ctrl_tmp.carry <= result_with_carry(64);
		end if;
		result_en := '1';
	    when OP_AND | OP_OR | OP_XOR =>
		result := logical_result;
		result_en := '1';
	    when OP_B =>
		f_out.redirect <= '1';
		if (insn_aa(e_in.insn)) then
		    f_out.redirect_nia <= std_ulogic_vector(signed(e_in.read_data2));
		else
		    f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(e_in.read_data2));
		end if;
	    when OP_BC =>
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' then
		    ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, ctrl.ctr) = 1 then
		    f_out.redirect <= '1';
		    if (insn_aa(e_in.insn)) then
			f_out.redirect_nia <= std_ulogic_vector(signed(e_in.read_data2));
		    else
			f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(e_in.read_data2));
		    end if;
		end if;
	    when OP_BCREG =>
                -- bits 10 and 6 distinguish between bclr, bcctr and bctar
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' and e_in.insn(10) = '0' then
		    ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, ctrl.ctr) = 1 then
		    f_out.redirect <= '1';
		    if e_in.insn(10) = '0' then
			f_out.redirect_nia <= ctrl.lr(63 downto 2) & "00";
		    else
			f_out.redirect_nia <= ctrl.ctr(63 downto 2) & "00";
		    end if;
		end if;
	    when OP_CMPB =>
		result := ppc_cmpb(e_in.read_data3, e_in.read_data2);
		result_en := '1';
	    when OP_CMP =>
		bf := insn_bf(e_in.insn);
		l := insn_l(e_in.insn);
		v.e.write_cr_enable := '1';
		crnum := to_integer(unsigned(bf));
		v.e.write_cr_mask := num_to_fxm(crnum);
		for i in 0 to 7 loop
		    lo := i*4;
		    hi := lo + 3;
		    v.e.write_cr_data(hi downto lo) := ppc_cmp(l, e_in.read_data1, e_in.read_data2);
		end loop;
	    when OP_CMPL =>
		bf := insn_bf(e_in.insn);
		l := insn_l(e_in.insn);
		v.e.write_cr_enable := '1';
		crnum := to_integer(unsigned(bf));
		v.e.write_cr_mask := num_to_fxm(crnum);
		for i in 0 to 7 loop
		    lo := i*4;
		    hi := lo + 3;
		    v.e.write_cr_data(hi downto lo) := ppc_cmpl(l, e_in.read_data1, e_in.read_data2);
		end loop;
	    when OP_CNTZ =>
		result := countzero_result;
		result_en := '1';
	    when OP_EXTS =>
		v.e.write_len := e_in.data_len;
		v.e.sign_extend := '1';
		result := e_in.read_data3;
		result_en := '1';
	    when OP_ISEL =>
		crbit := to_integer(unsigned(insn_bc(e_in.insn)));
		if e_in.cr(31-crbit) = '1' then
		    result := e_in.read_data1;
		else
		    result := e_in.read_data2;
		end if;
		result_en := '1';
	    when OP_MCRF =>
		bf := insn_bf(e_in.insn);
		bfa := insn_bfa(e_in.insn);
		v.e.write_cr_enable := '1';
		crnum := to_integer(unsigned(bf));
		scrnum := to_integer(unsigned(bfa));
		v.e.write_cr_mask := num_to_fxm(crnum);
		for i in 0 to 7 loop
		    lo := (7-i)*4;
		    hi := lo + 3;
		    if i = scrnum then
			newcrf := e_in.cr(hi downto lo);
		    end if;
		end loop;
		for i in 0 to 7 loop
		    lo := i*4;
		    hi := lo + 3;
		    v.e.write_cr_data(hi downto lo) := newcrf;
		end loop;
	    when OP_MFSPR =>
		if std_match(e_in.insn(20 downto 11), "0100100000") then
		    result := ctrl.ctr;
		    result_en := '1';
		elsif std_match(e_in.insn(20 downto 11), "0100000000") then
		    result := ctrl.lr;
		    result_en := '1';
		elsif std_match(e_in.insn(20 downto 11), "0110001000") then
		    result := ctrl.tb;
		    result_en := '1';
		end if;
	    when OP_MFCR =>
		if e_in.insn(20) = '0' then
		    -- mfcr
		    result := x"00000000" & e_in.cr;
		else
		    -- mfocrf
		    crnum := fxm_to_num(insn_fxm(e_in.insn));
		    result := (others => '0');
		    for i in 0 to 7 loop
			lo := (7-i)*4;
			hi := lo + 3;
			if crnum = i then
			    result(hi downto lo) := e_in.cr(hi downto lo);
			end if;
		    end loop;
		end if;
		result_en := '1';
	    when OP_MTCRF =>
		v.e.write_cr_enable := '1';
		if e_in.insn(20) = '0' then
		    -- mtcrf
		    v.e.write_cr_mask := insn_fxm(e_in.insn);
		else
		    -- mtocrf: We require one hot priority encoding here
		    crnum := fxm_to_num(insn_fxm(e_in.insn));
		    v.e.write_cr_mask := num_to_fxm(crnum);
		end if;
		v.e.write_cr_data := e_in.read_data3(31 downto 0);
	    when OP_MTSPR =>
		if std_match(e_in.insn(20 downto 11), "0100100000") then
		    ctrl_tmp.ctr <= e_in.read_data3;
		elsif std_match(e_in.insn(20 downto 11), "0100000000") then
		    ctrl_tmp.lr <= e_in.read_data3;
		end if;
	    when OP_POPCNTB =>
		result := ppc_popcntb(e_in.read_data3);
		result_en := '1';
	    when OP_POPCNTW =>
		result := ppc_popcntw(e_in.read_data3);
		result_en := '1';
	    when OP_POPCNTD =>
		result := ppc_popcntd(e_in.read_data3);
		result_en := '1';
	    when OP_PRTYD =>
		result := ppc_prtyd(e_in.read_data3);
		result_en := '1';
	    when OP_PRTYW =>
		result := ppc_prtyw(e_in.read_data3);
		result_en := '1';
	    when OP_RLC | OP_RLCL | OP_RLCR | OP_SHL | OP_SHR =>
		result := rotator_result;
		if e_in.output_carry = '1' then
		    ctrl_tmp.carry <= rotator_carry;
		end if;
		result_en := '1';
	    when OP_SIM_CONFIG =>
		-- bit 0 was used to select the microwatt console, which
		-- we no longer support.
		if SIM = true then
		    result := x"0000000000000000";
		else
		    result := x"0000000000000000";
		end if;
		result_en := '1';

	    when OP_TDI =>
		-- Keep our test cases happy for now, ignore trap instructions
		report "OP_TDI FIXME";

	    when others =>
		terminate_out <= '1';
		report "illegal";
	    end case;

	    if e_in.lr = '1' then
		ctrl_tmp.lr <= std_ulogic_vector(unsigned(e_in.nia) + 4);
	    end if;

	end if;

	v.e.write_data := result;
	v.e.write_enable := result_en;
	v.e.rc := e_in.rc;

	-- Update registers
	rin <= v;

	-- update outputs
	--f_out <= r.f;
	e_out <= r.e;
	flush_out <= f_out.redirect;
    end process;
end architecture behaviour;
