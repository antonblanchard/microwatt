-- Implements instructions that involve sorting bits,
-- that is, cfuged, pextd and pdepd.
--
-- cfuged: Sort the bits in the mask in RB into 0s at the left, 1s at the right
--         and move the bits in RS in the same fashion to give the result
-- pextd:  Like cfuged but the only use the bits of RS where the
--         corresponding bit in RB is 1
-- pdepd:  Inverse of pextd; take the low-order bits of RS and spread them out
--         to the bit positions which have a 1 in RB

-- NB opc is bits 7-6 of the instruction:
-- 00 = pdepd, 01 = pextd, 10 = cfuged

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.helpers.all;

entity bit_sorter is
    port (
        clk         : in std_ulogic;
        rst         : in std_ulogic;
        rs          : in std_ulogic_vector(63 downto 0);
        rb          : in std_ulogic_vector(63 downto 0);
        go          : in std_ulogic;
        opc         : in std_ulogic_vector(1 downto 0);
        done        : out std_ulogic;
        result      : out std_ulogic_vector(63 downto 0)
        );
end entity bit_sorter;

architecture behaviour of bit_sorter is

    signal val : std_ulogic_vector(63 downto 0);
    signal st  : std_ulogic;
    signal sd  : std_ulogic;
    signal opr : std_ulogic_vector(1 downto 0);
    signal bc  : unsigned(5 downto 0);
    signal jl  : unsigned(5 downto 0);
    signal jr  : unsigned(5 downto 0);
    signal sr_ml : std_ulogic_vector(63 downto 0);
    signal sr_mr : std_ulogic_vector(63 downto 0);
    signal sr_vl : std_ulogic_vector(63 downto 0);
    signal sr_vr : std_ulogic_vector(63 downto 0);

begin
    bsort_r: process(clk)
    begin
        if rising_edge(clk) then
            sd <= '0';
            if rst = '1' then
                st <= '0';
                opr <= "00";
                val <= (others => '0');
            elsif go = '1' then
                st <= '1';
                sr_ml <= rb;
                sr_mr <= rb;
                sr_vl <= rs;
                sr_vr <= rs;
                opr <= opc;
                val <= (others => '0');
                bc <= to_unsigned(0, 6);
                jl <= to_unsigned(63, 6);
                jr <= to_unsigned(0, 6);
            elsif st = '1' then
                if bc = 6x"3f" then
                    st <= '0';
                    sd <= '1';
                end if;
                bc <= bc + 1;
                if sr_ml(63) = '0' and opr(1) = '1' then
                    -- cfuged
                    val(to_integer(jl)) <= sr_vl(63);
                    jl <= jl - 1;
                end if;
                if sr_mr(0) = '1' then
                    if opr = "00" then
                        -- pdepd
                        val(to_integer(bc)) <= sr_vr(0);
                    else
                        -- cfuged or pextd
                        val(to_integer(jr)) <= sr_vr(0);
                    end if;
                    jr <= jr + 1;
                end if;
                sr_vl <= sr_vl(62 downto 0) & '0';
                if opr /= "00" or sr_mr(0) = '1' then
                    sr_vr <= '0' & sr_vr(63 downto 1);
                end if;
                sr_ml <= sr_ml(62 downto 0) & '0';
                sr_mr <= '0' & sr_mr(63 downto 1);
            end if;
        end if;
    end process;

    done <= sd;
    result <= val;

end behaviour;
