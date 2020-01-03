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
    port (
	clk   : in std_ulogic;

	-- asynchronous
	flush_out : out std_ulogic;
	stall_out : out std_ulogic;

	e_in  : in Decode2ToExecute1Type;

	-- asynchronous
	f_out : out Execute1ToFetch1Type;

	e_out : out Execute1ToWritebackType;

	icache_inval : out std_ulogic;
	terminate_out : out std_ulogic
	);
end entity execute1;

architecture behaviour of execute1 is
    type reg_type is record
	e : Execute1ToWritebackType;
	lr_update : std_ulogic;
	next_lr : std_ulogic_vector(63 downto 0);
    end record;

    signal r, rin : reg_type;

    signal ctrl: ctrl_t := (others => (others => '0'));
    signal ctrl_tmp: ctrl_t := (others => (others => '0'));

    signal right_shift, rot_clear_left, rot_clear_right: std_ulogic;
    signal rotator_result: std_ulogic_vector(63 downto 0);
    signal rotator_carry: std_ulogic;
    signal logical_result: std_ulogic_vector(63 downto 0);
    signal countzero_result: std_ulogic_vector(63 downto 0);

    procedure set_carry(e: inout Execute1ToWritebackType;
			carry32 : in std_ulogic;
			carry : in std_ulogic) is
    begin
	e.xerc.ca32 := carry32;
	e.xerc.ca := carry;
	e.write_xerc_enable := '1';
    end;

    procedure set_ov(e: inout Execute1ToWritebackType;
		     ov   : in std_ulogic;
		     ov32 : in std_ulogic) is
    begin
	e.xerc.ov32 := ov32;
	e.xerc.ov := ov;
	if ov = '1' then
	    e.xerc.so := '1';
	end if;
	e.write_xerc_enable := '1';
    end;

    function calc_ov(msb_a : std_ulogic; msb_b: std_ulogic;
		     ca: std_ulogic; msb_r: std_ulogic) return std_ulogic is
    begin
	return (ca xor msb_r) and not (msb_a xor msb_b);
    end;

    function decode_input_carry(ic : carry_in_t;
				xerc : xer_common_t) return std_ulogic is
    begin
	case ic is
	when ZERO =>
	    return '0';
	when CA =>
	    return xerc.ca;
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
	    assert not (r.lr_update = '1' and e_in.valid = '1')
		report "LR update collision with valid in EX1"
		severity failure;
	    if r.lr_update = '1' then
		report "LR update to " & to_hstring(r.next_lr);
	    end if;
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
	variable cr_op : std_ulogic_vector(9 downto 0);
	variable bt, ba, bb : std_ulogic_vector(4 downto 0);
	variable btnum, banum, bbnum : integer range 0 to 31;
	variable crresult : std_ulogic;
	variable l : std_ulogic;
	variable next_nia : std_ulogic_vector(63 downto 0);
        variable carry_32, carry_64 : std_ulogic;
    begin
	result := (others => '0');
	result_with_carry := (others => '0');
	result_en := '0';
	newcrf := (others => '0');

	v := r;
	v.e := Execute1ToWritebackInit;

	-- XER forwarding. To avoid having to track XER hazards, we
	-- use the previously latched value.
	--
	-- If the XER was modified by a multiply or a divide, those are
	-- single issue, we'll get the up to date value from decode2 from
	-- the register file.
	--
	-- If it was modified by an instruction older than the previous
	-- one in EX1, it will have also hit writeback and will be up
	-- to date in decode2.
	--
	-- That leaves us with the case where it was updated by the previous
	-- instruction in EX1. In that case, we can forward it back here.
	--
	-- This will break if we allow pipelining of multiply and divide,
	-- but ideally, those should go via EX1 anyway and run as a state
	-- machine from here.
	--
	-- One additional hazard to beware of is an XER:SO modifying instruction
	-- in EX1 followed immediately by a store conditional. Due to our
	-- writeback latency, the store will go down the LSU with the previous
	-- XER value, thus the stcx. will set CR0:SO using an obsolete SO value.
	--
	-- We will need to handle that if we ever make stcx. not single issue
	--
	-- We always pass a valid XER value downto writeback even when
	-- we aren't updating it, in order for XER:SO -> CR0:SO transfer
	-- to work for RC instructions.
	--
	if r.e.write_xerc_enable = '1' then
	    v.e.xerc := r.e.xerc;
	else
	    v.e.xerc := e_in.xerc;
	end if;

	v.lr_update := '0';

	ctrl_tmp <= ctrl;
	-- FIXME: run at 512MHz not core freq
	ctrl_tmp.tb <= std_ulogic_vector(unsigned(ctrl.tb) + 1);

	terminate_out <= '0';
	icache_inval <= '0';
	stall_out <= '0';
	f_out <= Execute1ToFetch1TypeInit;

	-- Next insn adder used in a couple of places
	next_nia := std_ulogic_vector(unsigned(e_in.nia) + 4);

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
		result_with_carry := ppc_adde(a_inv, e_in.read_data2,
					      decode_input_carry(e_in.input_carry, v.e.xerc));
		result := result_with_carry(63 downto 0);
                carry_32 := result(32) xor a_inv(32) xor e_in.read_data2(32);
                carry_64 := result_with_carry(64);
		if e_in.output_carry = '1' then
		    set_carry(v.e, carry_32, carry_64);
		end if;
		if e_in.oe = '1' then
		    set_ov(v.e,
			   calc_ov(a_inv(63), e_in.read_data2(63), carry_64, result_with_carry(63)),
			   calc_ov(a_inv(31), e_in.read_data2(31), carry_32, result_with_carry(31)));
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
		-- read_data1 is CTR
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' then
		    result := std_ulogic_vector(unsigned(e_in.read_data1) - 1);
		    result_en := '1';
		    v.e.write_reg := fast_spr_num(SPR_CTR);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, e_in.read_data1) = 1 then
		    f_out.redirect <= '1';
		    if (insn_aa(e_in.insn)) then
			f_out.redirect_nia <= std_ulogic_vector(signed(e_in.read_data2));
		    else
			f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(e_in.read_data2));
		    end if;
		end if;
	    when OP_BCREG =>
		-- read_data1 is CTR
		-- read_data2 is target register (CTR, LR or TAR)
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' and e_in.insn(10) = '0' then
		    result := std_ulogic_vector(unsigned(e_in.read_data1) - 1);
		    result_en := '1';
		    v.e.write_reg := fast_spr_num(SPR_CTR);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, e_in.read_data1) = 1 then
		    f_out.redirect <= '1';
		    f_out.redirect_nia <= e_in.read_data2(63 downto 2) & "00";
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
		    v.e.write_cr_data(hi downto lo) := ppc_cmp(l, e_in.read_data1, e_in.read_data2, v.e.xerc.so);
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
		    v.e.write_cr_data(hi downto lo) := ppc_cmpl(l, e_in.read_data1, e_in.read_data2, v.e.xerc.so);
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
		cr_op := insn_cr(e_in.insn);
		report "CR OP " & to_hstring(cr_op);
		if cr_op(0) = '0' then -- MCRF
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
		else
		    v.e.write_cr_enable := '1';
		    bt := insn_bt(e_in.insn);
		    ba := insn_ba(e_in.insn);
		    bb := insn_bb(e_in.insn);
		    btnum := 31 - to_integer(unsigned(bt));
		    banum := 31 - to_integer(unsigned(ba));
		    bbnum := 31 - to_integer(unsigned(bb));
		    case cr_op(8 downto 5) is
	            when "1001" => -- CREQV
			crresult := not(e_in.cr(banum) xor e_in.cr(bbnum));
	            when "0111" => -- CRNAND
			crresult := not(e_in.cr(banum) and e_in.cr(bbnum));
	            when "0100" => -- CRANDC
			crresult := (e_in.cr(banum) and not e_in.cr(bbnum));
	            when "1000" => -- CRAND
			crresult := (e_in.cr(banum) and e_in.cr(bbnum));
	            when "0001" => -- CRNOR
			crresult := not(e_in.cr(banum) or e_in.cr(bbnum));
	            when "1101" => -- CRORC
			crresult := (e_in.cr(banum) or not e_in.cr(bbnum));
	            when "0110" => -- CRXOR
			crresult := (e_in.cr(banum) xor e_in.cr(bbnum));
	            when "1110" => -- CROR
			crresult := (e_in.cr(banum) or e_in.cr(bbnum));
		    when others =>
		        report "BAD CR?";
	            end case;
		    v.e.write_cr_mask := num_to_fxm((31-btnum) / 4);
		    for i in 0 to 31 loop
			if i = btnum then
		            v.e.write_cr_data(i) := crresult;
			else
		            v.e.write_cr_data(i) := e_in.cr(i);
			end if;
		    end loop;
		end if;
	    when OP_MFSPR =>
		if is_fast_spr(e_in.read_reg1) then
		    result := e_in.read_data1;
		    if decode_spr_num(e_in.insn) = SPR_XER then
			result(63-32) := v.e.xerc.so;
			result(63-33) := v.e.xerc.ov;
			result(63-34) := v.e.xerc.ca;
			result(63-35 downto 63-43) := "000000000";
			result(63-44) := v.e.xerc.ov32;
			result(63-45) := v.e.xerc.ca32;
		    end if;
		else
		    case decode_spr_num(e_in.insn) is
		    when SPR_TB =>
			result := ctrl.tb;
		    when others =>
			result := (others => '0');
		    end case;
		end if;
		result_en := '1';
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
		report "MTSPR to SPR " & integer'image(decode_spr_num(e_in.insn)) &
		    "=" & to_hstring(e_in.read_data3);
		if is_fast_spr(e_in.write_reg) then
		    result := e_in.read_data3;
		    result_en := '1';
		    if decode_spr_num(e_in.insn) = SPR_XER then
			v.e.xerc.so := e_in.read_data3(63-32);
			v.e.xerc.ov := e_in.read_data3(63-33);
			v.e.xerc.ca := e_in.read_data3(63-34);
			v.e.xerc.ov32 := e_in.read_data3(63-44);
			v.e.xerc.ca32 := e_in.read_data3(63-45);
			v.e.write_xerc_enable := '1';
		    end if;
		else
