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
    signal dend       : std_ulogic_vector(128 downto 0);
    signal div        : unsigned(63 downto 0);
    signal quot       : std_ulogic_vector(63 downto 0);
    signal result     : std_ulogic_vector(63 downto 0);
    signal sresult    : std_ulogic_vector(63 downto 0);
    signal qbit       : std_ulogic;
    signal running    : std_ulogic;
    signal signcheck  : std_ulogic;
    signal count      : unsigned(6 downto 0);
    signal neg_result : std_ulogic;
    signal is_modulus : std_ulogic;
    signal is_32bit   : std_ulogic;
    signal extended   : std_ulogic;
    signal is_signed  : std_ulogic;
    signal rc         : std_ulogic;
    signal write_reg  : std_ulogic_vector(4 downto 0);
    signal overflow   : std_ulogic;
    signal did_ovf    : std_ulogic;

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
                if d_in.is_extended = '1' and not (d_in.is_signed = '1' and d_in.dividend(63) = '1') then
                    dend <= '0' & d_in.dividend & x"0000000000000000";
                else
                    dend <= '0' & x"0000000000000000" & d_in.dividend;
                end if;
                div <= unsigned(d_in.divisor);
                quot <= (others => '0');
                write_reg <= d_in.write_reg;
                neg_result <= '0';
                is_modulus <= d_in.is_modulus;
                extended <= d_in.is_extended;
                is_32bit <= d_in.is_32bit;
                is_signed <= d_in.is_signed;
                rc <= d_in.rc;
                count <= "1111111";
                running <= '1';
                overflow <= '0';
                signcheck <= d_in.is_signed and (d_in.dividend(63) or d_in.divisor(63));
            elsif signcheck = '1' then
                signcheck <= '0';
                neg_result <= dend(63) xor (div(63) and not is_modulus);
                if dend(63) = '1' then
                    if extended = '1' then
                        dend <= '0' & std_ulogic_vector(- signed(dend(63 downto 0))) & x"0000000000000000";
                    else
                        dend <= '0' & x"0000000000000000" & std_ulogic_vector(- signed(dend(63 downto 0)));
                    end if;
                end if;
                if div(63) = '1' then
                    div <= unsigned(- signed(div));
                end if;
            elsif running = '1' then
                if count = "0111111" then
                    running <= '0';
                end if;
                overflow <= quot(63);
                if dend(128) = '1' or unsigned(dend(127 downto 64)) >= div then
                    dend <= std_ulogic_vector(unsigned(dend(127 downto 64)) - div) &
                            dend(63 downto 0) & '0';
                    quot <= quot(62 downto 0) & '1';
                    count <= count + 1;
                elsif dend(128 downto 57) = x"000000000000000000" and count(6 downto 3) /= "0111" then
                    -- consume 8 bits of zeroes in one cycle
                    dend <= dend(120 downto 0) & x"00";
                    quot <= quot(55 downto 0) & x"00";
                    count <= count + 8;
                else
                    dend <= dend(127 downto 0) & '0';
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
            result <= dend(128 downto 65);
        else
            result <= quot;
        end if;
        if neg_result = '1' then
            sresult <= std_ulogic_vector(- signed(result));
        else
            sresult <= result;
        end if;
        did_ovf <= '0';
        if is_32bit = '0' then
            did_ovf <= overflow or (is_signed and (sresult(63) xor neg_result));
        elsif is_signed = '1' then
            if overflow = '1' or
                (sresult(63 downto 31) /= x"00000000" & '0' and
                 sresult(63 downto 31) /= x"ffffffff" & '1') then
                did_ovf <= '1';
            end if;
        else
            did_ovf <= overflow or (or (sresult(63 downto 32)));
        end if;
        if did_ovf = '1' then
            d_out.write_reg_data <= (others => '0');
        else
            d_out.write_reg_data <= sresult;
        end if;

        if count = "1000000" then
            d_out.valid <= '1';
            d_out.write_reg_enable <= '1';
            if rc = '1' then
                d_out.write_cr_enable <= '1';
                d_out.write_cr_mask <= num_to_fxm(0);
                if did_ovf = '1' then
                    d_out.write_cr_data <= x"20000000";
                else
                    d_out.write_cr_data <= compare_zero(sresult, is_32bit) & x"0000000";
                end if;
            end if;
        end if;
    end process;

end architecture behaviour;
