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
    type wb_arb_master_t is (WB1, WB2, WB3);
    signal candidate, selected : wb_arb_master_t;
begin

    wishbone_muxes: process(selected, wb_in, wb1_in, wb2_in, wb3_in)
    begin
	-- Requests from masters are fully muxed
	wb_out <= wb1_in when selected = WB1 else
		  wb2_in when selected = WB2 else
		  wb3_in when selected = WB3;

	-- Responses from slave don't need to mux the data bus
	wb1_out.dat <= wb_in.dat;
	wb2_out.dat <= wb_in.dat;
	wb3_out.dat <= wb_in.dat;
	wb1_out.ack <= wb_in.ack when selected = WB1 else '0';
	wb2_out.ack <= wb_in.ack when selected = WB2 else '0';
	wb3_out.ack <= wb_in.ack when selected = WB3 else '0';
	wb1_out.stall <= wb_in.stall when selected = WB1 else '1';
	wb2_out.stall <= wb_in.stall when selected = WB2 else '1';
	wb3_out.stall <= wb_in.stall when selected = WB3 else '1';
    end process;

    -- Candidate selection is dumb, priority order... we could
    -- instead consider some form of fairness but it's not really
    -- an issue at the moment.
    --
    wishbone_candidate: process(wb1_in.cyc, wb2_in.cyc, wb3_in.cyc)
    begin
	if wb1_in.cyc = '1' then
	    candidate <= WB1;
	elsif wb2_in.cyc = '1' then
	    candidate <= WB2;
	elsif wb3_in.cyc = '1' then
	    candidate <= WB3;
	else
	    candidate <= selected;
	end if;
    end process;

    wishbone_arbiter_process: process(clk)
    begin
	if rising_edge(clk) then
	    if rst = '1' then
		selected <= WB1;
	    elsif wb_out.cyc = '0' then
		selected <= candidate;
	    end if;
	end if;
    end process;
end behave;
