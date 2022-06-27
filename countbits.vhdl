library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.helpers.all;

entity bit_counter is
    port (
        clk         : in std_logic;
        rs          : in std_ulogic_vector(63 downto 0);
        stall       : in std_ulogic;
        count_right : in std_ulogic;
        do_popcnt   : in std_ulogic;
        is_32bit    : in std_ulogic;
        datalen     : in std_ulogic_vector(3 downto 0);
        result      : out std_ulogic_vector(63 downto 0)
        );
end entity bit_counter;

architecture behaviour of bit_counter is
    -- signals for count-leading/trailing-zeroes
    signal inp : std_ulogic_vector(63 downto 0);
    signal inp_r : std_ulogic_vector(63 downto 0);
    signal sum : std_ulogic_vector(64 downto 0);
    signal sum_r : std_ulogic_vector(64 downto 0);
    signal onehot : std_ulogic_vector(63 downto 0);
    signal edge : std_ulogic_vector(63 downto 0);
    signal bitnum : std_ulogic_vector(5 downto 0);
    signal cntz : std_ulogic_vector(63 downto 0);

    -- signals for popcnt
    signal dlen_r   : std_ulogic_vector(3 downto 0);
    signal pcnt_r   : std_ulogic;
    subtype twobit is unsigned(1 downto 0);
    type twobit32 is array(0 to 31) of twobit;
    signal pc2      : twobit32;
    subtype threebit is unsigned(2 downto 0);
    type threebit16 is array(0 to 15) of threebit;
    signal pc4      : threebit16;
    subtype fourbit is unsigned(3 downto 0);
    type fourbit8 is array(0 to 7) of fourbit;
    signal pc8      : fourbit8;
    signal pc8_r    : fourbit8;
    subtype sixbit is unsigned(5 downto 0);
    type sixbit2 is array(0 to 1) of sixbit;
    signal pc32     : sixbit2;
    signal popcnt   : std_ulogic_vector(63 downto 0);

begin
    countzero_r: process(clk)
    begin
        if rising_edge(clk) and stall = '0' then
            inp_r <= inp;
            sum_r <= sum;
        end if;
    end process;

    countzero: process(all)
        variable bitnum_e, bitnum_o : std_ulogic_vector(5 downto 0);
    begin
        if is_32bit = '0' then
            if count_right = '0' then
                inp <= bit_reverse(rs);
            else
                inp <= rs;
            end if;
        else
            inp(63 downto 32) <= x"FFFFFFFF";
            if count_right = '0' then
                inp(31 downto 0) <= bit_reverse(rs(31 downto 0));
            else
                inp(31 downto 0) <= rs(31 downto 0);
            end if;
        end if;

        sum <= std_ulogic_vector(unsigned('0' & not inp) + 1);

        -- The following occurs after a clock edge
        edge <= sum_r(63 downto 0) or inp_r;
        bitnum_e := edgelocation(edge, 6);
        onehot <= sum_r(63 downto 0) and inp_r;
        bitnum_o := bit_number(onehot);
        bitnum(5 downto 2) <= bitnum_e(5 downto 2);
        bitnum(1 downto 0) <= bitnum_o(1 downto 0);

        cntz <= 57x"0" & sum_r(64) & bitnum;
    end process;

    popcnt_r: process(clk)
    begin
        if rising_edge(clk) and stall = '0' then
            for i in 0 to 7 loop
                pc8_r(i) <= pc8(i);
            end loop;
            dlen_r <= datalen;
            pcnt_r <= do_popcnt;
        end if;
    end process;

    popcnt_a: process(all)
    begin
        for i in 0 to 31 loop
            pc2(i) <= unsigned("0" & rs(i * 2 downto i * 2)) + unsigned("0" & rs(i * 2 + 1 downto i * 2 + 1));
        end loop;
        for i in 0 to 15 loop
            pc4(i) <= ('0' & pc2(i * 2)) + ('0' & pc2(i * 2 + 1));
        end loop;
        for i in 0 to 7 loop
            pc8(i) <= ('0' & pc4(i * 2)) + ('0' & pc4(i * 2 + 1));
        end loop;

        -- after a clock edge
        for i in 0 to 1 loop
            pc32(i) <= ("00" & pc8_r(i * 4)) + ("00" & pc8_r(i * 4 + 1)) +
                       ("00" & pc8_r(i * 4 + 2)) + ("00" & pc8_r(i * 4 + 3));
        end loop;
        
        popcnt <= (others => '0');
        if dlen_r(3 downto 2) = "00" then
            -- popcntb
            for i in 0 to 7 loop
                popcnt(i * 8 + 3 downto i * 8) <= std_ulogic_vector(pc8_r(i));
            end loop;
        elsif dlen_r(3) = '0' then
            -- popcntw
            for i in 0 to 1 loop
                popcnt(i * 32 + 5 downto i * 32) <= std_ulogic_vector(pc32(i));
            end loop;
        else
            popcnt(6 downto 0) <= std_ulogic_vector(('0' & pc32(0)) + ('0' & pc32(1)));
        end if;
    end process;

    result <= cntz when pcnt_r = '0' else popcnt;

end behaviour;
