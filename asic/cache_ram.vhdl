library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity cache_ram is
    generic(
        ROW_BITS : integer := 5;
        WIDTH    : integer := 64;
        TRACE    : boolean := false;
        ADD_BUF  : boolean := false
        );

    port(
        clk     : in std_logic;

        rd_en   : in std_logic;
        rd_addr : in std_logic_vector(ROW_BITS - 1 downto 0);
        rd_data : out std_logic_vector(WIDTH - 1 downto 0);

        wr_sel  : in std_logic_vector(WIDTH/8 - 1 downto 0);
        wr_addr : in std_logic_vector(ROW_BITS - 1 downto 0);
        wr_data : in std_logic_vector(WIDTH - 1 downto 0)
        );

end cache_ram;

architecture rtl of cache_ram is
    component RAM32_1RW1R port(
        CLK     : in std_logic;

        EN0     : in std_logic;
        A0      : in std_logic_vector(4 downto 0);
        WE0     : in std_logic_vector(7 downto 0);
        Di0     : in std_logic_vector(63 downto 0);
        Do0     : out std_logic_vector(63 downto 0);

        EN1     : in std_logic;
        A1      : in std_logic_vector(4 downto 0);
        Do1     : out std_logic_vector(63 downto 0)
        );
    end component;

    signal wr_enable: std_logic;
    signal rd_data0_tmp : std_logic_vector(WIDTH - 1 downto 0);
    signal rd_data0_saved : std_logic_vector(WIDTH - 1 downto 0);
    signal rd_data0 : std_logic_vector(WIDTH - 1 downto 0);
    signal rd_en_prev: std_ulogic;
begin
    assert (ROW_BITS = 5)  report "ROW_BITS must be 5" severity FAILURE;
    assert (WIDTH = 64)    report "Must be 64 bit" severity FAILURE;
    assert (TRACE = false) report "Trace not supported" severity FAILURE;

    wr_enable <= or(wr_sel);

    cache_ram_0 : RAM32_1RW1R
        port map (
            CLK     => clk,

            EN0     => wr_enable,
            A0      => wr_addr,
            WE0     => wr_sel,
            Di0     => wr_data,
            Do0     => open,

            EN1     => rd_en,
            A1      => rd_addr,
            Do1     => rd_data0_tmp
            );

    -- The caches rely on cache_ram latching the last read. Handle it here
    -- for now.
    process(clk)
    begin
        if rising_edge(clk) then
            rd_en_prev <= rd_en;
            if rd_en_prev = '1' then
                rd_data0_saved <= rd_data0_tmp;
            end if;
        end if;
    end process;
    rd_data0 <= rd_data0_tmp when rd_en_prev = '1' else rd_data0_saved;

    buf: if ADD_BUF generate
    begin
        process(clk)
        begin
            if rising_edge(clk) then
                rd_data <= rd_data0;
            end if;
        end process;
    end generate;

    nobuf: if not ADD_BUF generate
    begin
        rd_data <= rd_data0;
    end generate;

end architecture rtl;
