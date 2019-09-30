library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

-- 64 bit direct mapped icache. All instructions are 4B aligned.

entity icache is
    generic (
        -- Line size in bytes
        LINE_SIZE : natural := 64;
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

    -- BRAM organisation: We never access more than wishbone_data_bits at
    -- a time so to save resources we make the array only that wide, and
    -- use consecutive indices for to make a cache "line"
    --
    -- ROW_SIZE is the width in bytes of the BRAM (based on WB, so 64-bits)
    constant ROW_SIZE      : natural := wishbone_data_bits / 8;
    -- ROW_PER_LINE is the number of row (wishbone transactions) in a line
    constant ROW_PER_LINE  : natural := LINE_SIZE / ROW_SIZE;
    -- BRAM_ROWS is the number of rows in BRAM needed to represent the full
    -- icache
    constant BRAM_ROWS     : natural := NUM_LINES * ROW_PER_LINE;
    -- INSN_PER_ROW is the number of 32bit instructions per BRAM row
    constant INSN_PER_ROW  : natural := wishbone_data_bits / 32;
    -- Bit fields counts in the address

    -- INSN_BITS is the number of bits to select an instruction in a row
    constant INSN_BITS     : natural := log2(INSN_PER_ROW);
    -- ROW_BITS is the number of bits to select a row 
    constant ROW_BITS      : natural := log2(BRAM_ROWS);
    -- ROW_LINEBITS is the number of bits to select a row within a line
    constant ROW_LINEBITS  : natural := log2(ROW_PER_LINE);
    -- LINE_OFF_BITS is the number of bits for the offset in a cache line
    constant LINE_OFF_BITS : natural := log2(LINE_SIZE);
    -- ROW_OFF_BITS is the number of bits for the offset in a row
    constant ROW_OFF_BITS  : natural := log2(ROW_SIZE);
    -- INDEX_BITS is the number if bits to select a cache line
    constant INDEX_BITS    : natural := log2(NUM_LINES);
    -- TAG_BITS is the number of bits of the tag part of the address
    constant TAG_BITS      : natural := 64 - LINE_OFF_BITS - INDEX_BITS;

    -- Example of layout for 32 lines of 64 bytes:
    --
    -- ..  tag    |index|  line  |
    -- ..         |   row   |    |
    -- ..         |     |   | |00| zero          (2)
    -- ..         |     |   |-|  | INSN_BITS     (1)
    -- ..         |     |---|    | ROW_LINEBITS  (3)
    -- ..         |     |--- - --| LINE_OFF_BITS (6)
    -- ..         |         |- --| ROW_OFF_BITS  (3)
    -- ..         |----- ---|    | ROW_BITS      (8)
    -- ..         |-----|        | INDEX_BITS    (5)
    -- .. --------|              | TAG_BITS      (53)

    subtype row_t is integer range 0 to BRAM_ROWS-1;
    subtype index_t is integer range 0 to NUM_LINES-1;

    -- The cache data BRAM organized as described above
    subtype cache_row_t is std_logic_vector(wishbone_data_bits-1 downto 0);
    type cache_array is array(row_t) of cache_row_t;

    -- The cache tags LUTRAM has a row per cache line
    subtype cache_tag_t is std_logic_vector(TAG_BITS-1 downto 0);
    type cache_tags_array is array(index_t) of cache_tag_t;

    -- Storage. Hopefully "cache_rows" is a BRAM, the rest is LUTs
    signal cache_rows   : cache_array;
    signal tags         : cache_tags_array;
    signal tags_valid   : std_ulogic_vector(NUM_LINES-1 downto 0);
    attribute ram_style : string;
    attribute ram_style of cache_rows : signal is "block";
    attribute ram_decomp : string;
    attribute ram_decomp of cache_rows : signal is "power";

    -- Cache reload state machine
    type state_t is (IDLE, WAIT_ACK);

    type reg_internal_t is record
	-- Cache hit state (1 cycle BRAM access)
	hit_row   : cache_row_t;
	hit_nia   : std_ulogic_vector(63 downto 0);
	hit_smark : std_ulogic;
	hit_valid : std_ulogic;

	-- Cache miss state (reload state machine)
        state            : state_t;
        wb               : wishbone_master_out;
        store_index      : index_t;
    end record;

    signal r : reg_internal_t;

    -- Async signals on incoming request
    signal req_index  : index_t;
    signal req_row    : row_t;
    signal req_tag    : cache_tag_t;
    signal req_is_hit : std_ulogic;

    -- Return the cache line index (tag index) for an address
    function get_index(addr: std_ulogic_vector(63 downto 0)) return index_t is
    begin
        return to_integer(unsigned(addr(63-TAG_BITS downto LINE_OFF_BITS)));
    end;

    -- Return the cache row index (data memory) for an address
    function get_row(addr: std_ulogic_vector(63 downto 0)) return row_t is
    begin
        return to_integer(unsigned(addr(63-TAG_BITS downto ROW_OFF_BITS)));
    end;

    -- Returns whether this is the last row of a line
    function is_last_row(addr: std_ulogic_vector(63 downto 0)) return boolean is
	constant ones : std_ulogic_vector(ROW_LINEBITS-1 downto 0) := (others => '1');
    begin
	return addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS) = ones;
    end;

    -- Return the address of the next row in the current cache line
    function next_row_addr(addr: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
	variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
	variable result  : std_ulogic_vector(63 downto 0);
    begin
	-- Is there no simpler way in VHDL to generate that 3 bits adder ?
	row_idx := addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS);
	row_idx := std_ulogic_vector(unsigned(row_idx) + 1);
	result := addr;
	result(LINE_OFF_BITS-1 downto ROW_OFF_BITS) := row_idx;
	return result;
    end;

    -- Read the instruction word for the given address in the current cache row
    function read_insn_word(addr: std_ulogic_vector(63 downto 0);
			    data: cache_row_t) return std_ulogic_vector is
	variable word: integer range 0 to INSN_PER_ROW-1;
    begin
        word := to_integer(unsigned(addr(INSN_BITS+2-1 downto 2)));
	return data(31+word*32 downto word*32);
    end;

    -- Get the tag value from the address
    function get_tag(addr: std_ulogic_vector(63 downto 0)) return cache_tag_t is
    begin
        return addr(63 downto 64-TAG_BITS);
    end;

