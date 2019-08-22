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
begin
	-- synchronous writes
	cr_write_0: process(clk)
		variable hi, lo : integer := 0;
	begin
		if rising_edge(clk) then
			if w_in.write_cr_enable = '1' then
				report "Writing " & to_hstring(w_in.write_cr_data) & " to CR mask " & to_hstring(w_in.write_cr_mask);

				for i in 0 to 7 loop
					if w_in.write_cr_mask(i) = '1' then
						lo := i*4;
						hi := lo + 3;
						crs(hi downto lo) <= w_in.write_cr_data(hi downto lo);
					end if;
				end loop;
			end if;
		end if;
	end process cr_write_0;

	-- asynchronous reads
	cr_read_0: process(all)
		variable hi, lo : integer := 0;
	begin
		--lo := (7-d_in.read_cr_nr_1)*4;
		--hi := lo + 3;

		--report "read " & integer'image(d_in.read_cr_nr_1) & " from CR " & to_hstring(crs(hi downto lo));
		--d_out.read_cr_data_1 <= crs(hi downto lo);

		-- Also return the entire CR to make mfcrf easier for now
		report "read CR " & to_hstring(crs);
		d_out.read_cr_data <= crs;

--		-- Forward any written data
--		if w_in.write_cr_enable = '1' then
--			if d_in.read_cr_nr_1 = w_in.write_cr_nr then
--				d_out.read_cr_data_1 <= w_in.write_cr_data;
--			end if;
--			if d_in.read_cr_nr_2 = w_in.write_cr_nr then
--				d_out.read_cr_data_2 <= w_in.write_cr_data;
--			end if;
--		end if;
	end process cr_read_0;
end architecture behaviour;
