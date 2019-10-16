--
-- Set associative dcache write-through
--
-- TODO (in no specific order):
--
-- * See list in icache.vhdl
-- * Complete load misses on the cycle when WB data comes instead of
--   at the end of line (this requires dealing with requests coming in
--   while not idle...)
-- * Load with update could use one less non-pipelined cycle by moving
--   the register update to the pipeline bubble that exists when going
--   back to the IDLE state.
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.helpers.all;
use work.wishbone_types.all;

entity dcache is
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

        d_in         : in Loadstore1ToDcacheType;
        d_out        : out DcacheToWritebackType;

	stall_out    : out std_ulogic;

        wishbone_out : out wishbone_master_out;
        wishbone_in  : in wishbone_slave_out
        );
end entity dcache;

architecture rtl of dcache is
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
    -- dcache
    constant BRAM_ROWS     : natural := NUM_LINES * ROW_PER_LINE;

    -- Bit fields counts in the address

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

    -- Type of operation on a "valid" input
    type op_t is (OP_NONE,
		  OP_LOAD_HIT,      -- Cache hit on load
		  OP_LOAD_MISS,     -- Load missing cache
		  OP_LOAD_NC,       -- Non-cachable load
		  OP_BAD,           -- BAD: Cache hit on NC load/store
		  OP_STORE_HIT,     -- Store hitting cache
		  OP_STORE_MISS);   -- Store missing cache
		      
    -- Cache state machine
    type state_t is (IDLE,	       -- Normal load hit processing
		     LOAD_UPDATE,      -- Load with update extra cycle
		     LOAD_UPDATE2,     -- Load with update extra cycle
		     RELOAD_WAIT_ACK,  -- Cache reload wait ack
		     STORE_WAIT_ACK,   -- Store wait ack
		     NC_LOAD_WAIT_ACK);-- Non-cachable load wait ack


    --
    -- Dcache operations:
    --
    -- In order to make timing, we use the BRAMs with an output buffer,
    -- which means that the BRAM output is delayed by an extra cycle.
    --
    -- Thus, the dcache has a 2-stage internal pipeline for cache hits
    -- with no stalls.
    --
    -- All other operations are handled via stalling in the first stage.
    --
    -- The second stage can thus complete a hit at the same time as the
    -- first stage emits a stall for a complex op.
    --

    -- First stage register, contains state for stage 1 of load hits
    -- and for the state machine used by all other operations
    --
    type reg_stage_1_t is record
	-- Latch the complete request from ls1
	req              : Loadstore1ToDcacheType;

	-- Cache hit state
	hit_way          : way_t;
	hit_load_valid   : std_ulogic;

	-- Register update (load/store with update)
	update_valid     : std_ulogic;

	-- Data buffer for "slow" read ops (load miss and NC loads).
	slow_data        : std_ulogic_vector(63 downto 0);
	slow_valid       : std_ulogic;

	-- Cache miss state (reload state machine)
        state            : state_t;
        wb               : wishbone_master_out;
	store_way        : way_t;
        store_index      : index_t;
    end record;

    signal r1 : reg_stage_1_t;

    -- Second stage register, only used for load hits
    --
    type reg_stage_2_t is record
	hit_way        : way_t;
	hit_load_valid : std_ulogic;
	load_is_update : std_ulogic;
	load_reg       : std_ulogic_vector(4 downto 0);
	data_shift     : std_ulogic_vector(2 downto 0);
	length         : std_ulogic_vector(3 downto 0);
	sign_extend    : std_ulogic;
	byte_reverse   : std_ulogic;
    end record;

    signal r2 : reg_stage_2_t;

    -- Async signals on incoming request
    signal req_index   : index_t;
    signal req_row     : row_t;
    signal req_hit_way : way_t;
    signal req_tag     : cache_tag_t;
    signal req_op      : op_t;

    -- Cache RAM interface
    type cache_ram_out_t is array(way_t) of cache_row_t;
    signal cache_out   : cache_ram_out_t;

    -- PLRU output interface
    type plru_out_t is array(index_t) of std_ulogic_vector(WAY_BITS-1 downto 0);
    signal plru_victim : plru_out_t;

    -- Wishbone read/write/cache write formatting signals
    signal bus_sel                  : wishbone_sel_type;
    signal store_data               : wishbone_data_type;
    
    --
    -- Helper functions to decode incoming requests
    --

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

    -- Generate byte enables from sizes
    function length_to_sel(length : in std_logic_vector(3 downto 0)) return std_ulogic_vector is
    begin
        case length is
            when "0001" =>
                return "00000001";
            when "0010" =>
                return "00000011";
            when "0100" =>
                return "00001111";
            when "1000" =>
                return "11111111";
            when others =>
                return "00000000";
        end case;
    end function length_to_sel;

    -- Calculate shift and byte enables for wishbone
    function wishbone_data_shift(address : in std_ulogic_vector(63 downto 0)) return natural is
    begin
        return to_integer(unsigned(address(2 downto 0))) * 8;
    end function wishbone_data_shift;

    function wishbone_data_sel(size : in std_logic_vector(3 downto 0);
			       address : in std_logic_vector(63 downto 0))
	return std_ulogic_vector is
    begin
        return std_ulogic_vector(shift_left(unsigned(length_to_sel(size)),
					    to_integer(unsigned(address(2 downto 0)))));
    end function wishbone_data_sel;

