library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity plrufn is
    generic (
        BITS : positive := 2
        )
        ;
    port (
        acc      : in  std_ulogic_vector(BITS-1 downto 0);
        tree_in  : in  std_ulogic_vector(2 ** BITS - 2 downto 0);
        tree_out : out std_ulogic_vector(2 ** BITS - 2 downto 0);
        lru      : out std_ulogic_vector(BITS-1 downto 0)
        );
end entity plrufn;

architecture rtl of plrufn is
    -- Each level of the tree (from leaf to root) has half the number of nodes
    -- of the previous level. So for a 2^N bits LRU, we have a level of N/2 bits
    -- one of N/4 bits etc.. down to 1. This gives us 2^N-1 nodes. Ie, 2 bits
    -- LRU has 3 nodes (2 + 1), 4 bits LRU has 15 nodes (8 + 4 + 2 + 1) etc...
    constant count : positive := 2 ** BITS - 1;
    subtype node_t is integer range 0 to count - 1;
begin

    get_lru: process(tree_in)
        variable node : node_t;
        variable abit : std_ulogic;
    begin
        node := 0;
        for i in 0 to BITS-1 loop
            abit := tree_in(node);
            if is_X(abit) then
                abit := '0';
            end if;
            lru(BITS-1-i) <= abit;
            if i /= BITS-1 then
                node := node * 2;
                if abit = '1' then
                    node := node + 2;
                else
                    node := node + 1;
                end if;
            end if;
        end loop;
    end process;

    update_lru: process(all)
        variable node : node_t;
        variable abit : std_ulogic;
    begin
        tree_out <= tree_in;
        node := 0;
        for i in 0 to BITS-1 loop
            abit := acc(BITS-1-i);
            if is_X(abit) then
                abit := '0';
            end if;
            tree_out(node) <= not abit;
            if i /= BITS-1 then
                node := node * 2;
                if abit = '1' then
                    node := node + 2;
                else
                    node := node + 1;
                end if;
            end if;
        end loop;
    end process;
end;
