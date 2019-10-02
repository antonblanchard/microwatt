library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cache_ram is
    generic(
	ROW_BITS : integer := 16;
	WIDTH    : integer := 64
	);

    port(
	clk     : in  std_logic;
	rd_en   : in  std_logic;
	rd_addr : in  std_logic_vector(ROW_BITS - 1 downto 0);
	rd_data : out std_logic_vector(WIDTH - 1 downto 0);
	wr_en   : in  std_logic;
	wr_addr : in  std_logic_vector(ROW_BITS - 1 downto 0);
	wr_data : in  std_logic_vector(WIDTH - 1 downto 0)
	);

end cache_ram;

architecture rtl of cache_ram is
    constant SIZE : integer := 2**ROW_BITS;

    type ram_type is array (0 to SIZE - 1) of std_logic_vector(WIDTH - 1 downto 0);
    signal ram : ram_type;
    attribute ram_style : string;
    attribute ram_style of ram : signal is "block";
    attribute ram_decomp : string;
    attribute ram_decomp of ram : signal is "power";

begin
    process(clk)
    begin
	if rising_edge(clk) then
	    if wr_en = '1' then
		ram(to_integer(unsigned(wr_addr))) <= wr_data;
	    end if;
	    if rd_en = '1' then
		rd_data <= ram(to_integer(unsigned(rd_addr)));
	    end if;
	end if;
    end process;
end;
