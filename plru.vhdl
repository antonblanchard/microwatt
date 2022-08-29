library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity plru is
    generic (
        BITS : positive := 2
        )
        ;
    port (
        clk    : in std_ulogic;
        rst    : in std_ulogic;

        acc    : in std_ulogic_vector(BITS-1 downto 0);
        acc_en : in std_ulogic;
        lru    : out std_ulogic_vector(BITS-1 downto 0)
        );
end entity plru;

architecture rtl of plru is
    -- Each level of the tree (from leaf to root) has half the number of nodes
    -- of the previous level. So for a 2^N bits LRU, we have a level of N/2 bits
    -- one of N/4 bits etc.. down to 1. This gives us 2^N-1 nodes. Ie, 2 bits
    -- LRU has 3 nodes (2 + 1), 4 bits LRU has 15 nodes (8 + 4 + 2 + 1) etc...
    constant count : positive := 2 ** BITS - 1;
    subtype node_t is integer range 0 to count - 1;
    type tree_t is array(node_t) of std_ulogic;

    signal tree: tree_t;
begin

    -- XXX Check if we can turn that into a little ROM instead that
    -- takes the tree bit vector and returns the LRU. See if it's better
    -- in term of FPGA resource usage...
    get_lru: process(tree)
        variable node : node_t;
        variable abit : std_ulogic;
    begin
        node := 0;
        for i in 0 to BITS-1 loop
--          report "GET: i:" & integer'image(i) & " node:" & integer'image(node) & " val:" & std_ulogic'image(tree(node));
            abit := tree(node);
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

    update_lru: process(clk)
        variable node : node_t;
        variable abit : std_ulogic;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tree <= (others => '0');
            elsif acc_en = '1' then
                node := 0;
                for i in 0 to BITS-1 loop
                    abit := acc(BITS-1-i);
                    tree(node) <= not abit;
--                  report "UPD: i:" & integer'image(i) & " node:" & integer'image(node) & " val" & std_ulogic'image(not abit);
                    if i /= BITS-1 then
                        node := node * 2;
                        if abit = '1' then
                            node := node + 2;
                        else
                            node := node + 1;
                        end if;
                    end if;
                end loop;
            end if;
        end if;
--        if falling_edge(clk) then
--            if acc_en = '1' then
--                report "UPD: tree:" & to_string(tree);
--            end if;
--        end if;
    end process;
end;
