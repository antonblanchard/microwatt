-- Based on:
-- The Potato Processor - A simple processor for FPGAs
-- (c) Kristian Klomsten Skordal 2014 - 2015 <kristian.skordal@wafflemail.net>

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;

use work.pp_utilities.all;

--! @brief Simple memory module for use in Wishbone-based systems.
entity mw_soc_memory is
    generic(
	MEMORY_SIZE   : natural := 4096; --! Memory size in bytes.
	RAM_INIT_FILE : string
	);
    port(
	clk : in std_logic;
	rst : in std_logic;

	-- Wishbone interface:
	wishbone_in  : in wishbone_master_out;
	wishbone_out : out wishbone_slave_out
	);
end entity mw_soc_memory;

architecture behaviour of mw_soc_memory is
    -- RAM type definition
    type ram_t is array(0 to (MEMORY_SIZE / 8) - 1) of std_logic_vector(63 downto 0);

    -- RAM loading
    impure function init_ram(name : STRING) return ram_t is
        file ram_file : text open read_mode is name;
        variable ram_line : line;
        variable temp_word : std_logic_vector(63 downto 0);
        variable temp_ram : ram_t := (others => (others => '0'));
    begin
        for i in 0 to (MEMORY_SIZE/8)-1 loop
            exit when endfile(ram_file);
            readline(ram_file, ram_line);
            hread(ram_line, temp_word);
            temp_ram(i) := temp_word;
        end loop;

        return temp_ram;
    end function;

    -- RAM instance
    signal memory : ram_t := init_ram(RAM_INIT_FILE);
    attribute ram_style : string;
    attribute ram_style of memory : signal is "block";
    attribute ram_decomp : string;
    attribute ram_decomp of memory : signal is "power";

    -- RAM interface
    constant ram_addr_bits : integer := log2(MEMORY_SIZE) - 3;
    signal ram_addr : std_logic_vector(ram_addr_bits - 1 downto 0);
    signal ram_di   : std_logic_vector(63 downto 0);
    signal ram_do   : std_logic_vector(63 downto 0);
    signal ram_sel  : std_logic_vector(7 downto 0);
    signal ram_we   : std_ulogic;

    -- Others
    signal ram_obuf      : std_logic_vector(63 downto 0);
    signal ack, ack_obuf : std_ulogic;
begin

    -- Actual RAM template    
    memory_0: process(clk)
    begin
	if rising_edge(clk) then
	    if ram_we = '1' then
		for i in 0 to 7 loop
		    if ram_sel(i) = '1' then
			memory(conv_integer(ram_addr))((i + 1) * 8 - 1 downto i * 8) <=
			    ram_di((i + 1) * 8 - 1 downto i * 8);
		    end if;
		end loop;
	    end if;
	    ram_do <= memory(conv_integer(ram_addr));
	    ram_obuf <= ram_do;
	end if;
    end process;

    -- Wishbone interface
    ram_addr <= wishbone_in.adr(ram_addr_bits + 2 downto 3);
    ram_di <= wishbone_in.dat;
    ram_sel <= wishbone_in.sel;
    ram_we <= wishbone_in.we and wishbone_in.stb and wishbone_in.cyc;
    wishbone_out.stall <= '0';
    wishbone_out.ack <= ack_obuf;
    wishbone_out.dat <= ram_obuf;

    wb_0: process(clk)
    begin
	if rising_edge(clk) then
	    if rst = '1' or wishbone_in.cyc = '0' then
		ack_obuf <= '0';
		ack <= '0';
	    else
		ack <= wishbone_in.stb;
		ack_obuf <= ack;
	    end if;
	end if;
    end process;

end architecture behaviour;
