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
        l_in         : in DcacheToWritebackType;

        w_out        : out WritebackToRegisterFileType;
        c_out        : out WritebackToCrFileType;

        complete_out : out std_ulogic
        );
end entity writeback;

architecture behaviour of writeback is
    subtype byte_index_t is unsigned(2 downto 0);
    type permutation_t is array(0 to 7) of byte_index_t;
    subtype byte_trim_t is std_ulogic_vector(1 downto 0);
    type trim_ctl_t is array(0 to 7) of byte_trim_t;
    type byte_sel_t is array(0 to 7) of std_ulogic;

    signal data_len : unsigned(3 downto 0);
    signal data_in : std_ulogic_vector(63 downto 0);
    signal data_permuted : std_ulogic_vector(63 downto 0);
    signal data_trimmed : std_ulogic_vector(63 downto 0);
    signal data_latched : std_ulogic_vector(63 downto 0);
    signal perm : permutation_t;
    signal use_second : byte_sel_t;
    signal byte_offset : unsigned(2 downto 0);
    signal brev_lenm1 : unsigned(2 downto 0);
    signal trim_ctl : trim_ctl_t;
    signal rc : std_ulogic;
    signal partial_write : std_ulogic;
    signal sign_extend : std_ulogic;
    signal negative : std_ulogic;
    signal second_word : std_ulogic;
begin
    writeback_0: process(clk)
    begin
        if rising_edge(clk) then
            if partial_write = '1' then
                data_latched <= data_permuted;
            end if;
        end if;
    end process;

    writeback_1: process(all)
        variable x : std_ulogic_vector(0 downto 0);
        variable y : std_ulogic_vector(0 downto 0);
        variable z : std_ulogic_vector(0 downto 0);
        variable w : std_ulogic_vector(0 downto 0);
        variable j : integer;
        variable k : unsigned(3 downto 0);
	variable cf: std_ulogic_vector(3 downto 0);
	variable xe: xer_common_t;
        variable zero : std_ulogic;
        variable sign : std_ulogic;
    begin
        x(0) := e_in.valid;
        y(0) := l_in.valid;
        assert (to_integer(unsigned(x)) + to_integer(unsigned(y))) <= 1 severity failure;

        x(0) := e_in.write_enable;
        y(0) := l_in.write_enable;
        assert (to_integer(unsigned(x)) + to_integer(unsigned(y))) <= 1 severity failure;

        w(0) := e_in.write_cr_enable;
        x(0) := (e_in.write_enable and e_in.rc);
        assert (to_integer(unsigned(w)) + to_integer(unsigned(x))) <= 1 severity failure;

        w_out <= WritebackToRegisterFileInit;
        c_out <= WritebackToCrFileInit;

        complete_out <= '0';
        if e_in.valid = '1' or l_in.valid = '1' then
            complete_out <= '1';
        end if;

        rc <= '0';
        brev_lenm1 <= "000";
        partial_write <= '0';
        second_word <= '0';
	xe := e_in.xerc;
	data_in <= (others => '0');

        if e_in.write_enable = '1' then
            w_out.write_reg <= e_in.write_reg;
            w_out.write_enable <= '1';
            rc <= e_in.rc;
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

        sign_extend <= l_in.sign_extend;
        data_len <= unsigned(l_in.write_len);
        byte_offset <= unsigned(l_in.write_shift);
	if l_in.write_enable = '1' then
            w_out.write_reg <= gpr_to_gspr(l_in.write_reg);
            if l_in.byte_reverse = '1' then
                brev_lenm1 <= unsigned(l_in.write_len(2 downto 0)) - 1;
            end if;
            w_out.write_enable <= '1';
            second_word <= l_in.second_word;
            if l_in.valid = '0' and (data_len + byte_offset > 8) then
                partial_write <= '1';
            end if;
	    xe := l_in.xerc;
        end if;

        -- shift and byte-reverse data bytes
        for i in 0 to 7 loop
            k := ('0' & (to_unsigned(i, 3) xor brev_lenm1)) + ('0' & byte_offset);
            perm(i) <= k(2 downto 0);
            use_second(i) <= k(3);
        end loop;
        for i in 0 to 7 loop
            j := to_integer(perm(i)) * 8;
            data_permuted(i * 8 + 7 downto i * 8) <= l_in.write_data(j + 7 downto j);
        end loop;

        -- If the data can arrive split over two cycles, this will be correct
        -- provided we don't have both sign extension and byte reversal.
        negative <= (data_len(3) and data_permuted(63)) or
		    (data_len(2) and data_permuted(31)) or
		    (data_len(1) and data_permuted(15)) or
                    (data_len(0) and data_permuted(7));

        -- trim and sign-extend
        for i in 0 to 7 loop
            if i < to_integer(data_len) then
                if second_word = '1' then
                    trim_ctl(i) <= '1' & not use_second(i);
                else
                    trim_ctl(i) <= not use_second(i) & '0';
                end if;
            else
                trim_ctl(i) <= '0' & (negative and sign_extend);
            end if;
        end loop;
        for i in 0 to 7 loop
            case trim_ctl(i) is
                when "11" =>
                    data_trimmed(i * 8 + 7 downto i * 8) <= data_latched(i * 8 + 7 downto i * 8);
                when "10" =>
                    data_trimmed(i * 8 + 7 downto i * 8) <= data_permuted(i * 8 + 7 downto i * 8);
                when "01" =>
                    data_trimmed(i * 8 + 7 downto i * 8) <= x"FF";
                when others =>
                    data_trimmed(i * 8 + 7 downto i * 8) <= x"00";
            end case;
        end loop;

        -- deliver to regfile
        if l_in.write_enable = '1' then
            w_out.write_data <= data_trimmed;
        else
            w_out.write_data <= e_in.write_data;
        end if;

        -- Perform CR0 update for RC forms
        -- Note that loads never have a form with an RC bit, therefore this can test e_in.write_data
        if rc = '1' then
            sign := e_in.write_data(63);
            zero := not (or e_in.write_data);
            c_out.write_cr_enable <= '1';
            c_out.write_cr_mask <= num_to_fxm(0);
	    cf(3) := sign;
	    cf(2) := not sign and not zero;
	    cf(1) := zero;
	    cf(0) := xe.so;
	    c_out.write_cr_data(31 downto 28) <= cf;
        end if;
    end process;
end;
