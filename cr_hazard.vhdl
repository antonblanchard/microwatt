library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cr_hazard is
    generic (
        PIPELINE_DEPTH : natural := 1
        );
    port(
        clk         : in std_ulogic;
        busy_in     : in std_ulogic;
        deferred    : in std_ulogic;
        complete_in : in std_ulogic;
        flush_in    : in std_ulogic;
        issuing     : in std_ulogic;

        cr_read_in  : in std_ulogic;
        cr_write_in : in std_ulogic;

        stall_out   : out std_ulogic
        );
end entity cr_hazard;
architecture behaviour of cr_hazard is
    type pipeline_entry_type is record
        valid : std_ulogic;
    end record;
    constant pipeline_entry_init : pipeline_entry_type := (valid => '0');

    type pipeline_t is array(0 to PIPELINE_DEPTH) of pipeline_entry_type;
    constant pipeline_t_init : pipeline_t := (others => pipeline_entry_init);

    signal r, rin : pipeline_t := pipeline_t_init;
begin
    cr_hazard0: process(clk)
    begin
        if rising_edge(clk) then
            r <= rin;
        end if;
    end process;

    cr_hazard1: process(all)
        variable v     : pipeline_t;
    begin
        v := r;

        -- XXX assumes PIPELINE_DEPTH = 1
        if complete_in = '1' then
            v(1).valid := '0';
        end if;
        stall_out <= cr_read_in and (v(0).valid or v(1).valid);

        -- XXX assumes PIPELINE_DEPTH = 1
        if busy_in = '0' then
            v(1) := r(0);
            v(0).valid := '0';
        end if;
        if deferred = '0' and issuing = '1' then
            v(0).valid := cr_write_in;
        end if;
        if flush_in = '1' then
            v(0).valid := '0';
            v(1).valid := '0';
        end if;

        -- update registers
        rin <= v;

    end process;
end;
