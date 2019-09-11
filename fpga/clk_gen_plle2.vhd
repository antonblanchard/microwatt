library ieee;
use ieee.std_logic_1164.all;

Library UNISIM;
use UNISIM.vcomponents.all;

entity clock_generator is
  generic (
    clk_period_hz : positive := 100000000);
  port (
    ext_clk        : in  std_logic;
    pll_rst_in   : in  std_logic;
    pll_clk_out    : out std_logic;
    pll_locked_out : out std_logic);
end entity clock_generator;

architecture rtl of clock_generator is

  signal clkfb : std_ulogic;

  type pll_settings_t is record
    clkin_period  : real    range 0.000 to 52.631;
    clkfbout_mult : integer range 2 to 64;
    clkout_divide : integer range 1 to 128;
    divclk_divide : integer range 1 to 56;
  end record;

  function gen_pll_settings (
    constant freq_hz : positive)
    return pll_settings_t is
  begin
    if freq_hz = 100000000 then
      return (clkin_period  => 10.0,
              clkfbout_mult => 16,
              clkout_divide => 32,
              divclk_divide => 1);
    else
      report "Unsupported input frequency" severity failure;
--      return (clkin_period  => 0.0,
--              clkfbout_mult => 0,
--              clkout_divide => 0,
--              divclk_divide => 0);
    end if;
  end function gen_pll_settings;

  constant pll_settings : pll_settings_t := gen_pll_settings(clk_period_hz);
begin

  pll : PLLE2_BASE
    generic map (
      BANDWIDTH          => "OPTIMIZED",
      CLKFBOUT_MULT      => pll_settings.clkfbout_mult,
      CLKIN1_PERIOD      => pll_settings.clkin_period,
      CLKOUT0_DIVIDE     => pll_settings.clkout_divide,
      DIVCLK_DIVIDE      => pll_settings.divclk_divide,
      STARTUP_WAIT       => "FALSE")
    port map (
      CLKOUT0  => pll_clk_out,
      CLKOUT1  => open,
      CLKOUT2  => open,
      CLKOUT3  => open,
      CLKOUT4  => open,
      CLKOUT5  => open,
      CLKFBOUT => clkfb,
      LOCKED   => pll_locked_out,
      CLKIN1   => ext_clk,
      PWRDWN   => '0',
      RST      => pll_rst_in,
      CLKFBIN  => clkfb);

end architecture rtl;
