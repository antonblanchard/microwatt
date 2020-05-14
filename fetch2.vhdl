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
	flush_in     : in std_ulogic;

	-- Results from icache
	i_in         : in IcacheToFetch2Type;

	-- Output to decode
	f_out        : out Fetch2ToDecode1Type
	);
end entity fetch2;

architecture behaviour of fetch2 is

    -- The icache cannot stall, so we need to stash a cycle
    -- of output from it when we stall.
    type reg_internal_type is record
	stash       : IcacheToFetch2Type;
	stash_valid : std_ulogic;
	stopped     : std_ulogic;
    end record;

    signal r_int, rin_int : reg_internal_type;
    signal r, rin : Fetch2ToDecode1Type;

begin
    regs : process(clk)
    begin
	if rising_edge(clk) then

	    if (r /= rin) then
		report "fetch2 rst:" & std_ulogic'image(rst) &
		    " S:" & std_ulogic'image(stall_in) &
		    " F:" & std_ulogic'image(flush_in) &
		    " T:" & std_ulogic'image(rin.stop_mark) &
		    " V:" & std_ulogic'image(rin.valid) &
                    " FF:" & std_ulogic'image(rin.fetch_failed) &
		    " nia:" & to_hstring(rin.nia);
	    end if;

	    -- Output state remains unchanged on stall, unless we are flushing
	    if rst = '1' or flush_in = '1' or stall_in = '0' then
		r <= rin;
	    end if;

	    -- Internal state is updated on every clock
	    r_int <= rin_int;
	end if;
    end process;

    comb : process(all)
	variable v      : Fetch2ToDecode1Type;
	variable v_int  : reg_internal_type;
	variable v_i_in : IcacheToFetch2Type;
    begin
	v := r;
	v_int := r_int;

	-- If stalling, stash away the current input from the icache
	if stall_in = '1' and v_int.stash_valid = '0' then
	    v_int.stash := i_in;
	    v_int.stash_valid := '1';
	end if;

	-- If unstalling, source input from the stash and invalidate it,
	-- otherwise source normally from the icache.
	--
	v_i_in := i_in;
	if v_int.stash_valid = '1' and stall_in = '0' then
	    v_i_in := v_int.stash;
	    v_int.stash_valid := '0';
	end if;

	v.valid := v_i_in.valid;
	v.stop_mark := v_i_in.stop_mark;
        v.fetch_failed := v_i_in.fetch_failed;
	v.nia := v_i_in.nia;
	v.insn := v_i_in.insn;

	-- Clear stash internal valid bit on flush. We still mark
	-- the stash itself as valid since we still want to override
	-- whatever comes form icache when unstalling, but we'll
	-- override it with something invalid.
	--
	if flush_in = '1' then
	    v_int.stash.valid := '0';
            v_int.stash.fetch_failed := '0';
	end if;

	-- If we are flushing or the instruction comes with a stop mark
	-- we tag it as invalid so it doesn't get decoded and executed
	if flush_in = '1' or v.stop_mark = '1' then
	    v.valid := '0';
            v.fetch_failed := '0';
	end if;

	-- Clear stash on reset
	if rst = '1' then
	    v_int.stash_valid := '0';
            v.valid := '0';
	end if;

	-- Update registers
	rin <= v;
	rin_int <= v_int;

	-- Update outputs
	f_out <= r;
    end process;

end architecture behaviour;
