library ieee;
use ieee.std_logic_1164.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity logic_analyzer is
    generic (
        INPUT_IOS  : integer range 0 to 32;
        OUTPUT_IOS : integer range 0 to 32
        );
    port (
        clk     : in std_ulogic;
        rst     : in std_ulogic;
        wb_in   : in wb_io_master_out;
        wb_out  : out wb_io_slave_out;
        io_in   : in std_ulogic_vector(INPUT_IOS-1 downto 0);
        io_out  : out std_ulogic_vector(OUTPUT_IOS-1 downto 0)
      );
end logic_analyzer;

architecture rtl of logic_analyzer is
    signal we: std_ulogic;
    signal re: std_ulogic;
    signal ack: std_ulogic;
begin
    -- Wishbone interface
    we <= wb_in.stb and wb_in.cyc and wb_in.we;
    re <= wb_in.stb and wb_in.cyc and not wb_in.we;
    wb_out.stall <= '0';
    wb_out.ack <= ack;

    wb_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                io_out <= (others => '0');
                ack <= '0';
            else
		if re = '1' then
                    wb_out.dat(INPUT_IOS-1 downto 0) <= io_in;
                    ack <= '1';
	        elsif  we = '1' then
                    io_out <= wb_in.dat(INPUT_IOS-1 downto 0);
                    ack <= '1';
		else
                    ack <= '0';
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
