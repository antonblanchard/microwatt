library ieee;
use ieee.std_logic_1164.all;

entity soc_reset is
    generic (
        PLL_RESET_CLOCKS : integer := 32;
        SOC_RESET_CLOCKS : integer := 32;
        RESET_LOW        : boolean := true
        );
    port (
        ext_clk       : in std_ulogic;
        pll_clk       : in std_ulogic;

        pll_locked_in : in std_ulogic;
        ext_rst_in    : in std_ulogic;

        pll_rst_out : out std_ulogic;
        rst_out       : out std_ulogic
        );
end soc_reset;

architecture rtl of soc_reset is
    signal ext_rst_n     : std_ulogic;
    signal rst_n         : std_ulogic;
    signal pll_rst_reg : std_ulogic_vector(PLL_RESET_CLOCKS downto 0) := (others => '1');
    signal soc_rst_reg   : std_ulogic_vector(SOC_RESET_CLOCKS downto 0) := (others => '1');
begin
    ext_rst_n <= ext_rst_in when RESET_LOW else not ext_rst_in;
    rst_n <= ext_rst_n and pll_locked_in;

    -- PLL reset is active high
    pll_rst_out <= pll_rst_reg(0);
    -- Pass active high reset around
    rst_out <= soc_rst_reg(0);

    -- Wait for external clock to become stable before starting the PLL
    -- By the time the FPGA has been loaded the clock should be well and
    -- truly stable, but lets give it a few cycles to be sure.
    pll_reset_0 : process(ext_clk)
    begin
        if (rising_edge(ext_clk)) then
            pll_rst_reg <= '0' & pll_rst_reg(pll_rst_reg'length-1 downto 1);
        end if;
    end process;

    -- Once our clock is stable and the external reset button isn't being
    -- pressed, assert the SOC reset for long enough for the CPU pipeline
    -- to clear completely.
    soc_reset_0 : process(pll_clk)
    begin
        if (rising_edge(pll_clk)) then
            if (rst_n = '0') then
                soc_rst_reg <= (others => '1');
            else
                soc_rst_reg <= '0' & soc_rst_reg(soc_rst_reg'length-1 downto 1);
            end if;
        end if;
    end process;
end rtl;
