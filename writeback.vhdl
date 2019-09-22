library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity writeback is
    port (
        clk          : in std_ulogic;

        e_in         : in Execute2ToWritebackType;
        l_in         : in Loadstore2ToWritebackType;
        m_in         : in MultiplyToWritebackType;
        d_in         : in DividerToWritebackType;

        w_out        : out WritebackToRegisterFileType;
        c_out        : out WritebackToCrFileType;

        complete_out : out std_ulogic
        );
end entity writeback;

architecture behaviour of writeback is
begin
    writeback_1: process(all)
        variable x : std_ulogic_vector(0 downto 0);
        variable y : std_ulogic_vector(0 downto 0);
        variable z : std_ulogic_vector(0 downto 0);
        variable w : std_ulogic_vector(0 downto 0);
    begin
        x := "" & e_in.valid;
        y := "" & l_in.valid;
        z := "" & m_in.valid;
        w := "" & d_in.valid;
        assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z)) + to_integer(unsigned(w))) <= 1 severity failure;

        x := "" & e_in.write_enable;
        y := "" & l_in.write_enable;
        z := "" & m_in.write_reg_enable;
        w := "" & d_in.write_reg_enable;
        assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z)) + to_integer(unsigned(w))) <= 1 severity failure;

        x := "" & e_in.write_cr_enable;
        y := "" & m_in.write_cr_enable;
        z := "" & d_in.write_cr_enable;
        assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) + to_integer(unsigned(z))) <= 1 severity failure;

        w_out <= WritebackToRegisterFileInit;
        c_out <= WritebackToCrFileInit;

        complete_out <= '0';
        if e_in.valid = '1' or l_in.valid = '1' or m_in.valid = '1' or d_in.valid = '1' then
            complete_out <= '1';
        end if;

        if e_in.write_enable = '1' then
            w_out.write_reg <= e_in.write_reg;
            w_out.write_data <= e_in.write_data;
            w_out.write_enable <= '1';
        end if;

        if e_in.write_cr_enable = '1' then
            c_out.write_cr_enable <= '1';
            c_out.write_cr_mask <= e_in.write_cr_mask;
            c_out.write_cr_data <= e_in.write_cr_data;
        end if;

        if l_in.write_enable = '1' then
            w_out.write_reg <= l_in.write_reg;
            w_out.write_data <= l_in.write_data;
            w_out.write_enable <= '1';
        end if;

        if m_in.write_reg_enable = '1' then
            w_out.write_enable <= '1';
            w_out.write_reg <= m_in.write_reg_nr;
            w_out.write_data <= m_in.write_reg_data;
        end if;

        if m_in.write_cr_enable = '1' then
            c_out.write_cr_enable <= '1';
            c_out.write_cr_mask <= m_in.write_cr_mask;
            c_out.write_cr_data <= m_in.write_cr_data;
        end if;

        if d_in.write_reg_enable = '1' then
            w_out.write_enable <= '1';
            w_out.write_reg <= d_in.write_reg_nr;
            w_out.write_data <= d_in.write_reg_data;
        end if;

        if d_in.write_cr_enable = '1' then
            c_out.write_cr_enable <= '1';
            c_out.write_cr_mask <= d_in.write_cr_mask;
            c_out.write_cr_data <= d_in.write_cr_data;
        end if;
    end process;
end;
