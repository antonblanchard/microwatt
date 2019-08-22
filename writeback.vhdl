library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;

entity writeback is
	port (
		clk          : in std_ulogic;

		w_in         : in Execute2ToWritebackType;
		l_in         : in Loadstore2ToWritebackType;
		m_in         : in MultiplyToWritebackType;

		w_out        : out WritebackToRegisterFileType;
		c_out        : out WritebackToCrFileType;

		complete_out : out std_ulogic
	);
end entity writeback;

architecture behaviour of writeback is
	signal w     : Execute2ToWritebackType;
	signal l     : Loadstore2ToWritebackType;
	signal m     : MultiplyToWritebackType;
	signal w_tmp : WritebackToRegisterFileType;
	signal c_tmp : WritebackToCrFileType;
begin
	writeback_0: process(clk)
	begin
		if rising_edge(clk) then
			w <= w_in;
			l <= l_in;
			m <= m_in;
		end if;
	end process;

	w_out <= w_tmp;
	c_out <= c_tmp;

	complete_out <= '1' when w.valid or l.valid or m.valid else '0';

	writeback_1: process(all)
	begin
		--assert (unsigned(w.valid) + unsigned(l.valid) + unsigned(m.valid)) <= 1;
		--assert not(w.write_enable = '1' and l.write_enable = '1');

		w_tmp <= WritebackToRegisterFileInit;
		c_tmp <= WritebackToCrFileInit;

		if w.valid = '1' then
			if w.write_enable = '1' then
				w_tmp.write_reg <= w.write_reg;
				w_tmp.write_data <= w.write_data;
				w_tmp.write_enable <= '1';
			end if;

			if w.write_cr_enable = '1' then
				report "Writing CR ";
				c_tmp.write_cr_enable <= '1';
				c_tmp.write_cr_mask <= w.write_cr_mask;
				c_tmp.write_cr_data <= w.write_cr_data;
			end if;
		end if;

		if l.valid = '1' and l.write_enable = '1' then
			w_tmp.write_reg <= l.write_reg;
			w_tmp.write_data <= l.write_data;
			w_tmp.write_enable <= '1';
		end if;
		if l.valid = '1' and l.write_enable2 = '1' then
			w_tmp.write_reg2 <= l.write_reg2;
			w_tmp.write_data2 <= l.write_data2;
			w_tmp.write_enable2 <= '1';
		end if;

		if m.valid = '1' then
			if m.write_reg_enable = '1' then
				w_tmp.write_enable <= '1';
				w_tmp.write_reg <= m.write_reg_nr;
				w_tmp.write_data <= m.write_reg_data;
			end if;
			if m.write_cr_enable = '1' then
				report "Writing CR ";
				c_tmp.write_cr_enable <= '1';
				c_tmp.write_cr_mask <= m.write_cr_mask;
				c_tmp.write_cr_data <= m.write_cr_data;
			end if;
		end if;
	end process;
end;
