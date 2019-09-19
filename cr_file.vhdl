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
        variable cr_tmp : std_ulogic_vector(31 downto 0) := (others => '0');
    begin
        cr_tmp := crs;

        for i in 0 to 7 loop
            if w_in.write_cr_mask(i) = '1' then
                lo := i*4;
                hi := lo + 3;
                cr_tmp(hi downto lo) := w_in.write_cr_data(hi downto lo);
            end if;
        end loop;

        crs_updated <= cr_tmp;
    end process;

    -- synchronous writes
    cr_write_0: process(clk)
    begin
        if rising_edge(clk) then
            if w_in.write_cr_enable = '1' then
                report "Writing " & to_hstring(w_in.write_cr_data) & " to CR mask " & to_hstring(w_in.write_cr_mask);
            end if;
            crs <= crs_updated;
        end if;
    end process;

    -- asynchronous reads
    cr_read_0: process(all)
    begin
        -- just return the entire CR to make mfcrf easier for now
        if d_in.read = '1' then
            report "Reading CR " & to_hstring(crs_updated);
        end if;
        d_out.read_cr_data <= crs_updated;
    end process;
end architecture behaviour;
