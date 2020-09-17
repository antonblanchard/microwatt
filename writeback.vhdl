library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.crhelpers.all;

entity writeback is
    port (
        clk          : in std_ulogic;

        e_in         : in Execute1ToWritebackType;
        l_in         : in Loadstore1ToWritebackType;
        fp_in        : in FPUToWritebackType;

        w_out        : out WritebackToRegisterFileType;
        c_out        : out WritebackToCrFileType;

        complete_out : out std_ulogic
        );
end entity writeback;

architecture behaviour of writeback is
begin
    writeback_0: process(clk)
        variable x : std_ulogic_vector(0 downto 0);
        variable y : std_ulogic_vector(0 downto 0);
        variable w : std_ulogic_vector(0 downto 0);
    begin
        if rising_edge(clk) then
            -- Do consistency checks only on the clock edge
            x(0) := e_in.valid;
            y(0) := l_in.valid;
            w(0) := fp_in.valid;
            assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) +
                    to_integer(unsigned(w))) <= 1 severity failure;

            x(0) := e_in.write_enable or e_in.exc_write_enable;
            y(0) := l_in.write_enable;
            w(0) := fp_in.write_enable;
            assert (to_integer(unsigned(x)) + to_integer(unsigned(y)) +
                    to_integer(unsigned(w))) <= 1 severity failure;

            w(0) := e_in.write_cr_enable;
            x(0) := (e_in.write_enable and e_in.rc);
            y(0) := fp_in.write_cr_enable;
            assert (to_integer(unsigned(w)) + to_integer(unsigned(x)) +
                    to_integer(unsigned(y))) <= 1 severity failure;
        end if;
    end process;

    writeback_1: process(all)
	variable cf: std_ulogic_vector(3 downto 0);
        variable zero : std_ulogic;
        variable sign : std_ulogic;
	variable scf  : std_ulogic_vector(3 downto 0);
    begin
        w_out <= WritebackToRegisterFileInit;
        c_out <= WritebackToCrFileInit;

        complete_out <= '0';
        if e_in.valid = '1' or l_in.valid = '1' or fp_in.valid = '1' then
            complete_out <= '1';
        end if;

        if e_in.exc_write_enable = '1' then
            w_out.write_reg <= e_in.exc_write_reg;
            w_out.write_data <= e_in.exc_write_data;
            w_out.write_enable <= '1';
        else
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

            if e_in.write_xerc_enable = '1' then
                c_out.write_xerc_enable <= '1';
                c_out.write_xerc_data <= e_in.xerc;
            end if;

            if fp_in.write_enable = '1' then
                w_out.write_reg <= fp_in.write_reg;
                w_out.write_data <= fp_in.write_data;
                w_out.write_enable <= '1';
            end if;

            if fp_in.write_cr_enable = '1' then
                c_out.write_cr_enable <= '1';
                c_out.write_cr_mask <= fp_in.write_cr_mask;
                c_out.write_cr_data <= fp_in.write_cr_data;
            end if;

            if l_in.write_enable = '1' then
                w_out.write_reg <= l_in.write_reg;
                w_out.write_data <= l_in.write_data;
                w_out.write_enable <= '1';
            end if;

            if l_in.rc = '1' then
                -- st*cx. instructions
                scf(3) := '0';
                scf(2) := '0';
                scf(1) := l_in.store_done;
                scf(0) := l_in.xerc.so;
                c_out.write_cr_enable <= '1';
                c_out.write_cr_mask <= num_to_fxm(0);
                c_out.write_cr_data(31 downto 28) <= scf;
            end if;

            -- Perform CR0 update for RC forms
            -- Note that loads never have a form with an RC bit, therefore this can test e_in.write_data
            if e_in.rc = '1' and e_in.write_enable = '1' then
                zero := not (or e_in.write_data(31 downto 0));
                if e_in.mode_32bit = '0' then
                    sign := e_in.write_data(63);
                    zero := zero and not (or e_in.write_data(63 downto 32));
                else
                    sign := e_in.write_data(31);
                end if;
                c_out.write_cr_enable <= '1';
                c_out.write_cr_mask <= num_to_fxm(0);
                cf(3) := sign;
                cf(2) := not sign and not zero;
                cf(1) := zero;
                cf(0) := e_in.xerc.so;
                c_out.write_cr_data(31 downto 28) <= cf;
            end if;
        end if;
    end process;
end;
