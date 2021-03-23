library ieee;
use ieee.std_logic_1164.all;

library work;

entity main_bram is
    generic(
        WIDTH        : natural := 64;
        HEIGHT_BITS  : natural := 11;
        MEMORY_SIZE  : natural := (8*1024);
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

    signal obuf : std_logic_vector(WIDTH-1 downto 0);
begin
    assert (WIDTH = 64)         report "Must be 64 bit" severity FAILURE;
    -- Do we have a log2 round up issue here?
    assert (HEIGHT_BITS = 10)   report "HEIGHT_BITS must be 10" severity FAILURE;
    assert (MEMORY_SIZE = 4096) report "MEMORY_SIZE must be 4096" severity FAILURE;

    sel_qual <= sel when we = '1' else (others => '0');

    memory_0 : RAM512
        port map (
            CLK  => clk,
            WE0  => sel_qual(7 downto 0),
            EN0  => re or we,
            Di0  => din(63 downto 0),
            Do0  => obuf(63 downto 0),
            A0   => addr(8 downto 0)
            );

    -- The wishbone BRAM wrapper assumes a 1 cycle delay
    memory_read_buffer: process(clk)
    begin
        if rising_edge(clk) then
            dout <= obuf;
        end if;
    end process;
end architecture behaviour;
