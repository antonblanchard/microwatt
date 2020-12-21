library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity fetch1 is
    generic(
	RESET_ADDRESS     : std_logic_vector(63 downto 0) := (others => '0');
	ALT_RESET_ADDRESS : std_logic_vector(63 downto 0) := (others => '0')
	);
    port(
	clk           : in std_ulogic;
	rst           : in std_ulogic;

	-- Control inputs:
	stall_in      : in std_ulogic;
	flush_in      : in std_ulogic;
	stop_in       : in std_ulogic;
	alt_reset_in  : in std_ulogic;

	-- redirect from execution unit
	e_in          : in Execute1ToFetch1Type;

        -- redirect from decode1
        d_in          : in Decode1ToFetch1Type;

	-- Request to icache
	i_out         : out Fetch1ToIcacheType;

        -- outputs to logger
        log_out       : out std_ulogic_vector(42 downto 0)
	);
end entity fetch1;

architecture behaviour of fetch1 is
    type reg_internal_t is record
        mode_32bit: std_ulogic;
    end record;
    signal r, r_next : Fetch1ToIcacheType;
    signal r_int, r_next_int : reg_internal_t;
    signal log_nia : std_ulogic_vector(42 downto 0);
begin

    regs : process(clk)
    begin
	if rising_edge(clk) then
            log_nia <= r.nia(63) & r.nia(43 downto 2);
	    if r /= r_next then
		report "fetch1 rst:" & std_ulogic'image(rst) &
                    " IR:" & std_ulogic'image(r_next.virt_mode) &
                    " P:" & std_ulogic'image(r_next.priv_mode) &
                    " E:" & std_ulogic'image(r_next.big_endian) &
                    " 32:" & std_ulogic'image(r_next_int.mode_32bit) &
		    " R:" & std_ulogic'image(e_in.redirect) & std_ulogic'image(d_in.redirect) &
		    " S:" & std_ulogic'image(stall_in) &
		    " T:" & std_ulogic'image(stop_in) &
		    " nia:" & to_hstring(r_next.nia) &
		    " SM:" & std_ulogic'image(r_next.stop_mark);
	    end if;
	    r <= r_next;
	    r_int <= r_next_int;
	end if;
    end process;
    log_out <= log_nia;

    comb : process(all)
	variable v : Fetch1ToIcacheType;
	variable v_int : reg_internal_t;
    begin
	v := r;
	v_int := r_int;
        v.sequential := '0';

	if rst = '1' then
	    if alt_reset_in = '1' then
		v.nia :=  ALT_RESET_ADDRESS;
	    else
		v.nia :=  RESET_ADDRESS;
	    end if;
            v.virt_mode := '0';
            v.priv_mode := '1';
            v.big_endian := '0';
            v_int.mode_32bit := '0';
	elsif e_in.redirect = '1' then
	    v.nia := e_in.redirect_nia(63 downto 2) & "00";
            if e_in.mode_32bit = '1' then
                v.nia(63 downto 32) := (others => '0');
            end if;
            v.virt_mode := e_in.virt_mode;
            v.priv_mode := e_in.priv_mode;
            v.big_endian := e_in.big_endian;
            v_int.mode_32bit := e_in.mode_32bit;
        elsif d_in.redirect = '1' then
            v.nia := d_in.redirect_nia(63 downto 2) & "00";
            if r_int.mode_32bit = '1' then
                v.nia(63 downto 32) := (others => '0');
            end if;
	elsif stall_in = '0' then

            -- If the last NIA value went down with a stop mark, it didn't get
            -- executed, and hence we shouldn't increment NIA.
	    if r.stop_mark = '0' then
                if r_int.mode_32bit = '0' then
                    v.nia := std_ulogic_vector(unsigned(r.nia) + 4);
                else
                    v.nia := x"00000000" & std_ulogic_vector(unsigned(r.nia(31 downto 0)) + 4);
                end if;
                v.sequential := '1';
	    end if;
	end if;

	v.req := not rst and not stop_in;
	v.stop_mark := stop_in;

	r_next <= v;
	r_next_int <= v_int;

	-- Update outputs to the icache
	i_out <= r;

    end process;

end architecture behaviour;
