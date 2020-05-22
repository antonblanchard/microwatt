library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;

entity dram_init_mem is
    port (
        clk     : in std_ulogic;
        wb_in	: in wb_io_master_out;
        wb_out	: out wb_io_slave_out
      );
end entity dram_init_mem;

architecture rtl of dram_init_mem is

    constant INIT_RAM_SIZE : integer := 16384;
    constant INIT_RAM_ABITS :integer := 14;
    constant INIT_RAM_FILE : string := "litedram/generated/sim/litedram_core.init";

    type ram_t is array(0 to (INIT_RAM_SIZE / 4) - 1) of std_logic_vector(31 downto 0);

    impure function init_load_ram(name : string) return ram_t is
	file ram_file : text open read_mode is name;
	variable temp_word : std_logic_vector(63 downto 0);
	variable temp_ram : ram_t := (others => (others => '0'));
	variable ram_line : line;
    begin
	for i in 0 to (INIT_RAM_SIZE/8)-1 loop
	    exit when endfile(ram_file);
	    readline(ram_file, ram_line);
	    hread(ram_line, temp_word);
	    temp_ram(i*2) := temp_word(31 downto 0);
	    temp_ram(i*2+1) := temp_word(63 downto 32);
	end loop;
	return temp_ram;
    end function;

    signal init_ram : ram_t := init_load_ram(INIT_RAM_FILE);

    attribute ram_style : string;
    attribute ram_style of init_ram: signal is "block";

begin

    init_ram_0: process(clk)
	variable adr : integer;
    begin
	if rising_edge(clk) then
	    wb_out.ack <= '0';
	    if (wb_in.cyc and wb_in.stb) = '1' then
		adr := to_integer((unsigned(wb_in.adr(INIT_RAM_ABITS-1 downto 2))));
		if wb_in.we = '0' then
		    wb_out.dat <= init_ram(adr);
		else
		    for i in 0 to 3 loop
			if wb_in.sel(i) = '1' then
			    init_ram(adr)(((i + 1) * 8) - 1 downto i * 8) <=
				wb_in.dat(((i + 1) * 8) - 1 downto i * 8);
			end if;
		    end loop;
		end if;
		wb_out.ack <= '1';
	    end if;
	end if;
    end process;

    wb_out.stall <= '0';

end architecture rtl;
