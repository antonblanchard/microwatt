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

        cr_read_in          : in std_ulogic;
        cr_write_in         : in std_ulogic;
        ov_read_in          : in std_ulogic;
        ov_write_in         : in std_ulogic;

        valid_out           : out std_ulogic;
        stopped_out         : out std_ulogic;

        gpr_bypass_a        : out std_ulogic_vector(1 downto 0);
        gpr_bypass_b        : out std_ulogic_vector(1 downto 0);
        gpr_bypass_c        : out std_ulogic_vector(1 downto 0);
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
        variable byp_a : std_ulogic_vector(1 downto 0);
        variable byp_b : std_ulogic_vector(1 downto 0);
        variable byp_c : std_ulogic_vector(1 downto 0);
        variable tag_cr : instr_tag_t;
        variable byp_cr : std_ulogic_vector(1 downto 0);
        variable tag_ov : instr_tag_t;
        variable tag_prev : instr_tag_t;
    begin
        tag_a := instr_tag_init;
        for i in tag_number_t loop
            if tag_regs(i).wr_gpr = '1' and tag_regs(i).recent = '1' and tag_regs(i).reg = gpr_a_read_in then
                tag_a.valid := gpr_a_read_valid_in;
                tag_a.tag := i;
            end if;
        end loop;
        tag_b := instr_tag_init;
        for i in tag_number_t loop
            if tag_regs(i).wr_gpr = '1' and tag_regs(i).recent = '1' and tag_regs(i).reg = gpr_b_read_in then
                tag_b.valid := gpr_b_read_valid_in;
                tag_b.tag := i;
            end if;
        end loop;
        tag_c := instr_tag_init;
        for i in tag_number_t loop
            if tag_regs(i).wr_gpr = '1' and tag_regs(i).recent = '1' and tag_regs(i).reg = gpr_c_read_in then
                tag_c.valid := gpr_c_read_valid_in;
                tag_c.tag := i;
            end if;
        end loop;

        byp_a := "00";
        if EX1_BYPASS and tag_match(execute_next_tag, tag_a) then
            byp_a := "01";
        elsif EX1_BYPASS and tag_match(execute2_next_tag, tag_a) then
            byp_a := "10";
        elsif tag_match(complete_in, tag_a) then
            byp_a := "11";
        end if;
        byp_b := "00";
        if EX1_BYPASS and tag_match(execute_next_tag, tag_b) then
            byp_b := "01";
        elsif EX1_BYPASS and tag_match(execute2_next_tag, tag_b) then
            byp_b := "10";
        elsif tag_match(complete_in, tag_b) then
            byp_b := "11";
        end if;
        byp_c := "00";
        if EX1_BYPASS and tag_match(execute_next_tag, tag_c) then
            byp_c := "01";
        elsif EX1_BYPASS and tag_match(execute2_next_tag, tag_c) then
            byp_c := "10";
        elsif tag_match(complete_in, tag_c) then
            byp_c := "11";
        end if;

        gpr_bypass_a <= byp_a;
        gpr_bypass_b <= byp_b;
        gpr_bypass_c <= byp_c;

        gpr_tag_stall <= (tag_a.valid and not (or (byp_a))) or
                         (tag_b.valid and not (or (byp_b))) or
                         (tag_c.valid and not (or (byp_c)));

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
