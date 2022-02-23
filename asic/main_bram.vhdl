library ieee;
use ieee.std_logic_1164.all;

library work;

entity main_bram is
    generic(
        WIDTH        : natural := 64;
        HEIGHT_BITS  : natural;
        MEMORY_SIZE  : natural;
        RAM_INIT_FILE : string
        );
    port(
        clk  : in std_logic;
        addr : in std_logic_vector(HEIGHT_BITS - 1 downto 0) ;
        din  : in std_logic_vector(WIDTH-1 downto 0);
        dout : out std_logic_vector(WIDTH-1 downto 0);
        sel  : in std_logic_vector((WIDTH/8)-1 downto 0);
        re   : in std_ulogic;
        we   : in std_ulogic
        );
end entity main_bram;

architecture behaviour of main_bram is
    component RAM512 port (
        CLK : in std_ulogic;
        WE0 : in std_ulogic_vector(7 downto 0);
        EN0 : in std_ulogic;
        Di0 : in std_ulogic_vector(63 downto 0);
        Do0 : out std_ulogic_vector(63 downto 0);
        A0  : in std_ulogic_vector(8 downto 0)
    );
    end component;

    signal sel_qual: std_ulogic_vector((WIDTH/8)-1 downto 0);

    signal addr_buf : std_logic_vector(HEIGHT_BITS-1 downto 0);
    signal din_buf : std_logic_vector(WIDTH-1 downto 0);
    signal sel_buf : std_logic_vector((WIDTH/8)-1 downto 0);
    signal re_buf : std_ulogic;
    signal we_buf : std_ulogic;
begin
    assert (WIDTH = 64)         report "Must be 64 bit" severity FAILURE;
    -- Do we have a log2 round up issue here?
    assert (HEIGHT_BITS = 9)    report "HEIGHT_BITS must be 10" severity FAILURE;
    assert (MEMORY_SIZE = 4096) report "MEMORY_SIZE must be 4096" severity FAILURE;

    sel_qual <= sel_buf when we_buf = '1' else (others => '0');

    memory_0 : RAM512
        port map (
            CLK  => clk,
            WE0  => sel_qual(7 downto 0),
            EN0  => re_buf or we_buf,
            Di0  => din_buf(63 downto 0),
            Do0  => dout(63 downto 0),
            A0   => addr_buf(8 downto 0)
            );

    -- The wishbone BRAM wrapper assumes a 1 cycle delay.
    -- Since the DFFRAM already registers outputs, place this on the input side.
    memory_read_buffer: process(clk)
    begin
        if rising_edge(clk) then
            addr_buf <= addr;
            din_buf <= din;
            sel_buf <= sel;
            re_buf <= re;
            we_buf <= we;
        end if;
    end process;
end architecture behaviour;
