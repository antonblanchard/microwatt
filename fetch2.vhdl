library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity fetch2 is
    port(
	clk          : in std_ulogic;
	rst          : in std_ulogic;

	stall_in     : in std_ulogic;
	stall_out    : out std_ulogic;

	flush_in     : in std_ulogic;
	stop_in      : in std_ulogic;

	i_in         : in IcacheToFetch2Type;
	i_out        : out Fetch2ToIcacheType;

	f_in         : in Fetch1ToFetch2Type;

	f_out        : out Fetch2ToDecode1Type
	);
end entity fetch2;

architecture behaviour of fetch2 is
    signal r, rin : Fetch2ToDecode1Type;
begin
    regs : process(clk)
    begin
	if rising_edge(clk) then
	    -- Output state remains unchanged on stall, unless we are flushing
	    if rst = '1' or flush_in = '1' or stall_in = '0' then
		r <= rin;
	    end if;
	end if;
    end process;

    comb : process(all)
	variable v : Fetch2ToDecode1Type;
    begin
	v := r;

	-- asynchronous icache lookup
	i_out.req <= '1';
	i_out.addr <= f_in.nia;
	v.valid := i_in.ack;
	v.nia := f_in.nia;
	v.insn := i_in.insn;
	stall_out <= stop_in or not i_in.ack;

	if flush_in = '1' or stop_in = '1' then
	    v.valid := '0';
	end if;
	v.stop_mark := stop_in;

	-- Update registers
	rin <= v;

	-- Update outputs
	f_out <= r;
    end process;
end architecture behaviour;
