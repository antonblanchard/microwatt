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
        EX1_BYPASS : boolean := true
        );
    port (
	clk   : in std_ulogic;
        rst   : in std_ulogic;

	-- asynchronous
	flush_out : out std_ulogic;
	stall_out : out std_ulogic;

	e_in  : in Decode2ToExecute1Type;

	-- asynchronous
        l_out : out Execute1ToLoadstore1Type;
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
	mul_in_progress : std_ulogic;
        div_in_progress : std_ulogic;
        cntz_in_progress : std_ulogic;
	slow_op_dest : gpr_index_t;
	slow_op_rc : std_ulogic;
	slow_op_oe : std_ulogic;
	slow_op_xerc : xer_common_t;
    end record;

    signal r, rin : reg_type;

    signal a_in, b_in, c_in : std_ulogic_vector(63 downto 0);

    signal ctrl: ctrl_t := (others => (others => '0'));
    signal ctrl_tmp: ctrl_t := (others => (others => '0'));

    signal right_shift, rot_clear_left, rot_clear_right: std_ulogic;
    signal rotator_result: std_ulogic_vector(63 downto 0);
    signal rotator_carry: std_ulogic;
    signal logical_result: std_ulogic_vector(63 downto 0);
    signal countzero_result: std_ulogic_vector(63 downto 0);
    signal popcnt_result: std_ulogic_vector(63 downto 0);
    signal parity_result: std_ulogic_vector(63 downto 0);

    -- multiply signals
    signal x_to_multiply: Execute1ToMultiplyType;
    signal multiply_to_x: MultiplyToExecute1Type;

    -- divider signals
    signal x_to_divider: Execute1ToDividerType;
    signal divider_to_x: DividerToExecute1Type;

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
	    rs => c_in,
	    ra => a_in,
	    shift => b_in(6 downto 0),
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
	    rs => c_in,
	    rb => b_in,
	    op => e_in.insn_type,
	    invert_in => e_in.invert_a,
	    invert_out => e_in.invert_out,
	    result => logical_result,
            datalen => e_in.data_len,
            popcnt => popcnt_result,
            parity => parity_result
	    );

    countzero_0: entity work.zero_counter
	port map (
            clk => clk,
	    rs => c_in,
	    count_right => e_in.insn(10),
	    is_32bit => e_in.is_32bit,
	    result => countzero_result
	    );

    multiply_0: entity work.multiply
        port map (
            clk => clk,
            m_in => x_to_multiply,
            m_out => multiply_to_x
            );

    divider_0: entity work.divider
        port map (
            clk => clk,
            rst => rst,
            d_in => x_to_divider,
            d_out => divider_to_x
            );

    a_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data1 = '1' else e_in.read_data1;
    b_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data2 = '1' else e_in.read_data2;
    c_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data3 = '1' else e_in.read_data3;

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
        variable sign1, sign2 : std_ulogic;
        variable abs1, abs2 : signed(63 downto 0);
	variable overflow : std_ulogic;
	variable negative : std_ulogic;
        variable zerohi, zerolo : std_ulogic;
        variable msb_a, msb_b : std_ulogic;
        variable a_lt : std_ulogic;
        variable lv : Execute1ToLoadstore1Type;
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
	v.mul_in_progress := '0';
        v.div_in_progress := '0';
        v.cntz_in_progress := '0';

	-- signals to multiply unit
	x_to_multiply <= Execute1ToMultiplyInit;
	x_to_multiply.insn_type <= e_in.insn_type;
	x_to_multiply.is_32bit <= e_in.is_32bit;

	if e_in.is_32bit = '1' then
	    if e_in.is_signed = '1' then
		x_to_multiply.data1 <= (others => a_in(31));
		x_to_multiply.data1(31 downto 0) <= a_in(31 downto 0);
		x_to_multiply.data2 <= (others => b_in(31));
		x_to_multiply.data2(31 downto 0) <= b_in(31 downto 0);
	    else
		x_to_multiply.data1 <= '0' & x"00000000" & a_in(31 downto 0);
		x_to_multiply.data2 <= '0' & x"00000000" & b_in(31 downto 0);
	    end if;
	else
	    if e_in.is_signed = '1' then
		x_to_multiply.data1 <= a_in(63) & a_in;
		x_to_multiply.data2 <= b_in(63) & b_in;
	    else
		x_to_multiply.data1 <= '0' & a_in;
		x_to_multiply.data2 <= '0' & b_in;
	    end if;
	end if;

        -- signals to divide unit
        sign1 := '0';
        sign2 := '0';
        if e_in.is_signed = '1' then
            if e_in.is_32bit = '1' then
                sign1 := a_in(31);
                sign2 := b_in(31);
            else
                sign1 := a_in(63);
                sign2 := b_in(63);
            end if;
        end if;
        -- take absolute values
        if sign1 = '0' then
            abs1 := signed(a_in);
        else
            abs1 := - signed(a_in);
        end if;
        if sign2 = '0' then
            abs2 := signed(b_in);
        else
            abs2 := - signed(b_in);
        end if;

        x_to_divider <= Execute1ToDividerInit;
        x_to_divider.is_signed <= e_in.is_signed;
	x_to_divider.is_32bit <= e_in.is_32bit;
        if e_in.insn_type = OP_MOD then
            x_to_divider.is_modulus <= '1';
        end if;
        x_to_divider.neg_result <= sign1 xor (sign2 and not x_to_divider.is_modulus);
        if e_in.is_32bit = '0' then
            -- 64-bit forms
            if e_in.insn_type = OP_DIVE then
                x_to_divider.is_extended <= '1';
            end if;
            x_to_divider.dividend <= std_ulogic_vector(abs1);
            x_to_divider.divisor <= std_ulogic_vector(abs2);
        else
            -- 32-bit forms
            x_to_divider.is_extended <= '0';
            if e_in.insn_type = OP_DIVE then   -- extended forms
                x_to_divider.dividend <= std_ulogic_vector(abs1(31 downto 0)) & x"00000000";
            else
                x_to_divider.dividend <= x"00000000" & std_ulogic_vector(abs1(31 downto 0));
            end if;
            x_to_divider.divisor <= x"00000000" & std_ulogic_vector(abs2(31 downto 0));
        end if;

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
	    v.slow_op_dest := gspr_to_gpr(e_in.write_reg);
	    v.slow_op_rc := e_in.rc;
	    v.slow_op_oe := e_in.oe;
	    v.slow_op_xerc := v.e.xerc;

	    case_0: case e_in.insn_type is

	    when OP_ILLEGAL =>
		terminate_out <= '1';
		report "illegal";
	    when OP_NOP =>
		-- Do nothing
	    when OP_ADD | OP_CMP =>
		if e_in.invert_a = '0' then
		    a_inv := a_in;
		else
		    a_inv := not a_in;
		end if;
		result_with_carry := ppc_adde(a_inv, b_in,
					      decode_input_carry(e_in.input_carry, v.e.xerc));
		result := result_with_carry(63 downto 0);
                carry_32 := result(32) xor a_inv(32) xor b_in(32);
                carry_64 := result_with_carry(64);
                if e_in.insn_type = OP_ADD then
                    if e_in.output_carry = '1' then
                        set_carry(v.e, carry_32, carry_64);
                    end if;
                    if e_in.oe = '1' then
                        set_ov(v.e,
                               calc_ov(a_inv(63), b_in(63), carry_64, result_with_carry(63)),
                               calc_ov(a_inv(31), b_in(31), carry_32, result_with_carry(31)));
                    end if;
                    result_en := '1';
                else
                    -- CMP and CMPL instructions
                    -- Note, we have done RB - RA, not RA - RB
                    bf := insn_bf(e_in.insn);
                    l := insn_l(e_in.insn);
                    v.e.write_cr_enable := '1';
                    crnum := to_integer(unsigned(bf));
                    v.e.write_cr_mask := num_to_fxm(crnum);
                    zerolo := not (or (a_in(31 downto 0) xor b_in(31 downto 0)));
                    zerohi := not (or (a_in(63 downto 32) xor b_in(63 downto 32)));
                    if zerolo = '1' and (l = '0' or zerohi = '1') then
                        -- values are equal
                        newcrf := "001" & v.e.xerc.so;
                    else
                        if l = '1' then
                            -- 64-bit comparison
                            msb_a := a_in(63);
                            msb_b := b_in(63);
                        else
                            -- 32-bit comparison
                            msb_a := a_in(31);
                            msb_b := b_in(31);
                        end if;
                        if msb_a /= msb_b then
                            -- Subtraction might overflow, but
                            -- comparison is clear from MSB difference.
                            -- for signed, 0 is greater; for unsigned, 1 is greater
                            a_lt := msb_a xnor e_in.is_signed;
                        else
                            -- Subtraction cannot overflow since MSBs are equal.
                            -- carry = 1 indicates RA is smaller (signed or unsigned)
                            a_lt := (not l and carry_32) or (l and carry_64);
                        end if;
                        newcrf := a_lt & not a_lt & '0' & v.e.xerc.so;
                    end if;
                    for i in 0 to 7 loop
                        lo := i*4;
                        hi := lo + 3;
                        v.e.write_cr_data(hi downto lo) := newcrf;
                    end loop;
                end if;
	    when OP_AND | OP_OR | OP_XOR =>
		result := logical_result;
		result_en := '1';
	    when OP_B =>
		f_out.redirect <= '1';
		if (insn_aa(e_in.insn)) then
		    f_out.redirect_nia <= std_ulogic_vector(signed(b_in));
		else
		    f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(b_in));
		end if;
	    when OP_BC =>
		-- read_data1 is CTR
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' then
		    result := std_ulogic_vector(unsigned(a_in) - 1);
		    result_en := '1';
		    v.e.write_reg := fast_spr_num(SPR_CTR);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, a_in) = 1 then
		    f_out.redirect <= '1';
		    if (insn_aa(e_in.insn)) then
			f_out.redirect_nia <= std_ulogic_vector(signed(b_in));
		    else
			f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(b_in));
		    end if;
		end if;
	    when OP_BCREG =>
		-- read_data1 is CTR
		-- read_data2 is target register (CTR, LR or TAR)
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' and e_in.insn(10) = '0' then
		    result := std_ulogic_vector(unsigned(a_in) - 1);
		    result_en := '1';
		    v.e.write_reg := fast_spr_num(SPR_CTR);
		end if;
		if ppc_bc_taken(bo, bi, e_in.cr, a_in) = 1 then
		    f_out.redirect <= '1';
		    f_out.redirect_nia <= b_in(63 downto 2) & "00";
		end if;
	    when OP_CMPB =>
		result := ppc_cmpb(c_in, b_in);
		result_en := '1';
            when OP_CNTZ =>
                v.e.valid := '0';
                v.cntz_in_progress := '1';
                stall_out <= '1';
            when OP_EXTS =>
                -- note data_len is a 1-hot encoding
		negative := (e_in.data_len(0) and c_in(7)) or
			    (e_in.data_len(1) and c_in(15)) or
			    (e_in.data_len(2) and c_in(31));
		result := (others => negative);
		if e_in.data_len(2) = '1' then
		    result(31 downto 16) := c_in(31 downto 16);
		end if;
		if e_in.data_len(2) = '1' or e_in.data_len(1) = '1' then
		    result(15 downto 8) := c_in(15 downto 8);
		end if;
		result(7 downto 0) := c_in(7 downto 0);
		result_en := '1';
	    when OP_ISEL =>
		crbit := to_integer(unsigned(insn_bc(e_in.insn)));
		if e_in.cr(31-crbit) = '1' then
		    result := a_in;
		else
		    result := b_in;
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
			crresult := '0';
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
		    result := a_in;
		    if decode_spr_num(e_in.insn) = SPR_XER then
			-- bits 0:31 and 35:43 are treated as reserved and return 0s when read using mfxer
			result(63 downto 32) := (others => '0');
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
		v.e.write_cr_data := c_in(31 downto 0);
	    when OP_MTSPR =>
		report "MTSPR to SPR " & integer'image(decode_spr_num(e_in.insn)) &
		    "=" & to_hstring(c_in);
		if is_fast_spr(e_in.write_reg) then
		    result := c_in;
		    result_en := '1';
		    if decode_spr_num(e_in.insn) = SPR_XER then
			v.e.xerc.so := c_in(63-32);
			v.e.xerc.ov := c_in(63-33);
			v.e.xerc.ca := c_in(63-34);
			v.e.xerc.ov32 := c_in(63-44);
			v.e.xerc.ca32 := c_in(63-45);
			v.e.write_xerc_enable := '1';
		    end if;
		else
