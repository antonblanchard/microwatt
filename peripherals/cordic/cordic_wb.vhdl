library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic_wb is
    port(
        clk        : in  std_ulogic;
        rst        : in  std_ulogic;

        -- Wishbone IO interface (Microwatt)
        wb_adr_i   : in  std_ulogic_vector(29 downto 0);
        wb_dat_i   : in  std_ulogic_vector(31 downto 0);
        wb_dat_o   : out std_ulogic_vector(31 downto 0);
        wb_we_i    : in  std_ulogic;
        wb_stb_i   : in  std_ulogic;
        wb_cyc_i   : in  std_ulogic;
        wb_ack_o   : out std_ulogic;

        -- CORDIC core interface
        cordic_x      : out std_ulogic_vector(31 downto 0);
        cordic_y      : out std_ulogic_vector(31 downto 0);
        cordic_start  : out std_ulogic;
        cordic_done   : in  std_ulogic;
        cordic_result : in  std_ulogic_vector(31 downto 0)
    );
end entity cordic_wb;

architecture rtl of cordic_wb is

    signal x_reg     : std_ulogic_vector(31 downto 0) := (others => '0');
    signal y_reg     : std_ulogic_vector(31 downto 0) := (others => '0');
    signal start_reg : std_ulogic := '0';

begin

    -- Drive CORDIC core
    cordic_x     <= x_reg;
    cordic_y     <= y_reg;
    cordic_start <= start_reg;

    -- Wishbone slave
    process(clk)
        variable addr : std_ulogic_vector(2 downto 0);
    begin
        if rising_edge(clk) then
            wb_ack_o <= '0';

            if rst = '1' then
                x_reg     <= (others => '0');
                y_reg     <= (others => '0');
                start_reg <= '0';
                wb_dat_o  <= (others => '0');

            elsif wb_cyc_i = '1' and wb_stb_i = '1' then
                wb_ack_o <= '1';
                addr := wb_adr_i(4 downto 2);  -- word offsets

                if wb_we_i = '1' then
                    -- WRITE
                    case addr is
                        when "000" => x_reg <= wb_dat_i;         -- 0x00
                        when "001" => y_reg <= wb_dat_i;         -- 0x04
                        when "010" => start_reg <= wb_dat_i(0);  -- 0x08
                        when others => null;
                    end case;
                else
                    -- READ
                    case addr is
                        when "000" => wb_dat_o <= x_reg;                     -- 0x00
                        when "001" => wb_dat_o <= y_reg;                     -- 0x04
                        when "011" => wb_dat_o <= (31 downto 1 => '0') & cordic_done; -- 0x0C
                        when "100" => wb_dat_o <= cordic_result;             -- 0x10
                        when others => wb_dat_o <= (others => '0');
                    end case;
                end if;
            end if;

            -- Auto-clear start when done
            if cordic_done = '1' then
                start_reg <= '0';
            end if;
        end if;
    end process;

end architecture rtl;

