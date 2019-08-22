library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;

package crhelpers is
	function fxm_to_num(fxm: std_ulogic_vector(7 downto 0)) return integer;
	function num_to_fxm(num: integer) return std_ulogic_vector;
	--function from_crfile(cr: crfile) return std_ulogic_vector;
	--function extract_one_crfield(cr: crfile; fxm: std_ulogic_vector(7 downto 0)) return std_ulogic_vector;
	--function insert_multiple_crfields(cr_in: crfile; rs: std_ulogic_vector(63 downto 0); fxm: std_ulogic_vector(7 downto 0)) return crfile;
	--function insert_one_crfield(cr_in: crfile; rs: std_ulogic_vector(63 downto 0); fxm: std_ulogic_vector(7 downto 0)) return crfile;
end package crhelpers;

package body crhelpers is

	function fxm_to_num(fxm: std_ulogic_vector(7 downto 0)) return integer is
	begin
		-- If multiple fields are set (undefined), match existing
		-- hardware by returning the first one.
		for i in 0 to 7 loop
			-- Big endian bit numbering
			if fxm(7-i) = '1' then
				return i;
			end if;
		end loop;

		-- If no fields are set (undefined), also match existing
		-- hardware by returning cr7.
		return 7;
	end;

	function num_to_fxm(num: integer) return std_ulogic_vector is
	begin
		case num is
			when 0 =>
				return "10000000";
			when 1 =>
				return "01000000";
			when 2 =>
				return "00100000";
			when 3 =>
				return "00010000";
			when 4 =>
				return "00001000";
			when 5 =>
				return "00000100";
			when 6 =>
				return "00000010";
			when 7 =>
				return "00000001";
			when others =>
				return "00000000";
		end case;
	end;

--	function from_crfile(cr: crfile) return std_ulogic_vector is
--		variable combined_cr : std_ulogic_vector(31 downto 0) := (others => '0');
--		variable high, low: integer range 0 to 31 := 0;
--	begin
--		for i in 0 to cr'length-1 loop
--			low := 4*(7-i);
--			high := low+3;
--			combined_cr(high downto low) := cr(i);
--		end loop;
--
--		return combined_cr;
--	end function;
--
--	function extract_one_crfield(cr: crfile; fxm: std_ulogic_vector(7 downto 0)) return std_ulogic_vector is
--		variable combined_cr : std_ulogic_vector(63 downto 0) := (others => '0');
--		variable crnum: integer range 0 to 7 := 0;
--	begin
--		crnum := fxm_to_num(fxm);
--
--		-- Vivado doesn't support non constant vector slice
--		-- low := 4*(7-crnum);
--		-- high := low+3;
--		-- combined_cr(high downto low) := cr(crnum);
--		case_0: case crnum is
--		when 0 =>
--		    combined_cr(31 downto 28) := cr(0);
--		when 1 =>
--		    combined_cr(27 downto 24) := cr(1);
--		when 2 =>
--		    combined_cr(23 downto 20) := cr(2);
--		when 3 =>
--		    combined_cr(19 downto 16) := cr(3);
--		when 4 =>
--		    combined_cr(15 downto 12) := cr(4);
--		when 5 =>
--		    combined_cr(11 downto 8) := cr(5);
--		when 6 =>
--		    combined_cr(7 downto 4) := cr(6);
--		when 7 =>
--		    combined_cr(3 downto 0) := cr(7);
--		end case;
--
--		return combined_cr;
--	end;
--
--	function insert_multiple_crfields(cr_in: crfile; rs: std_ulogic_vector(63 downto 0); fxm: std_ulogic_vector(7 downto 0)) return crfile is
--		variable cr : crfile;
--		variable combined_cr : std_ulogic_vector(63 downto 0) := (others => '0');
--		variable high, low: integer range 0 to 31 := 0;
--	begin
--		cr := cr_in;
--
--		for i in 0 to 7 loop
--			-- BE bit numbering
--			if fxm(7-i) = '1' then
--				low := 4*(7-i);
--				high := low+3;
--				cr(i) := rs(high downto low);
--			end if;
--		end loop;
--
--		return cr;
--	end;
--
--	function insert_one_crfield(cr_in: crfile; rs: std_ulogic_vector(63 downto 0); fxm: std_ulogic_vector(7 downto 0)) return crfile is
--		variable cr : crfile;
--		variable crnum: integer range 0 to 7 := 0;
--		variable high, low: integer range 0 to 31 := 0;
--	begin
--		cr := cr_in;
--		crnum := fxm_to_num(fxm);
--		low := 4*(7-crnum);
--		high := low+3;
--		cr(crnum) := rs(high downto low);
--		return cr;
--	end;
end package body crhelpers;
