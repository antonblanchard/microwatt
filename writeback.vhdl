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
	type reg_internal_type is record
		complete : std_ulogic;
	end record;
	type reg_type is record
		w : WritebackToRegisterFileType;
		c : WritebackToCrFileType;
	end record;
	signal r, rin : reg_type;
	signal r_int, rin_int : reg_internal_type;
begin
	writeback_0: process(clk)
	begin
		if rising_edge(clk) then
			r <= rin;
			r_int <= rin_int;
		end if;
	end process;

	writeback_1: process(all)
		variable x: std_ulogic_vector(0 downto 0);
		variable y: std_ulogic_vector(0 downto 0);
		variable z: std_ulogic_vector(0 downto 0);
		variable v : reg_type;
		variable v_int : reg_internal_type;
	begin
		v := r;
		v_int := r_int;

		x := "" & e_in.valid;
		y := "" & l_in.valid;
		z := "" & m_in.valid;
		assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z))) <= 1;

		x := "" & e_in.write_enable;
		y := "" & l_in.write_enable;
		z := "" & m_in.write_reg_enable;
		assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z))) <= 1;

		assert not(e_in.write_cr_enable = '1' and m_in.write_cr_enable = '1');

		v.w := WritebackToRegisterFileInit;
		v.c := WritebackToCrFileInit;

		v_int.complete := '0';
		if e_in.valid = '1' or l_in.valid = '1' or m_in.valid = '1' then
			v_int.complete := '1';
		end if;

		if e_in.write_enable = '1' then
			v.w.write_reg := e_in.write_reg;
			v.w.write_data := e_in.write_data;
			v.w.write_enable := '1';
		end if;

		if e_in.write_cr_enable = '1' then
			v.c.write_cr_enable := '1';
			v.c.write_cr_mask := e_in.write_cr_mask;
			v.c.write_cr_data := e_in.write_cr_data;
		end if;

		if l_in.write_enable = '1' then
			v.w.write_reg := l_in.write_reg;
			v.w.write_data := l_in.write_data;
			v.w.write_enable := '1';
		end if;

		if m_in.write_reg_enable = '1' then
			v.w.write_enable := '1';
			v.w.write_reg := m_in.write_reg_nr;
			v.w.write_data := m_in.write_reg_data;
		end if;

		if m_in.write_cr_enable = '1' then
			v.c.write_cr_enable := '1';
			v.c.write_cr_mask := m_in.write_cr_mask;
			v.c.write_cr_data := m_in.write_cr_data;
		end if;

		-- Update registers
                rin <= v;
                rin_int <= v_int;

                -- Update outputs
		complete_out <= r_int.complete;
                w_out <= r.w;
                c_out <= r.c;
	end process;
end;
