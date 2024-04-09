--
-- Set associative icache
--
-- TODO (in no specific order):
--
--   * Add debug interface to inspect cache content
--   * Add multi-hit error detection
--   * Maybe add parity ? There's a few bits free in each BRAM row on Xilinx
--   * Add optimization: service hits on partially loaded lines
--   * Add optimization: (maybe) interrupt reload on fluch/redirect
--   * Check if playing with the geometry of the cache tags allow for more
--     efficient use of distributed RAM and less logic/muxes. Currently we
--     write TAG_BITS width which may not match full ram blocks and might
--     cause muxes to be inferred for "partial writes".
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils.all;
use work.common.all;
use work.decode_types.all;
use work.wishbone_types.all;

-- 64 bit direct mapped icache. All instructions are 4B aligned.

entity icache is
    generic (
        SIM : boolean := false;
        HAS_FPU : boolean := true;
        -- Line size in bytes
        LINE_SIZE : positive := 64;
        -- BRAM organisation: We never access more than wishbone_data_bits at
        -- a time so to save resources we make the array only that wide, and
        -- use consecutive indices for to make a cache "line"
        --
        -- ROW_SIZE is the width in bytes of the BRAM (based on WB, so 64-bits)
        ROW_SIZE  : positive := wishbone_data_bits / 8;
        -- Number of lines in a set
        NUM_LINES : positive := 32;
        -- Number of ways
        NUM_WAYS  : positive := 4;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
    port (
        clk          : in std_ulogic;
        rst          : in std_ulogic;

        i_in         : in Fetch1ToIcacheType;
        i_out        : out IcacheToDecode1Type;

        stall_in     : in std_ulogic;
	stall_out    : out std_ulogic;
	flush_in     : in std_ulogic;
	inval_in     : in std_ulogic;

        wishbone_out : out wishbone_master_out;
        wishbone_in  : in wishbone_slave_out;

        wb_snoop_in  : in wishbone_master_out := wishbone_master_out_init;

        events       : out IcacheEventType;
        log_out      : out std_ulogic_vector(57 downto 0)
        );
end entity icache;

architecture rtl of icache is
    constant ROW_SIZE_BITS : natural := ROW_SIZE*8;
    -- ROW_PER_LINE is the number of row (wishbone transactions) in a line
    constant ROW_PER_LINE  : natural := LINE_SIZE / ROW_SIZE;
    -- BRAM_ROWS is the number of rows in BRAM needed to represent the full
    -- icache
    constant BRAM_ROWS     : natural := NUM_LINES * ROW_PER_LINE;
    -- INSN_PER_ROW is the number of 32bit instructions per BRAM row
    constant INSN_PER_ROW  : natural := ROW_SIZE_BITS / 32;
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
    -- INDEX_BITS is the number of bits to select a cache line
    constant INDEX_BITS    : natural := log2(NUM_LINES);
    -- SET_SIZE_BITS is the log base 2 of the set size
    constant SET_SIZE_BITS : natural := LINE_OFF_BITS + INDEX_BITS;
    -- TAG_BITS is the number of bits of the tag part of the address
    -- the +1 is to allow the endianness to be stored in the tag
    constant TAG_BITS      : natural := REAL_ADDR_BITS - SET_SIZE_BITS + 1;
    -- WAY_BITS is the number of bits to select a way
    -- Make sure this is at least 1, to avoid 0-element vectors
    constant WAY_BITS     : natural := maximum(log2(NUM_WAYS), 1);

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

    subtype row_t is unsigned(ROW_BITS-1 downto 0);
    subtype index_t is integer range 0 to NUM_LINES-1;
    subtype index_sig_t is unsigned(INDEX_BITS-1 downto 0);
    subtype way_t is integer range 0 to NUM_WAYS-1;
    subtype way_sig_t is unsigned(WAY_BITS-1 downto 0);
    subtype row_in_line_t is unsigned(ROW_LINEBITS-1 downto 0);

    -- We store a pre-decoded 10-bit insn_code along with the bottom 26 bits of
    -- each instruction, giving a total of 36 bits per instruction, which
    -- fits neatly into the block RAMs available on FPGAs.
    -- For illegal instructions, the top 4 bits are ones and the bottom 6 bits
    -- are the instruction's primary opcode, so we have the whole instruction
    -- word available (e.g. to put in HEIR).  For other instructions, the
    -- primary opcode is not stored but could be determined from the insn_code.
    constant PREDECODE_BITS : natural := 10;
    constant INSN_IMAGE_BITS : natural := 26;
    constant ICWORDLEN : natural := PREDECODE_BITS + INSN_IMAGE_BITS;
    constant ROW_WIDTH : natural := INSN_PER_ROW * ICWORDLEN;

    -- The cache data BRAM organized as described above for each way
    subtype cache_row_t is std_ulogic_vector(ROW_WIDTH-1 downto 0);

    -- We define a cache tag RAM per way, accessed synchronously
    subtype cache_tag_t is std_logic_vector(TAG_BITS-1 downto 0);
    type cache_tags_set_t is array(way_t) of cache_tag_t;
    type cache_tags_array_t is array(index_t) of cache_tag_t;

    -- Set of cache tags read on the last clock edge
    signal cache_tags_set : cache_tags_set_t;
    -- Set of cache tags for snooping writes to memory
    signal snoop_tags_set : cache_tags_set_t;
    -- Flags indicating write-hit-read on the cache tags
    signal tag_overwrite : std_ulogic_vector(NUM_WAYS - 1 downto 0);

    -- The cache valid bits
    subtype cache_way_valids_t is std_ulogic_vector(NUM_WAYS-1 downto 0);
    type cache_valids_t is array(index_t) of cache_way_valids_t;
    type row_per_line_valid_t is array(0 to ROW_PER_LINE - 1) of std_ulogic;
    signal cache_valids : cache_valids_t;

    -- Cache reload state machine
    type state_t is (IDLE, STOP_RELOAD, CLR_TAG, WAIT_ACK);

    type reg_internal_t is record
	-- Cache hit state (Latches for 1 cycle BRAM access)
	hit_way   : way_sig_t;
	hit_nia   : std_ulogic_vector(63 downto 0);
        hit_ra    : real_addr_t;
	hit_smark : std_ulogic;
	hit_valid : std_ulogic;
        big_endian: std_ulogic;
        predicted  : std_ulogic;
        pred_ntaken: std_ulogic;

	-- Cache miss state (reload state machine)
        state            : state_t;
        wb               : wishbone_master_out;
	store_way        : way_sig_t;
        store_index      : index_sig_t;
        recv_row         : row_t;
        recv_valid       : std_ulogic;
	store_row        : row_t;
        store_tag        : cache_tag_t;
        store_valid      : std_ulogic;
        end_row_ix       : row_in_line_t;
        rows_valid       : row_per_line_valid_t;

        stalled_hit      : std_ulogic;  -- remembers hit while stalled
        stalled_way      : way_sig_t;

        -- TLB miss state
        fetch_failed     : std_ulogic;
    end record;

    signal r : reg_internal_t;

    signal ev : IcacheEventType;

    -- Async signals on incoming request
    signal req_index   : index_sig_t;
    signal req_row     : row_t;
    signal req_hit_way : way_sig_t;
    signal req_tag     : cache_tag_t;
    signal req_is_hit  : std_ulogic;
    signal req_is_miss : std_ulogic;
    signal req_raddr   : real_addr_t;

    signal real_addr     : real_addr_t;

    -- Cache RAM interface
    type cache_ram_out_t is array(way_t) of cache_row_t;
    signal cache_out     : cache_ram_out_t;
    signal cache_wr_data : std_ulogic_vector(ROW_WIDTH - 1 downto 0);
    signal wb_rd_data    : std_ulogic_vector(ROW_SIZE_BITS - 1 downto 0);

    -- PLRU output interface
    signal plru_victim : way_sig_t;

    -- Memory write snoop signals
    signal snoop_valid  : std_ulogic;
    signal snoop_index  : index_sig_t;
    signal snoop_tag    : cache_tag_t;
    signal snoop_index2 : index_sig_t;
    signal snoop_hits   : cache_way_valids_t;

    signal log_insn : std_ulogic_vector(35 downto 0);

    -- Return the cache line index (tag index) for an address
    function get_index(addr: real_addr_t) return index_sig_t is
    begin
        return unsigned(addr(SET_SIZE_BITS - 1 downto LINE_OFF_BITS));
    end;

    -- Return the cache row index (data memory) for an address
    function get_row(addr: std_ulogic_vector) return row_t is
    begin
        return unsigned(addr(SET_SIZE_BITS - 1 downto ROW_OFF_BITS));
    end;

    -- Return the index of a row within a line
    function get_row_of_line(row: row_t) return row_in_line_t is
    begin
        return row(ROW_LINEBITS-1 downto 0);
    end;

    -- Returns whether this is the last row of a line
    function is_last_row_wb_addr(wb_addr: wishbone_addr_type; last: row_in_line_t) return boolean is
    begin
	return unsigned(wb_addr(LINE_OFF_BITS - ROW_OFF_BITS - 1 downto 0)) = last;
    end;

    -- Returns whether this is the last row of a line
    function is_last_row(row: row_t; last: row_in_line_t) return boolean is
    begin
	return get_row_of_line(row) = last;
    end;

    -- Return the address of the next row in the current cache line
    function next_row_wb_addr(wb_addr: wishbone_addr_type)
	return std_ulogic_vector is
	variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
	variable result  : wishbone_addr_type;
    begin
	-- Is there no simpler way in VHDL to generate that 3 bits adder ?
	row_idx := wb_addr(ROW_LINEBITS - 1 downto 0);
	row_idx := std_ulogic_vector(unsigned(row_idx) + 1);
	result := wb_addr;
	result(ROW_LINEBITS - 1 downto 0) := row_idx;
	return result;
    end;

    -- Return the next row in the current cache line. We use a dedicated
    -- function in order to limit the size of the generated adder to be
    -- only the bits within a cache line (3 bits with default settings)
    --
    function next_row(row: row_t) return row_t is
	variable row_v   : std_ulogic_vector(ROW_BITS-1 downto 0);
	variable row_idx : unsigned(ROW_LINEBITS-1 downto 0);
	variable result  : std_ulogic_vector(ROW_BITS-1 downto 0);
    begin
	row_v := std_ulogic_vector(row);
	row_idx := row(ROW_LINEBITS-1 downto 0);
	row_v(ROW_LINEBITS-1 downto 0) := std_ulogic_vector(row_idx + 1);
	return unsigned(row_v);
    end;

    -- Read the instruction word for the given address in the current cache row
    function read_insn_word(addr: std_ulogic_vector(63 downto 0);
			    data: cache_row_t) return std_ulogic_vector is
	variable word: integer range 0 to INSN_PER_ROW-1;
    begin
        assert not is_X(addr) severity failure;
        word := to_integer(unsigned(addr(INSN_BITS+2-1 downto 2)));
	return data(word * ICWORDLEN + ICWORDLEN - 1 downto word * ICWORDLEN);
    end;

    -- Get the tag value from the address
    function get_tag(addr: real_addr_t; endian: std_ulogic) return cache_tag_t is
    begin
        return endian & addr(addr'left downto SET_SIZE_BITS);
    end;

begin

    -- byte-swap read data if big endian
    process(all)
        variable j: integer;
    begin
        if r.store_tag(TAG_BITS - 1) = '0' then
            wb_rd_data <= wishbone_in.dat;
        else
            for ii in 0 to (wishbone_in.dat'length / 8) - 1 loop
                j := ((ii / 4) * 4) + (3 - (ii mod 4));
                wb_rd_data(ii * 8 + 7 downto ii * 8) <= wishbone_in.dat(j * 8 + 7 downto j * 8);
            end loop;
        end if;
    end process;

    predecoder_0: entity work.predecoder
        generic map (
            HAS_FPU => HAS_FPU,
            WIDTH => INSN_PER_ROW,
            ICODE_LEN => PREDECODE_BITS,
            IMAGE_LEN => INSN_IMAGE_BITS
            )
        port map (
            clk => clk,
            valid_in => wishbone_in.ack,
            insns_in => wb_rd_data,
            icodes_out => cache_wr_data
            );

    assert LINE_SIZE mod ROW_SIZE = 0;
    assert ispow2(LINE_SIZE)    report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES)    report "NUM_LINES not power of 2" severity FAILURE;
    assert ispow2(ROW_PER_LINE) report "ROW_PER_LINE not power of 2" severity FAILURE;
    assert ispow2(INSN_PER_ROW) report "INSN_PER_ROW not power of 2" severity FAILURE;
    assert (ROW_BITS = INDEX_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (LINE_OFF_BITS = ROW_OFF_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS + 1 = TAG_BITS + INDEX_BITS + LINE_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS + 1 = TAG_BITS + ROW_BITS + ROW_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;

    sim_debug: if SIM generate
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
    end generate;

    -- Generate a cache RAM for each way
    rams: for i in 0 to NUM_WAYS-1 generate
	signal do_read  : std_ulogic;
	signal do_write : std_ulogic;
	signal rd_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal wr_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal dout     : cache_row_t;
	signal wr_sel   : std_ulogic_vector(0 downto 0);
        signal ic_tags  : cache_tags_array_t;
    begin
        -- Cache data RAMs, one per way
	way: entity work.cache_ram
	    generic map (
		ROW_BITS => ROW_BITS,
		WIDTH => ROW_WIDTH,
                BYTEWID => ROW_WIDTH
		)
	    port map (
		clk     => clk,
		rd_en   => do_read,
		rd_addr => rd_addr,
		rd_data => dout,
		wr_sel  => wr_sel,
		wr_addr => wr_addr,
		wr_data => cache_wr_data
		);
	process(all)
	begin
	    do_read <= not stall_in;
	    do_write <= '0';
	    if r.recv_valid = '1' and r.store_way = to_unsigned(i, WAY_BITS) then
		do_write <= '1';
	    end if;
	    cache_out(i) <= dout;
	    rd_addr <= std_ulogic_vector(req_row);
	    wr_addr <= std_ulogic_vector(r.store_row);
            wr_sel(0) <= do_write;
	end process;

        -- Cache tag RAMs, one per way, are read and written synchronously.
        -- They are instantiated like this instead of trying to describe them as
        -- a single array in order to avoid problems with writing a single way.
        process(clk)
            variable replace_way : way_sig_t;
            variable snoop_addr : real_addr_t;
            variable next_raddr : real_addr_t;
        begin
            if rising_edge(clk) then
                replace_way := to_unsigned(0, WAY_BITS);
                if NUM_WAYS > 1 then
                    -- Get victim way from plru
                    replace_way := plru_victim;
                end if;
                -- Read tags using NIA for next cycle
                if flush_in = '1' or i_in.req = '0' or (stall_in = '0' and stall_out = '0') then
                    next_raddr := i_in.next_rpn & i_in.next_nia(MIN_LG_PGSZ - 1 downto 0);
                    cache_tags_set(i) <= ic_tags(to_integer(get_index(next_raddr)));
                    -- Check for simultaneous write to the same location
                    tag_overwrite(i) <= '0';
                    if r.state = CLR_TAG and r.store_index = get_index(next_raddr) and
                        to_unsigned(i, WAY_BITS) = replace_way then
                        tag_overwrite(i) <= '1';
                    end if;
                end if;

                -- Second read port for snooping writes to memory
                if (wb_snoop_in.cyc and wb_snoop_in.stb and wb_snoop_in.we) = '1' then
                    snoop_addr := addr_to_real(wb_to_addr(wb_snoop_in.adr));
                    snoop_tags_set(i) <= ic_tags(to_integer(get_index(snoop_addr)));
                end if;

                -- Write one tag when in CLR_TAG state
                if r.state = CLR_TAG and to_unsigned(i, WAY_BITS) = replace_way then
                    ic_tags(to_integer(r.store_index)) <= r.store_tag;
                end if;

                if rst = '1' then
                    tag_overwrite(i) <= '0';
                end if;
            end if;
        end process;
    end generate;
    
    -- Generate PLRUs
    maybe_plrus: if NUM_WAYS > 1 generate
        type plru_array is array(index_t) of std_ulogic_vector(NUM_WAYS - 2 downto 0);
        signal plru_ram    : plru_array;
        signal plru_cur    : std_ulogic_vector(NUM_WAYS - 2 downto 0);
        signal plru_upd    : std_ulogic_vector(NUM_WAYS - 2 downto 0);
        signal plru_acc    : std_ulogic_vector(WAY_BITS-1 downto 0);
        signal plru_out    : std_ulogic_vector(WAY_BITS-1 downto 0);
    begin
        plru : entity work.plrufn
            generic map (
                BITS => WAY_BITS
                )
            port map (
                acc => plru_acc,
                tree_in => plru_cur,
                tree_out => plru_upd,
                lru => plru_out
                );

        process(all)
        begin
            -- Read PLRU bits from array
            if is_X(r.hit_ra) then
                plru_cur <= (others => 'X');
            else
                plru_cur <= plru_ram(to_integer(get_index(r.hit_ra)));
            end if;

            -- PLRU interface
            plru_acc <= std_ulogic_vector(r.hit_way);
            plru_victim <= unsigned(plru_out);
        end process;

        -- synchronous writes to PLRU array
        process(clk)
        begin
            if rising_edge(clk) then
                if r.hit_valid = '1' then
                    assert not is_X(r.hit_ra) severity failure;
                    plru_ram(to_integer(get_index(r.hit_ra))) <= plru_upd;
                end if;
            end if;
        end process;
    end generate;

    -- Cache hit detection, output to fetch2 and other misc logic
    icache_comb : process(all)
	variable is_hit  : std_ulogic;
	variable hit_way : way_sig_t;
        variable insn    : std_ulogic_vector(ICWORDLEN - 1 downto 0);
        variable icode   : insn_code;
        variable ra      : real_addr_t;
    begin
	-- Extract line, row and tag from request
        ra := i_in.rpn & i_in.nia(MIN_LG_PGSZ - 1 downto 0);
        real_addr <= ra;
        req_index <= get_index(ra);
        req_row <= get_row(ra);
	req_tag <= get_tag(ra, i_in.big_endian);

	-- Calculate address of beginning of cache row, will be
	-- used for cache miss processing if needed
	--
	req_raddr <= ra(REAL_ADDR_BITS - 1 downto ROW_OFF_BITS) &
		     (ROW_OFF_BITS-1 downto 0 => '0');

	-- Test if pending request is a hit on any way
	hit_way := to_unsigned(0, WAY_BITS);
	is_hit := '0';
        if i_in.req = '1' then
            assert not is_X(req_index) and not is_X(req_row) severity failure;
        end if;
	for i in way_t loop
	    if i_in.req = '1' and
                cache_valids(to_integer(req_index))(i) = '1' and
                tag_overwrite(i) = '0' and
                cache_tags_set(i) = req_tag then
                hit_way := to_unsigned(i, WAY_BITS);
                is_hit := '1';
	    end if;
	end loop;
        if r.state = WAIT_ACK and r.store_valid = '1' and
            req_index = r.store_index and
            req_tag = r.store_tag and
            r.rows_valid(to_integer(req_row(ROW_LINEBITS-1 downto 0))) = '1' then
            is_hit := '1';
            hit_way := r.store_way;
        end if;
        if r.stalled_hit = '1' then
            is_hit := '1';
            hit_way := r.stalled_way;
        end if;

	-- Generate the "hit" and "miss" signals for the synchronous blocks
        if i_in.req = '1' and flush_in = '0' and rst = '0' then
            req_is_hit  <= is_hit;
            req_is_miss <= not is_hit;
        else
            req_is_hit  <= '0';
            req_is_miss <= '0';
        end if;
	req_hit_way <= hit_way;

	-- Output instruction from current cache row
	--
	-- Note: This is a mild violation of our design principle of having pipeline
	--       stages output from a clean latch. In this case we output the result
	--       of a mux. The alternative would be output an entire row which
	--       I prefer not to do just yet as it would force fetch2 to know about
	--       some of the cache geometry information.
	--
        icode := INSN_illegal;
        if is_X(r.hit_way) then
            insn := (others => 'X');
        else
            insn := read_insn_word(r.hit_nia, cache_out(to_integer(r.hit_way)));
        end if;
        assert not (r.hit_valid = '1' and is_X(r.hit_way)) severity failure;
        -- Currently we use only the top bit for indicating illegal
        -- instructions because we know that insn_codes fit into 9 bits.
        if is_X(insn) then
            insn := (others => '0');
        elsif insn(ICWORDLEN - 1) = '0' then
            icode := insn_code'val(to_integer(unsigned(insn(ICWORDLEN-1 downto INSN_IMAGE_BITS))));
            insn(31 downto 26) := recode_primary_opcode(icode);
        end if;

        i_out.insn <= insn(31 downto 0);
        i_out.icode <= icode;
        log_insn <= insn;
	i_out.valid <= r.hit_valid;
	i_out.nia <= r.hit_nia;
	i_out.stop_mark <= r.hit_smark;
        i_out.fetch_failed <= r.fetch_failed;
        i_out.big_endian <= r.big_endian;
        i_out.next_predicted <= r.predicted;
        i_out.next_pred_ntaken <= r.pred_ntaken;

	-- Stall fetch1 if we have a cache miss
	stall_out <= i_in.req and not is_hit and not flush_in;

	-- Wishbone requests output (from the cache miss reload machine)
	wishbone_out <= r.wb;
    end process;

    -- Cache hit synchronous machine
    icache_hit : process(clk)
    begin
        if rising_edge(clk) then
            -- keep outputs to fetch2 unchanged on a stall
            -- except that flush or reset sets valid to 0
            if rst = '1' or flush_in = '1' then
                r.hit_valid <= '0';
                r.stalled_hit <= '0';
                r.stalled_way <= to_unsigned(0, WAY_BITS);
            elsif stall_in = '1' then
                if r.state = CLR_TAG then
                    r.stalled_hit <= '0';
                elsif req_is_hit = '1' then
                    -- if we have a hit while stalled, remember it
                    r.stalled_hit <= '1';
                    r.stalled_way <= req_hit_way;
                end if;
            else
                -- On a hit, latch the request for the next cycle, when the BRAM data
                -- will be available on the cache_out output of the corresponding way
                --
                r.hit_valid <= req_is_hit;
                if req_is_hit = '1' then
                    r.hit_way <= req_hit_way;
		    -- this is a bit fragile but better than propogating bad values
		    assert not is_X(i_in.nia) report "metavalue in NIA" severity FAILURE;

                    report "cache hit nia:" & to_hstring(i_in.nia) &
                        " IR:" & std_ulogic'image(i_in.virt_mode) &
                        " SM:" & std_ulogic'image(i_in.stop_mark) &
                        " idx:" & to_hstring(req_index) &
                        " tag:" & to_hstring(req_tag) &
                        " way:" & to_hstring(req_hit_way) &
                        " RA:" & to_hstring(real_addr);
                end if;
                r.stalled_hit <= '0';
	    end if;
            if stall_in = '0' then
                -- Send stop marks and NIA down regardless of validity
                r.hit_smark <= i_in.stop_mark;
                r.hit_nia <= i_in.nia;
                r.hit_ra <= real_addr;
                r.big_endian <= i_in.big_endian;
                r.predicted <= i_in.predicted;
                r.pred_ntaken <= i_in.pred_ntaken;
                r.fetch_failed <= i_in.fetch_fail and not flush_in;
            end if;
            if i_out.valid = '1' then
                assert not is_X(i_out.insn) severity failure;
            end if;
	end if;
    end process;

    -- Cache miss/reload synchronous machine
    icache_miss : process(clk)
	variable tagset    : cache_tags_set_t;
        variable tag       : cache_tag_t;
        variable snoop_addr : real_addr_t;
        variable snoop_cache_tags : cache_tags_set_t;
        variable replace_way : way_sig_t;
    begin
        if rising_edge(clk) then
            ev.icache_miss <= '0';
            ev.itlb_miss_resolved <= '0';
            r.recv_valid <= '0';
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

                snoop_valid <= '0';
                snoop_index <= to_unsigned(0, INDEX_BITS);
                snoop_hits <= (others => '0');
            else
                -- Detect snooped writes and decode address into index and tag
                -- Since we never write, any write should be snooped
                snoop_valid <= wb_snoop_in.cyc and wb_snoop_in.stb and wb_snoop_in.we;
                snoop_addr := addr_to_real(wb_to_addr(wb_snoop_in.adr));
                snoop_index <= get_index(snoop_addr);
                snoop_tag <= get_tag(snoop_addr, '0');
                snoop_hits <= (others => '0');

                -- On the next cycle, match up tags with the snooped address
                -- to see if any ways need to be invalidated
                if snoop_valid = '1' then
                    for i in way_t loop
                        tag := snoop_tags_set(i);
                        -- Ignore endian bit in comparison
                        tag(TAG_BITS - 1) := '0';
                        if tag = snoop_tag then
                            snoop_hits(i) <= '1';
                        end if;
                    end loop;
                end if;
                snoop_index2 <= snoop_index;

                -- Process cache invalidations
                if inval_in = '1' then
                    for i in index_t loop
                        cache_valids(i) <= (others => '0');
                    end loop;
                    r.store_valid <= '0';
                else
                    -- Do invalidations from snooped stores to memory,
                    -- two cycles after the address appears on wb_snoop_in.
                    for i in way_t loop
                        if snoop_hits(i) = '1' then
                            assert not is_X(snoop_index2) severity failure;
                            cache_valids(to_integer(snoop_index2))(i) <= '0';
                        end if;
                    end loop;
                end if;

		-- Main state machine
		case r.state is
		when IDLE =>
                    -- Reset per-row valid flags, only used in WAIT_ACK
                    for i in 0 to ROW_PER_LINE - 1 loop
                        r.rows_valid(i) <= '0';
                    end loop;

		    -- We need to read a cache line
		    if req_is_miss = '1' then
			report "cache miss nia:" & to_hstring(i_in.nia) &
                            " IR:" & std_ulogic'image(i_in.virt_mode) &
			    " SM:" & std_ulogic'image(i_in.stop_mark) &
			    " idx:" & to_hstring(req_index) &
			    " tag:" & to_hstring(req_tag) &
                            " RA:" & to_hstring(real_addr);
                        ev.icache_miss <= '1';

			-- Keep track of our index and way for subsequent stores
			r.store_index <= req_index;
                        r.recv_row <= get_row(req_raddr);
			r.store_row <= get_row(req_raddr);
                        r.store_tag <= req_tag;
                        r.store_valid <= '1';
                        r.end_row_ix <= get_row_of_line(get_row(req_raddr)) - 1;

			-- Prep for first wishbone read. We calculate the address of
			-- the start of the cache line and start the WB cycle.
			--
			r.wb.adr <= addr_to_wb(req_raddr);
			r.wb.cyc <= '1';
			r.wb.stb <= '1';

			-- Track that we had one request sent
			r.state <= CLR_TAG;
		    end if;

		when CLR_TAG | WAIT_ACK =>
                    assert not is_X(r.store_index) severity failure;
                    assert not is_X(r.store_row) severity failure;
                    assert not is_X(r.recv_row) severity failure;
                    if r.state = CLR_TAG then
                        replace_way := to_unsigned(0, WAY_BITS);
                        if NUM_WAYS > 1 then
                            -- Get victim way from plru
                            replace_way := plru_victim;
                        end if;
			r.store_way <= replace_way;

			-- Force misses on that way while reloading that line
                        assert not is_X(replace_way) severity failure;
                        cache_valids(to_integer(r.store_index))(to_integer(replace_way)) <= '0';

                        r.state <= WAIT_ACK;
                    end if;

                    -- If we are writing in this cycle, mark row valid and see if we are done
                    if r.recv_valid = '1' then
                        r.rows_valid(to_integer(r.store_row(ROW_LINEBITS-1 downto 0))) <= not inval_in;
			if is_last_row(r.store_row, r.end_row_ix) then
			    -- Cache line is now valid
			    cache_valids(to_integer(r.store_index))(to_integer(r.store_way)) <=
                                r.store_valid and not inval_in;
			    -- We are done
			    r.state <= IDLE;
			end if;
			-- Increment store row counter
			r.store_row <= r.recv_row;
                    end if;

		    -- If we are still sending requests, was one accepted ?
		    if wishbone_in.stall = '0' and r.wb.stb = '1' then
			-- That was the last word ? We are done sending. Clear stb.
			--
			if is_last_row_wb_addr(r.wb.adr, r.end_row_ix) then
			    r.wb.stb <= '0';
			end if;

			-- Calculate the next row address
			r.wb.adr <= next_row_wb_addr(r.wb.adr);
		    end if;

                    -- Abort reload if we get an invalidation
                    if inval_in = '1' then
                        r.wb.stb <= '0';
                        r.state <= STOP_RELOAD;
                    end if;

		    -- Incoming acks processing
		    if wishbone_in.ack = '1' then
			-- Check for completion
			if is_last_row(r.recv_row, r.end_row_ix) then
			    -- Complete wishbone cycle
			    r.wb.cyc <= '0';
			end if;
                        r.recv_valid <= '1';

			-- Increment receive row counter
			r.recv_row <= next_row(r.recv_row);
		    end if;

                when STOP_RELOAD =>
                    -- Wait for all outstanding requests to be satisfied, then
                    -- go to IDLE state.
                    if get_row_of_line(r.recv_row) = get_row_of_line(get_row(wb_to_addr(r.wb.adr))) then
                        r.wb.cyc <= '0';
                        r.state <= IDLE;
                    end if;
                    if wishbone_in.ack = '1' then
			-- Increment store row counter
			r.recv_row <= next_row(r.recv_row);
		    end if;
		end case;
	    end if;
	end if;
    end process;

    icache_log: if LOG_LENGTH > 0 generate
        -- Output data to logger
        signal log_data    : std_ulogic_vector(57 downto 0);
    begin
        data_log: process(clk)
            variable lway: way_sig_t;
            variable wstate: std_ulogic;
        begin
            if rising_edge(clk) then
                lway := req_hit_way;
                wstate := '0';
                if r.state /= IDLE then
                    wstate := '1';
                end if;
                log_data <= i_out.valid &
                            log_insn &
                            wishbone_in.ack &
                            r.wb.adr(2 downto 0) &
                            r.wb.stb & r.wb.cyc &
                            wishbone_in.stall &
                            stall_out &
                            r.fetch_failed &
                            r.hit_nia(5 downto 2) &
                            wstate &
                            std_ulogic_vector(resize(lway, 3)) &
                            req_is_hit & req_is_miss &
                            '1' & -- was access_ok
                            '1';  -- was ra_valid
            end if;
        end process;
        log_out <= log_data;
    end generate;

    events <= ev;

end;
