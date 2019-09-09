library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity writeback is
	port (
		clk          : in std_ulogic;

		e_in         : in Execute2ToWritebackType;
		l_in         : in Loadstore2ToWritebackType;
		m_in         : in MultiplyToWritebackType;

		w_out        : out WritebackToRegisterFileType;
		c_out        : out WritebackToCrFileType;

		complete_out : out std_ulogic
	);
end entity writeback;

architecture behaviour of writeback is
	signal e     : Execute2ToWritebackType;
	signal l     : Loadstore2ToWritebackType;
	signal m     : MultiplyToWritebackType;
	signal w_tmp : WritebackToRegisterFileType;
	signal c_tmp : WritebackToCrFileType;
begin
	writeback_0: process(clk)
	begin
		if rising_edge(clk) then
			e <= e_in;
			l <= l_in;
			m <= m_in;
		end if;
	end process;

	w_out <= w_tmp;
	c_out <= c_tmp;

	complete_out <= '1' when e.valid or l.valid or m.valid else '0';

	writeback_1: process(all)
		variable x: std_ulogic_vector(0 downto 0);
		variable y: std_ulogic_vector(0 downto 0);
		variable z: std_ulogic_vector(0 downto 0);
	begin
		x := "" & e.valid;
		y := "" & l.valid;
		z := "" & m.valid;
		assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z))) <= 1;

		x := "" & e.write_enable;
		y := "" & l.write_enable;
		z := "" & m.write_reg_enable;
		assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z))) <= 1;

		assert not(e.write_cr_enable = '1' and m.write_cr_enable = '1');

		w_tmp <= WritebackToRegisterFileInit;
		c_tmp <= WritebackToCrFileInit;

		if e.write_enable = '1' then
			w_tmp.write_reg <= e.write_reg;
			w_tmp.write_data <= e.write_data;
			w_tmp.write_enable <= '1';
		end if;

		if e.write_cr_enable = '1' then
			c_tmp.write_cr_enable <= '1';
			c_tmp.write_cr_mask <= e.write_cr_mask;
			c_tmp.write_cr_data <= e.write_cr_data;
		end if;

		if l.write_enable = '1' then
			w_tmp.write_reg <= l.write_reg;
			w_tmp.write_data <= l.write_data;
			w_tmp.write_enable <= '1';
		end if;

		if m.write_reg_enable = '1' then
			w_tmp.write_enable <= '1';
			w_tmp.write_reg <= m.write_reg_nr;
			w_tmp.write_data <= m.write_reg_data;
		end if;

		if m.write_cr_enable = '1' then
			c_tmp.write_cr_enable <= '1';
			c_tmp.write_cr_mask <= m.write_cr_mask;
			c_tmp.write_cr_data <= m.write_cr_data;
		end if;
	end process;
end;
