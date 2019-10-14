library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

-- 2 cycle ALU
-- We handle rc form instructions here

entity execute2 is
    port (
        clk   : in std_ulogic;

        e_in  : in Execute1ToExecute2Type;
        e_out : out Execute2ToWritebackType
        );
end execute2;

architecture behave of execute2 is
    signal r, rin : Execute2ToWritebackType;
begin
    execute2_0: process(clk)
    begin
        if rising_edge(clk) then
            r <= rin;
        end if;
    end process;

    execute2_1: process(all)
        variable v : Execute2ToWritebackType;
    begin
        v := rin;

        v.valid := e_in.valid;
        v.write_enable := e_in.write_enable;
        v.write_reg := e_in.write_reg;
        v.write_data := e_in.write_data;
        v.write_cr_enable := e_in.write_cr_enable;
        v.write_cr_mask := e_in.write_cr_mask;
        v.write_cr_data := e_in.write_cr_data;
        v.rc := e_in.rc;

        -- Update registers
        rin <= v;

        -- Update outputs
        e_out <= r;
    end process;
end;
