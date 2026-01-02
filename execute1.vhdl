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
        SIM : boolean := false;
        EX1_BYPASS : boolean := true;
        HAS_FPU : boolean := true;
        CPU_INDEX : natural;
        NCPUS : positive := 1;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
    port (
	clk   : in std_ulogic;
        rst   : in std_ulogic;

	-- asynchronous
	flush_in : in std_ulogic;
	busy_out : out std_ulogic;

	e_in  : in Decode2ToExecute1Type;
        l_in  : in Loadstore1ToExecute1Type;
        fp_in : in FPUToExecute1Type;

	ext_irq_in : std_ulogic;
        interrupt_in : WritebackToExecute1Type;

        tb_ctrl : timebase_ctrl;

	-- asynchronous
        l_out : out Execute1ToLoadstore1Type;
        fp_out : out Execute1ToFPUType;

	e_out : out Execute1ToWritebackType;
        bypass_data : out bypass_data_t;
        bypass_cr_data : out cr_bypass_data_t;
        bypass2_data : out bypass_data_t;
        bypass2_cr_data : out cr_bypass_data_t;

        dbg_ctrl_out : out ctrl_t;

        msg_in       : in std_ulogic;
        msg_out      : out std_ulogic_vector(NCPUS-1 downto 0);

        run_out      : out std_ulogic;
	icache_inval : out std_ulogic;
	terminate_out : out std_ulogic;

        -- PMU event buses
        wb_events    : in WritebackEventType;
        ls_events    : in Loadstore1EventType;
        dc_events    : in DcacheEventType;
        ic_events    : in IcacheEventType;

        -- Access to SPRs from core_debug module
        dbg_spr_req   : in std_ulogic;
        dbg_spr_ack   : out std_ulogic;
        dbg_spr_addr  : in std_ulogic_vector(7 downto 0);
        dbg_spr_data  : out std_ulogic_vector(63 downto 0);

        -- debug
        sim_dump      : in std_ulogic;
        sim_dump_done : out std_ulogic;

        log_out : out std_ulogic_vector(11 downto 0);
        log_rd_addr : out std_ulogic_vector(31 downto 0);
        log_rd_data : in std_ulogic_vector(63 downto 0);
        log_wr_addr : in std_ulogic_vector(31 downto 0)
	);
end entity execute1;

architecture behaviour of execute1 is
    type side_effect_type is record
        terminate : std_ulogic;
        icache_inval : std_ulogic;
        write_msr : std_ulogic;
        write_xerlow : std_ulogic;
        write_dec : std_ulogic;
        write_cfar : std_ulogic;
        set_cfar : std_ulogic;
        write_loga : std_ulogic;
        inc_loga : std_ulogic;
        write_pmuspr : std_ulogic;
        ramspr_write_even : std_ulogic;
        ramspr_write_odd : std_ulogic;
        mult_32s : std_ulogic;
        write_fscr : std_ulogic;
        write_ic : std_ulogic;
        write_lpcr : std_ulogic;
        write_heir : std_ulogic;
        set_heir : std_ulogic;
        write_ctrl : std_ulogic;
        write_dscr : std_ulogic;
        write_ciabr : std_ulogic;
        enter_wait : std_ulogic;
        scv_trap : std_ulogic;
        write_tbl : std_ulogic;
        write_tbu : std_ulogic;
        send_hmsg : std_ulogic_vector(NCPUS-1 downto 0);
        clr_hmsg : std_ulogic;
    end record;
    constant side_effect_init : side_effect_type := (send_hmsg => (others => '0'), others => '0');

    type actions_type is record
        e : Execute1ToWritebackType;
        se : side_effect_type;
        complete : std_ulogic;
        exception : std_ulogic;
        trap : std_ulogic;
        advance_nia : std_ulogic;
        redir_to_next : std_ulogic;
        new_msr : std_ulogic_vector(63 downto 0);
        take_branch : std_ulogic;
        direct_branch : std_ulogic;
        start_mul : std_ulogic;
        start_div : std_ulogic;
        start_bsort : std_ulogic;
        start_bperm : std_ulogic;
        do_trace : std_ulogic;
        ciabr_trace : std_ulogic;
        fp_intr : std_ulogic;
        res2_sel : std_ulogic_vector(1 downto 0);
        bypass_valid : std_ulogic;
        spr_write_data : std_ulogic_vector(63 downto 0);
        ic : std_ulogic_vector(3 downto 0);
    end record;
    constant actions_type_init : actions_type :=
        (e => Execute1ToWritebackInit, se => side_effect_init,
         new_msr => (others => '0'), res2_sel => "00",
         spr_write_data => 64x"0", ic => x"0", others => '0');

    type reg_stage1_type is record
	e : Execute1ToWritebackType;
        se : side_effect_type;
        busy: std_ulogic;
        fp_exception_next : std_ulogic;
        trace_next : std_ulogic;
        trace_ciabr : std_ulogic;
        prev_op : insn_type_t;
        prev_prefixed : std_ulogic;
        oe : std_ulogic;
        mul_select : std_ulogic_vector(2 downto 0);
        res2_sel : std_ulogic_vector(1 downto 0);
        spr_select : spr_id;
        pmu_spr_num : std_ulogic_vector(4 downto 0);
        redir_to_next : std_ulogic;
        advance_nia : std_ulogic;
        lr_from_next : std_ulogic;
	mul_in_progress : std_ulogic;
        mul_finish : std_ulogic;
        div_in_progress : std_ulogic;
        bsort_in_progress : std_ulogic;
        bperm_in_progress : std_ulogic;
        no_instr_avail : std_ulogic;
        instr_dispatch : std_ulogic;
        ext_interrupt : std_ulogic;
        taken_branch_event : std_ulogic;
        br_mispredict : std_ulogic;
        msr : std_ulogic_vector(63 downto 0);
        xerc : xer_common_t;
        xerc_valid : std_ulogic;
        ramspr_wraddr : ramspr_index;
        spr_write_data : std_ulogic_vector(63 downto 0);
        ic : std_ulogic_vector(3 downto 0);
        prefixed : std_ulogic;
        insn : std_ulogic_vector(31 downto 0);
        prefix : std_ulogic_vector(25 downto 0);
    end record;
    constant reg_stage1_type_init : reg_stage1_type :=
        (e => Execute1ToWritebackInit, se => side_effect_init,
         busy => '0',
         fp_exception_next => '0', trace_next => '0', trace_ciabr => '0',
         prev_op => OP_ILLEGAL, prev_prefixed => '0',
         oe => '0', mul_select => "000", res2_sel => "00",
         spr_select => spr_id_init, pmu_spr_num => 5x"0",
         redir_to_next => '0', advance_nia => '0', lr_from_next => '0',
         mul_in_progress => '0', mul_finish => '0', div_in_progress => '0',
         bsort_in_progress => '0', bperm_in_progress => '0',
         no_instr_avail => '0', instr_dispatch => '0', ext_interrupt => '0',
         taken_branch_event => '0', br_mispredict => '0',
         msr => 64x"0",
         xerc => xerc_init, xerc_valid => '0',
         ramspr_wraddr => (others => '0'), spr_write_data => 64x"0",
         ic => x"0",
         prefixed => '0', insn => 32x"0", prefix => 26x"0");

    type reg_stage2_type is record
	e : Execute1ToWritebackType;
        se : side_effect_type;
        ext_interrupt : std_ulogic;
        taken_branch_event : std_ulogic;
        br_mispredict : std_ulogic;
        log_addr_spr : std_ulogic_vector(31 downto 0);
    end record;
    constant reg_stage2_type_init : reg_stage2_type :=
        (e => Execute1ToWritebackInit, se => side_effect_init,
         log_addr_spr => 32x"0", others => '0');

    signal ex1, ex1in : reg_stage1_type;
    signal ex2, ex2in : reg_stage2_type;
    signal actions : actions_type;

    signal a_in, b_in, c_in : std_ulogic_vector(63 downto 0);
    signal cr_in : std_ulogic_vector(31 downto 0);
    signal xerc_in : xer_common_t;

    signal valid_in : std_ulogic;
    signal ctrl: ctrl_t := ctrl_t_init;
    signal ctrl_tmp: ctrl_t := ctrl_t_init;
    signal dec_sign: std_ulogic;
    signal rotator_result: std_ulogic_vector(63 downto 0);
    signal rotator_carry: std_ulogic;
    signal logical_result: std_ulogic_vector(63 downto 0);
    signal countbits_result: std_ulogic_vector(63 downto 0);
    signal alu_result: std_ulogic_vector(63 downto 0);
    signal adder_result: std_ulogic_vector(63 downto 0);
    signal misc_result: std_ulogic_vector(63 downto 0);
    signal multicyc_result: std_ulogic_vector(63 downto 0);
    signal bsort_result: std_ulogic_vector(63 downto 0);
    signal spr_result: std_ulogic_vector(63 downto 0);
    signal next_nia : std_ulogic_vector(63 downto 0);
    signal s1_sel : result_sel_t;
    signal log_spr_data : std_ulogic_vector(63 downto 0);

    signal carry_32 : std_ulogic;
    signal carry_64 : std_ulogic;
    signal overflow_32 : std_ulogic;
    signal overflow_64 : std_ulogic;

    signal trapval : std_ulogic_vector(4 downto 0);

    signal write_cr_mask : std_ulogic_vector(7 downto 0);
    signal write_cr_data : std_ulogic_vector(31 downto 0);

    -- multiply signals
    signal x_to_multiply: MultiplyInputType;
    signal multiply_to_x: MultiplyOutputType;
    signal x_to_mult_32s: MultiplyInputType;
    signal mult_32s_to_x: MultiplyOutputType;

    -- divider signals
    signal x_to_divider: Execute1ToDividerType;
    signal divider_to_x: DividerToExecute1Type := DividerToExecute1Init;

    -- bit-sort unit signals
    signal bsort_start : std_ulogic;
    signal bsort_done  : std_ulogic;
    signal bperm_start : std_ulogic;
    signal bperm_done : std_ulogic;

    -- random number generator signals
    signal random_raw  : std_ulogic_vector(63 downto 0);
    signal random_cond : std_ulogic_vector(63 downto 0);
    signal random_err  : std_ulogic;

    -- PMU signals
    signal x_to_pmu : Execute1ToPMUType;
    signal pmu_to_x : PMUToExecute1Type;
    signal pmu_trace : std_ulogic;

    -- signals for logging
    signal exception_log : std_ulogic;
    signal irq_valid_log : std_ulogic;

    -- SPR-related signals
    type ramspr_half_t is array(ramspr_index_range) of std_ulogic_vector(63 downto 0);
    signal even_sprs : ramspr_half_t := (others => (others => '0'));
    signal odd_sprs : ramspr_half_t := (others => (others => '0'));
    signal ramspr_even : std_ulogic_vector(63 downto 0);
    signal ramspr_odd : std_ulogic_vector(63 downto 0);
    signal ramspr_result : std_ulogic_vector(63 downto 0);
    signal ramspr_rd_odd : std_ulogic;
    signal ramspr_wr_addr : ramspr_index;
    signal ramspr_even_wr_data : std_ulogic_vector(63 downto 0);
    signal ramspr_even_wr_enab : std_ulogic;
    signal ramspr_odd_wr_data : std_ulogic_vector(63 downto 0);
    signal ramspr_odd_wr_enab : std_ulogic;

    signal stage2_stall : std_ulogic;

    signal timebase : std_ulogic_vector(63 downto 0);
    signal tb_next  : std_ulogic_vector(63 downto 0);
    signal tb_carry : std_ulogic;

    -- directed hypervisor doorbell state
    signal dhd_pending : std_ulogic;

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

    procedure set_carry(e: inout Execute1ToWritebackType;
			carry32 : in std_ulogic;
			carry : in std_ulogic) is
    begin
	e.xerc.ca32 := carry32;
	e.xerc.ca := carry;
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
        when OV =>
            return xerc.ov;
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
        msr_out(MSR_HV) := '1';         -- HV is always set
	msr_out(63 downto 31) := msr(63 downto 31);
	msr_out(26 downto 22) := msr(26 downto 22);
	msr_out(15 downto 0)  := msr(15 downto 0);
	return msr_out;
    end;

    function intr_srr1(msr: std_ulogic_vector; flags: std_ulogic_vector)
        return std_ulogic_vector is
        variable srr1: std_ulogic_vector(63 downto 0);
    begin
        srr1(63 downto 61) := msr(63 downto 61);
        srr1(MSR_HV)       := '1';
        srr1(59 downto 31) := msr(59 downto 31);
        srr1(63 downto 31) := msr(63 downto 31);
        srr1(30 downto 27) := flags(14 downto 11);
        srr1(26 downto 22) := msr(26 downto 22);
        srr1(21 downto 16) := flags(5 downto 0);
        srr1(15 downto  0) := msr(15 downto 0);
        return srr1;
    end;

    -- Work out whether a signed value fits into n bits,
    -- that is, see if it is in the range -2^(n-1) .. 2^(n-1) - 1
    function fits_in_n_bits(val: std_ulogic_vector; n: integer) return boolean is
        variable x, xp1: std_ulogic_vector(val'left downto val'right);
    begin
        x := val;
        if val(val'left) = '0' then
            x := not val;
        end if;
        xp1 := bit_reverse(std_ulogic_vector(unsigned(bit_reverse(x)) + 1));
        x := x and not xp1;
        -- For positive inputs, x has ones at the positions
        -- to the left of the leftmost 1 bit in val.
        -- For negative inputs, x has ones to the left of
        -- the leftmost 0 bit in val.
        return x(n - 1) = '1';
    end;

    function assemble_xer(xerc: xer_common_t; xer_low: std_ulogic_vector)
        return std_ulogic_vector is
    begin
        return 32x"0" & xerc.so & xerc.ov & xerc.ca & "000000000" &
            xerc.ov32 & xerc.ca32 & xer_low(17 downto 0);
    end;

    function assemble_fscr(c: ctrl_t) return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0);
    begin
        ret := (others => '0');
        ret(59 downto 56) := c.fscr_ic;
        ret(FSCR_PREFIX) := c.fscr_pref;
        ret(FSCR_SCV) := c.fscr_scv;
        ret(FSCR_TAR) := c.fscr_tar;
        ret(FSCR_DSCR) := c.fscr_dscr;
        return ret;
    end;

    function assemble_lpcr(c: ctrl_t) return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0);
    begin
        ret := (others => '0');
        ret(LPCR_HAIL) := c.lpcr_hail;
        ret(LPCR_EVIRT) := c.lpcr_evirt;
        ret(LPCR_UPRT) := '1';
        ret(LPCR_HR) := '1';
        ret(LPCR_LD) := c.lpcr_ld;
        ret(LPCR_HEIC) := c.lpcr_heic;
        ret(LPCR_LPES) := c.lpcr_lpes;
        ret(LPCR_HVICE) := c.lpcr_hvice;
        return ret;
    end;

    function assemble_ctrl(c: ctrl_t; msrpr: std_ulogic) return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0);
    begin
        ret := (others => '0');
        ret(0) := c.run;
        ret(15) := c.run and not msrpr;
        return ret;
    end;

    -- return contents of DEXCR or HDEXCR
    -- top 32 bits are zeroed for access via non-privileged number
    function assemble_dexcr(c: ctrl_t; insn: std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0);
        variable spr : std_ulogic_vector(9 downto 0);
        variable dexh, dexl : aspect_bits_t;
    begin
        ret := (others => '0');
        spr := insn(15 downto 11) & insn(20 downto 16);
        if spr(9) = '1' then
            dexh := c.dexcr_pnh;
            dexl := c.dexcr_pro;
        else
            dexh := c.hdexcr_hyp;
            dexl := c.hdexcr_enf;
        end if;
        if spr(4) = '0' then
            dexl := (others => '0');
        end if;
        ret := dexh(DEXCR_SBHE) & "00" & dexh(DEXCR_IBRTPD) & dexh(DEXCR_SRAPD) &
               dexh(DEXCR_NPHIE) & dexh(DEXCR_PHIE) & 25x"0" &
               dexl(DEXCR_SBHE) & "00" & dexl(DEXCR_IBRTPD) & dexl(DEXCR_SRAPD) &
               dexl(DEXCR_NPHIE) & dexl(DEXCR_PHIE) & 25x"0";
        return ret;
    end;

    function assemble_dec(c: ctrl_t) return std_ulogic_vector is
    begin
        if c.lpcr_ld = '1' then
            return c.dec;
        else
            return 32x"0" & c.dec(31 downto 0);
        end if;
    end;

    -- Tell vivado to keep the hierarchy for the random module so that the
    -- net names in the xdc file match.
    attribute keep_hierarchy : string;
    attribute keep_hierarchy of random_0 : label is "yes";

