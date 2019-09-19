library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wishbone_types.all;

entity wishbone_arbiter is
    port (
        clk     : in std_ulogic;
        rst     : in std_ulogic;

        wb1_in  : in wishbone_master_out;
        wb1_out : out wishbone_slave_out;

        wb2_in  : in wishbone_master_out;
        wb2_out : out wishbone_slave_out;

        wb_out  : out wishbone_master_out;
        wb_in   : in wishbone_slave_out
        );
end wishbone_arbiter;

architecture behave of wishbone_arbiter is
    type wishbone_arbiter_state_t is (IDLE, WB1_BUSY, WB2_BUSY);
    signal state : wishbone_arbiter_state_t := IDLE;
begin
    wb1_out <= wb_in when state = WB1_BUSY else wishbone_slave_out_init;
    wb2_out <= wb_in when state = WB2_BUSY else wishbone_slave_out_init;

    wb_out <= wb1_in when state = WB1_BUSY else wb2_in when state = WB2_BUSY else wishbone_master_out_init;

    wishbone_arbiter_process: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
            else
                case state is
                    when IDLE =>
                        if wb1_in.cyc = '1' then
                            state <= WB1_BUSY;
                        elsif wb2_in.cyc = '1' then
                            state <= WB2_BUSY;
                        end if;
                    when WB1_BUSY =>
                        if wb1_in.cyc = '0' then
                            state <= IDLE;
                        end if;
                    when WB2_BUSY =>
                        if wb2_in.cyc = '0' then
                            state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;
end behave;
