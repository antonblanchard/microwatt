library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity cr_file is
	port(
		clk   : in std_logic;

		d_in  : in Decode2ToCrFileType;
		d_out : out CrFileToDecode2Type;

		w_in  : in WritebackToCrFileType
	);
end entity cr_file;

architecture behaviour of cr_file is
	signal crs : std_ulogic_vector(31 downto 0) := (others => '0');
	signal crs_updated : std_ulogic_vector(31 downto 0) := (others => '0');
begin
	cr_create_0: process(all)
		variable hi, lo : integer := 0;
	begin
		for i in 0 to 7 loop
			if w_in.write_cr_mask(i) = '1' then
				lo := i*4;
				hi := lo + 3;
				crs_updated(hi downto lo) <= w_in.write_cr_data(hi downto lo);
			end if;
		end loop;
	end process;

	-- synchronous writes
	cr_write_0: process(clk)
	begin
		if rising_edge(clk) then
			if w_in.write_cr_enable = '1' then
				report "Writing " & to_hstring(w_in.write_cr_data) & " to CR mask " & to_hstring(w_in.write_cr_mask);
				crs <= crs_updated;
			end if;
		end if;
	end process;

	-- asynchronous reads
	cr_read_0: process(all)
		variable hi, lo : integer := 0;
	begin
		-- just return the entire CR to make mfcrf easier for now
		if d_in.read = '1' then
			report "Reading CR " & to_hstring(crs_updated);
		end if;
		if w_in.write_cr_enable then
			d_out.read_cr_data <= crs_updated;
		else
			d_out.read_cr_data <= crs;
		end if;
	end process;
end architecture behaviour;
