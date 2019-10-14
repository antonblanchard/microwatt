library ieee;
use ieee.std_logic_1164.all;

entity control is
    generic (
        PIPELINE_DEPTH : natural := 2
        );
    port (
        clk         : in std_ulogic;
        rst         : in std_ulogic;

        complete_in : in std_ulogic;
        valid_in    : in std_ulogic;
        flush_in    : in std_ulogic;
        sgl_pipe_in : in std_ulogic;
        stop_mark_in : in std_ulogic;

        valid_out   : out std_ulogic;
        stall_out   : out std_ulogic;
        stopped_out : out std_ulogic
        );
end entity control;

architecture rtl of control is
    type state_type is (IDLE, WAIT_FOR_PREV_TO_COMPLETE, WAIT_FOR_CURR_TO_COMPLETE);

    type reg_internal_type is record
        state : state_type;
        outstanding : integer range -1 to PIPELINE_DEPTH+1;
    end record;
    constant reg_internal_init : reg_internal_type := (state => IDLE, outstanding => 0);

    signal r_int, rin_int : reg_internal_type := reg_internal_init;
begin
    control0: process(clk)
    begin
        if rising_edge(clk) then
            r_int <= rin_int;
        end if;
    end process;

    control1 : process(all)
        variable v_int : reg_internal_type;
        variable valid_tmp : std_ulogic;
    begin
        v_int := r_int;

        -- asynchronous
        valid_tmp := valid_in and not flush_in;
        stall_out <= '0';

        if complete_in = '1' then
            assert r_int.outstanding <= 1 report "Outstanding bad " & integer'image(r_int.outstanding) severity failure;
            v_int.outstanding := r_int.outstanding - 1;
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
                if (flush_in = '0') and (valid_tmp = '1') and (sgl_pipe_in = '1') then
                    if v_int.outstanding /= 0 then
                        v_int.state := WAIT_FOR_PREV_TO_COMPLETE;
                        valid_tmp := '0';
                        stall_out <= '1';
                    else
                        -- send insn out and wait on it to complete
                        v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
                    end if;
                end if;

            when WAIT_FOR_PREV_TO_COMPLETE =>
                if v_int.outstanding = 0 then
                    -- send insn out and wait on it to complete
                    v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
                else
                    valid_tmp := '0';
                    stall_out <= '1';
                end if;

            when WAIT_FOR_CURR_TO_COMPLETE =>
                if v_int.outstanding = 0 then
                    v_int.state := IDLE;
                else
                    valid_tmp := '0';
                    stall_out <= '1';
                end if;
        end case;

        -- track outstanding instructions
        if valid_tmp = '1' then
            v_int.outstanding := v_int.outstanding + 1;
        end if;

        if rst = '1' then
            v_int.state := IDLE;
            v_int.outstanding := 0;
            stall_out <= '0';
        end if;

        -- update outputs
        valid_out <= valid_tmp;

        -- update registers
        rin_int <= v_int;
    end process;
end;