begin

    assert LINE_SIZE mod ROW_SIZE = 0 report "LINE_SIZE not multiple of ROW_SIZE" severity FAILURE;
    assert ispow2(LINE_SIZE)    report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES)    report "NUM_LINES not power of 2" severity FAILURE;
    assert ispow2(ROW_PER_LINE) report "ROW_PER_LINE not power of 2" severity FAILURE;
    assert (ROW_BITS = INDEX_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (LINE_OFF_BITS = ROW_OFF_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = TAG_BITS + INDEX_BITS + LINE_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = TAG_BITS + ROW_BITS + ROW_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = wishbone_data_bits)
	report "Can't yet handle a wishbone width that isn't 64-bits" severity FAILURE;
    
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

	    process(req_index, req_op, req_hit_way, plru_out)
	    begin
		-- PLRU interface
		if (req_op = OP_LOAD_HIT or
		    req_op = OP_STORE_HIT) and req_index = i then
		    plru_acc_en <= '1';
		else
		    plru_acc_en <= '0';
		end if;
		plru_acc <= std_ulogic_vector(to_unsigned(req_hit_way, WAY_BITS));
		plru_victim(i) <= plru_out;
	    end process;
	end generate;
    end generate;

    -- Cache request parsing and hit detection
    dcache_request : process(all)
	variable is_hit  : std_ulogic;
	variable hit_way : way_t;
	variable op      : op_t;
        variable tmp     : std_ulogic_vector(63 downto 0);
        variable data    : std_ulogic_vector(63 downto 0);
	variable opsel   : std_ulogic_vector(3 downto 0);
    begin
	-- Extract line, row and tag from request
        req_index <= get_index(d_in.addr);
        req_row <= get_row(d_in.addr);
        req_tag <= get_tag(d_in.addr);

	-- Test if pending request is a hit on any way
	hit_way := 0;
	is_hit := '0';
	for i in way_t loop
	    if d_in.valid = '1' and cache_valids(req_index)(i) = '1' then
		if read_tag(i, cache_tags(req_index)) = req_tag then
		    hit_way := i;
		    is_hit := '1';
		end if;
	    end if;
	end loop;

	-- The way that matched on a hit	       
	req_hit_way <= hit_way;

	-- Combine the request and cache his status to decide what
	-- operation needs to be done
	--
	opsel := d_in.valid & d_in.load & d_in.nc & is_hit;
	case opsel is
	when "1101" => op := OP_LOAD_HIT;
	when "1100" => op := OP_LOAD_MISS;
	when "1110" => op := OP_LOAD_NC;
	when "1001" => op := OP_STORE_HIT;
	when "1000" => op := OP_STORE_MISS;
	when "1010" => op := OP_STORE_MISS;
	when "1011" => op := OP_BAD;
	when "1111" => op := OP_BAD;
	when others => op := OP_NONE;
	end case;

	req_op <= op;

    end process;

    --
    -- Misc signal assignments
    --

    -- Wire up wishbone request latch out of stage 1
    wishbone_out <= r1.wb;

    -- Wishbone & BRAM write data formatting for stores (most of it already
    -- happens in loadstore1, this is the remaining data shifting)
    --
    store_data  <= std_logic_vector(shift_left(unsigned(d_in.data),
					       wishbone_data_shift(d_in.addr)));

    -- Wishbone read and write and BRAM write sel bits generation
    bus_sel     <= wishbone_data_sel(d_in.length, d_in.addr);

   -- TODO: Generate errors
   -- err_nc_collision <= '1' when req_op = OP_BAD else '0';

    -- Generate stalls from stage 1 state machine
    stall_out <= '1' when r1.state /= IDLE else '0';

    -- Writeback (loads and reg updates) & completion control logic
    --
    writeback_control: process(all)
    begin

	-- The mux on d_out.write reg defaults to the normal load hit case.
	d_out.write_enable <= '0';
	d_out.valid <= '0';
	d_out.write_reg <= r2.load_reg;
	d_out.write_data <= cache_out(r2.hit_way);
	d_out.write_len <= r2.length;
	d_out.write_shift <= r2.data_shift;
	d_out.sign_extend <= r2.sign_extend;
	d_out.byte_reverse <= r2.byte_reverse;
	d_out.second_word <= '0';

	-- We have a valid load or store hit or we just completed a slow
	-- op such as a load miss, a NC load or a store
	--
	-- Note: the load hit is delayed by one cycle. However it can still
	-- not collide with r.slow_valid (well unless I miscalculated) because
	-- slow_valid can only be set on a subsequent request and not on its
	-- first cycle (the state machine must have advanced), which makes
	-- slow_valid at least 2 cycles from the previous hit_load_valid.
	--

	-- Sanity: Only one of these must be set in any given cycle
	assert (r1.update_valid and r2.hit_load_valid) /= '1' report
	    "unexpected hit_load_delayed collision with update_valid"
	    severity FAILURE;
	assert (r1.slow_valid and r2.hit_load_valid) /= '1' report
	    "unexpected hit_load_delayed collision with slow_valid"
	    severity FAILURE;
	assert (r1.slow_valid and r1.update_valid) /= '1' report
	    "unexpected update_valid collision with slow_valid"
	    severity FAILURE;

	-- Delayed load hit case is the standard path
	if r2.hit_load_valid = '1' then
	    d_out.write_enable <= '1';

	    -- If it's not a load with update, complete it now
	    if r2.load_is_update = '0' then
		d_out.valid <= '1';
		end if;
	end if;

	-- Slow ops (load miss, NC, stores)
	if r1.slow_valid = '1' then
	    -- If it's a load, enable register writeback and switch
	    -- mux accordingly
	    --
	    if r1.req.load then	    
		d_out.write_reg <= r1.req.write_reg;
		d_out.write_enable <= '1';

		-- Read data comes from the slow data latch, formatter
		-- from the latched request.
		--
		d_out.write_data <= r1.slow_data;
		d_out.write_shift <= r1.req.addr(2 downto 0);
		d_out.sign_extend <= r1.req.sign_extend;
		d_out.byte_reverse <= r1.req.byte_reverse;
		d_out.write_len <= r1.req.length;
	    end if;

	    -- If it's a store or a non-update load form, complete now
	    if r1.req.load = '0' or r1.req.update = '0' then
		d_out.valid <= '1';
	    end if;
	end if;

	-- We have a register update to do.
	if r1.update_valid = '1' then
	    d_out.write_enable <= '1';
	    d_out.write_reg <= r1.req.update_reg;

	    -- Change the read data mux to the address that's going into
	    -- the register and the formatter does nothing.
	    --
	    d_out.write_data <= r1.req.addr;
	    d_out.write_shift <= "000";
	    d_out.write_len <= "1000";
	    d_out.sign_extend <= '0';
	    d_out.byte_reverse <= '0';

	    -- If it was a load, this completes the operation (load with
	    -- update case).
	    --
	    if r1.req.load = '1' then
		d_out.valid <= '1';
	    end if;
	end if;

    end process;

    --
    -- Generate a cache RAM for each way. This handles the normal
    -- reads, writes from reloads and the special store-hit update
    -- path as well.
    --
    -- Note: the BRAMs have an extra read buffer, meaning the output
    --       is pipelined an extra cycle. This differs from the
    --       icache. The writeback logic needs to take that into
    --       account by using 1-cycle delayed signals for load hits.
    --
    rams: for i in 0 to NUM_WAYS-1 generate
	signal do_read  : std_ulogic;
	signal rd_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal do_write : std_ulogic;
	signal wr_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal wr_data  : std_ulogic_vector(wishbone_data_bits-1 downto 0);
	signal wr_sel   : std_ulogic_vector(ROW_SIZE-1 downto 0);
	signal dout     : cache_row_t;
    begin
	way: entity work.cache_ram
	    generic map (
		ROW_BITS => ROW_BITS,
		WIDTH => wishbone_data_bits,
		ADD_BUF => true
		)
	    port map (
		clk     => clk,
		rd_en   => do_read,
		rd_addr => rd_addr,
		rd_data => dout,
		wr_en   => do_write,
		wr_sel  => wr_sel,
		wr_addr => wr_addr,
		wr_data => wr_data
		);
	process(all)
	begin
	    -- Cache hit reads
	    do_read <= '1';
	    rd_addr <= std_ulogic_vector(to_unsigned(req_row, ROW_BITS));
	    cache_out(i) <= dout;

	    -- Write mux:
	    --
	    -- Defaults to wishbone read responses (cache refill),
	    --
	    -- For timing, the mux on wr_data/sel/addr is not dependent on anything
	    -- other than the current state. Only the do_write signal is.
	    --
	    if r1.state = IDLE then
		-- When IDLE, the only write path is the store-hit update case
		wr_addr  <= std_ulogic_vector(to_unsigned(req_row, ROW_BITS));
		wr_data  <= store_data;
		wr_sel   <= bus_sel;
	    else
		-- Otherwise, we might be doing a reload
		wr_data <= wishbone_in.dat;
		wr_sel  <= (others => '1');
		wr_addr <= std_ulogic_vector(to_unsigned(get_row(r1.wb.adr), ROW_BITS));
	    end if;

	    -- The two actual write cases here
	    do_write <= '0';
	    if r1.state = RELOAD_WAIT_ACK and wishbone_in.ack = '1' and r1.store_way = i then
		do_write <= '1';
	    end if;
	    if req_op = OP_STORE_HIT and req_hit_way = i then
		assert r1.state /= RELOAD_WAIT_ACK report "Store hit while in state:" &
		    state_t'image(r1.state)
		    severity FAILURE;
		do_write <= '1';
	    end if;
	end process;
    end generate;

    --
    -- Cache hit synchronous machine for the easy case. This handles
    -- non-update form load hits and stage 1 to stage 2 transfers
    --
    dcache_fast_hit : process(clk)
    begin
        if rising_edge(clk) then
	    -- stage 1 -> stage 2
	    r2.hit_load_valid <= r1.hit_load_valid;
	    r2.hit_way        <= r1.hit_way;
	    r2.load_is_update <= r1.req.update;
	    r2.load_reg       <= r1.req.write_reg;
	    r2.data_shift     <= r1.req.addr(2 downto 0);
	    r2.length         <= r1.req.length;
	    r2.sign_extend    <= r1.req.sign_extend;
	    r2.byte_reverse   <= r1.req.byte_reverse;

	    -- If we have a request incoming, we have to latch it as d_in.valid
	    -- is only set for a single cycle. It's up to the control logic to
	    -- ensure we don't override an uncompleted request (for now we are
	    -- single issue on load/stores so we are fine, later, we can generate
	    -- a stall output if necessary).

	    if d_in.valid = '1' then
		r1.req <= d_in;

		report "op:" & op_t'image(req_op) &
		    " addr:" & to_hstring(d_in.addr) &
		    " upd:" & std_ulogic'image(d_in.update) &
		    " nc:" & std_ulogic'image(d_in.nc) &
		    " reg:" & to_hstring(d_in.write_reg) &
		    " idx:" & integer'image(req_index) &
		    " tag:" & to_hstring(req_tag) &
		    " way: " & integer'image(req_hit_way);
	    end if;

	    -- Fast path for load/store hits. Set signals for the writeback controls.
	    if req_op = OP_LOAD_HIT then
		r1.hit_way <= req_hit_way;
		r1.hit_load_valid <= '1';
	    else
		r1.hit_load_valid <= '0';
	    end if;
	end if;
    end process;

    --
    -- Every other case is handled by this stage machine:
    --
    --   * Cache load miss/reload (in conjunction with "rams")
    --   * Load hits for update forms
    --   * Load hits for non-cachable forms
    --   * Stores (the collision case is handled in "rams")
    --
    -- All wishbone requests generation is done here. This machine
    -- operates at stage 1.
    --
    dcache_slow : process(clk)
	variable way : integer range 0 to NUM_WAYS-1;
	variable tagset : cache_tags_set_t;
    begin
        if rising_edge(clk) then
	    -- On reset, clear all valid bits to force misses
            if rst = '1' then
		for i in index_t loop
		    cache_valids(i) <= (others => '0');
		end loop;
                r1.state <= IDLE;
		r1.slow_valid <= '0';
		r1.update_valid <= '0';
                r1.wb.cyc <= '0';
                r1.wb.stb <= '0';

		-- Not useful normally but helps avoiding tons of sim warnings
		r1.wb.adr <= (others => '0');
            else
		-- One cycle pulses reset
		r1.slow_valid <= '0';
		r1.update_valid <= '0';

		-- We cannot currently process a new request when not idle
		assert req_op = OP_NONE or r1.state = IDLE report "request " &
		    op_t'image(req_op) & " while in state " & state_t'image(r1.state)
		    severity FAILURE;

		-- Main state machine
		case r1.state is
		when IDLE =>
		    case req_op is
		    when OP_LOAD_HIT =>
			-- We have a load with update hit, we need the delayed update cycle
			if d_in.update = '1' then
			    r1.state <= LOAD_UPDATE;
			end if;

		    when OP_LOAD_MISS =>
			-- Normal load cache miss, start the reload machine
			--
			-- First find a victim way from the PLRU
			--
			way := to_integer(unsigned(plru_victim(req_index)));

			report "cache miss addr:" & to_hstring(d_in.addr) &
			    " idx:" & integer'image(req_index) &
			    " way:" & integer'image(way) &
			    " tag:" & to_hstring(req_tag);

			-- Force misses on that way while reloading that line
			cache_valids(req_index)(way) <= '0';

			-- Store new tag in selected way
			for i in 0 to NUM_WAYS-1 loop
			    if i = way then
				tagset := cache_tags(req_index);
				write_tag(i, tagset, req_tag);
				cache_tags(req_index) <= tagset;
			    end if;
			end loop;

			-- Keep track of our index and way for subsequent stores.
			r1.store_index <= req_index;
			r1.store_way <= way;

			-- Prep for first wishbone read. We calculate the address of
			-- the start of the cache line
			--
			r1.wb.adr <= d_in.addr(63 downto LINE_OFF_BITS) &
				     (LINE_OFF_BITS-1 downto 0 => '0');
			r1.wb.sel <= (others => '1');
			r1.wb.we  <= '0';
			r1.wb.cyc <= '1';
			r1.wb.stb <= '1';
			r1.state <= RELOAD_WAIT_ACK;

		    when OP_LOAD_NC =>
                        r1.wb.sel <= bus_sel;
                        r1.wb.adr <= d_in.addr(63 downto 3) & "000";
                        r1.wb.cyc <= '1';
                        r1.wb.stb <= '1';
			r1.wb.we <= '0';
			r1.state <= NC_LOAD_WAIT_ACK;

		    when OP_STORE_HIT | OP_STORE_MISS =>
			-- For store-with-update do the register update
			if d_in.update = '1' then
			    r1.update_valid <= '1';
			end if;
                        r1.wb.sel <= bus_sel;
                        r1.wb.adr <= d_in.addr(63 downto 3) & "000";
			r1.wb.dat <= store_data;
                        r1.wb.cyc <= '1';
                        r1.wb.stb <= '1';
			r1.wb.we <= '1';
			r1.state <= STORE_WAIT_ACK;

		    -- OP_NONE and OP_BAD do nothing
		    when OP_NONE =>
		    when OP_BAD =>
		    end case;

		when RELOAD_WAIT_ACK =>
		    if wishbone_in.ack = '1' then
			-- Is this the data we were looking for ? Latch it so
			-- we can respond later. We don't currently complete the
			-- pending miss request immediately, we wait for the
			-- whole line to be loaded. The reason is that if we
			-- did, we would potentially get new requests in while
			-- not idle, which we don't currently know how to deal
			-- with.
			--
			if r1.wb.adr(LINE_OFF_BITS-1 downto ROW_OFF_BITS) =
			    r1.req.addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS) then
			    r1.slow_data <= wishbone_in.dat;
			end if;

			-- That was the last word ? We are done
			if is_last_row(r1.wb.adr) then
			    cache_valids(r1.store_index)(way) <= '1';
			    r1.wb.cyc <= '0';
			    r1.wb.stb <= '0';

			    -- Complete the load that missed. For load with update
			    -- we also need to do the deferred update cycle.
			    --
			    r1.slow_valid <= '1';
			    if r1.req.load = '1' and r1.req.update = '1' then
				r1.state <= LOAD_UPDATE;
				report "completing miss with load-update !";
			    else
				r1.state <= IDLE;
				report "completing miss !";
			    end if;
			else
			    -- Otherwise, calculate the next row address
			    r1.wb.adr <= next_row_addr(r1.wb.adr);
			end if;
		    end if;

		when LOAD_UPDATE =>
		    -- We need the extra cycle to complete a load with update
		    r1.state <= LOAD_UPDATE2;
		when LOAD_UPDATE2 =>
		    -- We need the extra cycle to complete a load with update
		    r1.update_valid <= '1';
		    r1.state <= IDLE;

		when STORE_WAIT_ACK | NC_LOAD_WAIT_ACK =>
                    if wishbone_in.ack = '1' then
			if r1.state = NC_LOAD_WAIT_ACK then
			    r1.slow_data <= wishbone_in.dat;
			end if;
			r1.slow_valid <= '1';
			r1.wb.cyc <= '0';
			r1.wb.stb <= '0';
			r1.state <= IDLE;
		    end if;
		end case;
	    end if;
	end if;
    end process;
end;
