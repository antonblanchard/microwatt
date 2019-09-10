library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wishbone_types.all;

-- TODO: Use an array of master/slaves with parametric size
entity wishbone_arbiter is
    port (clk     : in std_ulogic;
	  rst     : in std_ulogic;

	  wb1_in  : in wishbone_master_out;
	  wb1_out : out wishbone_slave_out;

	  wb2_in  : in wishbone_master_out;
	  wb2_out : out wishbone_slave_out;

	  wb3_in  : in wishbone_master_out;
	  wb3_out : out wishbone_slave_out;

	  wb_out  : out wishbone_master_out;
	  wb_in   : in wishbone_slave_out
	  );
end wishbone_arbiter;

architecture behave of wishbone_arbiter is
    type wishbone_arbiter_state_t is (IDLE, WB1_BUSY, WB2_BUSY, WB3_BUSY);
    signal state : wishbone_arbiter_state_t := IDLE;
begin

    wishbone_muxes: process(state, wb_in, wb1_in, wb2_in, wb3_in)
    begin
	-- Requests from masters are fully muxed
	wb_out <= wb1_in when state = WB1_BUSY else
		  wb2_in when state = WB2_BUSY else
		  wb3_in when state = WB3_BUSY else
		  wishbone_master_out_init;

	-- Responses from slave don't need to mux the data bus
	wb1_out.dat <= wb_in.dat;
	wb2_out.dat <= wb_in.dat;
	wb3_out.dat <= wb_in.dat;
	wb1_out.ack <= wb_in.ack when state = WB1_BUSY else '0';
	wb2_out.ack <= wb_in.ack when state = WB2_BUSY else '0';
	wb3_out.ack <= wb_in.ack when state = WB3_BUSY else '0';
    end process;

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
		    elsif wb3_in.cyc = '1' then
			state <= WB3_BUSY;
		    end if;
		when WB1_BUSY =>
		    if wb1_in.cyc = '0' then
			state <= IDLE;
		    end if;
		when WB2_BUSY =>
		    if wb2_in.cyc = '0' then
			state <= IDLE;
		    end if;
		when WB3_BUSY =>
		    if wb3_in.cyc = '0' then
			state <= IDLE;
		    end if;
		end case;
	    end if;
	end if;
    end process;
end behave;
