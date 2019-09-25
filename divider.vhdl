library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;
use work.crhelpers.all;

entity divider is
    port (
        clk   : in std_logic;
        rst   : in std_logic;
        d_in  : in Decode2ToDividerType;
        d_out : out DividerToWritebackType
        );
end entity divider;

architecture behaviour of divider is
    signal dend       : std_ulogic_vector(127 downto 0);
    signal div        : unsigned(63 downto 0);
    signal quot       : std_ulogic_vector(63 downto 0);
    signal result     : std_ulogic_vector(63 downto 0);
    signal sresult    : std_ulogic_vector(63 downto 0);
    signal qbit       : std_ulogic;
    signal running    : std_ulogic;
    signal count      : unsigned(6 downto 0);
    signal neg_result : std_ulogic;
    signal is_modulus : std_ulogic;
    signal is_32bit   : std_ulogic;
    signal rc         : std_ulogic;
    signal write_reg  : std_ulogic_vector(4 downto 0);

    function compare_zero(value : std_ulogic_vector(63 downto 0); is_32 : std_ulogic)
        return std_ulogic_vector is
    begin
        if is_32 = '1' then
            if value(31) = '1' then
                return "1000";
            elsif unsigned(value(30 downto 0)) > 0 then
                return "0100";
            else
                return "0010";
            end if;
        else
            if value(63) = '1' then
                return "1000";
            elsif unsigned(value(62 downto 0)) > 0 then
                return "0100";
            else
                return "0010";
            end if;
        end if;
    end function compare_zero;

begin
    divider_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                dend <= (others => '0');
                div <= (others => '0');
                quot <= (others => '0');
                running <= '0';
                count <= "0000000";
            elsif d_in.valid = '1' then
                if d_in.is_extended = '1' then
                    dend <= d_in.dividend & x"0000000000000000";
                else
                    dend <= x"0000000000000000" & d_in.dividend;
                end if;
                div <= unsigned(d_in.divisor);
                quot <= (others => '0');
                write_reg <= d_in.write_reg;
                neg_result <= d_in.neg_result;
                is_modulus <= d_in.is_modulus;
                is_32bit <= d_in.is_32bit;
                rc <= d_in.rc;
                count <= "0000000";
                running <= '1';
            elsif running = '1' then
                if count = "0111111" then
                    running <= '0';
                end if;
                if dend(127) = '1' or unsigned(dend(126 downto 63)) >= div then
                    dend <= std_ulogic_vector(unsigned(dend(126 downto 63)) - div) &
                            dend(62 downto 0) & '0';
                    quot <= quot(62 downto 0) & '1';
                    count <= count + 1;
                elsif dend(127 downto 56) = x"000000000000000000" and count(5 downto 3) /= "111" then
                    -- consume 8 bits of zeroes in one cycle
                    dend <= dend(119 downto 0) & x"00";
                    quot <= quot(55 downto 0) & x"00";
                    count <= count + 8;
                else
                    dend <= dend(126 downto 0) & '0';
                    quot <= quot(62 downto 0) & '0';
                    count <= count + 1;
                end if;
            else
                count <= "0000000";
            end if;
        end if;
    end process;

    divider_1: process(all)
    begin
        d_out <= DividerToWritebackInit;
        d_out.write_reg_nr <= write_reg;

        if is_modulus = '1' then
            result <= dend(127 downto 64);
        else
            result <= quot;
        end if;
        if neg_result = '1' then
            sresult <= std_ulogic_vector(- signed(result));
        else
            sresult <= result;
        end if;
        d_out.write_reg_data <= sresult;

        if count(6) = '1' then
            d_out.valid <= '1';
            d_out.write_reg_enable <= '1';
            if rc = '1' then
                d_out.write_cr_enable <= '1';
                d_out.write_cr_mask <= num_to_fxm(0);
                d_out.write_cr_data <= compare_zero(sresult, is_32bit) & x"0000000";
            end if;
        end if;
    end process;

end architecture behaviour;
