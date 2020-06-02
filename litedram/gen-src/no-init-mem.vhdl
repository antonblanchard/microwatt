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

    wb_out.dat <= (others => '0');
    wb_out.stall <= '0';
    wb_out.ack <= wb_in.stb and wb_in.cyc;

end architecture rtl;
