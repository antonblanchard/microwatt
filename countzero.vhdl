library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity zero_counter is
    port (
        clk         : in std_logic;
	rs          : in std_ulogic_vector(63 downto 0);
	count_right : in std_ulogic;
	is_32bit    : in std_ulogic;
	result      : out std_ulogic_vector(63 downto 0)
	);
end entity zero_counter;

architecture behaviour of zero_counter is
    -- Reverse the order of bits in a word
    function bit_reverse(a: std_ulogic_vector) return std_ulogic_vector is
        variable ret: std_ulogic_vector(a'left downto a'right);
    begin
        for i in a'right to a'left loop
            ret(a'left + a'right - i) := a(i);
        end loop;
        return ret;
    end;

    -- If there is only one bit set in a doubleword, return its bit number
    -- (counting from the right).  Each bit of the result is obtained by
    -- ORing together 32 bits of the input:
    --  bit 0 = a[1] or a[3] or a[5] or ...
    --  bit 1 = a[2] or a[3] or a[6] or a[7] or ...
    --  bit 2 = a[4..7] or a[12..15] or ...
    --  bit 5 = a[32..63] ORed together
    function bit_number(a: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
        variable ret: std_ulogic_vector(5 downto 0);
        variable stride: natural;
        variable bit: std_ulogic;
        variable k: natural;
    begin
        stride := 2;
        for i in 0 to 5 loop
            bit := '0';
            for j in 0 to (64 / stride) - 1 loop
                k := j * stride;
                bit := bit or (or a(k + stride - 1 downto k + (stride / 2)));
            end loop;
            ret(i) := bit;
            stride := stride * 2;
        end loop;
        return ret;
    end;

    signal inp : std_ulogic_vector(63 downto 0);
    signal sum : std_ulogic_vector(64 downto 0);
    signal msb_r : std_ulogic;
    signal onehot : std_ulogic_vector(63 downto 0);
    signal onehot_r : std_ulogic_vector(63 downto 0);
    signal bitnum : std_ulogic_vector(5 downto 0);

begin
    countzero_r: process(clk)
    begin
        if rising_edge(clk) then
            msb_r <= sum(64);
            onehot_r <= onehot;
        end if;
    end process;

    countzero: process(all)
    begin
        if is_32bit = '0' then
            if count_right = '0' then
                inp <= bit_reverse(rs);
            else
                inp <= rs;
            end if;
        else
            inp(63 downto 32) <= x"FFFFFFFF";
            if count_right = '0' then
                inp(31 downto 0) <= bit_reverse(rs(31 downto 0));
            else
                inp(31 downto 0) <= rs(31 downto 0);
            end if;
        end if;

        sum <= std_ulogic_vector(unsigned('0' & not inp) + 1);
        onehot <= sum(63 downto 0) and inp;

        -- The following occurs after a clock edge
        bitnum <= bit_number(onehot_r);

        result <= x"00000000000000" & "0" & msb_r & bitnum;
    end process;
end behaviour;
