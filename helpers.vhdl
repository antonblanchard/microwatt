library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

package helpers is
    function fls_32 (val: std_ulogic_vector(31 downto 0)) return integer;
    function ffs_32 (val: std_ulogic_vector(31 downto 0)) return integer;

    function fls_64 (val: std_ulogic_vector(63 downto 0)) return integer;
    function ffs_64 (val: std_ulogic_vector(63 downto 0)) return integer;

    function popcnt8(val: std_ulogic_vector(7 downto 0)) return std_ulogic_vector;
    function popcnt32(val: std_ulogic_vector(31 downto 0)) return std_ulogic_vector;
    function popcnt64(val: std_ulogic_vector(63 downto 0)) return std_ulogic_vector;

    function cmp_one_byte(a, b: std_ulogic_vector(7 downto 0)) return std_ulogic_vector;

    function ppc_signed_compare(a, b: signed(63 downto 0); so: std_ulogic) return std_ulogic_vector;
    function ppc_unsigned_compare(a, b: unsigned(63 downto 0); so: std_ulogic) return std_ulogic_vector;

    function ra_or_zero(ra: std_ulogic_vector(63 downto 0); reg: std_ulogic_vector(4 downto 0)) return std_ulogic_vector;

    function byte_reverse(val: std_ulogic_vector(63 downto 0); size: integer) return std_ulogic_vector;

    function sign_extend(val: std_ulogic_vector(63 downto 0); size: natural) return std_ulogic_vector;
end package helpers;

package body helpers is
    function fls_32 (val: std_ulogic_vector(31 downto 0)) return integer is
        variable ret: integer;
    begin
        ret := 32;
        for i in val'range loop
            if val(i) = '1' then
                ret := 31 - i;
                exit;
            end if;
        end loop;

        return ret;
    end;

    function ffs_32 (val: std_ulogic_vector(31 downto 0)) return integer is
        variable ret: integer;
    begin
        ret := 32;
        for i in val'reverse_range loop
            if val(i) = '1' then
                ret := i;
                exit;
            end if;
        end loop;

        return ret;
    end;

    function fls_64 (val: std_ulogic_vector(63 downto 0)) return integer is
        variable ret: integer;
    begin
        ret := 64;
        for i in val'range loop
            if val(i) = '1' then
                ret := 63 - i;
                exit;
            end if;
        end loop;

        return ret;
    end;

    function ffs_64 (val: std_ulogic_vector(63 downto 0)) return integer is
        variable ret: integer;
    begin
        ret := 64;
        for i in val'reverse_range loop
            if val(i) = '1' then
                ret := i;
                exit;
            end if;
        end loop;

        return ret;
    end;

    function popcnt8(val: std_ulogic_vector(7 downto 0)) return std_ulogic_vector is
        variable ret: unsigned(3 downto 0) := (others => '0');
    begin
        for i in val'range loop
            ret := ret + ("000" & val(i));
        end loop;

        return std_ulogic_vector(resize(ret, val'length));
    end;

    function popcnt32(val: std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
        variable ret: unsigned(5 downto 0) := (others => '0');
    begin
        for i in val'range loop
            ret := ret + ("00000" & val(i));
        end loop;

        return std_ulogic_vector(resize(ret, val'length));
    end;

    function popcnt64(val: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
        variable ret: unsigned(6 downto 0) := (others => '0');
    begin
        for i in val'range loop
            ret := ret + ("000000" & val(i));
        end loop;

        return std_ulogic_vector(resize(ret, val'length));
    end;

    function cmp_one_byte(a, b: std_ulogic_vector(7 downto 0)) return std_ulogic_vector is
        variable ret: std_ulogic_vector(7 downto 0);
    begin
        if a = b then
            ret := x"ff";
        else
            ret := x"00";
        end if;

        return ret;
    end;

    function ppc_signed_compare(a, b: signed(63 downto 0); so: std_ulogic) return std_ulogic_vector is
        variable ret: std_ulogic_vector(2 downto 0);
    begin
        if a < b then
            ret := "100";
        elsif a > b then
            ret := "010";
        else
            ret := "001";
        end if;

        return ret & so;
    end;

    function ppc_unsigned_compare(a, b: unsigned(63 downto 0); so: std_ulogic) return std_ulogic_vector is
        variable ret: std_ulogic_vector(2 downto 0);
    begin
        if a < b then
            ret := "100";
        elsif a > b then
            ret := "010";
        else
            ret := "001";
        end if;

        return ret & so;
    end;

    function ra_or_zero(ra: std_ulogic_vector(63 downto 0); reg: std_ulogic_vector(4 downto 0)) return std_ulogic_vector is
    begin
        if to_integer(unsigned(reg)) = 0 then
            return x"0000000000000000";
        else
            return ra;
        end if;
    end;

    function byte_reverse(val: std_ulogic_vector(63 downto 0); size: integer) return std_ulogic_vector is
        variable ret : std_ulogic_vector(63 downto 0) := (others => '0');
    begin
        -- Vivado doesn't support non constant vector slices, so we have to code
        -- each of these.
        case_0: case size is
            when 2 =>
                for_2 : for k in 0 to 1 loop
                    ret(((8*k)+7) downto (8*k)) := val((8*(1-k)+7) downto (8*(1-k)));
                end loop;
            when 4 =>
                for_4 : for k in 0 to 3 loop
                    ret(((8*k)+7) downto (8*k)) := val((8*(3-k)+7) downto (8*(3-k)));
                end loop;
            when 8 =>
                for_8 : for k in 0 to 7 loop
                    ret(((8*k)+7) downto (8*k)) := val((8*(7-k)+7) downto (8*(7-k)));
                end loop;
            when others =>
                report "bad byte reverse length " & integer'image(size) severity failure;
        end case;

        return ret;
    end;

    function sign_extend(val: std_ulogic_vector(63 downto 0); size: natural) return std_ulogic_vector is
        variable ret : signed(63 downto 0) := (others => '0');
        variable upper : integer := 0;
    begin
        case_0: case size is
            when 2 =>
                ret := resize(signed(val(15 downto 0)), 64);
            when 4 =>
                ret := resize(signed(val(31 downto 0)), 64);
            when 8 =>
                ret := resize(signed(val(63 downto 0)), 64);
            when others =>
                report "bad byte reverse length " & integer'image(size) severity failure;
        end case;

        return std_ulogic_vector(ret);

    end;
end package body helpers;
