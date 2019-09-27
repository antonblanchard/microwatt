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

        i_in         : in Fetch1ToIcacheType;
        i_out        : out IcacheToFetch2Type;

	stall_out    : out std_ulogic;
	flush_in     : in std_ulogic;

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

    -- Storage. Hopefully "cachelines" is a BRAM, the rest is LUTs
    signal cachelines   : cacheline_array;
    signal tags         : cacheline_tag_array;
    signal tags_valid : std_ulogic_vector(NUM_LINES-1 downto 0);
    attribute ram_style : string;
    attribute ram_style of cachelines : signal is "block";
    attribute ram_decomp : string;
    attribute ram_decomp of cachelines : signal is "power";

    -- Cache reload state machine
    type state_type is (IDLE, WAIT_ACK);

    type reg_internal_type is record
	-- Cache hit state (1 cycle BRAM access)
	hit_line  : cacheline_type;
	hit_nia   : std_ulogic_vector(63 downto 0);
	hit_smark : std_ulogic;
	hit_valid : std_ulogic;

	-- Cache miss state (reload state machine)
        state       : state_type;
        wb          : wishbone_master_out;
        store_index : integer range 0 to (NUM_LINES-1);
        store_mask  : std_ulogic_vector(LINE_SIZE_DW-1 downto 0);
    end record;

    signal r : reg_internal_type;

    -- Async signals decoding incoming requests
    signal req_index  : integer range 0 to NUM_LINES-1;
    signal req_tag    : std_ulogic_vector(TAG_BITS-1 downto 0);
    signal req_word   : integer range 0 to LINE_SIZE_DW*2-1;
    signal req_is_hit : std_ulogic;

    -- Return the cache line index (tag index) for an address
    function get_index(addr: std_ulogic_vector(63 downto 0)) return integer is
    begin
        return to_integer(unsigned(addr((OFFSET_BITS+INDEX_BITS-1) downto OFFSET_BITS)));
    end;

    -- Return the word index in a cache line for an address
    function get_word(addr: std_ulogic_vector(63 downto 0)) return integer is
    begin
        return to_integer(unsigned(addr(OFFSET_BITS-1 downto 2)));
    end;

    -- Read a word in a cache line for an address
    function read_word(word: integer; data: cacheline_type) return std_ulogic_vector is
    begin
	return data((word+1)*32-1 downto word*32);
    end;

    -- Calculate the tag value from the address
    function get_tag(addr: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
    begin
        return addr(63 downto OFFSET_BITS+INDEX_BITS);
    end;

begin
    assert ispow2(LINE_SIZE) report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES) report "NUM_LINES not power of 2" severity FAILURE;

    icache_comb : process(all)
    begin
	-- Calculate next index and tag index
        req_index <= get_index(i_in.nia);
        req_tag <= get_tag(i_in.nia);
	req_word <= get_word(i_in.nia);

	-- Test if pending request is a hit
	if tags(req_index) = req_tag then
	    req_is_hit <= tags_valid(req_index);
	else
	    req_is_hit <= '0';
	end if;

	-- Output instruction from current cache line
	--
	-- Note: This is a mild violation of our design principle of having pipeline
	--       stages output from a clean latch. In this case we output the result
	--       of a mux. The alternative would be output an entire cache line
	--       which I prefer not to do just yet.
	--
	i_out.valid <= r.hit_valid;
	i_out.insn <= read_word(get_word(r.hit_nia), r.hit_line);
	i_out.nia <= r.hit_nia;
	i_out.stop_mark <= r.hit_smark;

	-- This needs to match the latching of a new request in icache_hit
	stall_out <= not req_is_hit;

	-- Wishbone requests output (from the cache miss reload machine)
	wishbone_out <= r.wb;
    end process;

    icache_hit : process(clk)
    begin
        if rising_edge(clk) then
	    -- Assume we have nothing valid first
	    r.hit_valid <= '0';

	    -- Are we free to latch a new request ?
	    --
	    -- Note: this test needs to match the equation for generating stall_out
	    --
	    if i_in.req = '1' and req_is_hit = '1' and flush_in = '0' then
		-- Read the cache line (BRAM read port) and remember the NIA
		r.hit_line <= cachelines(req_index);
		r.hit_nia <= i_in.nia;
		r.hit_smark <= i_in.stop_mark;
		r.hit_valid <= '1';

		report "cache hit nia:" & to_hstring(i_in.nia) &
		    " SM:" & std_ulogic'image(i_in.stop_mark) &
		    " idx:" & integer'image(req_index) &
		    " tag:" & to_hstring(req_tag);
	    end if;

	    -- Flush requested ? discard...
	    if flush_in then
		r.hit_valid <= '0';
	    end if;
	end if;
    end process;

    icache_miss : process(clk)
	variable store_dword : std_ulogic_vector(OFFSET_BITS-4 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tags_valid <= (others => '0');
		r.store_mask  <= (others => '0');
                r.state <= IDLE;
                r.wb.cyc <= '0';
                r.wb.stb <= '0';

		-- We only ever do reads on wishbone
		r.wb.dat <= (others => '0');
		r.wb.sel <= "11111111";
		r.wb.we  <= '0';
            end if;

	    -- State machine
            case r.state is
	    when IDLE =>
		-- We need to read a cache line
		if i_in.req = '1' and req_is_hit = '0' then

		    report "cache miss nia:" & to_hstring(i_in.nia) &
			" SM:" & std_ulogic'image(i_in.stop_mark) &
			" idx:" & integer'image(req_index) &
			" tag:" & to_hstring(req_tag);

		    r.state <= WAIT_ACK;
		    r.store_mask  <= (0 => '1', others => '0');
		    r.store_index <= req_index;

		    -- Force misses while reloading that line
		    tags_valid(req_index) <= '0';
		    tags(req_index) <= req_tag;

		    -- Prep for first dword read
		    r.wb.adr <= i_in.nia(63 downto OFFSET_BITS) & (OFFSET_BITS-1 downto 0 => '0');
		    r.wb.cyc <= '1';
		    r.wb.stb <= '1';
		end if;
	    when WAIT_ACK =>
		if wishbone_in.ack = '1' then
		    -- Store the current dword in both the cache
		    for i in 0 to LINE_SIZE_DW-1 loop
			if r.store_mask(i) = '1' then
			    cachelines(r.store_index)(63 + i*64 downto i*64) <= wishbone_in.dat;
			end if;
		    end loop;

		    -- That was the last word ? We are done
		    if r.store_mask(LINE_SIZE_DW-1) = '1' then
			r.state <= IDLE;
			tags_valid(r.store_index) <= '1';
			r.wb.cyc <= '0';
			r.wb.stb <= '0';
		    else
			store_dword := r.wb.adr(OFFSET_BITS-1 downto 3);
			store_dword := std_ulogic_vector(unsigned(store_dword) + 1);
			r.wb.adr(OFFSET_BITS-1 downto 3) <= store_dword;
		    end if;
		    -- Advance to next word
		    r.store_mask <= r.store_mask(LINE_SIZE_DW-2 downto 0) & '0';
		end if;
            end case;
        end if;
    end process;
end;
