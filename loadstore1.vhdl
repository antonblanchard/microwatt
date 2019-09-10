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
	signal l       : Decode2ToLoadstore1Type;
	signal lsu_sum : std_ulogic_vector(63 downto 0);
begin
	-- Calculate the address in the first cycle
	lsu_sum <= std_ulogic_vector(unsigned(l.addr1) + unsigned(l.addr2)) when l.valid = '1' else (others => '0');

	loadstore1_0: process(clk)
	begin
		if rising_edge(clk) then
			l <= l_in;
		end if;
	end process;

	loadstore1_1: process(all)
	begin
		l_out.valid <= l.valid;
		l_out.load <= l.load;
		l_out.data <= l.data;
		l_out.write_reg <= l.write_reg;
		l_out.length <= l.length;
		l_out.byte_reverse <= l.byte_reverse;
		l_out.sign_extend <= l.sign_extend;
		l_out.update <= l.update;
		l_out.update_reg <= l.update_reg;

		l_out.addr <= lsu_sum;
	end process;
end;