begin
    assert ispow2(LINE_SIZE)    report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES)    report "NUM_LINES not power of 2" severity FAILURE;
    assert ispow2(ROW_PER_LINE) report "ROW_PER_LINE not power of 2" severity FAILURE;
    assert ispow2(INSN_PER_ROW) report "INSN_PER_ROW not power of 2" severity FAILURE;
    assert (ROW_BITS = INDEX_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (LINE_OFF_BITS = ROW_OFF_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = TAG_BITS + INDEX_BITS + LINE_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = TAG_BITS + ROW_BITS + ROW_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;

    debug: process
    begin
	report "ROW_SIZE      = " & natural'image(ROW_SIZE);
	report "ROW_PER_LINE  = " & natural'image(ROW_PER_LINE);
	report "BRAM_ROWS     = " & natural'image(BRAM_ROWS);
	report "INSN_PER_ROW  = " & natural'image(INSN_PER_ROW);
	report "INSN_BITS     = " & natural'image(INSN_BITS);
	report "ROW_BITS      = " & natural'image(ROW_BITS);
	report "ROW_LINEBITS  = " & natural'image(ROW_LINEBITS);
	report "LINE_OFF_BITS = " & natural'image(LINE_OFF_BITS);
	report "ROW_OFF_BITS  = " & natural'image(ROW_OFF_BITS);
	report "INDEX_BITS    = " & natural'image(INDEX_BITS);
	report "TAG_BITS      = " & natural'image(TAG_BITS);
	wait;
    end process;

    icache_comb : process(all)
    begin
	-- Extract line, row and tag from request
        req_index <= get_index(i_in.nia);
        req_row <= get_row(i_in.nia);
        req_tag <= get_tag(i_in.nia);

	-- Test if pending request is a hit
	if tags(req_index) = req_tag then
	    req_is_hit <= tags_valid(req_index);
	else
	    req_is_hit <= '0';
	end if;

	-- Output instruction from current cache row
	--
	-- Note: This is a mild violation of our design principle of having pipeline
	--       stages output from a clean latch. In this case we output the result
	--       of a mux. The alternative would be output an entire cache line
	--       which I prefer not to do just yet.
	--
        i_out.insn <= read_insn_word(r.hit_nia, r.hit_row);
	i_out.valid <= r.hit_valid;
	i_out.nia <= r.hit_nia;
	i_out.stop_mark <= r.hit_smark;

	-- This needs to match the latching of a new request in process icache_hit
	stall_out <= not req_is_hit;

	-- Wishbone requests output (from the cache miss reload machine)
	wishbone_out <= r.wb;
    end process;

    icache_hit : process(clk)
    begin
        if rising_edge(clk) then
	    -- Debug
	    if i_in.req = '1' then
		report "cache search for " & to_hstring(i_in.nia) &
		    " index:" & integer'image(req_index) &
		    " row:" & integer'image(req_row) &
		    " want_tag:" & to_hstring(req_tag) & " got_tag:" & to_hstring(req_tag) &
		    " valid:" & std_ulogic'image(tags_valid(req_index));
		if req_is_hit = '1' then
		    report "is hit !";
		else
		    report "is miss !";
		end if;
	    end if;

	    -- Are we free to latch a new request ?
	    --
	    -- Note: this test needs to match the equation for generating stall_out
	    --
	    if i_in.req = '1' and req_is_hit = '1' and flush_in = '0' then
		-- Read the cache line (BRAM read port) and remember the NIA
		r.hit_row <= cache_rows(req_row);
		r.hit_nia <= i_in.nia;
		r.hit_smark <= i_in.stop_mark;
		r.hit_valid <= '1';

		report "cache hit nia:" & to_hstring(i_in.nia) &
		    " SM:" & std_ulogic'image(i_in.stop_mark) &
		    " idx:" & integer'image(req_index) &
		    " tag:" & to_hstring(req_tag);
	    else
		r.hit_valid <= '0';
		-- Send stop marks down regardless of validity
		r.hit_smark <= i_in.stop_mark;
	    end if;
	end if;
    end process;

    icache_miss : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tags_valid <= (others => '0');
                r.state <= IDLE;
                r.wb.cyc <= '0';
                r.wb.stb <= '0';

		-- We only ever do reads on wishbone
		r.wb.dat <= (others => '0');
		r.wb.sel <= "11111111";
		r.wb.we  <= '0';
            else
		-- State machine
		case r.state is
		when IDLE =>
		    -- We need to read a cache line
		    if i_in.req = '1' and req_is_hit = '0' then
			report "cache miss nia:" & to_hstring(i_in.nia) &
			    " SM:" & std_ulogic'image(i_in.stop_mark) &
			    " idx:" & integer'image(req_index) &
			    " tag:" & to_hstring(req_tag);

			-- Force misses while reloading that line
			tags_valid(req_index) <= '0';
			tags(req_index) <= req_tag;
			r.store_index <= req_index;

			-- Prep for first wishbone read. We calculate the address off
			-- the start of the cache line
			r.wb.adr <= i_in.nia(63 downto LINE_OFF_BITS) &
				    (LINE_OFF_BITS-1 downto 0 => '0');
			r.wb.cyc <= '1';
			r.wb.stb <= '1';

			r.state <= WAIT_ACK;
		    end if;
		when WAIT_ACK =>
		    if wishbone_in.ack = '1' then
			-- Store the current dword in both the cache
			cache_rows(get_row(r.wb.adr)) <= wishbone_in.dat;

			-- That was the last word ? We are done
			if is_last_row(r.wb.adr) then
			    tags_valid(r.store_index) <= '1';
			    r.wb.cyc <= '0';
			    r.wb.stb <= '0';
			    r.state <= IDLE;
			else
			    -- Otherwise, calculate the next row address
			    r.wb.adr <= next_row_addr(r.wb.adr);
			end if;
		    end if;
		end case;
	    end if;
	end if;
    end process;
end;
