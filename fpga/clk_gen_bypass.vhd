library ieee;
use ieee.std_logic_1164.all;

entity clock_generator is
  port (
    ext_clk        : in  std_logic;
    pll_rst_in   : in  std_logic;
    pll_clk_out : out std_logic;
    pll_locked_out : out std_logic);

end entity clock_generator;

architecture bypass of clock_generator is

begin

  pll_locked_out <= not pll_rst_in;
  pll_clk_out <= ext_clk;

end architecture bypass;
