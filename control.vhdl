library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;

entity control is
    generic (
        EX1_BYPASS : boolean := true;
        PIPELINE_DEPTH : natural := 3
        );
    port (
        clk                 : in std_ulogic;
        rst                 : in std_ulogic;

        complete_in         : in instr_tag_t;
        valid_in            : in std_ulogic;
        flush_in            : in std_ulogic;
        deferred            : in std_ulogic;
        serialize           : in std_ulogic;
        stop_mark_in        : in std_ulogic;

        gpr_write_valid_in  : in std_ulogic;
        gpr_write_in        : in gspr_index_t;

        gpr_a_read_valid_in : in std_ulogic;
        gpr_a_read_in       : in gspr_index_t;

        gpr_b_read_valid_in : in std_ulogic;
        gpr_b_read_in       : in gspr_index_t;

        gpr_c_read_valid_in : in std_ulogic;
        gpr_c_read_in       : in gspr_index_t;

        execute_next_tag    : in instr_tag_t;
        execute_next_cr_tag : in instr_tag_t;
        execute2_next_tag    : in instr_tag_t;
        execute2_next_cr_tag : in instr_tag_t;
        writeback_tag       : in instr_tag_t;

        cr_read_in          : in std_ulogic;
        cr_write_in         : in std_ulogic;
        ov_read_in          : in std_ulogic;
        ov_write_in         : in std_ulogic;

        valid_out           : out std_ulogic;
        stopped_out         : out std_ulogic;

        -- Note on gpr_bypass_*: bits 1 to 3 are a 1-hot encoding of which
        -- bypass source we may possibly need to use; bit 0 is 1 if the bypass
        -- value should be used (i.e. any of bits 1-3 are 1 and the
        -- corresponding gpr_x_read_valid_in is also 1).
        gpr_bypass_a        : out std_ulogic_vector(3 downto 0);
        gpr_bypass_b        : out std_ulogic_vector(3 downto 0);
        gpr_bypass_c        : out std_ulogic_vector(3 downto 0);
        cr_bypass           : out std_ulogic_vector(1 downto 0);

        instr_tag_out       : out instr_tag_t
        );
end entity control;

architecture rtl of control is
    signal gpr_write_valid : std_ulogic;
    signal cr_write_valid  : std_ulogic;
    signal ov_write_valid  : std_ulogic;

    type tag_register is record
        wr_gpr : std_ulogic;
        reg    : gspr_index_t;
        recent : std_ulogic;
        wr_cr  : std_ulogic;
        wr_ov  : std_ulogic;
        valid  : std_ulogic;
    end record;

    type tag_regs_array is array(tag_number_t) of tag_register;
    signal tag_regs : tag_regs_array;

    signal instr_tag  : instr_tag_t;

    signal gpr_tag_stall : std_ulogic;
    signal cr_tag_stall  : std_ulogic;
    signal ov_tag_stall  : std_ulogic;
    signal serial_stall  : std_ulogic;

    signal curr_tag : tag_number_t;
    signal next_tag : tag_number_t;

    signal curr_cr_tag : tag_number_t;
    signal curr_ov_tag : tag_number_t;
    signal prev_tag : tag_number_t;

