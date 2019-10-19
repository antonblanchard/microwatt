-- Based on:
-- The Potato Processor - A simple processor for FPGAs
-- (c) Kristian Klomsten Skordal 2014 - 2015 <kristian.skordal@wafflemail.net>

library ieee;
use ieee.std_logic_1164.all;
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
    signal wb_adr_in : std_logic_vector(log2(MEMORY_SIZE) - 1 downto 0);
    type ram_t is array(0 to (MEMORY_SIZE / 8) - 1) of std_logic_vector(63 downto 0);

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

    signal memory : ram_t := init_ram(RAM_INIT_FILE);

    attribute ram_style : string;
    attribute ram_style of memory : signal is "block";

    attribute ram_decomp : string;
    attribute ram_decomp of memory : signal is "power"; 

    type state_type is (IDLE, ACK);
    signal state : state_type;

    signal read_ack : std_logic;

begin

    wb_adr_in <= wishbone_in.adr(log2(MEMORY_SIZE) - 1 downto 0);

    wishbone_out.ack <= read_ack and wishbone_in.cyc and wishbone_in.stb;
    wishbone_out.stall <= '0' when wishbone_in.cyc = '0' else not wishbone_out.ack;

    memory_0: process(clk)
    begin
	if rising_edge(clk) then
	    if rst = '1' then
		read_ack <= '0';
		state <= IDLE;
	    else
		if wishbone_in.cyc = '1' then
		    case state is
		    when IDLE =>
			if wishbone_in.stb = '1' and wishbone_in.we = '1' then
			    for i in 0 to 7 loop
				if wishbone_in.sel(i) = '1' then
				    memory(to_integer(unsigned(wb_adr_in(wb_adr_in'left downto 3))))(((i + 1) * 8) - 1 downto i * 8)
					<= wishbone_in.dat(((i + 1) * 8) - 1 downto i * 8);
				end if;
			    end loop;
			    read_ack <= '1';
			    state <= ACK;
			elsif wishbone_in.stb = '1' then
			    wishbone_out.dat <= memory(to_integer(unsigned(wb_adr_in(wb_adr_in'left downto 3))));
			    read_ack <= '1';
			    state <= ACK;
			end if;
		    when ACK =>
			read_ack <= '0';
			state <= IDLE;
		    end case;
		else
		    state <= IDLE;
		    read_ack <= '0';
		end if;
	    end if;
	end if;
    end process;

end architecture behaviour;
