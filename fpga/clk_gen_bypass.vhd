library ieee;
use ieee.std_logic_1164.all;

entity clock_generator is
  port (
    clk        : in  std_logic;
    resetn     : in  std_logic;
    system_clk : out std_logic;
    locked     : out std_logic);

end entity clock_generator;

architecture bypass of clock_generator is

begin

  locked <= not resetn;
  system_clk <= clk;

end architecture bypass;
