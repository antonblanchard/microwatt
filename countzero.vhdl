library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity zero_counter is
    port (
	rs          : in std_ulogic_vector(63 downto 0);
	count_right : in std_ulogic;
	is_32bit    : in std_ulogic;
	result      : out std_ulogic_vector(63 downto 0)
	);
end entity zero_counter;

architecture behaviour of zero_counter is
begin
    zerocounter0: process(all)
        variable l32, r32 : std_ulogic;
        variable v32      : std_ulogic_vector(31 downto 0);
        variable v16      : std_ulogic_vector(15 downto 0);
        variable v8       : std_ulogic_vector(7 downto 0);
        variable v4       : std_ulogic_vector(3 downto 0);
        variable sel      : std_ulogic_vector(5 downto 0);
    begin
        l32 := '0';
        r32 := '0';
        v32 := (others => '0');
        v16 := (others => '0');
        v8  := (others => '0');
        v4  := (others => '0');
        sel := (others => '0');

	l32 := or (rs(63 downto 32));
	r32 := or (rs(31 downto 0));
	if (l32 = '0' or is_32bit = '1') and r32 = '0' then
	    -- operand is zero, return 32 for 32-bit, else 64
	    result <= x"00000000000000" & '0' & not is_32bit & is_32bit & "00000";
	else

	    if count_right = '0' then
		sel(5) := l32 and (not is_32bit);
	    else
		sel(5) := (not r32) and (not is_32bit);
	    end if;
	    if sel(5) = '1' then
		v32 := rs(63 downto 32);
	    else
		v32 := rs(31 downto 0);
	    end if;

	    if count_right = '0' then
		sel(4) := or (v32(31 downto 16));
	    else
		sel(4) := not (or (v32(15 downto 0)));
	    end if;
	    if sel(4) = '1' then
		v16 := v32(31 downto 16);
	    else
		v16 := v32(15 downto 0);
	    end if;

	    if count_right = '0' then
		sel(3) := or (v16(15 downto 8));
	    else
		sel(3) := not (or (v16(7 downto 0)));
	    end if;
	    if sel(3) = '1' then
		v8 := v16(15 downto 8);
	    else
		v8 := v16(7 downto 0);
	    end if;

	    if count_right = '0' then
		sel(2) := or (v8(7 downto 4));
	    else
		sel(2) := not (or (v8(3 downto 0)));
	    end if;
	    if sel(2) = '1' then
		v4 := v8(7 downto 4);
	    else
		v4 := v8(3 downto 0);
	    end if;

	    if count_right = '0' then
		if v4(3) = '1' then
		    sel(1 downto 0) := "11";
		elsif v4(2) = '1' then
		    sel(1 downto 0) := "10";
		elsif v4(1) = '1' then
		    sel(1 downto 0) := "01";
		else
		    sel(1 downto 0) := "00";
		end if;
		result <= x"00000000000000" & "00" & (not sel(5) and not is_32bit) & not sel(4 downto 0);
	    else
		if v4(0) = '1' then
		    sel(1 downto 0) := "00";
		elsif v4(1) = '1' then
		    sel(1 downto 0) := "01";
		elsif v4(2) = '1' then
		    sel(1 downto 0) := "10";
		else
		    sel(1 downto 0) := "11";
		end if;
		result <= x"00000000000000" & "00" & sel;
	    end if;
	end if;

    end process;
end behaviour;
