library ieee;
use ieee.std_logic_1164.all;

library work;

package git is
    constant GIT_HASH : std_ulogic_vector(55 downto 0) := x"1234567890abcd";
    constant GIT_DIRTY : std_ulogic := '0';
end git;
