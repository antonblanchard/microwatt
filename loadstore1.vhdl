library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.helpers.all;

-- 2 cycle LSU
-- We calculate the address in the first cycle

entity loadstore1 is
    port (
        clk   : in std_ulogic;

        l_in  : in Decode2ToLoadstore1Type;

        l_out : out Loadstore1ToDcacheType
        );
end loadstore1;

architecture behave of loadstore1 is
    signal r, rin : Loadstore1ToDcacheType;
    signal lsu_sum : std_ulogic_vector(63 downto 0);
begin
    -- Calculate the address in the first cycle
    lsu_sum <= std_ulogic_vector(unsigned(l_in.addr1) + unsigned(l_in.addr2)) when l_in.valid = '1' else (others => '0');

    loadstore1_0: process(clk)
    begin
        if rising_edge(clk) then
            r <= rin;
        end if;
    end process;

    loadstore1_1: process(all)
        variable v : Loadstore1ToDcacheType;
    begin
        v := r;

        v.valid := l_in.valid;
        v.load := l_in.load;
        v.data := l_in.data;
        v.write_reg := l_in.write_reg;
        v.length := l_in.length;
        v.byte_reverse := l_in.byte_reverse;
        v.sign_extend := l_in.sign_extend;
        v.update := l_in.update;
        v.update_reg := l_in.update_reg;

	-- XXX Temporary hack. Mark the op as non-cachable if the address
	-- is the form 0xc-------
	--
	-- This will have to be replaced by a combination of implementing the
	-- proper HV CI load/store instructions and having an MMU to get the I
	-- bit otherwise.
	if lsu_sum(31 downto 28) = "1100" then
	    v.nc := '1';
	else
	    v.nc := '0';
	end if;

	-- XXX Do length_to_sel here ?

        -- byte reverse stores in the first cycle
        if v.load = '0' and l_in.byte_reverse = '1' then
            v.data := byte_reverse(l_in.data, to_integer(unsigned(l_in.length)));
        end if;

        v.addr := lsu_sum;

        -- Update registers
        rin <= v;

        -- Update outputs
        l_out <= r;
    end process;
end;
