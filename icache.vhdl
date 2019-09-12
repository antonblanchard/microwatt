library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

-- 64 bit direct mapped icache. All instructions are 4B aligned.

entity icache is
    generic (
        -- Line size in 64bit doublewords
        LINE_SIZE_DW : natural := 8;
        -- Number of lines
        NUM_LINES : natural := 32
        );
    port (
        clk          : in std_ulogic;
        rst          : in std_ulogic;

        i_in         : in Fetch2ToIcacheType;
        i_out        : out IcacheToFetch2Type;

        wishbone_out : out wishbone_master_out;
        wishbone_in  : in wishbone_slave_out
        );
end entity icache;

architecture rtl of icache is
    function log2(i : natural) return integer is
        variable tmp : integer := i;
        variable ret : integer := 0;
    begin
        while tmp > 1 loop
            ret  := ret + 1;
            tmp := tmp / 2;
        end loop;
        return ret;
    end function;

    function ispow2(i : integer) return boolean is
    begin
        if to_integer(to_unsigned(i, 32) and to_unsigned(i - 1, 32)) = 0 then
            return true;
        else
            return false;
        end if;
    end function;

    constant LINE_SIZE : natural := LINE_SIZE_DW*8;
    constant OFFSET_BITS : natural := log2(LINE_SIZE);
    constant INDEX_BITS : natural := log2(NUM_LINES);
    constant TAG_BITS : natural := 64 - OFFSET_BITS - INDEX_BITS;

    subtype cacheline_type is std_logic_vector((LINE_SIZE*8)-1 downto 0);
    type cacheline_array is array(0 to NUM_LINES-1) of cacheline_type;

    subtype cacheline_tag_type is std_logic_vector(TAG_BITS-1 downto 0);
    type cacheline_tag_array is array(0 to NUM_LINES-1) of cacheline_tag_type;

    signal cachelines : cacheline_array := (others => (others => '0'));
    signal tags       : cacheline_tag_array := (others => (others => '0'));
    signal tags_valid : std_ulogic_vector(NUM_LINES-1 downto 0) := (others => '0');

    attribute ram_style : string;
    attribute ram_style of cachelines : signal is "block";

    attribute ram_decomp : string;
    attribute ram_decomp of cachelines : signal is "power";

    type state_type is (IDLE, WAIT_ACK);

    type reg_internal_type is record
        state : state_type;
        w     : wishbone_master_out;
        store_index     : integer range 0 to (NUM_LINES-1);
        store_word  : integer range 0 to (LINE_SIZE-1);
    end record;

    signal r : reg_internal_type;

    signal read_index : integer range 0 to NUM_LINES-1;
    signal read_tag   : std_ulogic_vector(63-OFFSET_BITS-INDEX_BITS downto 0);
    signal read_miss  : boolean;

    function get_index(addr: std_ulogic_vector(63 downto 0)) return integer is
    begin
        return to_integer(unsigned(addr((OFFSET_BITS+INDEX_BITS-1) downto OFFSET_BITS)));
    end;

    function get_word(addr: std_ulogic_vector(63 downto 0); data: cacheline_type) return std_ulogic_vector is
        variable word : integer;
    begin
        word := to_integer(unsigned(addr(OFFSET_BITS-1 downto 2)));
        return data((word+1)*32-1 downto word*32);
    end;

    function get_tag(addr: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
    begin
        return addr(63 downto OFFSET_BITS+INDEX_BITS);
    end;
begin
    assert ispow2(LINE_SIZE) report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES) report "NUM_LINES not power of 2" severity FAILURE;

    icache_read : process(all)
    begin
        read_index <= get_index(i_in.addr);
        read_tag <= get_tag(i_in.addr);
        read_miss <= false;

        i_out.ack <= '0';
        i_out.insn <= get_word(i_in.addr, cachelines(read_index));

        if i_in.req = '1' then
            if (tags_valid(read_index) = '1') and (tags(read_index) = read_tag) then
                -- report hit asynchronously
                i_out.ack <= '1';
            else
                read_miss <= true;
            end if;
        end if;
    end process;

    wishbone_out <= r.w;

    icache_write : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tags_valid <= (others => '0');
                r.state <= IDLE;
                r.w.cyc <= '0';
                r.w.stb <= '0';
            end if;

            r.w.dat <= (others => '0');
            r.w.sel <= "11111111";
            r.w.we  <= '0';

            case r.state is
                when IDLE =>
                    if read_miss = true then
                        r.state <= WAIT_ACK;
                        r.store_word <= 0;
                        r.store_index <= read_index;

                        tags(read_index) <= read_tag;
                        tags_valid(read_index) <= '0';

                        r.w.adr <= i_in.addr(63 downto OFFSET_BITS) & (OFFSET_BITS-1 downto 0 => '0');
                        r.w.cyc <= '1';
                        r.w.stb <= '1';
                    end if;
                when WAIT_ACK =>
                    if wishbone_in.ack = '1' then
                        cachelines(r.store_index)((r.store_word+1)*64-1 downto ((r.store_word)*64)) <= wishbone_in.dat;
                        r.store_word <= r.store_word + 1;

                        if r.store_word = (LINE_SIZE_DW-1) then
                            r.state <= IDLE;
                            tags_valid(r.store_index) <= '1';
                            r.w.cyc <= '0';
                            r.w.stb <= '0';
                        else
                            r.w.adr(OFFSET_BITS-1 downto 3) <= std_ulogic_vector(to_unsigned(r.store_word+1, OFFSET_BITS-3));
                        end if;
                    end if;
            end case;
        end if;
    end process;
end;
