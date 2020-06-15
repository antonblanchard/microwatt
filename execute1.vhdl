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
	busy_out : out std_ulogic;

	e_in  : in Decode2ToExecute1Type;
        l_in  : in Loadstore1ToExecute1Type;

	ext_irq_in : std_ulogic;

	-- asynchronous
        l_out : out Execute1ToLoadstore1Type;
	f_out : out Execute1ToFetch1Type;

	e_out : out Execute1ToWritebackType;

        dbg_msr_out : out std_ulogic_vector(63 downto 0);

	icache_inval : out std_ulogic;
	terminate_out : out std_ulogic;

        log_out : out std_ulogic_vector(14 downto 0);
        log_rd_addr : out std_ulogic_vector(31 downto 0);
        log_rd_data : in std_ulogic_vector(63 downto 0);
        log_wr_addr : in std_ulogic_vector(31 downto 0)
	);
end entity execute1;

architecture behaviour of execute1 is
    type reg_type is record
	e : Execute1ToWritebackType;
        busy: std_ulogic;
        terminate: std_ulogic;
	lr_update : std_ulogic;
	next_lr : std_ulogic_vector(63 downto 0);
	mul_in_progress : std_ulogic;
        div_in_progress : std_ulogic;
        cntz_in_progress : std_ulogic;
        slow_op_insn : insn_type_t;
	slow_op_dest : gpr_index_t;
	slow_op_rc : std_ulogic;
	slow_op_oe : std_ulogic;
	slow_op_xerc : xer_common_t;
        last_nia : std_ulogic_vector(63 downto 0);
        log_addr_spr : std_ulogic_vector(31 downto 0);
    end record;
    constant reg_type_init : reg_type :=
        (e => Execute1ToWritebackInit, busy => '0', lr_update => '0', terminate => '0',
         mul_in_progress => '0', div_in_progress => '0', cntz_in_progress => '0',
         slow_op_insn => OP_ILLEGAL, slow_op_rc => '0', slow_op_oe => '0', slow_op_xerc => xerc_init,
         next_lr => (others => '0'), last_nia => (others => '0'), others => (others => '0'));

    signal r, rin : reg_type;

    signal a_in, b_in, c_in : std_ulogic_vector(63 downto 0);

    signal valid_in : std_ulogic;
    signal ctrl: ctrl_t := (irq_state => WRITE_SRR0, others => (others => '0'));
    signal ctrl_tmp: ctrl_t := (irq_state => WRITE_SRR0, others => (others => '0'));
    signal right_shift, rot_clear_left, rot_clear_right: std_ulogic;
    signal rot_sign_ext: std_ulogic;
    signal rotator_result: std_ulogic_vector(63 downto 0);
    signal rotator_carry: std_ulogic;
    signal logical_result: std_ulogic_vector(63 downto 0);
    signal countzero_result: std_ulogic_vector(63 downto 0);

    -- multiply signals
    signal x_to_multiply: Execute1ToMultiplyType;
    signal multiply_to_x: MultiplyToExecute1Type;

    -- divider signals
    signal x_to_divider: Execute1ToDividerType;
    signal divider_to_x: DividerToExecute1Type;

    -- signals for logging
    signal exception_log : std_ulogic;
    signal irq_valid_log : std_ulogic;
    signal log_data : std_ulogic_vector(14 downto 0);

    type privilege_level is (USER, SUPER);
    type op_privilege_array is array(insn_type_t) of privilege_level;
    constant op_privilege: op_privilege_array := (
        OP_ATTN => SUPER,
        OP_MFMSR => SUPER,
        OP_MTMSRD => SUPER,
        OP_RFID => SUPER,
        OP_TLBIE => SUPER,
        others => USER
        );

    function instr_is_privileged(op: insn_type_t; insn: std_ulogic_vector(31 downto 0))
        return boolean is
    begin
        if op_privilege(op) = SUPER then
            return true;
        elsif op = OP_MFSPR or op = OP_MTSPR then
            return insn(20) = '1';
        else
            return false;
        end if;
    end;

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

    function msr_copy(msr: std_ulogic_vector(63 downto 0))
	return std_ulogic_vector is
	variable msr_out: std_ulogic_vector(63 downto 0);
    begin
	-- ISA says this:
	--  Defined MSR bits are classified as either full func-
	--  tion or partial function. Full function MSR bits are
	--  saved in SRR1 or HSRR1 when an interrupt other
	--  than a System Call Vectored interrupt occurs and
	--  restored by rfscv, rfid, or hrfid, while partial func-
	--  tion MSR bits are not saved or restored.
	--  Full function MSR bits lie in the range 0:32, 37:41, and
	--  48:63, and partial function MSR bits lie in the range
	--  33:36 and 42:47. (Note this is IBM bit numbering).
	msr_out := (others => '0');
	msr_out(63 downto 31) := msr(63 downto 31);
	msr_out(26 downto 22) := msr(26 downto 22);
	msr_out(15 downto 0)  := msr(15 downto 0);
	return msr_out;
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
            sign_ext_rs => rot_sign_ext,
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
            datalen => e_in.data_len
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

    dbg_msr_out <= ctrl.msr;
    log_rd_addr <= r.log_addr_spr;

    a_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data1 = '1' else e_in.read_data1;
    b_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data2 = '1' else e_in.read_data2;
    c_in <= r.e.write_data when EX1_BYPASS and e_in.bypass_data3 = '1' else e_in.read_data3;

    busy_out <= l_in.busy or r.busy;
    valid_in <= e_in.valid and not busy_out;

    terminate_out <= r.terminate;

    execute1_0: process(clk)
    begin
	if rising_edge(clk) then
            if rst = '1' then
                r <= reg_type_init;
                ctrl.msr <= (MSR_SF => '1', MSR_LE => '1', others => '0');
                ctrl.irq_state <= WRITE_SRR0;
            else
                r <= rin;
                ctrl <= ctrl_tmp;
                assert not (r.lr_update = '1' and valid_in = '1')
                    report "LR update collision with valid in EX1"
                    severity failure;
                if r.lr_update = '1' then
                    report "LR update to " & to_hstring(r.next_lr);
                end if;
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
        variable cr_operands : std_ulogic_vector(1 downto 0);
	variable bt, ba, bb : std_ulogic_vector(4 downto 0);
	variable btnum, banum, bbnum : integer range 0 to 31;
	variable crresult : std_ulogic;
	variable l : std_ulogic;
	variable next_nia : std_ulogic_vector(63 downto 0);
        variable carry_32, carry_64 : std_ulogic;
        variable sign1, sign2 : std_ulogic;
        variable abs1, abs2 : signed(63 downto 0);
	variable overflow : std_ulogic;
        variable zerohi, zerolo : std_ulogic;
        variable msb_a, msb_b : std_ulogic;
        variable a_lt : std_ulogic;
        variable lv : Execute1ToLoadstore1Type;
	variable irq_valid : std_ulogic;
	variable exception : std_ulogic;
        variable exception_nextpc : std_ulogic;
        variable trapval : std_ulogic_vector(4 downto 0);
        variable illegal : std_ulogic;
        variable is_branch : std_ulogic;
        variable taken_branch : std_ulogic;
        variable abs_branch : std_ulogic;
        variable spr_val : std_ulogic_vector(63 downto 0);
    begin
	result := (others => '0');
	result_with_carry := (others => '0');
	result_en := '0';
	newcrf := (others => '0');
        is_branch := '0';
        taken_branch := '0';
        abs_branch := '0';

	v := r;
	v.e := Execute1ToWritebackInit;
        lv := Execute1ToLoadstore1Init;

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

        -- signals to multiply and divide units
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

	x_to_multiply <= Execute1ToMultiplyInit;
	x_to_multiply.is_32bit <= e_in.is_32bit;

        x_to_divider <= Execute1ToDividerInit;
        x_to_divider.is_signed <= e_in.is_signed;
	x_to_divider.is_32bit <= e_in.is_32bit;
        if e_in.insn_type = OP_MOD then
            x_to_divider.is_modulus <= '1';
        end if;

        x_to_multiply.neg_result <= sign1 xor sign2;
        x_to_divider.neg_result <= sign1 xor (sign2 and not x_to_divider.is_modulus);
        if e_in.is_32bit = '0' then
            -- 64-bit forms
            x_to_multiply.data1 <= std_ulogic_vector(abs1);
            x_to_multiply.data2 <= std_ulogic_vector(abs2);
            if e_in.insn_type = OP_DIVE then
                x_to_divider.is_extended <= '1';
            end if;
            x_to_divider.dividend <= std_ulogic_vector(abs1);
            x_to_divider.divisor <= std_ulogic_vector(abs2);
        else
            -- 32-bit forms
            x_to_multiply.data1 <= x"00000000" & std_ulogic_vector(abs1(31 downto 0));
            x_to_multiply.data2 <= x"00000000" & std_ulogic_vector(abs2(31 downto 0));
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
	ctrl_tmp.dec <= std_ulogic_vector(unsigned(ctrl.dec) - 1);

	irq_valid := '0';
	if ctrl.msr(MSR_EE) = '1' then
	    if ctrl.dec(63) = '1' then
		ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#900#, 64));
		report "IRQ valid: DEC";
		irq_valid := '1';
	    elsif ext_irq_in = '1' then
		ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#500#, 64));
		report "IRQ valid: External";
		irq_valid := '1';
	    end if;
	end if;

	v.terminate := '0';
	icache_inval <= '0';
	v.busy := '0';
	f_out <= Execute1ToFetch1TypeInit;
        -- send MSR[IR] and ~MSR[PR] up to fetch1
        f_out.virt_mode <= ctrl.msr(MSR_IR);
        f_out.priv_mode <= not ctrl.msr(MSR_PR);

	-- Next insn adder used in a couple of places
	next_nia := std_ulogic_vector(unsigned(e_in.nia) + 4);

	-- rotator control signals
	right_shift <= '1' when e_in.insn_type = OP_SHR else '0';
	rot_clear_left <= '1' when e_in.insn_type = OP_RLC or e_in.insn_type = OP_RLCL else '0';
	rot_clear_right <= '1' when e_in.insn_type = OP_RLC or e_in.insn_type = OP_RLCR else '0';
        rot_sign_ext <= '1' when e_in.insn_type = OP_EXTSWSLI else '0';

	ctrl_tmp.irq_state <= WRITE_SRR0;
	exception := '0';
        illegal := '0';
        exception_nextpc := '0';
        v.e.exc_write_enable := '0';
        v.e.exc_write_reg := fast_spr_num(SPR_SRR0);
        v.e.exc_write_data := e_in.nia;
        if valid_in = '1' then
            v.last_nia := e_in.nia;
        end if;

 	if ctrl.irq_state = WRITE_SRR1 then
 	    v.e.exc_write_reg := fast_spr_num(SPR_SRR1);
 	    v.e.exc_write_data := ctrl.srr1;
            v.e.exc_write_enable := '1';
            ctrl_tmp.msr(MSR_SF) <= '1';
            ctrl_tmp.msr(MSR_EE) <= '0';
            ctrl_tmp.msr(MSR_PR) <= '0';
            ctrl_tmp.msr(MSR_IR) <= '0';
            ctrl_tmp.msr(MSR_DR) <= '0';
            ctrl_tmp.msr(MSR_RI) <= '0';
            ctrl_tmp.msr(MSR_LE) <= '1';
	    f_out.redirect <= '1';
            f_out.virt_mode <= '0';
            f_out.priv_mode <= '1';
	    f_out.redirect_nia <= ctrl.irq_nia;
            v.e.valid := '1';
	    report "Writing SRR1: " & to_hstring(ctrl.srr1);

	elsif irq_valid = '1' and valid_in = '1' then
	    -- we need two cycles to write srr0 and 1
	    -- will need more when we have to write HEIR
            -- Don't deliver the interrupt until we have a valid instruction
            -- coming in, so we have a valid NIA to put in SRR0.
	    exception := '1';
	    ctrl_tmp.srr1 <= msr_copy(ctrl.msr);

        elsif valid_in = '1' and ctrl.msr(MSR_PR) = '1' and
            instr_is_privileged(e_in.insn_type, e_in.insn) then
            -- generate a program interrupt
            exception := '1';
            ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#700#, 64));
            ctrl_tmp.srr1 <= msr_copy(ctrl.msr);
            -- set bit 45 to indicate privileged instruction type interrupt
            ctrl_tmp.srr1(63 - 45) <= '1';
            report "privileged instruction";
            
	elsif valid_in = '1' and e_in.unit = ALU then

	    report "execute nia " & to_hstring(e_in.nia);

	    v.e.valid := '1';
	    v.e.write_reg := e_in.write_reg;
            v.slow_op_insn := e_in.insn_type;
	    v.slow_op_dest := gspr_to_gpr(e_in.write_reg);
	    v.slow_op_rc := e_in.rc;
	    v.slow_op_oe := e_in.oe;
	    v.slow_op_xerc := v.e.xerc;

	    case_0: case e_in.insn_type is

	    when OP_ILLEGAL =>
		-- we need two cycles to write srr0 and 1
		-- will need more when we have to write HEIR
		illegal := '1';
	    when OP_SC =>
		-- check bit 1 of the instruction is 1 so we know this is sc;
                -- 0 would mean scv, so generate an illegal instruction interrupt
		-- we need two cycles to write srr0 and 1
                if e_in.insn(1) = '1' then
                    exception := '1';
                    exception_nextpc := '1';
                    ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#C00#, 64));
                    ctrl_tmp.srr1 <= msr_copy(ctrl.msr);
                    report "sc";
                else
                    illegal := '1';
                end if;
	    when OP_ATTN =>
                -- check bits 1-10 of the instruction to make sure it's attn
                -- if not then it is illegal
                if e_in.insn(10 downto 1) = "0100000000" then
                    v.terminate := '1';
                    report "ATTN";
                else
                    illegal := '1';
                end if;
	    when OP_NOP =>
		-- Do nothing
	    when OP_ADD | OP_CMP | OP_TRAP =>
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
                    -- trap, CMP and CMPL instructions
                    -- Note, we have done RB - RA, not RA - RB
                    if e_in.insn_type = OP_CMP then
                        l := insn_l(e_in.insn);
                    else
                        l := not e_in.is_32bit;
                    end if;
                    zerolo := not (or (a_in(31 downto 0) xor b_in(31 downto 0)));
                    zerohi := not (or (a_in(63 downto 32) xor b_in(63 downto 32)));
                    if zerolo = '1' and (l = '0' or zerohi = '1') then
                        -- values are equal
                        trapval := "00100";
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
                            trapval := msb_a & msb_b & '0' & msb_b & msb_a;
                        else
                            -- Subtraction cannot overflow since MSBs are equal.
                            -- carry = 1 indicates RA is smaller (signed or unsigned)
                            a_lt := (not l and carry_32) or (l and carry_64);
                            trapval := a_lt & not a_lt & '0' & a_lt & not a_lt;
                        end if;
                    end if;
                    if e_in.insn_type = OP_CMP then
                        if e_in.is_signed = '1' then
                            newcrf := trapval(4 downto 2) & v.e.xerc.so;
                        else
                            newcrf := trapval(1 downto 0) & trapval(2) & v.e.xerc.so;
                        end if;
                        bf := insn_bf(e_in.insn);
                        crnum := to_integer(unsigned(bf));
                        v.e.write_cr_enable := '1';
                        v.e.write_cr_mask := num_to_fxm(crnum);
                        for i in 0 to 7 loop
                            lo := i*4;
                            hi := lo + 3;
                            v.e.write_cr_data(hi downto lo) := newcrf;
                        end loop;
                    else
                        -- trap instructions (tw, twi, td, tdi)
                        if or (trapval and insn_to(e_in.insn)) = '1' then
                            -- generate trap-type program interrupt
                            exception := '1';
                            ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#700#, 64));
                            ctrl_tmp.srr1 <= msr_copy(ctrl.msr);
                            -- set bit 46 to say trap occurred
                            ctrl_tmp.srr1(63 - 46) <= '1';
                            report "trap";
                        end if;
                    end if;
                end if;
	    when OP_AND | OP_OR | OP_XOR | OP_POPCNT | OP_PRTY | OP_CMPB | OP_EXTS =>
		result := logical_result;
		result_en := '1';
	    when OP_B =>
                is_branch := '1';
                taken_branch := '1';
                abs_branch := insn_aa(e_in.insn);
	    when OP_BC =>
		-- read_data1 is CTR
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
		if bo(4-2) = '0' then
		    result := std_ulogic_vector(unsigned(a_in) - 1);
		    result_en := '1';
		    v.e.write_reg := fast_spr_num(SPR_CTR);
		end if;
                is_branch := '1';
		taken_branch := ppc_bc_taken(bo, bi, e_in.cr, a_in);
                abs_branch := insn_aa(e_in.insn);
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
		if ppc_bc_taken(bo, bi, e_in.cr, a_in) = '1' then
		    f_out.redirect <= '1';
		    f_out.redirect_nia <= b_in(63 downto 2) & "00";
		end if;

	    when OP_RFID =>
		f_out.redirect <= '1';
                f_out.virt_mode <= b_in(MSR_IR) or b_in(MSR_PR);
                f_out.priv_mode <= not b_in(MSR_PR);
		f_out.redirect_nia <= a_in(63 downto 2) & "00"; -- srr0
                -- Can't use msr_copy here because the partial function MSR
                -- bits should be left unchanged, not zeroed.
                ctrl_tmp.msr(63 downto 31) <= b_in(63 downto 31);
                ctrl_tmp.msr(26 downto 22) <= b_in(26 downto 22);
                ctrl_tmp.msr(15 downto 0)  <= b_in(15 downto 0);
                if b_in(MSR_PR) = '1' then
                    ctrl_tmp.msr(MSR_EE) <= '1';
                    ctrl_tmp.msr(MSR_IR) <= '1';
                    ctrl_tmp.msr(MSR_DR) <= '1';
                end if;

            when OP_CNTZ =>
                v.e.valid := '0';
                v.cntz_in_progress := '1';
                v.busy := '1';
	    when OP_ISEL =>
		crbit := to_integer(unsigned(insn_bc(e_in.insn)));
		if e_in.cr(31-crbit) = '1' then
		    result := a_in;
		else
		    result := b_in;
		end if;
		result_en := '1';
	    when OP_CROP =>
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
                    -- Bits 5-8 of cr_op give the truth table of the requested
                    -- logical operation
                    cr_operands := e_in.cr(banum) & e_in.cr(bbnum);
                    crresult := cr_op(5 + to_integer(unsigned(cr_operands)));
		    v.e.write_cr_mask := num_to_fxm((31-btnum) / 4);
		    for i in 0 to 31 loop
			if i = btnum then
		            v.e.write_cr_data(i) := crresult;
			else
		            v.e.write_cr_data(i) := e_in.cr(i);
			end if;
		    end loop;
		end if;
	    when OP_MFMSR =>
		result := ctrl.msr;
		result_en := '1';
	    when OP_MFSPR =>
		report "MFSPR to SPR " & integer'image(decode_spr_num(e_in.insn)) &
		    "=" & to_hstring(a_in);
		result_en := '1';
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
                    spr_val := c_in;
		    case decode_spr_num(e_in.insn) is
		    when SPR_TB =>
			spr_val := ctrl.tb;
		    when SPR_DEC =>
			spr_val := ctrl.dec;
                    when 724 =>     -- LOG_ADDR SPR
                        spr_val := log_wr_addr & r.log_addr_spr;
                    when 725 =>     -- LOG_DATA SPR
                        spr_val := log_rd_data;
                        v.log_addr_spr := std_ulogic_vector(unsigned(r.log_addr_spr) + 1);
                    when others =>
                        -- mfspr from unimplemented SPRs should be a nop in
                        -- supervisor mode and a program interrupt for user mode
                        if ctrl.msr(MSR_PR) = '1' then
                            illegal := '1';
                        end if;
		    end case;
                    result := spr_val;
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
		v.e.write_cr_data := c_in(31 downto 0);
            when OP_MTMSRD =>
                if e_in.insn(16) = '1' then
                    -- just update EE and RI
                    ctrl_tmp.msr(MSR_EE) <= c_in(MSR_EE);
                    ctrl_tmp.msr(MSR_RI) <= c_in(MSR_RI);
                else
                    -- Architecture says to leave out bits 3 (HV), 51 (ME)
                    -- and 63 (LE) (IBM bit numbering)
                    ctrl_tmp.msr(63 downto 61) <= c_in(63 downto 61);
                    ctrl_tmp.msr(59 downto 13) <= c_in(59 downto 13);
                    ctrl_tmp.msr(11 downto 1)  <= c_in(11 downto 1);
                    if c_in(MSR_PR) = '1' then
                        ctrl_tmp.msr(MSR_EE) <= '1';
                        ctrl_tmp.msr(MSR_IR) <= '1';
                        ctrl_tmp.msr(MSR_DR) <= '1';
                    end if;
                end if;
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
		    -- slow spr
		    case decode_spr_num(e_in.insn) is
		    when SPR_DEC =>
			ctrl_tmp.dec <= c_in;
                    when 724 =>     -- LOG_ADDR SPR
                        v.log_addr_spr := c_in(31 downto 0);
		    when others =>
                        -- mtspr to unimplemented SPRs should be a nop in
                        -- supervisor mode and a program interrupt for user mode
                        if ctrl.msr(MSR_PR) = '1' then
                            illegal := '1';
                        end if;
		    end case;
		end if;
	    when OP_RLC | OP_RLCL | OP_RLCR | OP_SHL | OP_SHR | OP_EXTSWSLI =>
		result := rotator_result;
		if e_in.output_carry = '1' then
		    set_carry(v.e, rotator_carry, rotator_carry);
		end if;
		result_en := '1';

	    when OP_ISYNC =>
		f_out.redirect <= '1';
		f_out.redirect_nia <= next_nia;

	    when OP_ICBI =>
		icache_inval <= '1';

	    when OP_MUL_L64 | OP_MUL_H64 | OP_MUL_H32 =>
		v.e.valid := '0';
		v.mul_in_progress := '1';
		v.busy := '1';
		x_to_multiply.valid <= '1';

	    when OP_DIV | OP_DIVE | OP_MOD =>
		v.e.valid := '0';
		v.div_in_progress := '1';
		v.busy := '1';
		x_to_divider.valid <= '1';

            when others =>
		v.terminate := '1';
		report "illegal";
	    end case;

	    v.e.rc := e_in.rc and valid_in;

            -- Mispredicted branches cause a redirect
            if is_branch = '1' and taken_branch /= e_in.br_pred then
                f_out.redirect <= '1';
                if taken_branch = '1' then
                    if abs_branch = '1' then
                        f_out.redirect_nia <= b_in;
                    else
                        f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(b_in));
                    end if;
                else
                    f_out.redirect_nia <= next_nia;
                end if;
            end if;

	    -- Update LR on the next cycle after a branch link
	    -- If we're not writing back anything else, we can write back LR
            -- this cycle, otherwise we take an extra cycle.  We use the
            -- exc_write path since next_nia is written through that path
            -- in other places.
	    if e_in.lr = '1' then
                if result_en = '0' then
                    v.e.exc_write_enable := '1';
                    v.e.exc_write_data := next_nia;
                    v.e.exc_write_reg := fast_spr_num(SPR_LR);
                else
                    v.lr_update := '1';
                    v.next_lr := next_nia;
                    v.e.valid := '0';
                    report "Delayed LR update to " & to_hstring(next_nia);
                    v.busy := '1';
                end if;
	    end if;

        elsif valid_in = '1' then
            -- instruction for other units, i.e. LDST
            if e_in.unit = LDST then
                lv.valid := '1';
            end if;

	elsif r.lr_update = '1' then
            v.e.exc_write_enable := '1';
	    v.e.exc_write_data := r.next_lr;
	    v.e.exc_write_reg := fast_spr_num(SPR_LR);
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
                    overflow := '0';
                    case r.slow_op_insn is
                        when OP_MUL_H32 =>
                            result := multiply_to_x.result(63 downto 32) &
                                      multiply_to_x.result(63 downto 32);
                        when OP_MUL_H64 =>
                            result := multiply_to_x.result(127 downto 64);
                        when others =>
                            -- i.e. OP_MUL_L64
                            result := multiply_to_x.result(63 downto 0);
                            overflow := multiply_to_x.overflow;
                    end case;
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
		v.busy := '1';
		v.mul_in_progress := r.mul_in_progress;
		v.div_in_progress := r.div_in_progress;
	    end if;
	end if;

        if illegal = '1' then
            exception := '1';
            ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#700#, 64));
            ctrl_tmp.srr1 <= msr_copy(ctrl.msr);
            -- Since we aren't doing Hypervisor emulation assist (0xe40) we
            -- set bit 44 to indicate we have an illegal
            ctrl_tmp.srr1(63 - 44) <= '1';
            report "illegal";
        end if;
	if exception = '1' then
            v.e.exc_write_enable := '1';
            if exception_nextpc = '1' then
                v.e.exc_write_data := next_nia;
            end if;
            ctrl_tmp.irq_state <= WRITE_SRR1;
            v.busy := '1';
            v.e.valid := '0';
	end if;

	v.e.write_data := result;
	v.e.write_enable := result_en;

        -- generate DSI or DSegI for load/store exceptions
        -- or ISI or ISegI for instruction fetch exceptions
        if l_in.exception = '1' then
            ctrl_tmp.srr1 <= msr_copy(ctrl.msr);
            if l_in.instr_fault = '0' then
                if l_in.segment_fault = '0' then
                    ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#300#, 64));
                else
                    ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#380#, 64));
                end if;
            else
                if l_in.segment_fault = '0' then
                    ctrl_tmp.srr1(63 - 33) <= l_in.invalid;
                    ctrl_tmp.srr1(63 - 35) <= l_in.perm_error; -- noexec fault
                    ctrl_tmp.srr1(63 - 44) <= l_in.badtree;
                    ctrl_tmp.srr1(63 - 45) <= l_in.rc_error;
                    ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#400#, 64));
                else
                    ctrl_tmp.irq_nia <= std_logic_vector(to_unsigned(16#480#, 64));
                end if;
            end if;
            v.e.exc_write_enable := '1';
            v.e.exc_write_reg := fast_spr_num(SPR_SRR0);
            v.e.exc_write_data := r.last_nia;
            report "ldst exception writing srr0=" & to_hstring(r.last_nia);
            ctrl_tmp.irq_state <= WRITE_SRR1;
        end if;

        -- Outputs to loadstore1 (async)
        lv.op := e_in.insn_type;
        lv.nia := e_in.nia;
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
        lv.reserve := e_in.reserve;
        lv.rc := e_in.rc;
        lv.insn := e_in.insn;
        -- decode l*cix and st*cix instructions here
        if e_in.insn(31 downto 26) = "011111" and e_in.insn(10 downto 9) = "11" and
            e_in.insn(5 downto 1) = "10101" then
            lv.ci := '1';
        end if;
        lv.virt_mode := ctrl.msr(MSR_DR);
        lv.priv_mode := not ctrl.msr(MSR_PR);

	-- Update registers
	rin <= v;

	-- update outputs
	--f_out <= r.f;
        l_out <= lv;
	e_out <= r.e;
	flush_out <= f_out.redirect;

        exception_log <= exception;
        irq_valid_log <= irq_valid;
    end process;

    ex1_log : process(clk)
    begin
        if rising_edge(clk) then
            log_data <= ctrl.msr(MSR_EE) & ctrl.msr(MSR_PR) &
                        ctrl.msr(MSR_IR) & ctrl.msr(MSR_DR) &
                        exception_log &
                        irq_valid_log &
                        std_ulogic_vector(to_unsigned(irq_state_t'pos(ctrl.irq_state), 1)) &
                        "000" &
                        r.e.write_enable &
                        r.e.valid &
                        f_out.redirect &
                        r.busy &
                        flush_out;
        end if;
    end process;
    log_out <= log_data;
end architecture behaviour;
