library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.insn_helpers.all;

entity decode2 is
    generic (
        EX1_BYPASS : boolean := true;
        HAS_FPU : boolean := true;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
    port (
        clk   : in std_ulogic;
        rst   : in std_ulogic;

        complete_in : in instr_tag_t;
        busy_in   : in std_ulogic;
        stall_out : out std_ulogic;

        stopped_out : out std_ulogic;

        flush_in: in std_ulogic;

        tb_ctrl : timebase_ctrl;

        d_in  : in Decode1ToDecode2Type;

        e_out : out Decode2ToExecute1Type;

        r_in  : in RegisterFileToDecode2Type;
        r_out : out Decode2ToRegisterFileType;

        c_in  : in CrFileToDecode2Type;
        c_out : out Decode2ToCrFileType;

        execute_bypass    : in bypass_data_t;
        execute_cr_bypass : in cr_bypass_data_t;
        execute2_bypass    : in bypass_data_t;
        execute2_cr_bypass : in cr_bypass_data_t;
        writeback_bypass  : in bypass_data_t;

        -- Access to SPRs from core_debug module
        dbg_spr_req  : in std_ulogic;
        dbg_spr_addr : in std_ulogic_vector(7 downto 0);

        log_out : out std_ulogic_vector(9 downto 0)
	);
end entity decode2;

architecture behaviour of decode2 is
    type reg_type is record
        e : Decode2ToExecute1Type;
        repeat : repeat_t;
        busy : std_ulogic;
        sgl_pipe : std_ulogic;
        prev_sgl : std_ulogic;
        input_ov  : std_ulogic;
        output_ov : std_ulogic;
        read_rspr : std_ulogic;
    end record;
    constant reg_type_init : reg_type :=
        (e => Decode2ToExecute1Init, repeat => NONE, others => '0');

    signal dc2, dc2in : reg_type;

    signal deferred : std_ulogic;

    type decode_input_reg_t is record
        reg_valid : std_ulogic;
        reg       : gspr_index_t;
    end record;
    constant decode_input_reg_init : decode_input_reg_t := ('0', (others => '0'));

    type decode_output_reg_t is record
        reg_valid : std_ulogic;
        reg       : gspr_index_t;
    end record;
    constant decode_output_reg_init : decode_output_reg_t := ('0', (others => '0'));

    function decode_input_reg_a (t : input_reg_a_t; insn_in : std_ulogic_vector(31 downto 0);
                                 prefix : std_ulogic_vector(25 downto 0))
        return std_ulogic is
    begin
        if t = RA or ((t = RA_OR_ZERO or t = RA0_OR_CIA) and insn_ra(insn_in) /= "00000") then
            return '1';
        elsif t = CIA or (t = RA0_OR_CIA and insn_prefix_r(prefix) = '1') then
            return '0';
        elsif t = FRA then
            return '1';
        else
            return '0';
        end if;
    end;

    function decode_a_const (t : input_reg_a_t; prefix : std_ulogic_vector(25 downto 0); ia : std_ulogic_vector(63 downto 0))
        return std_ulogic_vector is
    begin
        if t = CIA or (t = RA0_OR_CIA and insn_prefix_r(prefix) = '1') then
            return ia;
        else
            return 64x"0";
        end if;
    end;

    function decode_b_const (t : const_sel_t; insn_in : std_ulogic_vector(31 downto 0);
                           prefix : std_ulogic_vector(25 downto 0))
        return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0);
    begin
        case t is
            when CONST_UI =>
                ret := std_ulogic_vector(resize(unsigned(insn_ui(insn_in)), 64));
            when CONST_SI =>
                ret := std_ulogic_vector(resize(signed(insn_si(insn_in)), 64));
            when CONST_PSI =>
                ret := std_ulogic_vector(resize(signed(insn_prefixed_si(prefix, insn_in)), 64));
            when CONST_SI_HI =>
                ret := std_ulogic_vector(resize(signed(insn_si(insn_in)) & x"0000", 64));
            when CONST_UI_HI =>
                ret := std_ulogic_vector(resize(unsigned(insn_si(insn_in)) & x"0000", 64));
            when CONST_LI =>
                ret := std_ulogic_vector(resize(signed(insn_li(insn_in)) & "00", 64));
            when CONST_BD =>
                ret := std_ulogic_vector(resize(signed(insn_bd(insn_in)) & "00", 64));
            when CONST_DS =>
                ret := std_ulogic_vector(resize(signed(insn_ds(insn_in)) & "00", 64));
            when CONST_DQ =>
                ret := std_ulogic_vector(resize(signed(insn_dq(insn_in)) & "0000", 64));
            when CONST_DXHI4 =>
                ret := std_ulogic_vector(resize(signed(insn_dx(insn_in)) & x"0004", 64));
            when CONST_M1 =>
                ret := x"FFFFFFFFFFFFFFFF";
            when CONST_SH =>
                ret := x"00000000000000" & "00" & insn_in(1) & insn_in(15 downto 11);
            when CONST_SH32 =>
                ret := x"00000000000000" & "000" & insn_in(15 downto 11);
            when others =>
                ret := (others => '0');
        end case;

        return ret;
    end;

    function decode_input_reg_b (t : input_reg_b_t)
        return std_ulogic is
    begin
        case t is
            when RB | FRB =>
                return '1';
            when IMM =>
                return '0';
        end case;
    end;

    function decode_input_reg_c (t : input_reg_c_t)
        return std_ulogic is
    begin
        case t is
            when RS | RCR | FRS | FRC =>
                return '1';
            when NONE =>
                return '0';
        end case;
    end;

    function decode_output_reg (t : output_reg_a_t; insn_in : std_ulogic_vector(31 downto 0))
        return decode_output_reg_t is
    begin
        case t is
            when RT =>
                return ('1', gpr_to_gspr(insn_rt(insn_in)));
            when RA =>
                return ('1', gpr_to_gspr(insn_ra(insn_in)));
            when FRT =>
                if HAS_FPU then
                    return ('1', fpr_to_gspr(insn_frt(insn_in)));
                else
                    return ('0', "000000");
                end if;
            when NONE =>
                return ('0', "000000");
        end case;
    end;

    function decode_rc (t : rc_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic is
    begin
        case t is
            when RC | RCOE =>
                return insn_rc(insn_in);
            when ONE =>
                return '1';
            when NONE =>
                return '0';
        end case;
    end;

    function andor (mask_a : std_ulogic; val_a : std_ulogic_vector(63 downto 0);
                    mask_b : std_ulogic; val_b : std_ulogic_vector(63 downto 0);
                    mask_c : std_ulogic; val_c : std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
        variable t : std_ulogic_vector(63 downto 0) := (others => '0');
    begin
        if mask_a = '1' then
            t := val_a;
        end if;
        if mask_b = '1' then
            t := t or val_b;
        end if;
        if mask_c = '1' then
            t := t or val_c;
        end if;
        return t;
    end;

    signal decoded_reg_a : decode_input_reg_t;
    signal decoded_reg_b : decode_input_reg_t;
    signal decoded_reg_c : decode_input_reg_t;
    signal decoded_reg_o : decode_output_reg_t;

    -- issue control signals
    signal control_valid_in : std_ulogic;
    signal control_valid_out : std_ulogic;
    signal control_serialize : std_logic;

    signal gpr_write_valid : std_ulogic;
    signal gpr_write : gspr_index_t;

    signal gpr_a_read_valid : std_ulogic;
    signal gpr_a_read       : gspr_index_t;
    signal gpr_a_bypass     : std_ulogic_vector(3 downto 0);

    signal gpr_b_read_valid : std_ulogic;
    signal gpr_b_read       : gspr_index_t;
    signal gpr_b_bypass     : std_ulogic_vector(3 downto 0);

    signal gpr_c_read_valid : std_ulogic;
    signal gpr_c_read       : gspr_index_t;
    signal gpr_c_bypass     : std_ulogic_vector(3 downto 0);

    signal cr_read_valid   : std_ulogic;
    signal cr_write_valid  : std_ulogic;
    signal cr_bypass       : std_ulogic_vector(1 downto 0);

    signal ov_read_valid   : std_ulogic;
    signal ov_write_valid  : std_ulogic;

    signal instr_tag       : instr_tag_t;

begin
    control_0: entity work.control
	generic map (
            EX1_BYPASS => EX1_BYPASS
            )
	port map (
            clk         => clk,
            rst         => rst,

            complete_in => complete_in,
            valid_in    => control_valid_in,
            deferred    => deferred,
            flush_in    => flush_in,
            serialize   => control_serialize,
            stop_mark_in => d_in.stop_mark,

            gpr_write_valid_in => gpr_write_valid,
            gpr_write_in       => gpr_write,

            gpr_a_read_valid_in  => gpr_a_read_valid,
            gpr_a_read_in        => gpr_a_read,

            gpr_b_read_valid_in  => gpr_b_read_valid,
            gpr_b_read_in        => gpr_b_read,

            gpr_c_read_valid_in  => gpr_c_read_valid,
            gpr_c_read_in        => gpr_c_read,

            execute_next_tag     => execute_bypass.tag,
            execute_next_cr_tag  => execute_cr_bypass.tag,
            execute2_next_tag    => execute2_bypass.tag,
            execute2_next_cr_tag => execute2_cr_bypass.tag,

            cr_read_in           => cr_read_valid,
            cr_write_in          => cr_write_valid,
            cr_bypass            => cr_bypass,

            ov_read_in           => ov_read_valid,
            ov_write_in          => ov_write_valid,

            valid_out   => control_valid_out,
            stopped_out => stopped_out,

            gpr_bypass_a => gpr_a_bypass,
            gpr_bypass_b => gpr_b_bypass,
            gpr_bypass_c => gpr_c_bypass,

            instr_tag_out => instr_tag
            );

    deferred <= dc2.e.valid and busy_in;

    decode2_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' or flush_in = '1' then
                dc2 <= reg_type_init;
            elsif deferred = '0' then
                if dc2in.e.valid = '1' then
                    report "execute " & to_hstring(dc2in.e.nia) &
                        " tag=" & integer'image(dc2in.e.instr_tag.tag) & std_ulogic'image(dc2in.e.instr_tag.valid) &
                        " rpt=" & std_ulogic'image(dc2in.e.repeat) & " 2nd=" & std_ulogic'image(dc2in.e.second) & " wr=" & to_hstring(dc2in.e.write_reg);
                end if;
                dc2 <= dc2in;
            elsif dc2.read_rspr = '0' then
                -- Update debug SPR access signals even when stalled
                -- if the instruction in dc2.e doesn't read any SPRs.
                dc2.e.dbg_spr_access <= dc2in.e.dbg_spr_access;
                dc2.e.ramspr_even_rdaddr <= dc2in.e.ramspr_even_rdaddr;
                dc2.e.ramspr_odd_rdaddr <= dc2in.e.ramspr_odd_rdaddr;
                dc2.e.ramspr_rd_odd <= dc2in.e.ramspr_rd_odd;
            end if;
        end if;
    end process;

    c_out.read <= d_in.decode.input_cr;

    decode2_addrs: process(all)
        variable dec_a, dec_b, dec_c : decode_input_reg_t;
        variable dec_o : decode_output_reg_t;
    begin
        dec_a.reg_valid := decode_input_reg_a (d_in.decode.input_reg_a, d_in.insn, d_in.prefix);
        dec_a.reg := d_in.reg_a;
        dec_b.reg_valid := decode_input_reg_b (d_in.decode.input_reg_b);
        dec_b.reg := d_in.reg_b;
        dec_c.reg_valid := decode_input_reg_c (d_in.decode.input_reg_c);
        dec_c.reg := d_in.reg_c;
        dec_o := decode_output_reg (d_in.decode.output_reg_a, d_in.insn);
        case d_in.decode.repeat is
            when DUPD =>
                if d_in.second = '1' then
                    -- update-form loads, 2nd instruction writes RA
                    dec_o.reg := dec_a.reg;
                end if;
            when DRSP =>
                -- non-prefixed stq, stqcx do RS|1, RS in LE mode; others do RS, RS|1
                if d_in.second = (d_in.big_endian or d_in.prefixed) then
                    dec_c.reg(0) := '1';            -- do RS, RS|1
                end if;
            when DRTP =>
                -- non-prefixed lq, lqarx do RT|1, RT in LE mode; others do RT, RT|1
                if d_in.second = (d_in.big_endian or d_in.prefixed) then
                    dec_o.reg(0) := '1';
                end if;
            when others =>
        end case;
        -- For the second instance of a doubled instruction, we ignore the RA
        -- and RB operands, in order to avoid false dependencies on the output
        -- of the first instance.
        if d_in.second = '1' then
            dec_a.reg_valid := '0';
            dec_b.reg_valid := '0';
        end if;
        if d_in.valid = '0' or d_in.illegal_suffix = '1' then
            dec_a.reg_valid := '0';
            dec_b.reg_valid := '0';
            dec_c.reg_valid := '0';
            dec_o.reg_valid := '0';
        end if;

        decoded_reg_a <= dec_a;
        decoded_reg_b <= dec_b;
        decoded_reg_c <= dec_c;
        decoded_reg_o <= dec_o;
        r_out.read1_enable <= dec_a.reg_valid;
        r_out.read2_enable <= dec_b.reg_valid;
        r_out.read3_enable <= dec_c.reg_valid;

    end process;

    decode2_1: process(all)
        variable v : reg_type;
        variable length : std_ulogic_vector(3 downto 0);
        variable op : insn_type_t;
        variable unit : unit_t;
        variable valid_in : std_ulogic;
        variable decctr : std_ulogic;
        variable sprs_busy : std_ulogic;
    begin
        v := dc2;

        valid_in := d_in.valid or dc2.busy;

        if dc2.busy = '0' then
            v.e := Decode2ToExecute1Init;

            sprs_busy := '0';
            unit := d_in.decode.unit;

            if d_in.valid = '1' then
                v.prev_sgl := dc2.sgl_pipe;
                v.sgl_pipe := d_in.decode.sgl_pipe;
            end if;

            v.e.input_cr := d_in.decode.input_cr;
            v.e.output_cr := d_in.decode.output_cr;

            v.e.spr_select := d_in.spr_info;

            -- Work out whether XER SO/OV/OV32 bits are set
            -- or used by this instruction
            v.e.rc := decode_rc(d_in.decode.rc, d_in.insn);
            v.e.output_xer := d_in.decode.output_carry;
            v.input_ov := d_in.decode.output_carry;
            v.output_ov := '0';
            if d_in.decode.input_carry = OV then
                v.input_ov := '1';
                v.output_ov := '1';
            end if;
            if v.e.rc = '1' and d_in.decode.facility /= FPU then
                v.input_ov := '1';
            end if;
            case d_in.decode.insn_type is
                when OP_ADD | OP_MUL_L64 | OP_DIV | OP_DIVE =>
                    if d_in.decode.rc = RCOE and insn_oe(d_in.insn) = '1' then
                        v.e.oe := '1';
                        v.e.output_xer := '1';
                        v.output_ov := '1';
                        v.input_ov := '1';      -- need SO state if setting OV to 0
                    end if;
                when OP_MFSPR =>
                    if is_X(d_in.insn) then
                        v.input_ov := 'X';
                    else
                        case decode_spr_num(d_in.insn) is
                            when SPR_XER =>
                                v.input_ov := '1';
                            when SPR_DAR | SPR_DSISR | SPR_PID | SPR_PTCR |
                                SPR_DAWR0 | SPR_DAWR1 | SPR_DAWRX0 | SPR_DAWRX1 =>
                                unit := LDST;
                            when SPR_TAR =>
                                v.e.uses_tar := '1';
                            when SPR_UDSCR =>
                                v.e.uses_dscr := '1';
                            when others =>
                        end case;
                        if d_in.spr_info.wonly = '1' then
                            v.e.spr_select.valid := '0';
                        end if;
                    end if;
                when OP_MTSPR =>
                    if is_X(d_in.insn) then
                        v.e.output_xer := 'X';
                        v.output_ov := 'X';
                        v.sgl_pipe := 'X';
                    else
                        case decode_spr_num(d_in.insn) is
                            when SPR_XER =>
                                v.e.output_xer := '1';
                                v.output_ov := '1';
                            when SPR_DAR | SPR_DSISR | SPR_PID | SPR_PTCR |
                                SPR_DAWR0 | SPR_DAWR1 | SPR_DAWRX0 | SPR_DAWRX1 =>
                                unit := LDST;
                                if d_in.valid = '1' then
                                    v.sgl_pipe := '1';
                                end if;
                            when SPR_TAR =>
                                v.e.uses_tar := '1';
                            when SPR_UDSCR =>
                                v.e.uses_dscr := '1';
                            when others =>
                        end case;
                        if d_in.spr_info.ronly = '1' then
                            v.e.spr_select.valid := '0';
                        elsif d_in.spr_info.valid = '1' and d_in.valid = '1' then
                            v.sgl_pipe := '1';
                        end if;
                    end if;
                when OP_CMP | OP_MCRXRX =>
                    v.input_ov := '1';
                when others =>
            end case;

            if d_in.decode.lr = '1' then
                v.e.lr := insn_lk(d_in.insn);
                -- b and bc have even major opcodes; bcreg is considered absolute
                v.e.br_abs := insn_aa(d_in.insn) or d_in.insn(26);
            end if;
            op := d_in.decode.insn_type;

            -- Does this instruction decrement CTR?
            -- bc, bclr, bctar with BO(2) = 0 do, but not bcctr.
            decctr := '0';
            if d_in.insn(23) = '0' and
                (op = OP_BC or
                 (op = OP_BCREG and not (d_in.insn(10) = '1' and d_in.insn(6) = '0'))) then
                decctr := '1';
            end if;
            v.e.dec_ctr := decctr;

            if d_in.decode.repeat /= NONE then
                v.e.repeat := '1';
            end if;
            v.e.second := d_in.second;

            if decctr = '1' then
                -- read and write CTR
                v.e.ramspr_odd_rdaddr := RAMSPR_CTR;
                v.e.ramspr_wraddr := RAMSPR_CTR;
                v.e.ramspr_write_odd := '1';
                sprs_busy := '1';
            end if;
            if v.e.lr = '1' then
                -- write LR
                v.e.ramspr_wraddr := RAMSPR_LR;
                v.e.ramspr_write_even := '1';
            end if;

            case op is
                when OP_BCREG =>
                    if d_in.insn(10) = '0' then
                        v.e.ramspr_even_rdaddr := RAMSPR_LR;
                    elsif d_in.insn(6) = '0' then
                        v.e.ramspr_odd_rdaddr := RAMSPR_CTR;
                        v.e.ramspr_rd_odd := '1';
                    else
                        v.e.ramspr_even_rdaddr := RAMSPR_TAR;
                        v.e.uses_tar := '1';
                    end if;
                    sprs_busy := '1';
                when OP_MFSPR =>
                    v.e.ramspr_even_rdaddr := d_in.ram_spr.index;
                    v.e.ramspr_odd_rdaddr := d_in.ram_spr.index;
                    v.e.ramspr_rd_odd := d_in.ram_spr.isodd;
                    v.e.ramspr_32bit := d_in.ram_spr.is32b;
                    v.e.spr_is_ram := d_in.ram_spr.valid;
                    sprs_busy := d_in.ram_spr.valid;
                when OP_MTSPR =>
                    v.e.ramspr_wraddr := d_in.ram_spr.index;
                    v.e.ramspr_write_even := d_in.ram_spr.valid and not d_in.ram_spr.isodd;
                    v.e.ramspr_write_odd := d_in.ram_spr.valid and d_in.ram_spr.isodd;
                    v.e.spr_is_ram := d_in.ram_spr.valid;
                when OP_RFID =>
                    if d_in.insn(7) = '1' then
                        -- rfscv
                        v.e.ramspr_even_rdaddr := RAMSPR_LR;
                        v.e.ramspr_odd_rdaddr := RAMSPR_CTR;
                    elsif d_in.insn(9) = '0' then
                        -- rfid
                        v.e.ramspr_even_rdaddr := RAMSPR_SRR0;
                        v.e.ramspr_odd_rdaddr := RAMSPR_SRR1;
                    else
                        -- hrfid
                        v.e.ramspr_even_rdaddr := RAMSPR_HSRR0;
                        v.e.ramspr_odd_rdaddr := RAMSPR_HSRR1;
                    end if;
                    sprs_busy := '1';
                when OP_LOAD | OP_STORE =>
                    if d_in.decode.is_signed = '1' then
                        -- hash{st,chk}[p]
                        if d_in.insn(7) = '1' then
                            v.e.ramspr_odd_rdaddr := RAMSPR_HASHKY;
                        else
                            v.e.ramspr_odd_rdaddr := RAMSPR_HASHPK;
                        end if;
                        v.e.ramspr_rd_odd := '1';
                        sprs_busy := '1';
                    end if;
                when others =>
            end case;
            v.read_rspr := sprs_busy and d_in.valid;

            case d_in.decode.length is
                when is1B =>
                    length := "0001";
                when is2B =>
                    length := "0010";
                when is4B =>
                    length := "0100";
                when is8B =>
                    length := "1000";
                when NONE =>
                    length := "0000";
            end case;

            -- execute unit
            v.e.nia := d_in.nia;
            v.e.unit := unit;
            v.e.fac := d_in.decode.facility;
            v.e.read_reg1 := d_in.reg_a;
            v.e.read_reg2 := d_in.reg_b;
            v.e.read_reg3 := d_in.reg_c;
            v.e.reg_valid1 := decoded_reg_a.reg_valid;
            v.e.reg_valid2 := decoded_reg_b.reg_valid;
            v.e.reg_valid3 := decoded_reg_c.reg_valid;
            v.e.write_reg := decoded_reg_o.reg;
            v.e.write_reg_enable := decoded_reg_o.reg_valid;
            v.e.invert_a := d_in.decode.invert_a;
            v.e.insn_type := op;
            v.e.invert_out := d_in.decode.invert_out;
            v.e.input_carry := d_in.decode.input_carry;
            v.e.output_carry := d_in.decode.output_carry;
            v.e.is_32bit := d_in.decode.is_32bit;
            v.e.is_signed := d_in.decode.is_signed;
            v.e.insn := d_in.insn;
            v.e.data_len := length;
            v.e.byte_reverse := d_in.decode.byte_reverse;
            v.e.sign_extend := d_in.decode.sign_extend;
            v.e.update := d_in.decode.update;
            v.e.reserve := d_in.decode.reserve;
            v.e.br_pred := d_in.br_pred;
            v.e.result_sel := d_in.decode.result;
            v.e.sub_select := d_in.decode.subresult;
            v.e.privileged := d_in.decode.privileged;
            if (op = OP_MFSPR or op = OP_MTSPR) and d_in.insn(20) = '1' then
                v.e.privileged := '1';
            end if;
            -- Reading TB is privileged if syscon_tb_ctrl.rd_protect is 1
            if tb_ctrl.rd_prot = '1' and op = OP_MFSPR and d_in.spr_info.valid = '1' and
                 (d_in.spr_info.sel = SPRSEL_TB or d_in.spr_info.sel = SPRSEL_TBU) then
                v.e.privileged := '1';
            end if;
            v.e.prefixed := d_in.prefixed;
            v.e.prefix := d_in.prefix;
            v.e.illegal_suffix := d_in.illegal_suffix;
            v.e.misaligned_prefix := d_in.misaligned_prefix;

            -- rotator control signals
            v.e.right_shift := d_in.decode.invert_a;
            v.e.rot_clear_left := d_in.decode.subresult(2);
            v.e.rot_clear_right := d_in.decode.subresult(0);
            v.e.rot_sign_ext := d_in.decode.subresult(1);

            v.e.do_popcnt := '1' when op = OP_COUNTB and d_in.insn(7 downto 6) = "11" else '0';

            -- check for invalid forms that cause an illegal instruction interrupt
            -- Does RA = RT for a load quadword instr, or RB = RT for lqarx?
            if d_in.decode.repeat = DRTP and
                (insn_ra(d_in.insn) = insn_rt(d_in.insn) or
                 (d_in.decode.reserve = '1' and insn_rb(d_in.insn) = insn_rt(d_in.insn))) then
                v.e.illegal_form := '1';
            end if;
            -- Is RS/RT odd for a load/store quadword instruction?
            if (d_in.decode.repeat = DRSP or d_in.decode.repeat = DRTP) and d_in.insn(21) = '1' then
                v.e.illegal_form := '1';
            end if;
        end if;

        -- issue control
        control_valid_in <= valid_in;
        control_serialize <= v.sgl_pipe or v.prev_sgl;

        gpr_write_valid <= v.e.write_reg_enable;
        gpr_write <= v.e.write_reg;

        gpr_a_read_valid <= v.e.reg_valid1;
        gpr_a_read <= v.e.read_reg1;

        gpr_b_read_valid <= v.e.reg_valid2;
        gpr_b_read <= v.e.read_reg2;

        gpr_c_read_valid <= v.e.reg_valid3;
        gpr_c_read <= v.e.read_reg3;

        cr_write_valid <= v.e.output_cr or v.e.rc;
        -- Since ops that write CR only write some of the fields,
        -- any op that writes CR effectively also reads it.
        cr_read_valid <= cr_write_valid or v.e.input_cr;

        ov_read_valid <= v.input_ov;
        ov_write_valid <= v.output_ov;

        -- See if any of the operands can get their value via the bypass path.
        if gpr_a_bypass(0) = '1' then
            v.e.read_data1 := andor(gpr_a_bypass(1), execute_bypass.data,
                                    gpr_a_bypass(2), execute2_bypass.data,
                                    gpr_a_bypass(3), writeback_bypass.data);
        elsif dc2.busy = '0' then
            if decoded_reg_a.reg_valid = '1' then
                v.e.read_data1 := r_in.read1_data;
            else
                v.e.read_data1 := decode_a_const(d_in.decode.input_reg_a, d_in.prefix, d_in.nia);
            end if;
        end if;
        if gpr_b_bypass(0) = '1' then
            v.e.read_data2 := andor(gpr_b_bypass(1), execute_bypass.data,
                                    gpr_b_bypass(2), execute2_bypass.data,
                                    gpr_b_bypass(3), writeback_bypass.data);
        elsif dc2.busy = '0' then
            if decoded_reg_b.reg_valid = '1' then
                v.e.read_data2 := r_in.read2_data;
            else
                v.e.read_data2 := decode_b_const(d_in.decode.const_sel, d_in.insn, d_in.prefix);
            end if;
        end if;
        if gpr_c_bypass(0) = '1' then
            v.e.read_data3 := andor(gpr_c_bypass(1), execute_bypass.data,
                                    gpr_c_bypass(2), execute2_bypass.data,
                                    gpr_c_bypass(3), writeback_bypass.data);
        elsif dc2.busy = '0' then
            if decoded_reg_c.reg_valid = '1' then
                v.e.read_data3 := r_in.read3_data;
            else
                v.e.read_data3 := (others => '0');
            end if;
        end if;

        case cr_bypass is
            when "10" =>
                v.e.cr := execute_cr_bypass.data;
            when "11" =>
                v.e.cr := execute2_cr_bypass.data;
            when others =>
                v.e.cr := c_in.read_cr_data;
        end case;
        v.e.xerc := c_in.read_xerc_data;

        v.e.valid := control_valid_out;
        v.e.instr_tag := instr_tag;
        v.busy := valid_in and not control_valid_out;

        stall_out <= dc2.busy or deferred;

        v.e.dbg_spr_access := dbg_spr_req and not v.read_rspr;
        if v.e.dbg_spr_access = '1' then
            v.e.ramspr_even_rdaddr := unsigned(dbg_spr_addr(3 downto 1));
            v.e.ramspr_odd_rdaddr := unsigned(dbg_spr_addr(3 downto 1));
            v.e.ramspr_rd_odd := dbg_spr_addr(0);
        end if;

        -- Update registers
        dc2in <= v;

        -- Update outputs
        e_out <= dc2.e;
    end process;

    d2_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(9 downto 0);
    begin
        dec2_log : process(clk)
        begin
            if rising_edge(clk) then
                log_data <= dc2.e.nia(5 downto 2) &
                            dc2.e.valid &
                            stopped_out &
                            stall_out &
                            (gpr_a_bypass(1) xor gpr_a_bypass(0)) &
                            (gpr_b_bypass(1) xor gpr_b_bypass(0)) &
                            (gpr_c_bypass(1) xor gpr_c_bypass(0));
            end if;
        end process;
        log_out <= log_data;
    end generate;

end architecture behaviour;
