library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.helpers.all;
use work.wishbone_types.all;

-- 2 cycle LSU
-- In this cycle we read or write any data and do sign extension and update if required.

entity loadstore2 is
	port (
		clk   : in std_ulogic;

		l_in  : in Loadstore1ToLoadstore2Type;
		w_out : out Loadstore2ToWritebackType;

		m_in  : in wishbone_slave_out;
		m_out : out wishbone_master_out
	);
end loadstore2;

architecture behave of loadstore2 is
	signal l_saved : Loadstore1ToLoadstore2Type;
	signal w_tmp   : Loadstore2ToWritebackType;
	signal m_tmp   : wishbone_master_out;

	type state_t is (IDLE, WAITING_FOR_READ_ACK, WAITING_FOR_WRITE_ACK);
	signal state   : state_t := IDLE;

	function length_to_sel(length : in std_logic_vector(3 downto 0)) return std_ulogic_vector is
	begin
		case length is
			when "0001" =>
				return "00000001";
			when "0010" =>
				return "00000011";
			when "0100" =>
				return "00001111";
			when "1000" =>
				return "11111111";
			when others =>
				return "00000000";
		end case;
	end function length_to_sel;

	function wishbone_data_shift(address : in std_ulogic_vector(63 downto 0)) return natural is
	begin
		return to_integer(unsigned(address(2 downto 0))) * 8;
	end function wishbone_data_shift;

	function wishbone_data_sel(size : in std_logic_vector(3 downto 0); address : in std_logic_vector(63 downto 0)) return std_ulogic_vector is
	begin
		return std_ulogic_vector(shift_left(unsigned(length_to_sel(size)), to_integer(unsigned(address(2 downto 0)))));
	end function wishbone_data_sel;
begin
	w_out <= w_tmp;
	m_out <= m_tmp;

	loadstore2_0: process(clk)
		variable tmp : std_ulogic_vector(63 downto 0);
		variable data : std_ulogic_vector(63 downto 0);
	begin
		if rising_edge(clk) then
			tmp := (others => '0');
			data := (others => '0');

			w_tmp <= Loadstore2ToWritebackInit;

			l_saved <= l_saved;

			case_0: case state is
			when IDLE =>
				if l_in.valid = '1' then
					m_tmp <= wishbone_master_out_init;

					m_tmp.sel <= wishbone_data_sel(l_in.length, l_in.addr);
					m_tmp.adr <= l_in.addr(63 downto 3) & "000";
					m_tmp.cyc <= '1';
					m_tmp.stb <= '1';

					if l_in.load = '1' then
						m_tmp.we <= '0';

						l_saved <= l_in;
						state <= WAITING_FOR_READ_ACK;
					else
						m_tmp.we <= '1';

						w_tmp.valid <= '1';

						data := l_in.data;
						if l_in.byte_reverse = '1' then
							data := byte_reverse(data, to_integer(unsigned(l_in.length)));
						end if;

						m_tmp.dat <= std_logic_vector(shift_left(unsigned(data), wishbone_data_shift(l_in.addr)));

						assert l_in.sign_extend = '0' report "sign extension doesn't make sense for stores" severity failure;

						if l_in.update = '1' then
							w_tmp.write_enable <= '1';
							w_tmp.write_reg <= l_in.update_reg;
							w_tmp.write_data <= l_in.addr;
						end if;

						state <= WAITING_FOR_WRITE_ACK;
					end if;
				end if;

			when WAITING_FOR_READ_ACK =>
				if m_in.ack = '1' then
					tmp := std_logic_vector(shift_right(unsigned(m_in.dat), wishbone_data_shift(l_saved.addr)));
					case to_integer(unsigned(l_saved.length)) is
					when 0 =>
					when 1 =>
					        data(7 downto 0) := tmp(7 downto 0);
					when 2 =>
					        data(15 downto 0) := tmp(15 downto 0);
					when 4 =>
					        data(31 downto 0) := tmp(31 downto 0);
					when 8 =>
					        data(63 downto 0) := tmp(63 downto 0);
					when others =>
						assert false report "invalid length" severity failure;
					end case;

					if l_saved.sign_extend = '1' then
						data := sign_extend(data, to_integer(unsigned(l_saved.length)));
					end if;

					if l_saved.byte_reverse = '1' then
						data := byte_reverse(data, to_integer(unsigned(l_saved.length)));
					end if;

					w_tmp.write_data <= data;

					-- write data to register file
					w_tmp.valid <= '1';
					w_tmp.write_enable <= '1';
					w_tmp.write_reg <= l_saved.write_reg;

					if l_saved.update = '1' then
						w_tmp.write_enable2 <= '1';
						w_tmp.write_reg2 <= l_saved.update_reg;
						w_tmp.write_data2 <= l_saved.addr;
					end if;

					m_tmp <= wishbone_master_out_init;
					state <= IDLE;
				end if;

			when WAITING_FOR_WRITE_ACK =>
				if m_in.ack = '1' then
					m_tmp <= wishbone_master_out_init;
					state <= IDLE;
				end if;
			end case;
		end if;
	end process;
end;
