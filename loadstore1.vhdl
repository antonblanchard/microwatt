library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

-- 2 cycle LSU
-- We calculate the address in the first cycle

entity loadstore1 is
	port (
		clk   : in std_ulogic;

		l_in  : in Decode2ToLoadstore1Type;

		l_out : out Loadstore1ToLoadstore2Type
	);
end loadstore1;

architecture behave of loadstore1 is
	signal r, rin : Loadstore1ToLoadstore2Type;
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
		variable v : Loadstore1ToLoadstore2Type;
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

		v.addr := lsu_sum;

		-- Update registers
		rin <= v;

                -- Update outputs
                l_out <= r;
	end process;
end;
