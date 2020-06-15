library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.ppc_fx_insns.all;

entity logical is
    port (
        rs         : in std_ulogic_vector(63 downto 0);
        rb         : in std_ulogic_vector(63 downto 0);
        op         : in insn_type_t;
        invert_in  : in std_ulogic;
        invert_out : in std_ulogic;
        result     : out std_ulogic_vector(63 downto 0);
        datalen    : in std_logic_vector(3 downto 0)
        );
end entity logical;

architecture behaviour of logical is

    subtype twobit is unsigned(1 downto 0);
    type twobit32 is array(0 to 31) of twobit;
    signal pc2      : twobit32;
    subtype threebit is unsigned(2 downto 0);
    type threebit16 is array(0 to 15) of threebit;
    signal pc4      : threebit16;
    subtype fourbit is unsigned(3 downto 0);
    type fourbit8 is array(0 to 7) of fourbit;
    signal pc8      : fourbit8;
    subtype sixbit is unsigned(5 downto 0);
    type sixbit2 is array(0 to 1) of sixbit;
    signal pc32     : sixbit2;
    signal par0, par1 : std_ulogic;
    signal popcnt   : std_ulogic_vector(63 downto 0);
    signal parity   : std_ulogic_vector(63 downto 0);

begin
    logical_0: process(all)
        variable rb_adj, tmp : std_ulogic_vector(63 downto 0);
        variable negative : std_ulogic;
    begin
        -- population counts
        for i in 0 to 31 loop
            pc2(i) <= unsigned("0" & rs(i * 2 downto i * 2)) + unsigned("0" & rs(i * 2 + 1 downto i * 2 + 1));
        end loop;
        for i in 0 to 15 loop
            pc4(i) <= ('0' & pc2(i * 2)) + ('0' & pc2(i * 2 + 1));
        end loop;
        for i in 0 to 7 loop
            pc8(i) <= ('0' & pc4(i * 2)) + ('0' & pc4(i * 2 + 1));
        end loop;
        for i in 0 to 1 loop
            pc32(i) <= ("00" & pc8(i * 4)) + ("00" & pc8(i * 4 + 1)) +
                       ("00" & pc8(i * 4 + 2)) + ("00" & pc8(i * 4 + 3));
        end loop;
        popcnt <= (others => '0');
        if datalen(3 downto 2) = "00" then
            -- popcntb
            for i in 0 to 7 loop
                popcnt(i * 8 + 3 downto i * 8) <= std_ulogic_vector(pc8(i));
            end loop;
        elsif datalen(3) = '0' then
            -- popcntw
            for i in 0 to 1 loop
                popcnt(i * 32 + 5 downto i * 32) <= std_ulogic_vector(pc32(i));
            end loop;
        else
            popcnt(6 downto 0) <= std_ulogic_vector(('0' & pc32(0)) + ('0' & pc32(1)));
        end if;

        -- parity calculations
        par0 <= rs(0) xor rs(8) xor rs(16) xor rs(24);
        par1 <= rs(32) xor rs(40) xor rs(48) xor rs(56);
        parity <= (others => '0');
        if datalen(3) = '1' then
            parity(0) <= par0 xor par1;
        else
            parity(0) <= par0;
            parity(32) <= par1;
        end if;

        rb_adj := rb;
        if invert_in = '1' then
            rb_adj := not rb;
        end if;

        case op is
            when OP_AND =>
                tmp := rs and rb_adj;
            when OP_OR =>
                tmp := rs or rb_adj;
	    when OP_XOR =>
                tmp := rs xor rb_adj;
            when OP_POPCNT =>
                tmp := popcnt;
            when OP_PRTY =>
                tmp := parity;
            when OP_CMPB =>
                tmp := ppc_cmpb(rs, rb);
            when others =>
                -- EXTS
                -- note datalen is a 1-hot encoding
		negative := (datalen(0) and rs(7)) or
			    (datalen(1) and rs(15)) or
			    (datalen(2) and rs(31));
		tmp := (others => negative);
		if datalen(2) = '1' then
		    tmp(31 downto 16) := rs(31 downto 16);
		end if;
		if datalen(2) = '1' or datalen(1) = '1' then
		    tmp(15 downto 8) := rs(15 downto 8);
		end if;
		tmp(7 downto 0) := rs(7 downto 0);
        end case;

        if invert_out = '1' then
            tmp := not tmp;
        end if;
        result <= tmp;

    end process;
end behaviour;
