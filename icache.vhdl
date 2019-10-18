--
-- Set associative icache
--
-- TODO (in no specific order):
--
--   * Add debug interface to inspect cache content
--   * Add snoop/invalidate path
--   * Add multi-hit error detection
--   * Pipelined bus interface (wb or axi)
--   * Maybe add parity ? There's a few bits free in each BRAM row on Xilinx
--   * Add optimization: service hits on partially loaded lines
--   * Add optimization: (maybe) interrupt reload on fluch/redirect
--   * Check if playing with the geometry of the cache tags allow for more
--     efficient use of distributed RAM and less logic/muxes. Currently we
--     write TAG_BITS width which may not match full ram blocks and might
--     cause muxes to be inferred for "partial writes".
--   * Check if making the read size of PLRU a ROM helps utilization
--
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
        LINE_SIZE : positive := 64;
        -- Number of lines in a set
        NUM_LINES : positive := 32;
        -- Number of ways
        NUM_WAYS  : positive := 4
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
    -- WAY_BITS is the number of bits to select a way
    constant WAY_BITS     : natural := log2(NUM_WAYS);

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
    subtype way_t is integer range 0 to NUM_WAYS-1;

    -- The cache data BRAM organized as described above for each way
    subtype cache_row_t is std_ulogic_vector(wishbone_data_bits-1 downto 0);

    -- The cache tags LUTRAM has a row per set. Vivado is a pain and will
    -- not handle a clean (commented) definition of the cache tags as a 3d
    -- memory. For now, work around it by putting all the tags
    subtype cache_tag_t is std_logic_vector(TAG_BITS-1 downto 0);
--    type cache_tags_set_t is array(way_t) of cache_tag_t;
--    type cache_tags_array_t is array(index_t) of cache_tags_set_t;
    constant TAG_RAM_WIDTH : natural := TAG_BITS * NUM_WAYS;
    subtype cache_tags_set_t is std_logic_vector(TAG_RAM_WIDTH-1 downto 0);
    type cache_tags_array_t is array(index_t) of cache_tags_set_t;

    -- The cache valid bits
    subtype cache_way_valids_t is std_ulogic_vector(NUM_WAYS-1 downto 0);
    type cache_valids_t is array(index_t) of cache_way_valids_t;

    -- Storage. Hopefully "cache_rows" is a BRAM, the rest is LUTs
    signal cache_tags   : cache_tags_array_t;
    signal cache_valids : cache_valids_t;

    attribute ram_style : string;
    attribute ram_style of cache_tags : signal is "distributed";

    -- Cache reload state machine
    type state_t is (IDLE, WAIT_ACK);

    type reg_internal_t is record
	-- Cache hit state (Latches for 1 cycle BRAM access)
	hit_way   : way_t;
	hit_nia   : std_ulogic_vector(63 downto 0);
	hit_smark : std_ulogic;
	hit_valid : std_ulogic;

	-- Cache miss state (reload state machine)
        state            : state_t;
        wb               : wishbone_master_out;
	store_way        : way_t;
        store_index      : index_t;
	store_row        : row_t;
    end record;

    signal r : reg_internal_t;

    -- Async signals on incoming request
    signal req_index   : index_t;
    signal req_row     : row_t;
    signal req_hit_way : way_t;
    signal req_tag     : cache_tag_t;
    signal req_is_hit  : std_ulogic;
    signal req_is_miss : std_ulogic;
    signal req_laddr   : std_ulogic_vector(63 downto 0);

    -- Cache RAM interface
    type cache_ram_out_t is array(way_t) of cache_row_t;
    signal cache_out   : cache_ram_out_t;

    -- PLRU output interface
    type plru_out_t is array(index_t) of std_ulogic_vector(WAY_BITS-1 downto 0);
    signal plru_victim : plru_out_t;
    signal replace_way : way_t;

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
    function is_last_row_addr(addr: wishbone_addr_type) return boolean is
	constant ones : std_ulogic_vector(ROW_LINEBITS-1 downto 0) := (others => '1');
    begin
	return addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS) = ones;
    end;

    -- Returns whether this is the last row of a line
    function is_last_row(row: row_t) return boolean is
	variable row_v : std_ulogic_vector(ROW_BITS-1 downto 0);
	constant ones  : std_ulogic_vector(ROW_LINEBITS-1 downto 0) := (others => '1');
    begin
	row_v := std_ulogic_vector(to_unsigned(row, ROW_BITS));
	return row_v(ROW_LINEBITS-1 downto 0) = ones;
    end;

    -- Return the address of the next row in the current cache line
    function next_row_addr(addr: wishbone_addr_type)
	return std_ulogic_vector is
	variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
	variable result  : wishbone_addr_type;
    begin
	-- Is there no simpler way in VHDL to generate that 3 bits adder ?
	row_idx := addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS);
	row_idx := std_ulogic_vector(unsigned(row_idx) + 1);
	result := addr;
	result(LINE_OFF_BITS-1 downto ROW_OFF_BITS) := row_idx;
	return result;
    end;

    -- Return the next row in the current cache line. We use a dedicated
    -- function in order to limit the size of the generated adder to be
    -- only the bits within a cache line (3 bits with default settings)
    --
    function next_row(row: row_t) return row_t is
	variable row_v   : std_ulogic_vector(ROW_BITS-1 downto 0);
	variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
	variable result  : std_ulogic_vector(ROW_BITS-1 downto 0);
    begin
	row_v := std_ulogic_vector(to_unsigned(row, ROW_BITS));
	row_idx := row_v(ROW_LINEBITS-1 downto 0);
	row_v(ROW_LINEBITS-1 downto 0) := std_ulogic_vector(unsigned(row_idx) + 1);
	return to_integer(unsigned(row_v));
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

    -- Read a tag from a tag memory row
    function read_tag(way: way_t; tagset: cache_tags_set_t) return cache_tag_t is
    begin
	return tagset((way+1) * TAG_BITS - 1 downto way * TAG_BITS);
    end;

    -- Write a tag to tag memory row
    procedure write_tag(way: in way_t; tagset: inout cache_tags_set_t;
			tag: cache_tag_t) is
    begin
	tagset((way+1) * TAG_BITS - 1 downto way * TAG_BITS) := tag;
    end;

