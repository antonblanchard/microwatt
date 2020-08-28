library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;

entity control is
    generic (
        PIPELINE_DEPTH : natural := 2
        );
    port (
        clk                 : in std_ulogic;
        rst                 : in std_ulogic;

        complete_in         : in std_ulogic;
        valid_in            : in std_ulogic;
        flush_in            : in std_ulogic;
	busy_in             : in std_ulogic;
        deferred            : in std_ulogic;
        sgl_pipe_in         : in std_ulogic;
        stop_mark_in        : in std_ulogic;

        gpr_write_valid_in  : in std_ulogic;
        gpr_write_in        : in gspr_index_t;
        gpr_bypassable      : in std_ulogic;

        update_gpr_write_valid : in std_ulogic;
        update_gpr_write_reg : in gspr_index_t;

        gpr_a_read_valid_in : in std_ulogic;
        gpr_a_read_in       : in gspr_index_t;

        gpr_b_read_valid_in : in std_ulogic;
        gpr_b_read_in       : in gspr_index_t;

        gpr_c_read_valid_in : in std_ulogic;
        gpr_c_read_in       : in gspr_index_t;

        cr_read_in          : in std_ulogic;
        cr_write_in         : in std_ulogic;
        cr_bypassable       : in std_ulogic;

        valid_out           : out std_ulogic;
        stall_out           : out std_ulogic;
        stopped_out         : out std_ulogic;

        gpr_bypass_a        : out std_ulogic;
        gpr_bypass_b        : out std_ulogic;
        gpr_bypass_c        : out std_ulogic;
        cr_bypass           : out std_ulogic
        );
end entity control;

architecture rtl of control is
    type state_type is (IDLE, WAIT_FOR_PREV_TO_COMPLETE, WAIT_FOR_CURR_TO_COMPLETE);

    type reg_internal_type is record
        state : state_type;
        outstanding : integer range -1 to PIPELINE_DEPTH+2;
    end record;
    constant reg_internal_init : reg_internal_type := (state => IDLE, outstanding => 0);

    signal r_int, rin_int : reg_internal_type := reg_internal_init;

    signal stall_a_out  : std_ulogic;
    signal stall_b_out  : std_ulogic;
    signal stall_c_out  : std_ulogic;
    signal cr_stall_out : std_ulogic;

    signal gpr_write_valid : std_ulogic := '0';
    signal cr_write_valid  : std_ulogic := '0';

