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
                     DO_MFFS, DO_MTFSF);

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
    w_out.write_cr_enable <= r.instr_done and r.rc;
    w_out.write_cr_mask <= r.cr_mask;
    w_out.write_cr_data <= r.cr_result & r.cr_result & r.cr_result & r.cr_result &
                           r.cr_result & r.cr_result & r.cr_result & r.cr_result;

    fpu_1: process(all)
        variable v           : reg_type;
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
            v.cr_mask := num_to_fxm(1);
            v.b := e_in.frb;
        end if;

        v.writing_back := '0';
        v.instr_done := '0';

        case r.state is
            when IDLE =>
                if e_in.valid = '1' then
                    case e_in.insn(5 downto 1) is
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

            when DO_MFFS =>
                v.writing_back := '1';
                case r.insn(20 downto 16) is
                    when "00000" =>
                        -- mffs
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
        fp_result <= x"00000000" & r.fpscr;

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