begin

    assert LINE_SIZE mod ROW_SIZE = 0;
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
	report "WAY_BITS      = " & natural'image(WAY_BITS);
	wait;
    end process;

    -- Generate a cache RAM for each way
    rams: for i in 0 to NUM_WAYS-1 generate
	signal do_read  : std_ulogic;
	signal do_write : std_ulogic;
	signal rd_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal wr_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal dout     : cache_row_t;
    begin
	way: entity work.cache_ram
	    generic map (
		ROW_BITS => ROW_BITS,
		WIDTH => wishbone_data_bits
		)
	    port map (
		clk     => clk,
		rd_en   => do_read,
		rd_addr => rd_addr,
		rd_data => dout,
		wr_en   => do_write,
		wr_sel  => (others => '1'),
		wr_addr => wr_addr,
		wr_data => wishbone_in.dat
		);
	process(all)
	begin
	    do_read <= '1';
	    do_write <= '0';
	    if wishbone_in.ack = '1' and r.store_way = i then
		do_write <= '1';
	    end if;
	    cache_out(i) <= dout;
	    rd_addr <= std_ulogic_vector(to_unsigned(req_row, ROW_BITS));
	    wr_addr <= std_ulogic_vector(to_unsigned(r.store_row, ROW_BITS));
	end process;
    end generate;
    
    -- Generate PLRUs
    maybe_plrus: if NUM_WAYS > 1 generate
    begin
	plrus: for i in 0 to NUM_LINES-1 generate
	    -- PLRU interface
	    signal plru_acc    : std_ulogic_vector(WAY_BITS-1 downto 0);
	    signal plru_acc_en : std_ulogic;
	    signal plru_out    : std_ulogic_vector(WAY_BITS-1 downto 0);
	    
	begin
	    plru : entity work.plru
		generic map (
		    BITS => WAY_BITS
		    )
		port map (
		    clk => clk,
		    rst => rst,
		    acc => plru_acc,
		    acc_en => plru_acc_en,
		    lru => plru_out
		    );

	    process(req_index, req_is_hit, req_hit_way, req_is_hit, plru_out)
	    begin
		-- PLRU interface
		if req_is_hit = '1' and req_index = i then
		    plru_acc_en <= req_is_hit;
		else
		    plru_acc_en <= '0';
		end if;
		plru_acc <= std_ulogic_vector(to_unsigned(req_hit_way, WAY_BITS));
		plru_victim(i) <= plru_out;
	    end process;
	end generate;
    end generate;

    -- Cache hit detection, output to fetch2 and other misc logic
    icache_comb : process(all)
	variable is_hit  : std_ulogic;
	variable hit_way : way_t;
    begin
	-- Extract line, row and tag from request
        req_index <= get_index(i_in.nia);
        req_row <= get_row(i_in.nia);
        req_tag <= get_tag(i_in.nia);

	-- Calculate address of beginning of cache line, will be
	-- used for cache miss processing if needed
	--
	req_laddr <= i_in.nia(63 downto LINE_OFF_BITS) &
		     (LINE_OFF_BITS-1 downto 0 => '0');

	-- Test if pending request is a hit on any way
	hit_way := 0;
	is_hit := '0';
	for i in way_t loop
	    if i_in.req = '1' and cache_valids(req_index)(i) = '1' then
		if read_tag(i, cache_tags(req_index)) = req_tag then
		    hit_way := i;
		    is_hit := '1';
		end if;
	    end if;
	end loop;

	-- Generate the "hit" and "miss" signals for the synchronous blocks
	req_is_hit  <= i_in.req and is_hit and not flush_in;
	req_is_miss <= i_in.req and not is_hit and not flush_in;
	req_hit_way <= hit_way;

	-- The way to replace on a miss
	replace_way <= to_integer(unsigned(plru_victim(req_index)));

	-- Output instruction from current cache row
	--
	-- Note: This is a mild violation of our design principle of having pipeline
	--       stages output from a clean latch. In this case we output the result
	--       of a mux. The alternative would be output an entire row which
	--       I prefer not to do just yet as it would force fetch2 to know about
	--       some of the cache geometry information.
	--
        i_out.insn <= read_insn_word(r.hit_nia, cache_out(r.hit_way));
	i_out.valid <= r.hit_valid;
	i_out.nia <= r.hit_nia;
	i_out.stop_mark <= r.hit_smark;

	-- Stall fetch1 if we have a miss
	stall_out <= not is_hit;

	-- Wishbone requests output (from the cache miss reload machine)
	wishbone_out <= r.wb;
    end process;

    -- Cache hit synchronous machine
    icache_hit : process(clk)
    begin
        if rising_edge(clk) then
	    -- On a hit, latch the request for the next cycle, when the BRAM data
	    -- will be available on the cache_out output of the corresponding way
	    --
	    if req_is_hit = '1' then
		r.hit_way <= req_hit_way;
		r.hit_nia <= i_in.nia;
		r.hit_smark <= i_in.stop_mark;
		r.hit_valid <= '1';

		report "cache hit nia:" & to_hstring(i_in.nia) &
		    " SM:" & std_ulogic'image(i_in.stop_mark) &
		    " idx:" & integer'image(req_index) &
		    " tag:" & to_hstring(req_tag) &
		    " way: " & integer'image(req_hit_way);
	    else
		r.hit_valid <= '0';

		-- Send stop marks down regardless of validity
		r.hit_smark <= i_in.stop_mark;
	    end if;
	end if;
    end process;

    -- Cache miss/reload synchronous machine
    icache_miss : process(clk)
	variable tagset    : cache_tags_set_t;
	variable stbs_done : boolean;
    begin
        if rising_edge(clk) then
	    -- On reset, clear all valid bits to force misses
            if rst = '1' then
		for i in index_t loop
		    cache_valids(i) <= (others => '0');
		end loop;
                r.state <= IDLE;
                r.wb.cyc <= '0';
                r.wb.stb <= '0';

		-- We only ever do reads on wishbone
		r.wb.dat <= (others => '0');
		r.wb.sel <= "11111111";
		r.wb.we  <= '0';

		-- Not useful normally but helps avoiding tons of sim warnings
		r.wb.adr <= (others => '0');
            else
		-- Main state machine
		case r.state is
		when IDLE =>
		    -- We need to read a cache line
		    if req_is_miss = '1' then
			report "cache miss nia:" & to_hstring(i_in.nia) &
			    " SM:" & std_ulogic'image(i_in.stop_mark) &
			    " idx:" & integer'image(req_index) &
			    " way:" & integer'image(replace_way) &
			    " tag:" & to_hstring(req_tag);

			-- Force misses on that way while reloading that line
			cache_valids(req_index)(replace_way) <= '0';

			-- Store new tag in selected way
			for i in 0 to NUM_WAYS-1 loop
			    if i = replace_way then
				tagset := cache_tags(req_index);
				write_tag(i, tagset, req_tag);
				cache_tags(req_index) <= tagset;
			    end if;
			end loop;

			-- Keep track of our index and way for subsequent stores
			r.store_index <= req_index;
			r.store_way <= replace_way;
			r.store_row <= get_row(req_laddr);

			-- Prep for first wishbone read. We calculate the address of
			-- the start of the cache line and start the WB cycle.
			--
			r.wb.adr <= req_laddr(r.wb.adr'left downto 0);
			r.wb.cyc <= '1';
			r.wb.stb <= '1';

			-- Track that we had one request sent
			r.state <= WAIT_ACK;
		    end if;

		when WAIT_ACK =>
		    -- Requests are all sent if stb is 0
		    stbs_done := r.wb.stb = '0';

		    -- If we are still sending requests, was one accepted ?
		    if wishbone_in.stall = '0' and not stbs_done then
			-- That was the last word ? We are done sending. Clear
			-- stb and set stbs_done so we can handle an eventual last
			-- ack on the same cycle.
			--
			if is_last_row_addr(r.wb.adr) then
			    r.wb.stb <= '0';
			    stbs_done := true;
			end if;

			-- Calculate the next row address
			r.wb.adr <= next_row_addr(r.wb.adr);
		    end if;

		    -- Incoming acks processing
		    if wishbone_in.ack = '1' then
			-- Check for completion
			if stbs_done and is_last_row(r.store_row) then
			    -- Complete wishbone cycle
			    r.wb.cyc <= '0';

			    -- Cache line is now valid
			    cache_valids(r.store_index)(r.store_way) <= '1';

			    -- We are done
			    r.state <= IDLE;
			end if;

			-- Increment store row counter
			r.store_row <= next_row(r.store_row);
		    end if;
		end case;
	    end if;
	end if;
    end process;
end;
