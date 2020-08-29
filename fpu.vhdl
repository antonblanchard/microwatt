-- Floating-point unit for Microwatt

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.insn_helpers.all;
use work.decode_types.all;
use work.crhelpers.all;
use work.helpers.all;
use work.common.all;

entity fpu is
    port (
        clk : in std_ulogic;
        rst : in std_ulogic;

        e_in  : in  Execute1toFPUType;
        e_out : out FPUToExecute1Type;

        w_out : out FPUToWritebackType
        );
end entity fpu;

architecture behaviour of fpu is

    type state_t is (IDLE,
                     DO_MCRFS, DO_MTFSB, DO_MTFSFI, DO_MFFS, DO_MTFSF);

    type reg_type is record
        state        : state_t;
        busy         : std_ulogic;
        instr_done   : std_ulogic;
        do_intr      : std_ulogic;
        op           : insn_type_t;
        insn         : std_ulogic_vector(31 downto 0);
        dest_fpr     : gspr_index_t;
        fe_mode      : std_ulogic;
        rc           : std_ulogic;
        is_cmp       : std_ulogic;
        single_prec  : std_ulogic;
        fpscr        : std_ulogic_vector(31 downto 0);
        b            : std_ulogic_vector(63 downto 0);
        r            : std_ulogic_vector(63 downto 0);
        writing_back : std_ulogic;
        cr_result    : std_ulogic_vector(3 downto 0);
        cr_mask      : std_ulogic_vector(7 downto 0);
    end record;

    signal r, rin : reg_type;

    signal fp_result     : std_ulogic_vector(63 downto 0);

