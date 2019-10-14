library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpr_hazard is
    generic (
        PIPELINE_DEPTH : natural := 2
        );
    port(
        clk                : in std_logic;

        gpr_write_valid_in : in std_ulogic;
        gpr_write_in       : in std_ulogic_vector(4 downto 0);
        gpr_read_valid_in  : in std_ulogic;
        gpr_read_in        : in std_ulogic_vector(4 downto 0);

        stall_out          : out std_ulogic
        );
end entity gpr_hazard;
architecture behaviour of gpr_hazard is
    type pipeline_entry_type is record
        valid : std_ulogic;
        gpr   : std_ulogic_vector(4 downto 0);
    end record;
    constant pipeline_entry_init : pipeline_entry_type := (valid => '0', gpr => (others => '0'));

    type pipeline_t is array(0 to PIPELINE_DEPTH-1) of pipeline_entry_type;
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

        stall_out <= '0';
        loop_0: for i in 0 to PIPELINE_DEPTH-1 loop
            if ((r(i).valid = gpr_read_valid_in) and r(i).gpr = gpr_read_in) then
                stall_out <= '1';
            end if;
        end loop;

        v(0).valid := gpr_write_valid_in;
        v(0).gpr   := gpr_write_in;
        loop_1: for i in 0 to PIPELINE_DEPTH-2 loop
            -- propagate to next slot
            v(i+1) := r(i);
        end loop;

        -- asynchronous output
        if gpr_read_valid_in = '0' then
            stall_out <= '0';
        end if;

        -- update registers
        rin <= v;

    end process;
end;