begin

    rotator_0: entity work.rotator
	port map (
	    rs => c_in,
	    ra => a_in,
	    shift => b_in(6 downto 0),
	    insn => e_in.insn,
	    is_32bit => e_in.is_32bit,
	    right_shift => e_in.right_shift,
	    arith => e_in.is_signed,
	    clear_left => e_in.rot_clear_left,
	    clear_right => e_in.rot_clear_right,
            sign_ext_rs => e_in.rot_sign_ext,
	    result => rotator_result,
	    carry_out => rotator_carry
	    );

    logical_0: entity work.logical
	port map (
	    rs => c_in,
	    rb => b_in,
	    op => e_in.sub_select,
	    invert_in => e_in.invert_a,
	    invert_out => e_in.invert_out,
            is_signed => e_in.is_signed,
	    result => logical_result,
            datalen => e_in.data_len
	    );

    countbits_0: entity work.bit_counter
	port map (
            clk => clk,
	    rs => c_in,
            stall => stage2_stall,
	    count_right => e_in.insn(10),
	    is_32bit => e_in.is_32bit,
            do_popcnt => e_in.do_popcnt,
            datalen => e_in.data_len,
	    result => countbits_result
	    );

    multiply_0: entity work.multiply
        port map (
            clk => clk,
            m_in => x_to_multiply,
            m_out => multiply_to_x
            );

    mult_32s_0: entity work.multiply_32s
        port map (
            clk => clk,
            stall => stage2_stall,
            m_in => x_to_mult_32s,
            m_out => mult_32s_to_x
            );

    divider_0: if not HAS_FPU generate
        div_0: entity work.divider
            port map (
                clk => clk,
                rst => rst,
                d_in => x_to_divider,
                d_out => divider_to_x
                );
    end generate;

    bsort_0: entity work.bit_sorter
        port map (
            clk => clk,
            rst => rst,
            rs => c_in,
            rb => b_in,
            go => bsort_start,
            opc => e_in.insn(7 downto 6),
            done => bsort_done,
            do_bperm => bperm_start,
            bperm_done => bperm_done,
            result => bsort_result
            );

    random_0: entity work.random
        port map (
            clk => clk,
            data => random_cond,
            raw => random_raw,
            err => random_err
            );

    pmu_0: entity work.pmu
        port map (
            clk => clk,
            rst => rst,
            p_in => x_to_pmu,
            p_out => pmu_to_x
            );

    -- Timebase just increments at the system clock frequency.
    -- Ideally it would (appear to) run at 512MHz like IBM POWER systems,
    -- but Linux seems to cope OK with it being 100MHz or whatever.
    tbase: process(clk)
    begin
        if rising_edge(clk) then
            if tb_ctrl.reset = '1' then
                timebase <= (others => '0');
                tb_carry <= '0';
            else
                timebase <= tb_next;
                tb_carry <= and(tb_next(31 downto 0));
            end if;
        end if;
    end process;

    tbase_comb: process(all)
        variable thi, tlo : std_ulogic_vector(31 downto 0);
        variable carry : std_ulogic;
    begin
        tlo := timebase(31 downto 0);
        thi := timebase(63 downto 32);
        carry := '0';
        if stage2_stall = '0' and ex1.se.write_tbl = '1' then
            tlo := ex1.spr_write_data(31 downto 0);
        elsif tb_ctrl.freeze = '0' then
            tlo := std_ulogic_vector(unsigned(tlo) + 1);
            carry := tb_carry;
        end if;
        if stage2_stall = '0' and ex1.se.write_tbu = '1' then
            thi := ex1.spr_write_data(31 downto 0);
        else
            thi := std_ulogic_vector(unsigned(thi) + carry);
        end if;
        tb_next <= thi & tlo;
    end process;

    dec_sign <= (ctrl.dec(63) and ctrl.lpcr_ld) or (ctrl.dec(31) and not ctrl.lpcr_ld);

    dbg_ctrl_out <= ctrl;
    log_rd_addr <= ex2.log_addr_spr;

    -- Doorbells
    doorbell_sync : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or ex2.se.clr_hmsg = '1' then
                dhd_pending <= '0';
            elsif msg_in = '1' then
                dhd_pending <= '1';
            end if;
        end if;
    end process;

    a_in <= e_in.read_data1;
    b_in <= e_in.read_data2;
    c_in <= e_in.read_data3;
    cr_in <= e_in.cr;

    x_to_pmu.occur <= (instr_complete => wb_events.instr_complete,
                       fp_complete => wb_events.fp_complete,
                       ld_complete => ls_events.load_complete,
                       st_complete => ls_events.store_complete,
                       itlb_miss => ls_events.itlb_miss,
                       dc_load_miss => dc_events.load_miss,
                       dc_ld_miss_resolved => dc_events.dcache_refill,
                       dc_store_miss => dc_events.store_miss,
                       dtlb_miss => dc_events.dtlb_miss,
                       dtlb_miss_resolved => dc_events.dtlb_miss_resolved,
                       icache_miss => ic_events.icache_miss,
                       itlb_miss_resolved => ic_events.itlb_miss_resolved,
                       no_instr_avail => ex1.no_instr_avail,
                       dispatch => ex1.instr_dispatch,
                       ext_interrupt => ex2.ext_interrupt,
                       br_taken_complete => ex2.taken_branch_event,
                       br_mispredict => ex2.br_mispredict,
                       others => '0');
    x_to_pmu.nia <= e_in.nia;
    x_to_pmu.addr <= l_in.ea_for_pmu;
    x_to_pmu.addr_v <= l_in.ea_valid;
    x_to_pmu.spr_num <= ex1.pmu_spr_num;
    x_to_pmu.spr_val <= ex1.spr_write_data;
    x_to_pmu.run <= ctrl.run;
    x_to_pmu.trace <= pmu_trace;

    -- XER forwarding.  The CA and CA32 bits are only modified by instructions
    -- that are handled here, so for them we can just use the result most
    -- recently sent to writeback, unless a pipeline flush has happened in the
    -- meantime.
    -- Hazards for SO/OV/OV32 are handled by control.vhdl as there may be other
    -- units writing to them.  No forwarding is done because performance of
    -- instructions that alter them is not considered significant.
    xerc_in.so <= e_in.xerc.so;
    xerc_in.ov <= e_in.xerc.ov;
    xerc_in.ov32 <= e_in.xerc.ov32;
    xerc_in.ca <= ex1.xerc.ca when ex1.xerc_valid = '1' else e_in.xerc.ca;
    xerc_in.ca32 <= ex1.xerc.ca32 when ex1.xerc_valid = '1' else e_in.xerc.ca32;

    -- N.B. the busy signal from each source includes the
    -- stage2 stall from that source in it.
    busy_out <= l_in.busy or ex1.busy or fp_in.busy or ctrl.wait_state;

    valid_in <= e_in.valid and not (busy_out or flush_in or ex1.e.redirect or ex1.e.interrupt);

    -- SPRs stored in two small RAM arrays (two so that we can read and write
    -- two SPRs in each cycle).

    ramspr_read: process(all)
        variable even_rd_data, odd_rd_data : std_ulogic_vector(63 downto 0);
        variable wr_addr : ramspr_index;
        variable even_wr_enab, odd_wr_enab : std_ulogic;
        variable even_wr_data, odd_wr_data : std_ulogic_vector(63 downto 0);
        variable ramspr_even_data : std_ulogic_vector(63 downto 0);
        variable doit : std_ulogic;
    begin
        -- Read address mux and async RAM reading
        if is_X(e_in.ramspr_even_rdaddr) then
            even_rd_data := (others => 'X');
        else
            even_rd_data := even_sprs(to_integer(e_in.ramspr_even_rdaddr));
        end if;
        if is_X(e_in.ramspr_even_rdaddr) then
            odd_rd_data := (others => 'X');
        else
            odd_rd_data := odd_sprs(to_integer(e_in.ramspr_odd_rdaddr));
        end if;

        -- Write address and data muxes
        doit := ex1.e.valid and not stage2_stall and not flush_in;
        even_wr_enab := (ex1.se.ramspr_write_even and doit) or interrupt_in.intr;
        odd_wr_enab  := (ex1.se.ramspr_write_odd and doit) or interrupt_in.intr;
        if interrupt_in.intr = '1' then
            if interrupt_in.hv_intr = '1' then
                wr_addr := RAMSPR_HSRR0;
            elsif interrupt_in.scv_int = '1' then
                wr_addr := RAMSPR_LR;
            else
                wr_addr := RAMSPR_SRR0;
            end if;
        else
            wr_addr := ex1.ramspr_wraddr;
        end if;
        if ex1.lr_from_next = '1' then
            ramspr_even_data := next_nia;
        else
            ramspr_even_data := ex1.spr_write_data;
        end if;
        if interrupt_in.intr = '1' then
            even_wr_data := ex2.e.last_nia;
            odd_wr_data := intr_srr1(ctrl.msr, interrupt_in.srr1);
        else
            even_wr_data := ramspr_even_data;
            odd_wr_data := ex1.spr_write_data;
        end if;
        ramspr_wr_addr <= wr_addr;
        ramspr_even_wr_data <= even_wr_data;
        ramspr_even_wr_enab <= even_wr_enab;
        ramspr_odd_wr_data <= odd_wr_data;
        ramspr_odd_wr_enab <= odd_wr_enab;

        -- SPR RAM read with write data bypass
        -- We assume no instruction executes in the cycle immediately following
        -- an interrupt, so we don't need to bypass interrupt data
        if ex1.se.ramspr_write_even = '1' and e_in.ramspr_even_rdaddr = ex1.ramspr_wraddr then
            ramspr_even <= ramspr_even_data;
        else
            ramspr_even <= even_rd_data;
        end if;
        if ex1.se.ramspr_write_odd = '1' and e_in.ramspr_odd_rdaddr = ex1.ramspr_wraddr then
            ramspr_odd <= ex1.spr_write_data;
        else
            ramspr_odd <= odd_rd_data;
        end if;
        if e_in.ramspr_rd_odd = '0' then
            ramspr_result <= ramspr_even;
        else
            ramspr_result <= ramspr_odd;
        end if;
        if e_in.ramspr_32bit = '1' then
            ramspr_result(63 downto 32) <= 32x"0";
        end if;
    end process;

    ramspr_write: process(clk)
    begin
        if rising_edge(clk) then
            if ramspr_even_wr_enab = '1' then
		assert not is_X(ramspr_wr_addr) report "Writing to unknown address" severity FAILURE;
                even_sprs(to_integer(ramspr_wr_addr)) <= ramspr_even_wr_data;
                report "writing even spr " & integer'image(to_integer(ramspr_wr_addr)) & " data=" &
                    to_hstring(ramspr_even_wr_data);
            end if;
            if ramspr_odd_wr_enab = '1' then
		assert not is_X(ramspr_wr_addr) report "Writing to unknown address" severity FAILURE;
                odd_sprs(to_integer(ramspr_wr_addr)) <= ramspr_odd_wr_data;
                report "writing odd spr " & integer'image(to_integer(ramspr_wr_addr)) & " data=" &
                    to_hstring(ramspr_odd_wr_data);
            end if;
        end if;
    end process;

    -- First stage result mux
    s1_sel <= e_in.result_sel when ex1.busy = '0' else MCYC;
    with s1_sel select alu_result <=
        adder_result       when ADD,
        logical_result     when LOG,
        rotator_result     when ROT,
        multicyc_result    when MCYC,
        ramspr_result      when SPR,
        misc_result        when MSC,
        64x"0"             when others;

    execute1_0: process(clk)
    begin
	if rising_edge(clk) then
            if rst = '1' then
                ex1 <= reg_stage1_type_init;
                ex2 <= reg_stage2_type_init;
                ctrl <= ctrl_t_init;
                ctrl.msr <= (MSR_SF => '1', MSR_HV => '1', MSR_LE => '1', others => '0');
                ex1.msr <= (MSR_SF => '1', MSR_HV => '1', MSR_LE => '1', others => '0');
            else
                ex1 <= ex1in;
                ex2 <= ex2in;
                ctrl <= ctrl_tmp;
                if valid_in = '1' then
                    report "CPU " & natural'image(CPU_INDEX) & " execute " & to_hstring(e_in.nia) &
                        " op=" & insn_type_t'image(e_in.insn_type) &
                        " wr=" & to_hstring(ex1in.e.write_reg) & " we=" & std_ulogic'image(ex1in.e.write_enable) &
                        " tag=" & integer'image(ex1in.e.instr_tag.tag) & std_ulogic'image(ex1in.e.instr_tag.valid) &
                        " 2nd=" & std_ulogic'image(e_in.second);
                end if;
                -- We mustn't get stalled on a cycle where execute2 is
                -- completing an instruction or generating an interrupt
                if ex2.e.valid = '1' or ex2.e.interrupt = '1' then
                    assert stage2_stall = '0' severity failure;
                end if;
            end if;
	end if;
    end process;

    ex_dbg_spr: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '0' and dbg_spr_req = '1' then
                if e_in.dbg_spr_access = '1' and dbg_spr_ack = '0' then
                    if dbg_spr_addr(7) = '1' then
                        dbg_spr_data <= ramspr_result;
                    else
                        case dbg_spr_addr(3 downto 0) is
                            when SPRSEL_FSCR =>
                                dbg_spr_data <= assemble_fscr(ctrl);
                            when SPRSEL_LPCR =>
                                dbg_spr_data <= assemble_lpcr(ctrl);
                            when SPRSEL_HEIR =>
                                dbg_spr_data <= ctrl.heir;
                            when SPRSEL_CFAR =>
                                dbg_spr_data <= ctrl.cfar;
                            when others =>
                                dbg_spr_data <= assemble_xer(xerc_in, ctrl.xer_low);
                        end case;
                    end if;
                    dbg_spr_ack <= '1';
                end if;
            else
                dbg_spr_ack <= '0';
            end if;
        end if;
    end process;

    -- Data path for integer instructions (first execute stage)
    execute1_dp: process(all)
	variable a_inv : std_ulogic_vector(63 downto 0);
	variable sum_with_carry : std_ulogic_vector(64 downto 0);
        variable sign1, sign2 : std_ulogic;
        variable abs1, abs2 : signed(63 downto 0);
        variable addend : std_ulogic_vector(127 downto 0);
	variable addg6s : std_ulogic_vector(63 downto 0);
	variable crbit : integer range 0 to 31;
	variable isel_result : std_ulogic_vector(63 downto 0);
	variable darn : std_ulogic_vector(63 downto 0);
	variable setb_result : std_ulogic_vector(63 downto 0);
	variable mfcr_result : std_ulogic_vector(63 downto 0);
	variable lo, hi : integer;
	variable l : std_ulogic;
        variable zerohi, zerolo : std_ulogic;
        variable msb_a, msb_b : std_ulogic;
        variable a_lt : std_ulogic;
        variable a_lt_lo : std_ulogic;
        variable a_lt_hi : std_ulogic;
	variable newcrf : std_ulogic_vector(3 downto 0);
	variable bf, bfa : std_ulogic_vector(2 downto 0);
	variable crnum : crnum_t;
	variable scrnum : crnum_t;
        variable cr_operands : std_ulogic_vector(1 downto 0);
	variable crresult : std_ulogic;
	variable bt, ba, bb : std_ulogic_vector(4 downto 0);
        variable btnum : integer range 0 to 3;
	variable banum, bbnum : integer range 0 to 31;
        variable j : integer;
    begin
        -- Main adder
        if e_in.invert_a = '0' then
            a_inv := a_in;
        else
            a_inv := not a_in;
        end if;
        sum_with_carry := ppc_adde(a_inv, b_in,
                                   decode_input_carry(e_in.input_carry, xerc_in));
        adder_result <= sum_with_carry(63 downto 0);
        carry_32 <= sum_with_carry(32) xor a_inv(32) xor b_in(32);
        carry_64 <= sum_with_carry(64);
        overflow_32 <= calc_ov(a_inv(31), b_in(31), carry_32, sum_with_carry(31));
        overflow_64 <= calc_ov(a_inv(63), b_in(63), carry_64, sum_with_carry(63));

        -- signals to multiplier
        addend := (others => '0');
        if e_in.reg_valid3 = '1' then
            -- integer multiply-add, major op 4 (if it is a multiply)
            addend(63 downto 0) := c_in;
            if e_in.is_signed = '1' then
                addend(127 downto 64) := (others => c_in(63));
            end if;
        end if;
        x_to_multiply.data1 <= std_ulogic_vector(a_in);
        x_to_multiply.data2 <= std_ulogic_vector(b_in);
        x_to_multiply.is_signed <= e_in.is_signed;
        x_to_multiply.subtract <= '0';
        x_to_multiply.addend <= addend;

        -- Interface to divide unit
        if not HAS_FPU then
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

            x_to_divider.is_signed <= e_in.is_signed;
            x_to_divider.is_32bit <= e_in.is_32bit;
            x_to_divider.is_extended <= '0';
            x_to_divider.is_modulus <= '0';
            if e_in.insn_type = OP_MOD then
                x_to_divider.is_modulus <= '1';
            end if;
            x_to_divider.flush <= flush_in;
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
        end if;

        -- signals to 32-bit multiplier
        x_to_mult_32s.data1 <= 32x"0" & a_in(31 downto 0);
        x_to_mult_32s.data2 <= 32x"0" & b_in(31 downto 0);
        x_to_mult_32s.is_signed <= e_in.is_signed;
        -- The following are unused, but set here to avoid X states
        x_to_mult_32s.subtract <= '0';
        x_to_mult_32s.addend <= (others => '0');

        if ex1.mul_select(2) = '0' then
            case ex1.mul_select(1 downto 0) is
                when "00" =>
                    multicyc_result <= multiply_to_x.result(63 downto 0);
                when "01" =>
                    multicyc_result <= multiply_to_x.result(63 downto 32) &
                                       multiply_to_x.result(63 downto 32);
                when others =>
                    multicyc_result <= multiply_to_x.result(127 downto 64);
            end case;
        elsif ex1.mul_select(0) = '1' and not HAS_FPU then
            multicyc_result <= divider_to_x.write_reg_data;
        else
            multicyc_result <= bsort_result;
        end if;

        -- Compute misc_result
        case e_in.sub_select is
            when "000" =>
                misc_result <= (others => '0');
            when "001" =>
                -- addg6s
                addg6s := (others => '0');
                for i in 0 to 14 loop
                    lo := i * 4;
                    hi := (i + 1) * 4;
                    if (a_in(hi) xor b_in(hi) xor sum_with_carry(hi)) = '0' then
                        addg6s(lo + 3 downto lo) := "0110";
                    end if;
                end loop;
                if sum_with_carry(64) = '0' then
                    addg6s(63 downto 60) := "0110";
                end if;
                misc_result <= addg6s;
            when "010" =>
                -- isel
		crbit := to_integer(unsigned(insn_bc(e_in.insn)));
		if cr_in(31-crbit) = '1' then
		    isel_result := a_in;
		else
		    isel_result := b_in;
		end if;
                misc_result <= isel_result;
            when "011" =>
                -- darn
                darn := (others => '1');
                if random_err = '0' then
                    case e_in.insn(17 downto 16) is
                        when "00" =>
                            darn := x"00000000" & random_cond(31 downto 0);
                        when "10" =>
                            darn := random_raw;
                        when others =>
                            darn := random_cond;
                    end case;
                end if;
                misc_result <= darn;
            when "100" =>
                -- mfmsr
		misc_result <= ex1.msr;
            when "101" =>
		if e_in.insn(20) = '0' then
		    -- mfcr
		    mfcr_result := x"00000000" & cr_in;
		else
		    -- mfocrf
		    crnum := fxm_to_num(insn_fxm(e_in.insn));
		    mfcr_result := (others => '0');
		    for i in 0 to 7 loop
			lo := (7-i)*4;
			hi := lo + 3;
			if crnum = i then
			    mfcr_result(hi downto lo) := cr_in(hi downto lo);
			end if;
		    end loop;
		end if;
                misc_result <= mfcr_result;
            when "110" =>
                -- setb and set[n]bc[r]
                setb_result := (others => '0');
                if e_in.insn(9) = '0' then
                    -- setb
                    bfa := insn_bfa(e_in.insn);
                    crbit := to_integer(unsigned(bfa)) * 4;
                    if cr_in(31 - crbit) = '1' then
                        setb_result := (others => '1');
                    elsif cr_in(30 - crbit) = '1' then
                        setb_result(0) := '1';
                    end if;
                else
                    -- set[n]bc[r]
                    crbit := to_integer(unsigned(insn_bi(e_in.insn)));
                    if (cr_in(31 - crbit) xor e_in.insn(6)) = '1' then
                        if e_in.insn(7) = '0' then
                            setb_result(0) := '1';
                        else
                            setb_result := (others => '1');
                        end if;
                    end if;
                end if;
                misc_result <= setb_result;
            when others =>
                misc_result <= (others => '0');
        end case;

        -- compute comparison results
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
            trapval <= "00100";
        else
            a_lt_lo := '0';
            a_lt_hi := '0';
            if is_X(a_in) or is_X(b_in) then
                a_lt_lo := 'X';
                a_lt_hi := 'X';
            else
                if unsigned(a_in(30 downto 0)) < unsigned(b_in(30 downto 0)) then
                    a_lt_lo := '1';
                end if;
                if unsigned(a_in(62 downto 31)) < unsigned(b_in(62 downto 31)) then
                    a_lt_hi := '1';
                end if;
            end if;
            if l = '1' then
                -- 64-bit comparison
                msb_a := a_in(63);
                msb_b := b_in(63);
                a_lt := a_lt_hi or (zerohi and (a_in(31) xnor b_in(31)) and a_lt_lo);
            else
                -- 32-bit comparison
                msb_a := a_in(31);
                msb_b := b_in(31);
                a_lt := a_lt_lo;
            end if;
            if msb_a /= msb_b then
                -- Comparison is clear from MSB difference.
                -- for signed, 0 is greater; for unsigned, 1 is greater
                trapval <= msb_a & msb_b & '0' & msb_b & msb_a;
            else
                -- MSBs are equal, so signed and unsigned comparisons give the
                -- same answer.
                trapval <= a_lt & not a_lt & '0' & a_lt & not a_lt;
            end if;
        end if;

        -- CR result mux
        bf := insn_bf(e_in.insn);
        newcrf := (others => '0');
        case e_in.sub_select is
            when "000" =>
                -- CMP and CMPL instructions
                if e_in.is_signed = '1' then
                    newcrf := trapval(4 downto 2) & xerc_in.so;
                else
                    newcrf := trapval(1 downto 0) & trapval(2) & xerc_in.so;
                end if;
            when "001" =>
                newcrf := ppc_cmprb(a_in, b_in, insn_l(e_in.insn));
            when "010" =>
                newcrf := ppc_cmpeqb(a_in, b_in);
            when "011" =>
                -- CR logical instructions
                if is_X(e_in.insn) then
                    newcrf := (others => 'X');
                else
                    crnum := to_integer(unsigned(bf));
                    j := (7 - crnum) * 4;
                    newcrf := cr_in(j + 3 downto j);
                    bt := insn_bt(e_in.insn);
                    ba := insn_ba(e_in.insn);
                    bb := insn_bb(e_in.insn);
                    btnum := 3 - to_integer(unsigned(bt(1 downto 0)));
                    banum := 31 - to_integer(unsigned(ba));
                    bbnum := 31 - to_integer(unsigned(bb));
                    -- Bits 6-9 of the instruction word give the truth table
                    -- of the requested logical operation
                    cr_operands := cr_in(banum) & cr_in(bbnum);
                    crresult := e_in.insn(6 + to_integer(unsigned(cr_operands)));
                    for i in 0 to 3 loop
                        if i = btnum then
                            newcrf(i) := crresult;
                        end if;
                    end loop;
                end if;
            when "100" =>
                -- MCRF
                if is_X(e_in.insn) then
                    newcrf := (others => 'X');
                else
                    bfa := insn_bfa(e_in.insn);
                    scrnum := to_integer(unsigned(bfa));
                    j := (7 - scrnum) * 4;
                    newcrf := cr_in(j + 3 downto j);
                end if;
            when "101" =>
                -- MCRXRX
                newcrf := xerc_in.ov & xerc_in.ov32 & xerc_in.ca & xerc_in.ca32;
            when others =>
        end case;
        if e_in.insn_type = OP_MTCRF then
            if e_in.insn(20) = '0' then
                -- mtcrf
                write_cr_mask <= insn_fxm(e_in.insn);
            else
                -- mtocrf: We require one hot priority encoding here
                crnum := fxm_to_num(insn_fxm(e_in.insn));
                write_cr_mask <= num_to_fxm(crnum);
            end if;
        elsif e_in.output_cr = '1' and not is_X(bf) then
            crnum := to_integer(unsigned(bf));
            write_cr_mask <= num_to_fxm(crnum);
        else
            write_cr_mask <= (others => '0');
        end if;
        for i in 0 to 7 loop
            if write_cr_mask(i) = '0' then
                write_cr_data(i*4 + 3 downto i*4) <= cr_in(i*4 + 3 downto i*4);
            elsif e_in.insn_type = OP_MTCRF then
                write_cr_data(i*4 + 3 downto i*4) <= c_in(i*4 + 3 downto i*4);
            else
                write_cr_data(i*4 + 3 downto i*4) <= newcrf;
            end if;
        end loop;

    end process;

    execute1_actions: process(all)
        variable v: actions_type;
	variable bo, bi : std_ulogic_vector(4 downto 0);
        variable illegal : std_ulogic;
        variable privileged : std_ulogic;
        variable misaligned : std_ulogic;
        variable slow_op : std_ulogic;
        variable owait : std_ulogic;
        variable srr1 : std_ulogic_vector(63 downto 0);
        variable c32, c64 : std_ulogic;
        variable sprnum : spr_num_t;
    begin
        v := actions_type_init;
        v.e.write_data := alu_result;
        v.e.write_reg := e_in.write_reg;
        v.e.write_enable := e_in.write_reg_enable;
        v.e.rc := e_in.rc;
        v.e.write_cr_data := write_cr_data;
        v.e.write_cr_mask := write_cr_mask;
        v.e.write_cr_enable := e_in.output_cr or e_in.rc;
        v.e.write_xerc_enable := e_in.output_xer;
        v.e.xerc := xerc_in;
        v.new_msr := ex1.msr;
        v.e.redir_mode := ex1.msr(MSR_IR) & not ex1.msr(MSR_PR) &
                          not ex1.msr(MSR_LE) & not ex1.msr(MSR_SF);
        v.e.intr_vec := 16#700#;
        v.e.alt_intr := ctrl.lpcr_hail and ex1.msr(MSR_IR) and ex1.msr(MSR_DR);
        v.e.mode_32bit := not ex1.msr(MSR_SF);
        v.e.instr_tag := e_in.instr_tag;
        v.e.last_nia := e_in.nia;

        v.se.ramspr_write_even := e_in.ramspr_write_even;
        v.se.ramspr_write_odd := e_in.ramspr_write_odd;
        v.spr_write_data := c_in;
        if e_in.dec_ctr = '1' then
            v.spr_write_data := std_ulogic_vector(unsigned(ramspr_odd) - 1);
        end if;

        -- Note the difference between v.exception and v.trap:
        -- v.exception signals a condition that prevents execution of the
        -- instruction, and hence shouldn't depend on operand data, so as to
        -- avoid timing chains through both data and control paths.
        -- v.trap also means we want to generate an interrupt, but doesn't
        -- cancel instruction execution (hence we need to avoid setting any
        -- side-effect flags or write enables when generating a trap).
        -- With v.trap = 1 we will assert both ex1.e.valid and ex1.e.interrupt
        -- to writeback, and it will complete the instruction and take
        -- an interrupt.  It is OK for v.trap to depend on operand data.

        illegal := '0';
        privileged := '0';
        misaligned := e_in.misaligned_prefix;
        slow_op := '0';
        owait := '0';

        if e_in.illegal_suffix = '1' or e_in.illegal_form = '1' then
            illegal := '1';
        elsif ex1.msr(MSR_PR) = '1' then
            privileged := e_in.privileged;
        end if;

        v.do_trace := ex1.msr(MSR_SE);
        -- see if we have a CIABR map
        if ctrl.ciabr(0) = '1' and ctrl.ciabr(1) = not ex1.msr(MSR_PR) and
            ctrl.ciabr(63 downto 2) = e_in.nia(63 downto 2) then
            v.ciabr_trace := '1';
        end if;

        if e_in.output_carry = '1' then
            case e_in.result_sel is
                when ADD =>
                    c32 := carry_32;
                    c64 := carry_64;
                when ROT =>
                    c32 := rotator_carry;
                    c64 := rotator_carry;
                when others =>
                    c32 := '0';
                    c64 := '0';
            end case;
            if e_in.input_carry /= OV then
                set_carry(v.e, c32, c64);
            else
                v.e.xerc.ov := carry_64;
                v.e.xerc.ov32 := carry_32;
            end if;
        end if;

        case_0: case e_in.insn_type is
	    when OP_ILLEGAL =>
		illegal := '1';
	    when OP_SC =>
		-- check bit 1 of the instruction to distinguish sc from scv
                if e_in.insn(1) = '1' then
                    -- sc
                    v.e.intr_vec := 16#C00#;
                    if e_in.valid = '1' then
                        report "sc";
                    end if;
                else
                    -- scv
                    v.se.scv_trap := '1';
                    v.e.intr_vec := to_integer(unsigned(e_in.insn(11 downto 5))) * 32;
                end if;
                v.trap := '1';
                v.advance_nia := '1';
	    when OP_ATTN =>
                -- check bits 1-10 of the instruction to make sure it's attn
                -- if not then it is illegal
                if e_in.insn(10 downto 1) = "0100000000" then
                    v.se.terminate := '1';
                    if e_in.valid = '1' then
                        report "ATTN";
                    end if;
                else
                    illegal := '1';
                end if;
	    when OP_NOP | OP_DCBST | OP_ICBT =>
                -- Do nothing
	    when OP_ADD =>
                if e_in.oe = '1' then
                    set_ov(v.e, overflow_64, overflow_32);
                end if;
            when OP_COMPUTE =>
            when OP_CMP =>
            when OP_TRAP =>
                -- trap instructions (tw, twi, td, tdi)
                v.e.intr_vec := 16#700#;
                -- set bit 46 to say trap occurred
                v.e.srr1(47 - 46) := '1';
                if or (trapval and insn_to(e_in.insn)) = '1' then
                    -- generate trap-type program interrupt
                    v.trap := '1';
                    if e_in.valid = '1' then
                        report "trap";
                    end if;
                end if;

	    when OP_B =>
                v.take_branch := '1';
                v.direct_branch := '1';
                v.e.br_last := '1';
                v.e.br_taken := '1';
                if e_in.br_pred = '0' then
                    -- should never happen
                    v.e.redirect := '1';
                end if;
                if ex1.msr(MSR_BE) = '1' then
                    v.do_trace := '1';
                end if;
                v.se.set_cfar := '1';
            when OP_BC =>
                -- If CTR is being decremented, it is in ramspr_odd.
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
                v.take_branch := ppc_bc_taken(bo, bi, cr_in, ramspr_odd);
                -- Mispredicted branches cause a redirect
                if v.take_branch /= e_in.br_pred then
                    v.e.redirect := '1';
                end if;
                if v.take_branch = '0' then
                    v.redir_to_next := '1';
                end if;
                v.direct_branch := '1';
                v.e.br_last := '1';
                v.e.br_taken := v.take_branch;
                if ex1.msr(MSR_BE) = '1' then
                    v.do_trace := '1';
                end if;
                v.se.set_cfar := v.take_branch;
            when OP_BCREG =>
                -- If CTR is being decremented, it is in ramspr_odd.
                -- The target address is in ramspr_result (LR, CTR or TAR).
		bo := insn_bo(e_in.insn);
		bi := insn_bi(e_in.insn);
                v.take_branch := ppc_bc_taken(bo, bi, cr_in, ramspr_odd);
                -- Indirect branches are never predicted taken
                v.e.redirect := v.take_branch;
                v.e.br_taken := v.take_branch;
                if ex1.msr(MSR_BE) = '1' then
                    v.do_trace := '1';
                end if;
                v.se.set_cfar := v.take_branch;

	    when OP_RFID =>
                -- rfid, hrfid and rfscv.
                -- These all act the same given that we don't have
                -- privileged non-hypervisor mode or ultravisor mode.
                srr1 := ramspr_odd;
                v.e.redir_mode := (srr1(MSR_IR) or srr1(MSR_PR)) & not srr1(MSR_PR) &
                                  not srr1(MSR_LE) & not srr1(MSR_SF);
                -- Can't use msr_copy here because the partial function MSR
                -- bits should be left unchanged, not zeroed.
                v.new_msr(63 downto 61) := srr1(63 downto 61);
                v.new_msr(MSR_HV)       := '1';
                v.new_msr(59 downto 31) := srr1(59 downto 31);
                v.new_msr(26 downto 22) := srr1(26 downto 22);
                v.new_msr(15 downto 0)  := srr1(15 downto 0);
                if srr1(MSR_PR) = '1' then
                    v.new_msr(MSR_EE) := '1';
                    v.new_msr(MSR_IR) := '1';
                    v.new_msr(MSR_DR) := '1';
                end if;
                v.se.write_msr := '1';
                v.e.redirect := '1';
                v.se.set_cfar := '1';
                if HAS_FPU then
                    v.fp_intr := fp_in.exception and
                                 (srr1(MSR_FE0) or srr1(MSR_FE1));
                end if;
                v.do_trace := '0';

            when OP_COUNTB =>
                v.res2_sel := "01";
                slow_op := '1';
            when OP_MCRXRX =>
            when OP_DARN =>
	    when OP_MFMSR =>
	    when OP_MFSPR =>
                sprnum := decode_spr_num(e_in.insn);
		if e_in.spr_is_ram = '1' then
                    if e_in.valid = '1' and not is_X(e_in.insn) then
                        report "MFSPR to SPR " & integer'image(sprnum) &
                            "=" & to_hstring(alu_result);
                    end if;
		elsif e_in.spr_select.valid = '1' and e_in.spr_select.wonly = '0' then
                    if e_in.valid = '1' and not is_X(e_in.insn) then
                        report "MFSPR to slow SPR " & integer'image(sprnum);
                    end if;
                    slow_op := '1';
                    if e_in.spr_select.noop = '1' then
                        v.e.write_enable := '0';
                    end if;
                    if e_in.spr_select.ispmu = '0' then
                        case e_in.spr_select.sel is
                            when SPRSEL_LOGR =>
                                if e_in.insn(16) = '1' then
                                    v.se.inc_loga := '1';       -- reading LOG_DATA
                                end if;
                            when others =>
                        end case;
                        v.res2_sel := "10";
                    else
                        v.res2_sel := "11";
                    end if;
                else
                    -- mfspr from unimplemented SPRs should be a nop in
                    -- supervisor mode and a program or HEAI interrupt for user mode
                    -- LPCR[EVIRT] = 1 makes it HEAI in privileged mode
                    if e_in.valid = '1' and not is_X(e_in.insn) then
                        report "MFSPR to SPR " & integer'image(sprnum) & " invalid";
                    end if;
                    slow_op := '1';
                    v.e.write_enable := '0';
                    if ex1.msr(MSR_PR) = '1' or ctrl.lpcr_evirt = '1' or
                        sprnum = 0 or sprnum = 4 or sprnum = 5 or sprnum = 6 then
                        illegal := '1';
                    end if;
                end if;

            when OP_MSG =>
                -- msgsnd, msgclr
                if b_in(31 downto 27) = 5x"5" then
                    if e_in.insn(6) = '0' then  -- msgsnd
                        for cpuid in 0 to NCPUS-1 loop
                            if unsigned(b_in(19 downto 0)) = to_unsigned(cpuid, 20) then
                                v.se.send_hmsg(cpuid) := '1';
                            end if;
                        end loop;
                    else                        -- msgclr
                        v.se.clr_hmsg := '1';
                    end if;
                end if;

	    when OP_MTCRF =>
            when OP_MTMSRD =>
                v.se.write_msr := '1';
                if e_in.insn(16) = '1' then
                    -- just update EE and RI
                    v.new_msr(MSR_EE) := c_in(MSR_EE);
                    v.new_msr(MSR_RI) := c_in(MSR_RI);
                else
                    -- Architecture says to leave out bits 3 (HV), 51 (ME)
                    -- and 63 (LE) (IBM bit numbering)
                    if e_in.is_32bit = '0' then
                        v.new_msr(63 downto 61) := c_in(63 downto 61);
                        v.new_msr(59 downto 32) := c_in(59 downto 32);
                    end if;
                    v.new_msr(31 downto 13) := c_in(31 downto 13);
                    v.new_msr(11 downto 1)  := c_in(11 downto 1);
                    if c_in(MSR_PR) = '1' then
                        v.new_msr(MSR_EE) := '1';
                        v.new_msr(MSR_IR) := '1';
                        v.new_msr(MSR_DR) := '1';
                    end if;
                    if HAS_FPU then
                        v.fp_intr := fp_in.exception and
                                     (c_in(MSR_FE0) or c_in(MSR_FE1));
                    end if;
                end if;
	    when OP_MTSPR =>
                sprnum := decode_spr_num(e_in.insn);
                if e_in.valid = '1' and not is_X(e_in.insn) then
                    report "MTSPR to SPR " & integer'image(sprnum) &
                        "=" & to_hstring(c_in);
                end if;
                v.se.write_pmuspr := e_in.spr_select.ispmu;
                if e_in.spr_select.valid = '1' and e_in.spr_select.ispmu = '0' then
                    case e_in.spr_select.sel is
                        when SPRSEL_XER =>
                            v.e.xerc.so := c_in(63-32);
                            v.e.xerc.ov := c_in(63-33);
                            v.e.xerc.ca := c_in(63-34);
                            v.e.xerc.ov32 := c_in(63-44);
                            v.e.xerc.ca32 := c_in(63-45);
                            v.se.write_xerlow := '1';
                        when SPRSEL_DEC =>
                            v.se.write_dec := '1';
                        when SPRSEL_LOGR =>
                            -- must be writing LOG_ADDR; LOG_DATA is readonly
                            v.se.write_loga := '1';
                        when SPRSEL_CFAR =>
                            v.se.write_cfar := '1';
                        when SPRSEL_FSCR =>
                            v.se.write_fscr := '1';
                        when SPRSEL_LPCR =>
                            v.se.write_lpcr := '1';
                        when SPRSEL_HEIR =>
                            v.se.write_heir := '1';
                        when SPRSEL_CTRL =>
                            v.se.write_ctrl := '1';
                        when SPRSEL_DSCR =>
                            v.se.write_dscr := '1';
                        when SPRSEL_CIABR =>
                            v.se.write_ciabr := '1';
                        when SPRSEL_TB =>
                            v.se.write_tbl := '1';
                        when SPRSEL_TBU =>
                            v.se.write_tbu := '1';
                        when others =>
                    end case;
                end if;
		if e_in.spr_select.valid = '0' and e_in.spr_is_ram = '0' then
                    -- mtspr to unimplemented SPRs should be a nop in
                    -- supervisor mode and a program interrupt or HEAI for user mode
                    -- LPCR[EVIRT] = 1 makes it HEAI in privileged mode
                    if ex1.msr(MSR_PR) = '1' or ctrl.lpcr_evirt = '1' or
                        sprnum = 0 or sprnum = 4 or sprnum = 5 or sprnum = 6 then
                        illegal := '1';
                    end if;
		end if;

	    when OP_ISYNC =>
		v.e.redirect := '1';
                v.redir_to_next := '1';

	    when OP_ICBI =>
		v.se.icache_inval := '1';

            when OP_BSORT =>
                v.start_bsort := '1';
                slow_op := '1';
                owait := '1';

            when OP_BPERM =>
                v.start_bperm := '1';
                slow_op := '1';
                owait := '1';

	    when OP_MUL_L64 =>
                if e_in.is_32bit = '1' then
                    v.se.mult_32s := '1';
                    v.res2_sel := "00";
                else
                    -- Use standard multiplier
                    v.start_mul := '1';
                    owait := '1';
                end if;
                slow_op := '1';

	    when OP_MUL_H64 =>
                v.start_mul := '1';
                slow_op := '1';
                owait := '1';

            when OP_MUL_H32 =>
                v.se.mult_32s := '1';
                v.res2_sel := "01";
                slow_op := '1';

	    when OP_DIV | OP_DIVE | OP_MOD =>
                if not HAS_FPU then
                    v.start_div := '1';
                    slow_op := '1';
                    owait := '1';
                end if;

            when OP_WAIT =>
                if e_in.insn(22 downto 21) = "00" then
                    v.se.enter_wait := '1';
                end if;

            when OP_FETCH_FAILED =>
                -- Handling an ITLB miss doesn't count as having executed an instruction
                v.do_trace := '0';

            when others =>
                if e_in.valid = '1' and e_in.unit = ALU then
                    report "unhandled insn_type " & insn_type_t'image(e_in.insn_type);
                end if;
        end case;

        if ex1.msr(MSR_PR) = '1' and e_in.prefixed = '1' and
            ctrl.fscr_pref = '0' then
            -- Facility unavailable for prefixed instructions,
            -- which has higher priority than the alignment interrupt for
            -- misaligned prefixed instructions, which has higher priority than
            -- other facility unavailable interrupts.
            v.exception := '1';
            v.ic := std_ulogic_vector(to_unsigned(FSCR_PREFIX, 4));
            v.e.intr_vec := 16#f60#;
            v.se.write_ic := '1';

        elsif misaligned = '1' then
            -- generate an alignment interrupt
            -- This is higher priority than illegal because a misaligned
            -- prefix will come down as an OP_ILLEGAL instruction.
            v.exception := '1';
            v.e.intr_vec := 16#600#;
            v.e.srr1(47 - 35) := '1';
            v.e.srr1(47 - 34) := '1';
            if e_in.valid = '1' then
                report "misaligned prefixed instruction interrupt";
            end if;

        elsif privileged = '1' then
            -- generate a program interrupt
            v.exception := '1';
            v.e.srr1(47 - 34) := e_in.prefixed;
            -- set bit 45 to indicate privileged instruction type interrupt
            v.e.srr1(47 - 45) := '1';
            if e_in.valid = '1' then
                report "privileged instruction";
            end if;

        elsif illegal = '1' then
            -- generate hypervisor emulation assistance interrupt (HEAI)
            -- and write the offending instruction into HEIR
            v.exception := '1';
            v.e.srr1(47 - 34) := e_in.prefixed;
            v.e.intr_vec := 16#e40#;
            v.e.hv_intr := '1';
            v.se.set_heir := '1';
            if e_in.valid = '1' then
                report "illegal instruction";
            end if;

        elsif ex1.msr(MSR_PR) = '1' and v.se.scv_trap = '1' and
            ctrl.fscr_scv = '0' then
            -- Facility unavailable for scv instruction
            v.exception := '1';
            v.ic := std_ulogic_vector(to_unsigned(FSCR_SCV, 4));
            v.e.intr_vec := 16#f60#;
            v.se.write_ic := '1';

        elsif ex1.msr(MSR_PR) = '1' and e_in.uses_tar = '1' and
            ctrl.fscr_tar = '0' then
            -- Facility unavailable for TAR access
            v.exception := '1';
            v.ic := std_ulogic_vector(to_unsigned(FSCR_TAR, 4));
            v.e.intr_vec := 16#f60#;
            v.se.write_ic := '1';

        elsif ex1.msr(MSR_PR) = '1' and e_in.uses_dscr = '1' and
            ctrl.fscr_dscr = '0' then
            -- Facility unavailable for DSCR access
            v.exception := '1';
            v.ic := std_ulogic_vector(to_unsigned(FSCR_DSCR, 4));
            v.e.intr_vec := 16#f60#;
            v.se.write_ic := '1';

        elsif HAS_FPU and ex1.msr(MSR_FP) = '0' and e_in.fac = FPU then
            -- generate a floating-point unavailable interrupt
            v.exception := '1';
            v.e.srr1(47 - 34) := e_in.prefixed;
            v.e.intr_vec := 16#800#;
            if e_in.valid = '1' then
                report "FP unavailable interrupt";
            end if;
        end if;

        if e_in.unit = ALU then
            v.complete := e_in.valid and not v.exception and not owait;
            v.bypass_valid := e_in.valid and not slow_op;
        end if;

        actions <= v;
    end process;

    -- First execute stage
    execute1_1: process(all)
	variable v : reg_stage1_type;
	variable overflow : std_ulogic;
        variable lv : Execute1ToLoadstore1Type;
	variable irq_valid : std_ulogic;
	variable exception : std_ulogic;
        variable fv : Execute1ToFPUType;
        variable go : std_ulogic;
        variable bypass_valid : std_ulogic;
        variable is_scv : std_ulogic;
        variable dex : aspect_bits_t;
    begin
	v := ex1;
        if busy_out = '0' then
            v.e := actions.e;
            v.e.valid := '0';
            v.oe := e_in.oe;
            v.spr_select := e_in.spr_select;
            v.pmu_spr_num := e_in.insn(20 downto 16);
            v.mul_select := e_in.sub_select;
            v.se := side_effect_init;
            v.ramspr_wraddr := e_in.ramspr_wraddr;
            v.lr_from_next := e_in.lr;
            v.spr_write_data := actions.spr_write_data;
            v.ic := actions.ic;
            v.prefixed := e_in.prefixed;
            v.insn := e_in.insn;
            v.prefix := e_in.prefix;
            v.advance_nia := '0';
        end if;

        lv := Execute1ToLoadstore1Init;
        fv := Execute1ToFPUInit;

        x_to_multiply.valid <= '0';
        x_to_mult_32s.valid <= '0';
        x_to_divider.valid <= '0';
        v.ext_interrupt := '0';
        v.taken_branch_event := '0';
        v.br_mispredict := '0';
        v.busy := '0';
        bypass_valid := actions.bypass_valid;

        irq_valid := ex1.msr(MSR_EE) and
                     (pmu_to_x.intr or dec_sign or dhd_pending or
                      (ext_irq_in and (not ctrl.lpcr_heic or ex1.msr(MSR_PR))));

        if valid_in = '1' then
            v.prev_op := e_in.insn_type;
            v.prev_prefixed := e_in.prefixed;
            v.se.set_heir := actions.se.set_heir;
            v.se.write_ic := actions.se.write_ic;
        end if;

        -- Determine if there is any interrupt to be taken
        -- before/instead of executing this instruction
        exception := valid_in and actions.exception;
        if valid_in = '1' and e_in.second = '0' then
            if HAS_FPU and ex1.fp_exception_next = '1' then
                -- This is used for FP-type program interrupts that
                -- become pending due to MSR[FE0,FE1] changing from 00 to non-zero.
                exception := '1';
                v.e.intr_vec := 16#700#;
                v.e.srr1 := (others => '0');
                v.e.srr1(47 - 43) := '1';
                v.e.srr1(47 - 47) := '1';
            elsif ex1.trace_next = '1' then
                -- Generate a trace interrupt rather than executing the next instruction
                -- or taking any asynchronous interrupt
                exception := '1';
                v.e.intr_vec := 16#d00#;
                v.e.srr1 := (others => '0');
                v.e.srr1(47 - 33) := '1';
                v.e.srr1(47 - 34) := ex1.prev_prefixed;
                if (ex1.prev_op = OP_LOAD or ex1.prev_op = OP_ICBI or ex1.prev_op = OP_ICBT or
                    ex1.prev_op = OP_DCBF) and ex1.trace_ciabr = '0' then
                    v.e.srr1(47 - 35) := '1';
                elsif (ex1.prev_op = OP_STORE or ex1.prev_op = OP_DCBZ) and
                    ex1.trace_ciabr = '0' then
                    v.e.srr1(47 - 36) := '1';
                end if;
                v.e.srr1(47 - 43) := ex1.trace_ciabr;

            elsif irq_valid = '1' then
                -- Don't deliver the interrupt until we have a valid instruction
                -- coming in, so we have a valid NIA to put in SRR0.
                if pmu_to_x.intr = '1' then
                    v.e.intr_vec := 16#f00#;
                    report "IRQ valid: PMU";
                elsif dhd_pending = '1' then
                    v.e.intr_vec := 16#e80#;
                    v.e.hv_intr := '1';
                    v.se.clr_hmsg := '1';
                    report "Hypervisor doorbell";
                elsif dec_sign = '1' then
                    v.e.intr_vec := 16#900#;
                    report "IRQ valid: DEC";
                elsif ext_irq_in = '1' then
                    v.e.intr_vec := 16#500#;
                    report "IRQ valid: External";
                    v.ext_interrupt := '1';
                    v.e.hv_intr := not ctrl.lpcr_lpes;
                end if;
                v.e.srr1 := (others => '0');
                exception := '1';

            end if;
        end if;

        v.no_instr_avail := not (e_in.valid or l_in.busy or ex1.busy or fp_in.busy);

        go := valid_in and not exception;
        v.instr_dispatch := go;

	if go = '1' then
            v.se := actions.se;
            v.e.valid := actions.complete;
            v.taken_branch_event := actions.take_branch;
            v.trace_next := actions.do_trace or actions.ciabr_trace;
            v.trace_ciabr := actions.ciabr_trace;
            v.fp_exception_next := actions.fp_intr;
            v.res2_sel := actions.res2_sel;
            v.msr := actions.new_msr;
            x_to_multiply.valid <= actions.start_mul;
            x_to_mult_32s.valid <= actions.se.mult_32s;
            v.mul_in_progress := actions.start_mul;
            x_to_divider.valid <= actions.start_div;
            v.div_in_progress := actions.start_div;
            v.bsort_in_progress := actions.start_bsort;
            v.bperm_in_progress := actions.start_bperm;
            v.br_mispredict := v.e.redirect and actions.direct_branch;
            v.advance_nia := actions.advance_nia;
            v.redir_to_next := actions.redir_to_next;
            exception := actions.trap;

            -- Go busy while division is happening because the
            -- divider is not pipelined.  Also go busy while a
            -- multiply is happening in order to stop following
            -- instructions from using the wrong XER value
            -- (and for simplicity in the OE=0 case).
            v.busy := actions.start_div or actions.start_mul or
                      actions.start_bsort or actions.start_bperm;

            -- instruction for other units, i.e. LDST
            if e_in.unit = LDST then
                lv.valid := '1';
            end if;
            if HAS_FPU and e_in.unit = FPU then
                fv.valid := '1';
            end if;
        end if;
        is_scv := go and actions.se.scv_trap;
        bsort_start <= go and actions.start_bsort;
        bperm_start <= go and actions.start_bperm;
        pmu_trace <= go and actions.do_trace;

        -- evaluate DEXCR/HDEXCR bits that apply at present
        if ex1.msr(MSR_PR) = '0' then
            dex := ctrl.hdexcr_hyp;
        else
            dex := ctrl.dexcr_pro or ctrl.hdexcr_enf;
        end if;

        if not HAS_FPU and ex1.div_in_progress = '1' then
            v.div_in_progress := not divider_to_x.valid;
            v.busy := not divider_to_x.valid;
            if divider_to_x.valid = '1' and ex1.oe = '1' then
                v.e.xerc.ov := divider_to_x.overflow;
                v.e.xerc.ov32 := divider_to_x.overflow;
                if divider_to_x.overflow = '1' then
                    v.e.xerc.so := '1';
                end if;
            end if;
            v.e.valid := divider_to_x.valid;
            v.e.write_data := alu_result;
            bypass_valid := v.e.valid;
        end if;
        if ex1.mul_in_progress = '1' then
            v.mul_in_progress := not multiply_to_x.valid;
            v.mul_finish := multiply_to_x.valid and ex1.oe;
            v.e.valid := multiply_to_x.valid and not ex1.oe;
            v.busy := not v.e.valid;
            v.e.write_data := alu_result;
            bypass_valid := v.e.valid;
        end if;
        if ex1.mul_finish = '1' then
            v.mul_finish := '0';
            v.e.xerc.ov := multiply_to_x.overflow;
            v.e.xerc.ov32 := multiply_to_x.overflow;
            if multiply_to_x.overflow = '1' then
                v.e.xerc.so := '1';
            end if;
            v.e.valid := '1';
        end if;
        if ex1.bsort_in_progress = '1' then
            v.bsort_in_progress := not bsort_done;
            v.e.valid := bsort_done;
            v.busy := not bsort_done;
            v.e.write_data := alu_result;
            bypass_valid := bsort_done;
        end if;
        if ex1.bperm_in_progress = '1' then
            v.bperm_in_progress := not bperm_done;
            v.e.valid := bperm_done;
            v.busy := not bperm_done;
            v.e.write_data := alu_result;
            bypass_valid := bperm_done;
        end if;

        if v.e.write_xerc_enable = '1' and v.e.valid = '1' then
            v.xerc := v.e.xerc;
            v.xerc_valid := '1';
        end if;

        if (ex1.busy or l_in.busy or fp_in.busy) = '0' then
            v.e.interrupt := exception;
            v.e.is_scv := is_scv;
        end if;
        if v.e.valid = '0' then
            v.e.redirect := '0';
            v.e.br_last := '0';
        end if;
        if flush_in = '1' then
            v.e.valid := '0';
            v.e.interrupt := '0';
            v.e.redirect := '0';
            v.e.br_last := '0';
            v.busy := '0';
            v.div_in_progress := '0';
            v.mul_in_progress := '0';
            v.mul_finish := '0';
            v.xerc_valid := '0';
        end if;
        if flush_in = '1' or interrupt_in.intr = '1' then
            v.msr := ctrl_tmp.msr;
        end if;
        if interrupt_in.intr = '1' then
            v.trace_next := '0';
            v.fp_exception_next := '0';
        end if;

        bypass_data.tag.valid <= v.e.write_enable and bypass_valid;
        bypass_data.tag.tag <= v.e.instr_tag.tag;
        bypass_data.reg <= v.e.write_reg;
        bypass_data.data <= alu_result;

        bypass_cr_data.tag.valid <= e_in.output_cr and bypass_valid;
        bypass_cr_data.tag.tag <= e_in.instr_tag.tag;
        bypass_cr_data.data <= write_cr_data;

        -- Outputs to loadstore1 (async)
        lv.op := e_in.insn_type;
        lv.instr_tag := e_in.instr_tag;
        lv.addr1 := a_in;
        lv.addr2 := b_in;
        lv.data := c_in;
        lv.write_reg := e_in.write_reg;
        lv.length := e_in.data_len;
        lv.byte_reverse := e_in.byte_reverse xnor ex1.msr(MSR_LE);
        lv.sign_extend := e_in.sign_extend;
        lv.update := e_in.update;
        -- abuse e_in.is_signed to indicate hash store/check instructions
        lv.hash := e_in.is_signed;
        lv.xerc := xerc_in;
        lv.reserve := e_in.reserve;
        lv.rc := e_in.rc;
        lv.insn := e_in.insn;
        -- invert_a field is overloaded for load/store instructions
        -- to mark l*cix and st*cix
        lv.ci := e_in.invert_a;
        lv.virt_mode := ex1.msr(MSR_DR);
        lv.priv_mode := not ex1.msr(MSR_PR);
        lv.mode_32bit := not ex1.msr(MSR_SF);
        lv.is_32bit := e_in.is_32bit;
        lv.prefixed := e_in.prefixed;
        lv.repeat := e_in.repeat;
        lv.second := e_in.second;
        lv.e2stall := fp_in.f2stall;
        lv.hashkey := ramspr_odd;
        if e_in.insn(7) = '0' then
            lv.hash_enable := dex(DEXCR_PHIE);
        else
            lv.hash_enable := dex(DEXCR_NPHIE);
        end if;

        -- Outputs to FPU
        fv.op := e_in.insn_type;
        fv.insn := e_in.insn;
        fv.itag := e_in.instr_tag;
        fv.single := e_in.is_32bit;
        fv.is_signed := e_in.is_signed;
        fv.fe_mode := ex1.msr(MSR_FE0) & ex1.msr(MSR_FE1);
        fv.fra := a_in;
        fv.frb := b_in;
        fv.frc := c_in;
        fv.valid_a := e_in.reg_valid1;
        fv.valid_b := e_in.reg_valid2;
        fv.valid_c := e_in.reg_valid3;
        fv.frt := e_in.write_reg;
        fv.rc := e_in.rc;
        fv.out_cr := e_in.output_cr;
        fv.m32b := not ex1.msr(MSR_SF);
        fv.oe := e_in.oe;
        fv.xerc := xerc_in;
        fv.stall := l_in.l2stall;

	-- Update registers
	ex1in <= v;

	-- update outputs
        l_out <= lv;
        fp_out <= fv;
        irq_valid_log <= irq_valid;
    end process;

    -- Slow SPR read mux
    log_spr_data <= (log_wr_addr & ex2.log_addr_spr) when ex1.insn(16) = '0'
         else log_rd_data;
    with ex1.spr_select.sel select spr_result <=
        timebase when SPRSEL_TB,
        32x"0" & timebase(63 downto 32) when SPRSEL_TBU,
        assemble_dec(ctrl) when SPRSEL_DEC,
        32x"0" & PVR_MICROWATT when SPRSEL_PVR,
        log_spr_data when SPRSEL_LOGR,
        ctrl.cfar when SPRSEL_CFAR,
        assemble_fscr(ctrl) when SPRSEL_FSCR,
        assemble_lpcr(ctrl) when SPRSEL_LPCR,
        ctrl.heir when SPRSEL_HEIR,
        assemble_ctrl(ctrl, ex1.msr(MSR_PR)) when SPRSEL_CTRL,
        39x"0" & ctrl.dscr when SPRSEL_DSCR,
        56x"0" & std_ulogic_vector(to_unsigned(CPU_INDEX, 8)) when SPRSEL_PIR,
        ctrl.ciabr when SPRSEL_CIABR,
        assemble_dexcr(ctrl, ex1.insn) when SPRSEL_DEXCR,
        assemble_xer(ex1.e.xerc, ctrl.xer_low) when SPRSEL_XER,
        64x"0" when others;

    stage2_stall <= l_in.l2stall or fp_in.f2stall;

    -- Second execute stage control
    execute2_1: process(all)
	variable v : reg_stage2_type;
        variable bypass_valid : std_ulogic;
        variable rcresult : std_ulogic_vector(63 downto 0);
        variable sprres : std_ulogic_vector(63 downto 0);
        variable ex_result : std_ulogic_vector(63 downto 0);
        variable cr_res : std_ulogic_vector(31 downto 0);
        variable cr_mask : std_ulogic_vector(7 downto 0);
        variable sign, zero : std_ulogic;
        variable rcnz_hi, rcnz_lo : std_ulogic;
        variable irq_exc : std_ulogic;
    begin
	-- Next insn adder used in a couple of places
	next_nia <= std_ulogic_vector(unsigned(ex1.e.last_nia) + 4);

	v.log_addr_spr := ex2.log_addr_spr;

        v.e := ex1.e;
        v.se := ex1.se;
        v.ext_interrupt := ex1.ext_interrupt and not stage2_stall;
        v.taken_branch_event := ex1.taken_branch_event and not stage2_stall;
        v.br_mispredict := ex1.br_mispredict and not stage2_stall;
        if stage2_stall = '1' then
            v.e.last_nia := ex2.e.last_nia;
        elsif ex1.advance_nia = '1' then
            v.e.last_nia := next_nia;
        end if;
        if stage2_stall = '1' then
            v.e.valid := '0';
            v.e.interrupt := '0';
            v.se := side_effect_init;
        end if;

        if ex1.se.mult_32s = '1' and ex1.oe = '1' then
            v.e.xerc.ov := mult_32s_to_x.overflow;
            v.e.xerc.ov32 := mult_32s_to_x.overflow;
            if mult_32s_to_x.overflow = '1' then
                v.e.xerc.so := '1';
            end if;
        end if;

	ctrl_tmp <= ctrl;
	ctrl_tmp.dec <= std_ulogic_vector(unsigned(ctrl.dec) - 1);

        x_to_pmu.mfspr <= '0';
        x_to_pmu.mtspr <= '0';
        x_to_pmu.tbbits(3) <= timebase(63 - 47);
        x_to_pmu.tbbits(2) <= timebase(63 - 51);
        x_to_pmu.tbbits(1) <= timebase(63 - 55);
        x_to_pmu.tbbits(0) <= timebase(63 - 63);
        x_to_pmu.pmm_msr <= ctrl.msr(MSR_PMM);
        x_to_pmu.pr_msr <= ctrl.msr(MSR_PR);

        if v.e.valid = '0' or flush_in = '1' then
            v.e.write_enable := '0';
            v.e.write_cr_enable := '0';
            v.e.write_xerc_enable := '0';
            v.e.redirect := '0';
            v.e.br_last := '0';
            v.taken_branch_event := '0';
            v.br_mispredict := '0';
        end if;
        if flush_in = '1' then
            v.e.valid := '0';
            v.e.interrupt := '0';
            v.se := side_effect_init;
            v.ext_interrupt := '0';
        end if;

        -- This is split like this because mfspr doesn't have an Rc bit,
        -- and we don't want the zero-detect logic to be after the
        -- SPR mux for timing reasons.
        if ex1.se.mult_32s = '1' then
            if ex1.res2_sel(0) = '0' then
                rcresult := mult_32s_to_x.result(63 downto 0);
            else
                rcresult := mult_32s_to_x.result(63 downto 32) &
                            mult_32s_to_x.result(63 downto 32);
            end if;
        elsif ex1.res2_sel(0) = '0' then
            rcresult := ex1.e.write_data;
        else
            rcresult := countbits_result;
        end if;
        if ex1.res2_sel(0) = '0' then
            sprres := spr_result;
        else
            sprres := pmu_to_x.spr_val;
        end if;
        if ex1.res2_sel(1) = '1' then
            ex_result := sprres;
        elsif ex1.redir_to_next = '1' then
            ex_result := next_nia;
        else
            ex_result := rcresult;
        end if;

        cr_res := ex1.e.write_cr_data;
        cr_mask := ex1.e.write_cr_mask;
        if ex1.e.rc = '1' and ex1.e.write_enable = '1' then
            rcnz_lo := or (rcresult(31 downto 0));
            if ex1.e.mode_32bit = '0' then
                rcnz_hi := or (rcresult(63 downto 32));
                zero := not (rcnz_hi or rcnz_lo);
                sign := ex_result(63);
            else
                zero := not rcnz_lo;
                sign := ex_result(31);
            end if;
            cr_res(31) := sign;
            cr_res(30) := not (sign or zero);
            cr_res(29) := zero;
            cr_res(28) := v.e.xerc.so;
            cr_mask(7) := '1';
        end if;

        v.e.write_data := ex_result;
        v.e.write_cr_data := cr_res;
        v.e.write_cr_mask := cr_mask;

	if stage2_stall = '0' then
            if ex1.se.write_msr = '1' then
                ctrl_tmp.msr <= ex1.msr;
            end if;
            if ex1.se.write_xerlow = '1' then
                ctrl_tmp.xer_low <= ex1.spr_write_data(17 downto 0);
            end if;
            if ex1.se.write_dec = '1' then
                ctrl_tmp.dec <= ex1.spr_write_data;
            end if;
            if ex1.se.write_cfar = '1' then
                ctrl_tmp.cfar <= ex1.spr_write_data;
            elsif ex1.se.set_cfar = '1' then
                ctrl_tmp.cfar <= ex1.e.last_nia;
            end if;
            if ex1.se.write_loga = '1' then
                v.log_addr_spr := ex1.spr_write_data(31 downto 0);
            elsif ex1.se.inc_loga = '1' then
                v.log_addr_spr := std_ulogic_vector(unsigned(ex2.log_addr_spr) + 1);
            end if;
            x_to_pmu.mtspr <= ex1.se.write_pmuspr;
            if ex1.se.write_fscr = '1' then
                ctrl_tmp.fscr_ic <= ex1.spr_write_data(59 downto 56);
                ctrl_tmp.fscr_pref <= ex1.spr_write_data(FSCR_PREFIX);
                ctrl_tmp.fscr_scv <= ex1.spr_write_data(FSCR_SCV);
                ctrl_tmp.fscr_tar <= ex1.spr_write_data(FSCR_TAR);
                ctrl_tmp.fscr_dscr <= ex1.spr_write_data(FSCR_DSCR);
            elsif ex1.se.write_ic = '1' then
                ctrl_tmp.fscr_ic <= ex1.ic;
            end if;
            if ex1.se.write_lpcr = '1' then
                ctrl_tmp.lpcr_hail <= ex1.spr_write_data(LPCR_HAIL);
                ctrl_tmp.lpcr_evirt <= ex1.spr_write_data(LPCR_EVIRT);
                ctrl_tmp.lpcr_ld <= ex1.spr_write_data(LPCR_LD);
                ctrl_tmp.lpcr_heic <= ex1.spr_write_data(LPCR_HEIC);
                ctrl_tmp.lpcr_lpes <= ex1.spr_write_data(LPCR_LPES);
                ctrl_tmp.lpcr_hvice <= ex1.spr_write_data(LPCR_HVICE);
            end if;
            if ex1.se.write_heir = '1' then
                ctrl_tmp.heir <= ex1.spr_write_data;
            elsif ex1.se.set_heir = '1' then
                ctrl_tmp.heir(31 downto 0) <= ex1.insn;
                if ex1.prefixed = '1' then
                    ctrl_tmp.heir(63 downto 58) <= 6x"01";
                    ctrl_tmp.heir(57 downto 32) <= ex1.prefix;
                else
                    ctrl_tmp.heir(63 downto 32) <= (others => '0');
                end if;
            end if;
            if ex1.se.write_ctrl = '1' then
                ctrl_tmp.run <= ex1.spr_write_data(0);
            end if;
            if ex1.se.write_dscr = '1' then
                ctrl_tmp.dscr <= ex1.spr_write_data(24 downto 0);
            end if;
            if ex1.se.write_ciabr = '1' then
                ctrl_tmp.ciabr <= ex1.spr_write_data;
            end if;
            if ex1.se.enter_wait = '1' then
                ctrl_tmp.wait_state <= '1';
            end if;
        end if;

        -- pending exceptions clear any wait state
        -- ex1.fp_exception_next is not tested because it is not possible to
        -- get into wait state with a pending FP exception.
        irq_exc := pmu_to_x.intr or dec_sign or ext_irq_in or dhd_pending;
        if ex1.trace_next = '1' or irq_exc = '1' or interrupt_in.intr = '1' then
            ctrl_tmp.wait_state <= '0';
        end if;

 	if interrupt_in.intr = '1' then
            ctrl_tmp.msr(MSR_SF) <= '1';
            ctrl_tmp.msr(MSR_PR) <= '0';
            ctrl_tmp.msr(MSR_SE) <= '0';
            ctrl_tmp.msr(MSR_BE) <= '0';
            ctrl_tmp.msr(MSR_FP) <= '0';
            ctrl_tmp.msr(MSR_FE0) <= '0';
            ctrl_tmp.msr(MSR_FE1) <= '0';
            ctrl_tmp.msr(MSR_IR) <= interrupt_in.alt_int;
            ctrl_tmp.msr(MSR_DR) <= interrupt_in.alt_int;
            ctrl_tmp.msr(MSR_LE) <= '1';
            if interrupt_in.scv_int = '0' then
                ctrl_tmp.msr(MSR_EE) <= '0';
            end if;
            if interrupt_in.scv_int = '0' and interrupt_in.hv_intr = '0' then
                ctrl_tmp.msr(MSR_RI) <= '0';
            end if;
        end if;

        -- Don't bypass the result from mfspr to slow SPRs or PMU SPRs,
        -- because we don't want to send the value while stalled because it
        -- might change, and we don't want bypass_valid to depend on
        -- stage2_stall for timing reasons.
        bypass_valid := ex1.e.valid and not ex1.res2_sel(1);

        bypass2_data.tag.valid <= ex1.e.write_enable and bypass_valid;
        bypass2_data.tag.tag <= ex1.e.instr_tag.tag;
        bypass2_data.reg <= ex1.e.write_reg;
        bypass2_data.data <= ex_result;

        bypass2_cr_data.tag.valid <= (ex1.e.write_cr_enable or (ex1.e.rc and ex1.e.write_enable))
                                     and bypass_valid;
        bypass2_cr_data.tag.tag <= ex1.e.instr_tag.tag;
        bypass2_cr_data.data <= cr_res;

	-- Update registers
	ex2in <= v;

	-- update outputs
	e_out <= ex2.e;

        run_out <= ctrl.run;
        terminate_out <= ex2.se.terminate;
        icache_inval <= ex2.se.icache_inval;

        msg_out <= ex2.se.send_hmsg;

        exception_log <= v.e.interrupt;
    end process;

    sim_dump_test: if SIM generate
        dump_exregs: process(all)
            variable xer : std_ulogic_vector(63 downto 0);
        begin
            if sim_dump = '1' then
                report "LR " & to_hstring(even_sprs(to_integer(RAMSPR_LR)));
                report "CTR " & to_hstring(odd_sprs(to_integer(RAMSPR_CTR)));
                sim_dump_done <= '1';
            else
                sim_dump_done <= '0';
            end if;
        end process;
    end generate;

    -- Keep GHDL synthesis happy
    sim_dump_test_synth: if not SIM generate
        sim_dump_done <= '0';
    end generate;

    e1_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(11 downto 0);
    begin
        ex1_log : process(clk)
        begin
            if rising_edge(clk) then
                log_data <= ctrl.msr(MSR_EE) & ctrl.msr(MSR_PR) &
                            ctrl.msr(MSR_IR) & ctrl.msr(MSR_DR) &
                            exception_log &
                            irq_valid_log &
                            interrupt_in.intr &
                            ex2.e.write_enable &
                            ex2.e.valid &
                            (ex2.e.redirect or ex2.e.interrupt) &
                            ex1.busy &
                            flush_in;
            end if;
        end process;
        log_out <= log_data;
    end generate;
end architecture behaviour;