begin
    control0: process(clk)
    begin
        if rising_edge(clk) then
            for i in tag_number_t loop
                if rst = '1' or flush_in = '1' then
                    tag_regs(i).wr_gpr <= '0';
                    tag_regs(i).wr_cr <= '0';
                    tag_regs(i).wr_ov <= '0';
                    tag_regs(i).valid <= '0';
                else
                    if complete_in.valid = '1' and i = complete_in.tag then
                        assert tag_regs(i).valid = '1' report "spurious completion" severity failure;
                        tag_regs(i).wr_gpr <= '0';
                        tag_regs(i).wr_cr <= '0';
                        tag_regs(i).wr_ov <= '0';
                        tag_regs(i).valid <= '0';
                        report "tag " & integer'image(i) & " not valid";
                    end if;
                    if instr_tag.valid = '1' and gpr_write_valid = '1' and
                        tag_regs(i).reg = gpr_write_in then
                        tag_regs(i).recent <= '0';
                        if tag_regs(i).recent = '1' and tag_regs(i).wr_gpr = '1' then
                            report "tag " & integer'image(i) & " not recent";
                        end if;
                    end if;
                    if instr_tag.valid = '1' and i = instr_tag.tag then
                        tag_regs(i).wr_gpr <= gpr_write_valid;
                        tag_regs(i).reg <= gpr_write_in;
                        tag_regs(i).recent <= gpr_write_valid;
                        tag_regs(i).wr_cr <= cr_write_valid;
                        tag_regs(i).wr_ov <= ov_write_valid;
                        tag_regs(i).valid <= '1';
                        if gpr_write_valid = '1' then
                            report "tag " & integer'image(i) & " valid for gpr " & to_hstring(gpr_write_in);
                        end if;
                    end if;
                end if;
            end loop;
            if rst = '1' then
                curr_tag <= 0;
                curr_cr_tag <= 0;
                curr_ov_tag <= 0;
                prev_tag <= 0;
            else
                curr_tag <= next_tag;
                if instr_tag.valid = '1' and cr_write_valid = '1' then
                    curr_cr_tag <= instr_tag.tag;
                end if;
                if instr_tag.valid = '1' and ov_write_valid = '1' then
                    curr_ov_tag <= instr_tag.tag;
                end if;
                if valid_out = '1' then
                    prev_tag <= instr_tag.tag;
                end if;
            end if;
        end if;
    end process;

    control_hazards : process(all)
        variable gpr_stall : std_ulogic;
        variable tag_a : instr_tag_t;
        variable tag_b : instr_tag_t;
        variable tag_c : instr_tag_t;
        variable tag_s : instr_tag_t;
        variable tag_t : instr_tag_t;
        variable incr_tag : tag_number_t;
        variable byp_a : std_ulogic_vector(3 downto 0);
        variable byp_b : std_ulogic_vector(3 downto 0);
        variable byp_c : std_ulogic_vector(3 downto 0);
        variable tag_cr : instr_tag_t;
        variable byp_cr : std_ulogic_vector(1 downto 0);
        variable tag_ov : instr_tag_t;
        variable tag_prev : instr_tag_t;
        variable rma : std_ulogic_vector(TAG_COUNT-1 downto 0);
        variable rmb : std_ulogic_vector(TAG_COUNT-1 downto 0);
        variable rmc : std_ulogic_vector(TAG_COUNT-1 downto 0);
        variable tag_a_stall : std_ulogic;
        variable tag_b_stall : std_ulogic;
        variable tag_c_stall : std_ulogic;
    begin
        tag_a := instr_tag_init;
        tag_a_stall := '0';
        rma := (others => '0');
        for i in tag_number_t loop
            if tag_regs(i).valid = '1' and tag_regs(i).wr_gpr = '1' and
                tag_regs(i).reg = gpr_a_read_in and gpr_a_read_valid_in = '1' then
                rma(i) := '1';
                if tag_regs(i).recent = '1' then
                    tag_a_stall := '1';
                end if;
            end if;
        end loop;
        byp_a := "0000";
        if EX1_BYPASS and execute_next_tag.valid = '1' and
            rma(execute_next_tag.tag) = '1' then
            byp_a(1) := '1';
            tag_a := execute_next_tag;
        elsif EX1_BYPASS and execute2_next_tag.valid = '1' and
            rma(execute2_next_tag.tag) = '1' then
            byp_a(2) := '1';
            tag_a := execute2_next_tag;
        elsif writeback_tag.valid = '1' and rma(writeback_tag.tag) = '1' then
            byp_a(3) := '1';
            tag_a := writeback_tag;
        end if;
        byp_a(0) := gpr_a_read_valid_in and (byp_a(1) or byp_a(2) or byp_a(3));
        if tag_a.valid = '1' and tag_regs(tag_a.tag).valid = '1' and
            tag_regs(tag_a.tag).recent = '1' then
            tag_a_stall := '0';
        end if;

        tag_b := instr_tag_init;
        tag_b_stall := '0';
        rmb := (others => '0');
        for i in tag_number_t loop
            if tag_regs(i).valid = '1' and tag_regs(i).wr_gpr = '1' and
                tag_regs(i).reg = gpr_b_read_in and gpr_b_read_valid_in = '1' then
                rmb(i) := '1';
                if tag_regs(i).recent = '1' then
                    tag_b_stall := '1';
                end if;
            end if;
        end loop;
        byp_b := "0000";
        if EX1_BYPASS and execute_next_tag.valid = '1' and
            rmb(execute_next_tag.tag) = '1' then
            byp_b(1) := '1';
            tag_b := execute_next_tag;
        elsif EX1_BYPASS and execute2_next_tag.valid = '1' and
            rmb(execute2_next_tag.tag) = '1' then
            byp_b(2) := '1';
            tag_b := execute2_next_tag;
        elsif writeback_tag.valid = '1' and rmb(writeback_tag.tag) = '1' then
            byp_b(3) := '1';
            tag_b := writeback_tag;
        end if;
        byp_b(0) := gpr_b_read_valid_in and (byp_b(1) or byp_b(2) or byp_b(3));
        if tag_b.valid = '1' and tag_regs(tag_b.tag).valid = '1' and
            tag_regs(tag_b.tag).recent = '1' then
            tag_b_stall := '0';
        end if;

        tag_c := instr_tag_init;
        tag_c_stall := '0';
        rmc := (others => '0');
        for i in tag_number_t loop
            if tag_regs(i).valid = '1' and tag_regs(i).wr_gpr = '1' and
                tag_regs(i).reg = gpr_c_read_in and gpr_c_read_valid_in = '1' then
                rmc(i) := '1';
                if tag_regs(i).recent = '1' then
                    tag_c_stall := '1';
                end if;
            end if;
        end loop;
        byp_c := "0000";
        if EX1_BYPASS and execute_next_tag.valid = '1' and rmc(execute_next_tag.tag) = '1' then
            byp_c(1) := '1';
            tag_c := execute_next_tag;
        elsif EX1_BYPASS and execute2_next_tag.valid = '1' and rmc(execute2_next_tag.tag) = '1' then
            byp_c(2) := '1';
            tag_c := execute2_next_tag;
        elsif writeback_tag.valid = '1' and rmc(writeback_tag.tag) = '1' then
            byp_c(3) := '1';
            tag_c := writeback_tag;
        end if;
        byp_c(0) := gpr_c_read_valid_in and (byp_c(1) or byp_c(2) or byp_c(3));
        if tag_c.valid = '1' and tag_regs(tag_c.tag).valid = '1' and
            tag_regs(tag_c.tag).recent = '1' then
            tag_c_stall := '0';
        end if;

        gpr_bypass_a <= byp_a;
        gpr_bypass_b <= byp_b;
        gpr_bypass_c <= byp_c;

        gpr_tag_stall <= tag_a_stall or tag_b_stall or tag_c_stall;

        incr_tag := curr_tag;
        instr_tag.tag <= curr_tag;
        instr_tag.valid <= valid_out and not deferred;
        if instr_tag.valid = '1' then
            incr_tag := (curr_tag + 1) mod TAG_COUNT;
        end if;
        next_tag <= incr_tag;
        instr_tag_out <= instr_tag;

        -- CR hazards
        tag_cr.tag := curr_cr_tag;
        tag_cr.valid := cr_read_in and tag_regs(curr_cr_tag).wr_cr;
        if tag_match(tag_cr, complete_in) then
            tag_cr.valid := '0';
        end if;
        byp_cr := "00";
        if EX1_BYPASS and tag_match(execute_next_cr_tag, tag_cr) then
            byp_cr := "10";
        elsif EX1_BYPASS and tag_match(execute2_next_cr_tag, tag_cr) then
            byp_cr := "11";
        end if;

        cr_bypass <= byp_cr;
        cr_tag_stall <= tag_cr.valid and not byp_cr(1);

        -- OV hazards
        tag_ov.tag := curr_ov_tag;
        tag_ov.valid := ov_read_in and tag_regs(curr_ov_tag).wr_ov;
        if tag_match(tag_ov, complete_in) then
            tag_ov.valid := '0';
        end if;
        ov_tag_stall <= tag_ov.valid;

        tag_prev.tag := prev_tag;
        tag_prev.valid := tag_regs(prev_tag).valid;
        if tag_match(tag_prev, complete_in) then
            tag_prev.valid := '0';
        end if;
        serial_stall <= tag_prev.valid;
    end process;

    control1 : process(all)
        variable valid_tmp : std_ulogic;
    begin
        -- asynchronous
        valid_tmp := valid_in and not flush_in;

        if rst = '1' then
            gpr_write_valid <= '0';
            cr_write_valid <= '0';
            valid_tmp := '0';
        end if;

        -- Handle debugger stop
        stopped_out <= stop_mark_in and not serial_stall;

        -- Don't let it go out if there are GPR or CR hazards
        -- or we are waiting for the previous instruction to complete
        if (gpr_tag_stall or cr_tag_stall or ov_tag_stall or
            (serialize and serial_stall)) = '1' then
            valid_tmp := '0';
        end if;

        gpr_write_valid <= gpr_write_valid_in and valid_tmp;
        cr_write_valid <= cr_write_in and valid_tmp;
        ov_write_valid <= ov_write_in and valid_tmp;

        -- update outputs
        valid_out <= valid_tmp;
    end process;
end;