-- TODO: Implement slow SPRs	    
--		    case decode_spr_num(e_in.insn) is
--		    when others =>
--		    end case;
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
		    set_carry(v.e, rotator_carry, rotator_carry);
		end if;
		result_en := '1';
	    when OP_SIM_CONFIG =>
		-- bit 0 was used to select the microwatt console, which
		-- we no longer support.
		result := x"0000000000000000";
		result_en := '1';

	    when OP_TDI =>
		-- Keep our test cases happy for now, ignore trap instructions
		report "OP_TDI FIXME";

	    when OP_ISYNC =>
		f_out.redirect <= '1';
		f_out.redirect_nia <= next_nia;

	    when OP_ICBI =>
		icache_inval <= '1';

	    when others =>
		terminate_out <= '1';
		report "illegal";
	    end case;

	    -- Update LR on the next cycle after a branch link
	    --
	    -- WARNING: The LR update isn't tracked by our hazard tracker. This
	    --          will work (well I hope) because it only happens on branches
	    --          which will flush all decoded instructions. By the time
	    --          fetch catches up, we'll have the new LR. This will
	    --          *not* work properly however if we have a branch predictor,
	    --          in which case the solution would probably be to keep a
	    --          local cache of the updated LR in execute1 (flushed on
	    --          exceptions) that is used instead of the value from
	    --          decode when its content is valid.
	    if e_in.lr = '1' then
		v.lr_update := '1';
		v.next_lr := next_nia;
		v.e.valid := '0';
		report "Delayed LR update to " & to_hstring(next_nia);
		stall_out <= '1';
	    end if;
	elsif r.lr_update = '1' then
	    result_en := '1';
	    result := r.next_lr;
	    v.e.write_reg := fast_spr_num(SPR_LR);
	    v.e.write_len := x"8";
	    v.e.sign_extend := '0';
	    v.e.valid := '1';
	end if;

	v.e.write_data := result;
	v.e.write_enable := result_en;
	v.e.rc := e_in.rc and e_in.valid;

	-- Update registers
	rin <= v;

	-- update outputs
	--f_out <= r.f;
	e_out <= r.e;
	flush_out <= f_out.redirect;
    end process;
end architecture behaviour;
