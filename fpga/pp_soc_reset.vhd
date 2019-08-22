-- The Potato Processor - A simple processor for FPGAs
-- (c) Kristian Klomsten Skordal 2018 <kristian.skordal@wafflemail.net>

library ieee;
use ieee.std_logic_1164.all;
use work.pp_utilities.all;

--! @brief System reset unit.
--! Because most resets in the processor core are synchronous, at least one
--! clock pulse has to be given to the processor while the reset signal is
--! asserted. However, if the clock generator is being reset at the same time,
--! the system clock might not run during reset, preventing the processor from
--! properly resetting.
entity pp_soc_reset is
	generic(
		RESET_CYCLE_COUNT : natural := 20000000
	);
	port(
		clk : in std_logic;

		reset_n   : in  std_logic;
		reset_out : out std_logic;

		system_clk        : in std_logic;
		system_clk_locked : in std_logic
	);
end entity pp_soc_reset;

architecture behaviour of pp_soc_reset is

	subtype counter_type is natural range 0 to RESET_CYCLE_COUNT;
	signal counter : counter_type;

	signal fast_reset : std_logic := '0';
	signal slow_reset : std_logic := '1';
begin

	reset_out <= slow_reset;

--	process(clk)
--	begin
--		if rising_edge(clk) then
--			if reset_n = '0' then
--				fast_reset <= '1';
--			elsif system_clk_locked = '1' then
--				if fast_reset = '1' and slow_reset = '1' then
--					fast_reset <= '0';
--				end if;
--			end if;
--		end if;
--	end process;

	process(system_clk)
	begin
		if rising_edge(system_clk) then
			if reset_n = '0' then
				slow_reset <= '1';
				counter <= RESET_CYCLE_COUNT;
			else
				if counter = 0 then
					slow_reset <= '0';
				else
					counter <= counter - 1;
				end if;
			end if;
		end if;
	end process;

end architecture behaviour;
