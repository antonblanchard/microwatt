library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity gpr_hazard is
    generic (
        PIPELINE_DEPTH : natural := 1
        );
    port(
        clk                : in std_ulogic;
        busy_in            : in std_ulogic;
        deferred           : in std_ulogic;
        complete_in        : in std_ulogic;
        flush_in           : in std_ulogic;
        issuing            : in std_ulogic;

        gpr_write_valid_in : in std_ulogic;
        gpr_write_in       : in gspr_index_t;
        bypass_avail       : in std_ulogic;
        gpr_read_valid_in  : in std_ulogic;
        gpr_read_in        : in gspr_index_t;

        ugpr_write_valid   : in std_ulogic;
        ugpr_write_reg     : in gspr_index_t;

        stall_out          : out std_ulogic;
        use_bypass         : out std_ulogic
        );
end entity gpr_hazard;
architecture behaviour of gpr_hazard is
    type pipeline_entry_type is record
        valid  : std_ulogic;
        bypass : std_ulogic;
        gpr    : gspr_index_t;
        ugpr_valid : std_ulogic;
        ugpr   : gspr_index_t;
    end record;
    constant pipeline_entry_init : pipeline_entry_type := (valid => '0', bypass => '0', gpr => (others => '0'),
                                                           ugpr_valid => '0', ugpr => (others => '0'));

    type pipeline_t is array(0 to PIPELINE_DEPTH) of pipeline_entry_type;
    constant pipeline_t_init : pipeline_t := (others => pipeline_entry_init);

    signal r, rin : pipeline_t := pipeline_t_init;
begin
    gpr_hazard0: process(clk)
    begin
        if rising_edge(clk) then
            r <= rin;
        end if;
    end process;

    gpr_hazard1: process(all)
        variable v     : pipeline_t;
    begin
        v := r;

        if complete_in = '1' then
            v(PIPELINE_DEPTH).valid := '0';
            v(PIPELINE_DEPTH).ugpr_valid := '0';
        end if;

        stall_out <= '0';
        use_bypass <= '0';
        if gpr_read_valid_in = '1' then
            loop_0: for i in 0 to PIPELINE_DEPTH loop
                if v(i).valid = '1' and r(i).gpr = gpr_read_in then
                    if r(i).bypass = '1' then
                        use_bypass <= '1';
                    else
                        stall_out <= '1';
                    end if;
                end if;
                if v(i).ugpr_valid = '1' and r(i).ugpr = gpr_read_in then
                    stall_out <= '1';
                end if;
            end loop;
        end if;

        -- XXX assumes PIPELINE_DEPTH = 1
        if busy_in = '0' then
            v(1) := v(0);
            v(0).valid := '0';
            v(0).ugpr_valid := '0';
        end if;
        if deferred = '0' and issuing = '1' then
            v(0).valid  := gpr_write_valid_in;
            v(0).bypass := bypass_avail;
            v(0).gpr    := gpr_write_in;
            v(0).ugpr_valid := ugpr_write_valid;
            v(0).ugpr   := ugpr_write_reg;
        end if;
        if flush_in = '1' then
            v(0).valid := '0';
            v(0).ugpr_valid := '0';
            v(1).valid := '0';
            v(1).ugpr_valid := '0';
        end if;

        -- update registers
        rin <= v;

    end process;
end;
