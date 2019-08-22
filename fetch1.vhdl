library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity fetch1 is
	generic(
		RESET_ADDRESS : std_logic_vector(63 downto 0)
	);
	port(
		clk           : in std_ulogic;
		rst           : in std_ulogic;

		-- Control inputs:
		fetch_one_in  : in std_ulogic;

		-- redirect from execution unit
		e_in          : in Execute1ToFetch1Type;

		-- fetch data out
		f_out         : out Fetch1ToFetch2Type
	);
end entity fetch1;

architecture behaviour of fetch1 is
	type reg_type is record
		pc        : std_ulogic_vector(63 downto 0);
		fetch_one : std_ulogic;
	end record;

	signal r   : reg_type;
	signal rin : reg_type;
begin
	regs : process(clk)
	begin
		if rising_edge(clk) then
			r <= rin;
		end if;
	end process;

	comb : process(all)
		variable v           : reg_type;
		variable fetch_valid : std_ulogic;
		variable fetch_nia   : std_ulogic_vector(63 downto 0);
	begin
		v := r;

		fetch_valid := '0';
		fetch_nia := (others => '0');

		v.fetch_one := v.fetch_one or fetch_one_in;

		if e_in.redirect = '1' then
			v.pc := e_in.redirect_nia;
		end if;

		if v.fetch_one = '1' then
			fetch_nia := v.pc;
			fetch_valid := '1';
			v.pc := std_logic_vector(unsigned(v.pc) + 4);

			v.fetch_one := '0';
		end if;

		if rst = '1' then
			v.pc := RESET_ADDRESS;
			v.fetch_one := '0';
		end if;

		rin <= v;

		f_out.valid <= fetch_valid;
		f_out.nia <= fetch_nia;
	end process;

end architecture behaviour;
