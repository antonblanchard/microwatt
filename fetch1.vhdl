library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity fetch1 is
    generic(
	RESET_ADDRESS : std_logic_vector(63 downto 0) := (others => '0')
	);
    port(
	clk           : in std_ulogic;
	rst           : in std_ulogic;

	-- Control inputs:
	stall_in      : in std_ulogic;
	flush_in      : in std_ulogic;

	-- redirect from execution unit
	e_in          : in Execute1ToFetch1Type;

	-- fetch data out
	f_out         : out Fetch1ToFetch2Type
	);
end entity fetch1;

architecture behaviour of fetch1 is
    signal r, r_next : Fetch1ToFetch2Type;
begin

    regs : process(clk)
    begin
	if rising_edge(clk) then
	    if rst = '1' or e_in.redirect = '1' or stall_in = '0' then
		r <= r_next;
	    end if;
	end if;
    end process;

    comb : process(all)
	variable v : Fetch1ToFetch2Type;
    begin
	v := r;

	if rst = '1' then
	    v.nia :=  RESET_ADDRESS;
	elsif e_in.redirect = '1' then
	    v.nia := e_in.redirect_nia;
	else
	    v.nia := std_logic_vector(unsigned(v.nia) + 4);
	end if;

	r_next <= v;

	-- Update outputs to the icache
	f_out <= r;

	report "fetch1 rst:" & std_ulogic'image(rst) &
	    " R:" & std_ulogic'image(e_in.redirect) &
	    " S:" & std_ulogic'image(stall_in) &
	    " nia_next:" & to_hstring(r_next.nia) &
	    " nia:" & to_hstring(r.nia);

    end process;

end architecture behaviour;