begin
    gpr_hazard0: entity work.gpr_hazard
        generic map (
            PIPELINE_DEPTH => PIPELINE_DEPTH
            )
        port map (
            clk                => clk,
            busy_in            => busy_in,
	    deferred           => deferred,
            complete_in        => complete_in,
            flush_in           => flush_in,
            issuing            => valid_out,

            gpr_write_valid_in => gpr_write_valid,
            gpr_write_in       => gpr_write_in,
            bypass_avail       => gpr_bypassable,
            gpr_read_valid_in  => gpr_a_read_valid_in,
            gpr_read_in        => gpr_a_read_in,

            ugpr_write_valid   => update_gpr_write_valid,
            ugpr_write_reg     => update_gpr_write_reg,

            stall_out          => stall_a_out,
            use_bypass         => gpr_bypass_a
            );

    gpr_hazard1: entity work.gpr_hazard
        generic map (
            PIPELINE_DEPTH => PIPELINE_DEPTH
            )
        port map (
            clk                => clk,
            busy_in            => busy_in,
	    deferred           => deferred,
            complete_in        => complete_in,
            flush_in           => flush_in,
            issuing            => valid_out,

            gpr_write_valid_in => gpr_write_valid,
            gpr_write_in       => gpr_write_in,
            bypass_avail       => gpr_bypassable,
            gpr_read_valid_in  => gpr_b_read_valid_in,
            gpr_read_in        => gpr_b_read_in,

            ugpr_write_valid   => update_gpr_write_valid,
            ugpr_write_reg     => update_gpr_write_reg,

            stall_out          => stall_b_out,
            use_bypass         => gpr_bypass_b
            );

    gpr_hazard2: entity work.gpr_hazard
        generic map (
            PIPELINE_DEPTH => PIPELINE_DEPTH
            )
        port map (
            clk                => clk,
            busy_in            => busy_in,
	    deferred           => deferred,
            complete_in        => complete_in,
            flush_in           => flush_in,
            issuing            => valid_out,

            gpr_write_valid_in => gpr_write_valid,
            gpr_write_in       => gpr_write_in,
            bypass_avail       => gpr_bypassable,
            gpr_read_valid_in  => gpr_c_read_valid_in,
            gpr_read_in        => gpr_c_read_in,

            ugpr_write_valid   => update_gpr_write_valid,
            ugpr_write_reg     => update_gpr_write_reg,

            stall_out          => stall_c_out,
            use_bypass         => gpr_bypass_c
            );

    cr_hazard0: entity work.cr_hazard
        generic map (
            PIPELINE_DEPTH => PIPELINE_DEPTH
            )
        port map (
            clk                => clk,
            busy_in            => busy_in,
	    deferred           => deferred,
            complete_in        => complete_in,
            flush_in           => flush_in,
            issuing            => valid_out,

            cr_read_in         => cr_read_in,
            cr_write_in        => cr_write_valid,
            bypassable         => cr_bypassable,

            stall_out          => cr_stall_out,
            use_bypass         => cr_bypass
            );

    control0: process(clk)
    begin
        if rising_edge(clk) then
            assert rin_int.outstanding >= 0 and rin_int.outstanding <= (PIPELINE_DEPTH+1)
                report "Outstanding bad " & integer'image(rin_int.outstanding) severity failure;
            r_int <= rin_int;
        end if;
    end process;

    control1 : process(all)
        variable v_int : reg_internal_type;
        variable valid_tmp : std_ulogic;
        variable stall_tmp : std_ulogic;
    begin
        v_int := r_int;

        -- asynchronous
        valid_tmp := valid_in and not flush_in;
        stall_tmp := '0';

        if flush_in = '1' then
            -- expect to see complete_in next cycle
            v_int.outstanding := 1;
        elsif complete_in = '1' then
            v_int.outstanding := r_int.outstanding - 1;
        end if;

        if rst = '1' then
            v_int := reg_internal_init;
            valid_tmp := '0';
        end if;

        -- Handle debugger stop
        stopped_out <= '0';
        if stop_mark_in = '1' and v_int.outstanding = 0 then
            stopped_out <= '1';
        end if;

        -- state machine to handle instructions that must be single
        -- through the pipeline.
        case r_int.state is
            when IDLE =>
                if valid_tmp = '1' then
                    if (sgl_pipe_in = '1') then
                        if v_int.outstanding /= 0 then
                            v_int.state := WAIT_FOR_PREV_TO_COMPLETE;
                            stall_tmp := '1';
                        else
                            -- send insn out and wait on it to complete
                            v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
                        end if;
                    else
                        -- let it go out if there are no GPR hazards
                        stall_tmp := stall_a_out or stall_b_out or stall_c_out or cr_stall_out;
                    end if;
                end if;

            when WAIT_FOR_PREV_TO_COMPLETE =>
                if v_int.outstanding = 0 then
                    -- send insn out and wait on it to complete
                    v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
                else
                    stall_tmp := '1';
                end if;

            when WAIT_FOR_CURR_TO_COMPLETE =>
                if v_int.outstanding = 0 then
                    v_int.state := IDLE;
                    -- XXX Don't replicate this
                    if valid_tmp = '1' then
                        if (sgl_pipe_in = '1') then
                            if v_int.outstanding /= 0 then
                                v_int.state := WAIT_FOR_PREV_TO_COMPLETE;
                                stall_tmp := '1';
                            else
                                -- send insn out and wait on it to complete
                                v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
                            end if;
                        else
                            -- let it go out if there are no GPR hazards
                            stall_tmp := stall_a_out or stall_b_out or stall_c_out or cr_stall_out;
                        end if;
                    end if;
                else
                    stall_tmp := '1';
                end if;
        end case;

        if stall_tmp = '1' then
            valid_tmp := '0';
        end if;

        if valid_tmp = '1' then
            if deferred = '0' then
                v_int.outstanding := v_int.outstanding + 1;
            end if;
            gpr_write_valid <= gpr_write_valid_in;
            cr_write_valid <= cr_write_in;
        else
            gpr_write_valid <= '0';
            cr_write_valid <= '0';
        end if;

        -- update outputs
        valid_out <= valid_tmp;
        stall_out <= stall_tmp or deferred;

        -- update registers
        rin_int <= v_int;
    end process;
end;