begin
    fpu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.busy <= '0';
                r.instr_done <= '0';
                r.do_intr <= '0';
                r.fpscr <= (others => '0');
                r.writing_back <= '0';
            else
                assert not (r.state /= IDLE and e_in.valid = '1') severity failure;
                r <= rin;
            end if;
        end if;
    end process;

    e_out.busy <= r.busy;
    e_out.exception <= r.fpscr(FPSCR_FEX);
    e_out.interrupt <= r.do_intr;

    w_out.valid <= r.instr_done and not r.do_intr;
    w_out.write_enable <= r.writing_back;
    w_out.write_reg <= r.dest_fpr;
    w_out.write_data <= fp_result;
    w_out.write_cr_enable <= r.instr_done and (r.rc or r.is_cmp);
    w_out.write_cr_mask <= r.cr_mask;
    w_out.write_cr_data <= r.cr_result & r.cr_result & r.cr_result & r.cr_result &
                           r.cr_result & r.cr_result & r.cr_result & r.cr_result;

    fpu_1: process(all)
        variable v           : reg_type;
        variable fpscr_mask  : std_ulogic_vector(31 downto 0);
        variable illegal     : std_ulogic;
        variable j, k        : integer;
        variable flm         : std_ulogic_vector(7 downto 0);
    begin
        v := r;
        illegal := '0';
        v.busy := '0';

        -- capture incoming instruction
        if e_in.valid = '1' then
            v.insn := e_in.insn;
            v.op := e_in.op;
            v.fe_mode := or (e_in.fe_mode);
            v.dest_fpr := e_in.frt;
            v.single_prec := e_in.single;
            v.rc := e_in.rc;
            v.is_cmp := e_in.out_cr;
            if e_in.out_cr = '0' then
                v.cr_mask := num_to_fxm(1);
            else
                v.cr_mask := num_to_fxm(to_integer(unsigned(insn_bf(e_in.insn))));
            end if;
            v.b := e_in.frb;
        end if;

        v.writing_back := '0';
        v.instr_done := '0';
        fpscr_mask := (others => '1');

        case r.state is
            when IDLE =>
                if e_in.valid = '1' then
                    case e_in.insn(5 downto 1) is
                        when "00000" =>
                            v.state := DO_MCRFS;
                        when "00110" =>
                            if e_in.insn(8) = '0' then
                                v.state := DO_MTFSB;
                            else
                                v.state := DO_MTFSFI;
                            end if;
                        when "00111" =>
                            if e_in.insn(8) = '0' then
                                v.state := DO_MFFS;
                            else
                                v.state := DO_MTFSF;
                            end if;
                        when others =>
                            illegal := '1';
                    end case;
                end if;

            when DO_MCRFS =>
                j := to_integer(unsigned(insn_bfa(r.insn)));
                for i in 0 to 7 loop
                    if i = j then
                        k := (7 - i) * 4;
                        v.cr_result := r.fpscr(k + 3 downto k);
                        fpscr_mask(k + 3 downto k) := "0000";
                    end if;
                end loop;
                v.fpscr := r.fpscr and (fpscr_mask or x"6007F8FF");
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSB =>
                -- mtfsb{0,1}
                j := to_integer(unsigned(insn_bt(r.insn)));
                for i in 0 to 31 loop
                    if i = j then
                        v.fpscr(31 - i) := r.insn(6);
                    end if;
                end loop;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSFI =>
                -- mtfsfi
                j := to_integer(unsigned(insn_bf(r.insn)));
                if r.insn(16) = '0' then
                    for i in 0 to 7 loop
                        if i = j then
                            k := (7 - i) * 4;
                            v.fpscr(k + 3 downto k) := insn_u(r.insn);
                        end if;
                    end loop;
                end if;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MFFS =>
                v.writing_back := '1';
                case r.insn(20 downto 16) is
                    when "00000" =>
                        -- mffs
                    when "00001" =>
                        -- mffsce
                        v.fpscr(FPSCR_VE downto FPSCR_XE) := "00000";
                    when "10100" | "10101" =>
                        -- mffscdrn[i] (but we don't implement DRN)
                        fpscr_mask := x"000000FF";
                    when "10110" =>
                        -- mffscrn
                        fpscr_mask := x"000000FF";
                        v.fpscr(FPSCR_RN+1 downto FPSCR_RN) :=
                            r.b(FPSCR_RN+1 downto FPSCR_RN);
                    when "10111" =>
                        -- mffscrni
                        fpscr_mask := x"000000FF";
                        v.fpscr(FPSCR_RN+1 downto FPSCR_RN) := r.insn(12 downto 11);
                    when "11000" =>
                        -- mffsl
                        fpscr_mask := x"0007F0FF";
                    when others =>
                        illegal := '1';
                end case;
                v.instr_done := '1';
                v.state := IDLE;

            when DO_MTFSF =>
                if r.insn(25) = '1' then
                    flm := x"FF";
                elsif r.insn(16) = '1' then
                    flm := x"00";
                else
                    flm := r.insn(24 downto 17);
                end if;
                for i in 0 to 7 loop
                    k := i * 4;
                    if flm(i) = '1' then
                        v.fpscr(k + 3 downto k) := r.b(k + 3 downto k);
                    end if;
                end loop;
                v.instr_done := '1';
                v.state := IDLE;

        end case;

        -- Data path.
        -- Just enough to read FPSCR for now.
        v.r := x"00000000" & (r.fpscr and fpscr_mask);

        fp_result <= r.r;

        v.fpscr(FPSCR_VX) := (or (v.fpscr(FPSCR_VXSNAN downto FPSCR_VXVC))) or
                             (or (v.fpscr(FPSCR_VXSOFT downto FPSCR_VXCVI)));
        v.fpscr(FPSCR_FEX) := or (v.fpscr(FPSCR_VX downto FPSCR_XX) and
                                  v.fpscr(FPSCR_VE downto FPSCR_XE));
        if r.rc = '1' then
            v.cr_result := v.fpscr(FPSCR_FX downto FPSCR_OX);
        end if;

        if illegal = '1' then
            v.instr_done := '0';
            v.do_intr := '0';
            v.writing_back := '0';
            v.busy := '0';
            v.state := IDLE;
        else
            v.do_intr := v.instr_done and v.fpscr(FPSCR_FEX) and r.fe_mode;
            if v.state /= IDLE or v.do_intr = '1' then
                v.busy := '1';
            end if;
        end if;

        rin <= v;
        e_out.illegal <= illegal;
    end process;

end architecture behaviour;