-- TODO: Implement slow SPRs	    
--		    case decode_spr_num(e_in.insn) is
--		    when others =>
--		    end case;
		end if;
	    when OP_POPCNT =>
		result := popcnt_result;
		result_en := '1';
	    when OP_PRTY =>
		result := parity_result;
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

	    when OP_MUL_L64 | OP_MUL_H64 | OP_MUL_H32 =>
		v.e.valid := '0';
		v.mul_in_progress := '1';
		stall_out <= '1';
		x_to_multiply.valid <= '1';

	    when OP_DIV | OP_DIVE | OP_MOD =>
		v.e.valid := '0';
		v.div_in_progress := '1';
		stall_out <= '1';
		x_to_divider.valid <= '1';

            when OP_LOAD | OP_STORE =>
                -- loadstore/dcache has its own port to writeback
                v.e.valid := '0';

            when others =>
		terminate_out <= '1';
		report "illegal";
	    end case;

	    v.e.rc := e_in.rc and e_in.valid;

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
	    v.e.valid := '1';
        elsif r.cntz_in_progress = '1' then
            -- cnt[lt]z always takes two cycles
            result := countzero_result;
            result_en := '1';
            v.e.write_reg := gpr_to_gspr(v.slow_op_dest);
            v.e.rc := v.slow_op_rc;
            v.e.xerc := v.slow_op_xerc;
            v.e.valid := '1';
	elsif r.mul_in_progress = '1' or r.div_in_progress = '1' then
	    if (r.mul_in_progress = '1' and multiply_to_x.valid = '1') or
	       (r.div_in_progress = '1' and divider_to_x.valid = '1') then
		if r.mul_in_progress = '1' then
		    result := multiply_to_x.write_reg_data;
		    overflow := multiply_to_x.overflow;
		else
		    result := divider_to_x.write_reg_data;
		    overflow := divider_to_x.overflow;
		end if;
		result_en := '1';
		v.e.write_reg := gpr_to_gspr(v.slow_op_dest);
		v.e.rc := v.slow_op_rc;
		v.e.xerc := v.slow_op_xerc;
		v.e.write_xerc_enable := v.slow_op_oe;
		-- We must test oe because the RC update code in writeback
		-- will use the xerc value to set CR0:SO so we must not clobber
		-- xerc if OE wasn't set.
		if v.slow_op_oe = '1' then
		    v.e.xerc.ov := overflow;
		    v.e.xerc.ov32 := overflow;
		    v.e.xerc.so := v.slow_op_xerc.so or overflow;
		end if;
		v.e.valid := '1';
	    else
		stall_out <= '1';
		v.mul_in_progress := r.mul_in_progress;
		v.div_in_progress := r.div_in_progress;
	    end if;
	end if;

	v.e.write_data := result;
	v.e.write_enable := result_en;

        -- Outputs to loadstore1 (async)
        lv := Execute1ToLoadstore1Init;
        if e_in.valid = '1' and (e_in.insn_type = OP_LOAD or e_in.insn_type = OP_STORE) then
            lv.valid := '1';
        end if;
        if e_in.insn_type = OP_LOAD then
            lv.load := '1';
        end if;
        lv.addr1 := a_in;
        lv.addr2 := b_in;
        lv.data := c_in;
        lv.write_reg := gspr_to_gpr(e_in.write_reg);
        lv.length := e_in.data_len;
        lv.byte_reverse := e_in.byte_reverse;
        lv.sign_extend := e_in.sign_extend;
        lv.update := e_in.update;
        lv.update_reg := gspr_to_gpr(e_in.read_reg1);
        lv.xerc := v.e.xerc;

	-- Update registers
	rin <= v;

	-- update outputs
	--f_out <= r.f;
        l_out <= lv;
	e_out <= r.e;
	flush_out <= f_out.redirect;
    end process;
end architecture behaviour;
