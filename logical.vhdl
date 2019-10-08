library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;

entity logical is
    port (
        rs         : in std_ulogic_vector(63 downto 0);
        rb         : in std_ulogic_vector(63 downto 0);
        op         : in insn_type_t;
        invert_in  : in std_ulogic;
        invert_out : in std_ulogic;
        result     : out std_ulogic_vector(63 downto 0)
        );
end entity logical;

architecture behaviour of logical is
begin
    logical_0: process(all)
        variable rb_adj, tmp : std_ulogic_vector(63 downto 0);
    begin
        rb_adj := rb;
        if invert_in = '1' then
            rb_adj := not rb;
        end if;

        case op is
            when OP_AND =>
                tmp := rs and rb_adj;
            when OP_OR =>
                tmp := rs or rb_adj;
	    when others =>
                tmp := rs xor rb_adj;
        end case;

        result <= tmp;
        if invert_out = '1' then
            result <= not tmp;
        end if;

    end process;
end behaviour;
