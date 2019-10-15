library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cr_hazard is
    generic (
        PIPELINE_DEPTH : natural := 2
        );
    port(
        clk         : in std_logic;

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

    type pipeline_t is array(0 to PIPELINE_DEPTH-1) of pipeline_entry_type;
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

        stall_out <= '0';
        loop_0: for i in 0 to PIPELINE_DEPTH-1 loop
            if (r(i).valid = cr_read_in) then
                stall_out <= '1';
            end if;
        end loop;

        v(0).valid := cr_write_in;
        loop_1: for i in 0 to PIPELINE_DEPTH-2 loop
            -- propagate to next slot
            v(i+1) := r(i);
        end loop;

        -- asynchronous output
        if cr_read_in = '0' then
            stall_out <= '0';
        end if;

        -- update registers
        rin <= v;

    end process;
end;
