library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity gpr_hazard is
    generic (
        PIPELINE_DEPTH : natural := 2
        );
    port(
        clk                : in std_ulogic;
	stall_in           : in std_ulogic;

        gpr_write_valid_in : in std_ulogic;
        gpr_write_in       : in std_ulogic_vector(5 downto 0);
        bypass_avail       : in std_ulogic;
        gpr_read_valid_in  : in std_ulogic;
        gpr_read_in        : in std_ulogic_vector(5 downto 0);

        stall_out          : out std_ulogic;
        use_bypass         : out std_ulogic
        );
end entity gpr_hazard;
architecture behaviour of gpr_hazard is
    type pipeline_entry_type is record
        valid  : std_ulogic;
        bypass : std_ulogic;
        gpr    : std_ulogic_vector(5 downto 0);
    end record;
    constant pipeline_entry_init : pipeline_entry_type := (valid => '0', bypass => '0', gpr => (others => '0'));

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
        use_bypass <= '0';
        if gpr_read_valid_in = '1' then
            if r(0).valid = '1' and r(0).gpr = gpr_read_in then
                if r(0).bypass = '1' and stall_in = '0' then
                    use_bypass <= '1';
                else
                    stall_out <= '1';
                end if;
            end if;
            loop_0: for i in 1 to PIPELINE_DEPTH-1 loop
                if r(i).valid = '1' and r(i).gpr = gpr_read_in then
                    if r(i).bypass = '1' then
                        use_bypass <= '1';
                    else
                        stall_out <= '1';
                    end if;
                end if;
            end loop;
        end if;

        if stall_in = '0' then
            v(0).valid  := gpr_write_valid_in;
            v(0).bypass := bypass_avail;
            v(0).gpr    := gpr_write_in;
            loop_1: for i in 1 to PIPELINE_DEPTH-1 loop
                -- propagate to next slot
                v(i).valid  := r(i-1).valid;
                v(i).bypass := r(i-1).bypass;
                v(i).gpr    := r(i-1).gpr;
            end loop;

        else
            -- stage 0 stalled, so stage 1 becomes empty
            loop_1b: for i in 1 to PIPELINE_DEPTH-1 loop
                -- propagate to next slot
                if i = 1 then
                    v(i).valid := '0';
                else
                    v(i).valid  := r(i-1).valid;
                    v(i).bypass := r(i-1).bypass;
                    v(i).gpr    := r(i-1).gpr;
                end if;
            end loop;
        end if;

        -- update registers
        rin <= v;

    end process;
end;
