library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mma_unit is
    port (
        clk   : in std_ulogic;
        rst   : in std_ulogic;

        -- Control signals
        start : in std_ulogic;
        clear : in std_ulogic;

        -- INT8 signed operands
        a     : in std_ulogic_vector(7 downto 0);
        b     : in std_ulogic_vector(7 downto 0);

        -- Status signals
        busy  : out std_ulogic;
        done  : out std_ulogic;

        -- INT32 accumulator result
        result : out std_ulogic_vector(31 downto 0)
    );
end entity mma_unit;


architecture rtl of mma_unit is

    type state_t is (
        IDLE,
        COMPUTE
    );

    signal state : state_t := IDLE;

    signal a_reg : signed(7 downto 0) := (others => '0');
    signal b_reg : signed(7 downto 0) := (others => '0');

    signal accumulator : signed(31 downto 0) := (others => '0');

begin

    process(clk)
        variable product : signed(15 downto 0);
    begin

        if rising_edge(clk) then

            -- Reset
            if rst = '1' then

                state       <= IDLE;
                a_reg       <= (others => '0');
                b_reg       <= (others => '0');
                accumulator <= (others => '0');

                done <= '0';


            -- Clear accumulator
            elsif clear = '1' then

                accumulator <= (others => '0');
                done        <= '0';


            else

                done <= '0';

                case state is

                    ------------------------------------------------
                    -- IDLE STATE
                    ------------------------------------------------
                    when IDLE =>

                        if start = '1' then

                            -- Capture INT8 operands
                            a_reg <= signed(a);
                            b_reg <= signed(b);

                            state <= COMPUTE;

                        end if;


                    ------------------------------------------------
                    -- COMPUTE STATE
                    ------------------------------------------------
                    when COMPUTE =>

                        product := a_reg * b_reg;

                        accumulator <=
                            accumulator +
                            resize(product, 32);

                        done  <= '1';

                        state <= IDLE;

                end case;

            end if;

        end if;

    end process;


    ------------------------------------------------
    -- Output assignments
    ------------------------------------------------

    busy <= '1' when state = COMPUTE else '0';

    result <= std_ulogic_vector(accumulator);

end architecture rtl;
