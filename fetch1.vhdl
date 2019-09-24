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
    type reg_internal_type is record
	nia_next : std_ulogic_vector(63 downto 0);
    end record;
    signal r_int, rin_int : reg_internal_type;
    signal r, rin : Fetch1ToFetch2Type;
begin
    regs : process(clk)
    begin
	if rising_edge(clk) then
	    r <= rin;
	    r_int <= rin_int;
	end if;
    end process;

    comb : process(all)
	variable v     : Fetch1ToFetch2Type;
	variable v_int : reg_internal_type;
    begin
	v := r;
	v_int := r_int;

	if stall_in = '0' then
	    v.nia := r_int.nia_next;
	    v_int.nia_next := std_logic_vector(unsigned(r_int.nia_next) + 4);
	end if;

	if e_in.redirect = '1' then
	    v.nia := e_in.redirect_nia;
	    v_int.nia_next := std_logic_vector(unsigned(e_in.redirect_nia) + 4);
	end if;

	if rst = '1' then
	    v.nia := RESET_ADDRESS;
	    v_int.nia_next := std_logic_vector(unsigned(RESET_ADDRESS) + 4);
	end if;

	-- Update registers
	rin <= v;
	rin_int <= v_int;

	-- Update outputs
	f_out <= r;

	report "fetch1 R:" & std_ulogic'image(e_in.redirect) & " v.nia:" & to_hstring(v.nia) & " f_out.nia:" & to_hstring(f_out.nia);

    end process;

end architecture behaviour;
