library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cache_ram is
    generic(
	ROW_BITS : integer := 16;
	WIDTH    : integer := 64;
	TRACE    : boolean := false
	);

    port(
	clk     : in  std_logic;
	rd_en   : in  std_logic;
	rd_addr : in  std_logic_vector(ROW_BITS - 1 downto 0);
	rd_data : out std_logic_vector(WIDTH - 1 downto 0);
	wr_en   : in  std_logic;
	wr_sel  : in  std_logic_vector(WIDTH/8 - 1 downto 0);
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
	variable lbit : integer range 0 to WIDTH - 1;
	variable mbit : integer range 0 to WIDTH - 1;
	variable widx : integer range 0 to SIZE - 1;
    begin
	if rising_edge(clk) then
	    if wr_en = '1' then
		if TRACE then
		    report "write a:" & to_hstring(wr_addr) &
			" sel:" & to_hstring(wr_sel) &
			" dat:" & to_hstring(wr_data);
		end if;
		for i in 0 to WIDTH/8-1 loop
		    lbit := i * 8;
		    mbit := lbit + 7;
		    widx := to_integer(unsigned(wr_addr));
		    if wr_sel(i) = '1' then
			ram(widx)(mbit downto lbit) <= wr_data(mbit downto lbit);
		    end if;
		end loop;
	    end if;
	    if rd_en = '1' then
		rd_data <= ram(to_integer(unsigned(rd_addr)));
		if TRACE then
		    report "read a:" & to_hstring(rd_addr) &
			" dat:" & to_hstring(ram(to_integer(unsigned(rd_addr))));
		end if;
	    end if;
	end if;
    end process;
end;
