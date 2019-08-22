library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity fetch2 is
	port(
		clk          : in std_ulogic;

		-- instruction memory interface
		wishbone_in  : in wishbone_slave_out;
		wishbone_out : out wishbone_master_out;

		f_in         : in Fetch1ToFetch2Type;

		f_out        : out Fetch2ToDecode1Type
	);
end entity fetch2;

architecture behaviour of fetch2 is
	type reg_type is record
		valid : std_ulogic;
		nia   : std_ulogic_vector(63 downto 0);
	end record;

	signal f   : Fetch1ToFetch2Type;
	signal wishbone: wishbone_slave_out;
	signal r   : reg_type := (valid => '0', nia => (others => '0'));
	signal rin : reg_type := (valid => '0', nia => (others => '0'));
begin
	regs : process(clk)
	begin
		if rising_edge(clk) then
			wishbone <= wishbone_in;
			f <= f_in;
			r <= rin;
		end if;
	end process;

	comb : process(all)
		variable v : reg_type;
	begin
		v := r;

		if f.valid = '1' then
			v.valid := '1';
			v.nia := f.nia;
		end if;

		if v.valid = '1' and wishbone.ack = '1' then
			v.valid := '0';
		end if;

		rin <= v;

		wishbone_out.adr <= v.nia(63 downto 3) & "000";
		wishbone_out.dat <= (others => '0');
		wishbone_out.cyc <= v.valid;
		wishbone_out.stb <= v.valid;
		wishbone_out.sel <= "00001111" when v.nia(2) = '0' else "11110000";
		wishbone_out.we  <= '0';

		f_out.valid <= wishbone.ack;
		f_out.nia <= v.nia;
		f_out.insn <= wishbone.dat(31 downto 0) when v.nia(2) = '0' else wishbone.dat(63 downto 32);
	end process;
end architecture behaviour;
