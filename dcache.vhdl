--
-- Set associative dcache write-through
--
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils.all;
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
        NUM_WAYS  : positive := 4;
        -- L1 DTLB entries per set
        TLB_SET_SIZE : positive := 64;
        -- L1 DTLB number of sets
        TLB_NUM_WAYS : positive := 2;
        -- L1 DTLB log_2(page_size)
        TLB_LG_PGSZ : positive := 12;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
    port (
        clk          : in std_ulogic;
        rst          : in std_ulogic;

        d_in         : in Loadstore1ToDcacheType;
        d_out        : out DcacheToLoadstore1Type;

        m_in         : in MmuToDcacheType;
        m_out        : out DcacheToMmuType;

        snoop_in     : in wishbone_master_out := wishbone_master_out_init;

	stall_out    : out std_ulogic;

        wishbone_out : out wishbone_master_out;
        wishbone_in  : in wishbone_slave_out;

        events       : out DcacheEventType;

        log_out      : out std_ulogic_vector(19 downto 0)
        );
end entity dcache;

architecture rtl of dcache is
    -- BRAM organisation: We never access more than wishbone_data_bits at
    -- a time so to save resources we make the array only that wide, and
    -- use consecutive indices to make a cache "line"
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
    -- SET_SIZE_BITS is the log base 2 of the set size
    constant SET_SIZE_BITS : natural := LINE_OFF_BITS + INDEX_BITS;
    -- TAG_BITS is the number of bits of the tag part of the address
    constant TAG_BITS      : natural := REAL_ADDR_BITS - SET_SIZE_BITS;
    -- TAG_WIDTH is the width in bits of each way of the tag RAM
    constant TAG_WIDTH     : natural := TAG_BITS + 7 - ((TAG_BITS + 7) mod 8);
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
    -- .. --------|              | TAG_BITS      (45)

    subtype row_t is unsigned(ROW_BITS-1 downto 0);
    subtype index_t is unsigned(INDEX_BITS-1 downto 0);
    subtype way_t is unsigned(WAY_BITS-1 downto 0);
    subtype row_in_line_t is unsigned(ROW_LINEBITS-1 downto 0);

    -- The cache data BRAM organized as described above for each way
    subtype cache_row_t is std_ulogic_vector(wishbone_data_bits-1 downto 0);

    -- The cache tags LUTRAM has a row per set. Vivado is a pain and will
    -- not handle a clean (commented) definition of the cache tags as a 3d
    -- memory. For now, work around it by putting all the tags
    subtype cache_tag_t is std_logic_vector(TAG_BITS-1 downto 0);
--    type cache_tags_set_t is array(way_t) of cache_tag_t;
--    type cache_tags_array_t is array(0 to NUM_LINES-1) of cache_tags_set_t;
    constant TAG_RAM_WIDTH : natural := TAG_WIDTH * NUM_WAYS;
    subtype cache_tags_set_t is std_logic_vector(TAG_RAM_WIDTH-1 downto 0);
    type cache_tags_array_t is array(0 to NUM_LINES-1) of cache_tags_set_t;

    -- The cache valid bits
    subtype cache_way_valids_t is std_ulogic_vector(NUM_WAYS-1 downto 0);
    type cache_valids_t is array(0 to NUM_LINES-1) of cache_way_valids_t;
    type row_per_line_valid_t is array(0 to ROW_PER_LINE - 1) of std_ulogic;

    -- Storage. Hopefully implemented in LUTs
    signal cache_tags    : cache_tags_array_t;
    signal cache_tag_set : cache_tags_set_t;
    signal cache_valids  : cache_valids_t;

    attribute ram_style : string;
    attribute ram_style of cache_tags : signal is "distributed";

    -- L1 TLB.
    constant TLB_SET_BITS : natural := log2(TLB_SET_SIZE);
    constant TLB_WAY_BITS : natural := log2(TLB_NUM_WAYS);
    constant TLB_EA_TAG_BITS : natural := 64 - (TLB_LG_PGSZ + TLB_SET_BITS);
    constant TLB_TAG_WAY_BITS : natural := TLB_NUM_WAYS * TLB_EA_TAG_BITS;
    constant TLB_PTE_BITS : natural := 64;
    constant TLB_PTE_WAY_BITS : natural := TLB_NUM_WAYS * TLB_PTE_BITS;

    subtype tlb_way_t is integer range 0 to TLB_NUM_WAYS - 1;
    subtype tlb_way_sig_t is unsigned(TLB_WAY_BITS-1 downto 0);
    subtype tlb_index_t is integer range 0 to TLB_SET_SIZE - 1;
    subtype tlb_index_sig_t is unsigned(TLB_SET_BITS-1 downto 0);
    subtype tlb_way_valids_t is std_ulogic_vector(TLB_NUM_WAYS-1 downto 0);
    type tlb_valids_t is array(tlb_index_t) of tlb_way_valids_t;
    subtype tlb_tag_t is std_ulogic_vector(TLB_EA_TAG_BITS - 1 downto 0);
    subtype tlb_way_tags_t is std_ulogic_vector(TLB_TAG_WAY_BITS-1 downto 0);
    type tlb_tags_t is array(tlb_index_t) of tlb_way_tags_t;
    subtype tlb_pte_t is std_ulogic_vector(TLB_PTE_BITS - 1 downto 0);
    subtype tlb_way_ptes_t is std_ulogic_vector(TLB_PTE_WAY_BITS-1 downto 0);
    type tlb_ptes_t is array(tlb_index_t) of tlb_way_ptes_t;
    type hit_way_set_t is array(tlb_way_t) of way_t;

    signal dtlb_valids : tlb_valids_t;
    signal dtlb_tags : tlb_tags_t;
    signal dtlb_ptes : tlb_ptes_t;
    attribute ram_style of dtlb_tags : signal is "distributed";
    attribute ram_style of dtlb_ptes : signal is "distributed";

    -- Record for storing permission, attribute, etc. bits from a PTE
    type perm_attr_t is record
        reference : std_ulogic;
        changed   : std_ulogic;
        nocache   : std_ulogic;
        priv      : std_ulogic;
        rd_perm   : std_ulogic;
        wr_perm   : std_ulogic;
    end record;

    function extract_perm_attr(pte : std_ulogic_vector(TLB_PTE_BITS - 1 downto 0)) return perm_attr_t is
        variable pa : perm_attr_t;
    begin
        pa.reference := pte(8);
        pa.changed := pte(7);
        pa.nocache := pte(5);
        pa.priv := pte(3);
        pa.rd_perm := pte(2);
        pa.wr_perm := pte(1);
        return pa;
    end;

    constant real_mode_perm_attr : perm_attr_t := (nocache => '0', others => '1');

    -- Type of operation on a "valid" input
    type op_t is (OP_NONE,
		  OP_BAD,           -- NC cache hit, TLB miss, prot/RC failure
                  OP_STCX_FAIL,     -- conditional store w/o reservation
		  OP_LOAD_HIT,      -- Cache hit on load
		  OP_LOAD_MISS,     -- Load missing cache
		  OP_LOAD_NC,       -- Non-cachable load
		  OP_STORE_HIT,     -- Store hitting cache
		  OP_STORE_MISS);   -- Store missing cache
		      
    -- Cache state machine
    type state_t is (IDLE,	       -- Normal load hit processing
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
    -- with no stalls.  Stores also complete in 2 cycles in most
    -- circumstances.
    --
    -- A request proceeds through the pipeline as follows.
    --
    -- Cycle 0: Request is received from loadstore or mmu if either
    -- d_in.valid or m_in.valid is 1 (not both).  In this cycle portions
    -- of the address are presented to the TLB tag RAM and data RAM
    -- and the cache tag RAM and data RAM.
    --
    -- Clock edge between cycle 0 and cycle 1:
    -- Request is stored in r0 (assuming r0_full was 0).  TLB tag and
    -- data RAMs are read, and the cache tag RAM is read.  (Cache data
    -- comes out a cycle later due to its output register, giving the
    -- whole of cycle 1 to read the cache data RAM.)
    --
    -- Cycle 1: TLB and cache tag matching is done, the real address
    -- (RA) for the access is calculated, and the type of operation is
    -- determined (the OP_* values above).  This gives the TLB way for
    -- a TLB hit, and the cache way for a hit or the way to replace
    -- for a load miss.
    --
    -- Clock edge between cycle 1 and cycle 2:
    -- Request is stored in r1 (assuming r1.full was 0)
    -- The state machine transitions out of IDLE state for a load miss,
    -- a store, a dcbz, or a non-cacheable load.  r1.full is set to 1
    -- for a load miss, dcbz or non-cacheable load but not a store.
    --
    -- Cycle 2: Completion signals are asserted for a load hit,
    -- a store (excluding dcbz), a TLB operation, a conditional
    -- store which failed due to no matching reservation, or an error
    -- (cache hit on non-cacheable operation, TLB miss, or protection
    -- fault).
    --
    -- For a load miss, store, or dcbz, the state machine initiates
    -- a wishbone cycle, which takes at least 2 cycles.  For a store,
    -- if another store comes in with the same cache tag (therefore
    -- in the same 4k page), it can be added on to the existing cycle,
    -- subject to some constraints.
    -- While r1.full = 1, no new requests can go from r0 to r1, but
    -- requests can come in to r0 and be satisfied if they are
    -- cacheable load hits or stores with the same cache tag.
    --
    -- Writing to the cache data RAM is done at the clock edge
    -- at the end of cycle 2 for a store hit (excluding dcbz).
    -- Stores that miss are not written to the cache data RAM
    -- but just stored through to memory.
    -- Dcbz is done like a cache miss, but the wishbone cycle
    -- is a write rather than a read, and zeroes are written to
    -- the cache data RAM.  Thus dcbz will allocate the line in
    -- the cache as well as zeroing memory.
    --
    -- Since stores are written to the cache data RAM at the end of
    -- cycle 2, and loads can come in and hit on the data just stored,
    -- there is a two-stage bypass from store data to load data to
    -- make sure that loads always see previously-stored data even
    -- if it has not yet made it to the cache data RAM.
    --
    -- Load misses read the requested dword of the cache line first in
    -- the memory read request and then cycle around through the other
    -- dwords.  The load is completed on the cycle after the requested
    -- dword comes back from memory (using a forwarding path, rather
    -- than going via the cache data RAM).  We maintain an array of
    -- valid bits per dword for the line being refilled so that
    -- subsequent load requests to the same line can be completed as
    -- soon as the necessary data comes in from memory, without
    -- waiting for the whole line to be read.

    -- Stage 0 register, basically contains just the latched request
    type reg_stage_0_t is record
        req   : Loadstore1ToDcacheType;
        tlbie : std_ulogic;     -- indicates a tlbie request (from MMU)
        doall : std_ulogic;     -- with tlbie, indicates flush whole TLB
        tlbld : std_ulogic;     -- indicates a TLB load request (from MMU)
        mmu_req : std_ulogic;   -- indicates source of request
        d_valid : std_ulogic;   -- indicates req.data is valid now
    end record;

    signal r0 : reg_stage_0_t;
    signal r0_full : std_ulogic;

    type mem_access_request_t is record
        op        : op_t;
        valid     : std_ulogic;
        dcbz      : std_ulogic;
        real_addr : real_addr_t;
        data      : std_ulogic_vector(63 downto 0);
        byte_sel  : std_ulogic_vector(7 downto 0);
        hit_way   : way_t;
        same_tag  : std_ulogic;
        mmu_req   : std_ulogic;
    end record;

    -- First stage register, contains state for stage 1 of load hits
    -- and for the state machine used by all other operations
    --
    type reg_stage_1_t is record
        -- Info about the request
        full             : std_ulogic;          -- have uncompleted request
        mmu_req          : std_ulogic;          -- request is from MMU
        req              : mem_access_request_t;

	-- Cache hit state
	hit_way          : way_t;
	hit_load_valid   : std_ulogic;
        hit_index        : index_t;
        cache_hit        : std_ulogic;

        -- TLB hit state
        tlb_hit          : std_ulogic;
        tlb_hit_way      : tlb_way_sig_t;
        tlb_hit_index    : tlb_index_sig_t;

	-- data buffer for data forwarded from writes to reads
	forward_data     : std_ulogic_vector(63 downto 0);
        forward_tag      : cache_tag_t;
        forward_sel      : std_ulogic_vector(7 downto 0);
	forward_valid    : std_ulogic;
        forward_row      : row_t;
        data_out         : std_ulogic_vector(63 downto 0);

	-- Cache miss state (reload state machine)
        state            : state_t;
        dcbz             : std_ulogic;
        write_bram       : std_ulogic;
        write_tag        : std_ulogic;
        slow_valid       : std_ulogic;
        wb               : wishbone_master_out;
        reload_tag       : cache_tag_t;
	store_way        : way_t;
	store_row        : row_t;
        store_index      : index_t;
        end_row_ix       : row_in_line_t;
        rows_valid       : row_per_line_valid_t;
        acks_pending     : unsigned(2 downto 0);
        inc_acks         : std_ulogic;
        dec_acks         : std_ulogic;

        -- Signals to complete (possibly with error)
        ls_valid         : std_ulogic;
        ls_error         : std_ulogic;
        mmu_done         : std_ulogic;
        mmu_error        : std_ulogic;
        cache_paradox    : std_ulogic;

        -- Signal to complete a failed stcx.
        stcx_fail        : std_ulogic;
    end record;

    signal r1 : reg_stage_1_t;

    signal ev : DcacheEventType;

    -- Reservation information
    --
    type reservation_t is record
        valid : std_ulogic;
        addr  : std_ulogic_vector(63 downto LINE_OFF_BITS);
    end record;

    signal reservation : reservation_t;

    -- Async signals on incoming request
    signal req_index   : index_t;
    signal req_hit_way : way_t;
    signal req_tag     : cache_tag_t;
    signal req_op      : op_t;
    signal req_data    : std_ulogic_vector(63 downto 0);
    signal req_same_tag : std_ulogic;
    signal req_go      : std_ulogic;

    signal early_req_row  : row_t;
    signal early_rd_valid : std_ulogic;

    signal cancel_store : std_ulogic;
    signal set_rsrv     : std_ulogic;
    signal clear_rsrv   : std_ulogic;

    signal r0_valid   : std_ulogic;
    signal r0_stall   : std_ulogic;

    signal fwd_same_tag : std_ulogic;
    signal use_forward_st : std_ulogic;
    signal use_forward_rl : std_ulogic;
    signal use_forward2 : std_ulogic;

    -- Cache RAM interface
    type cache_ram_out_t is array(0 to NUM_WAYS-1) of cache_row_t;
    signal cache_out   : cache_ram_out_t;
    signal ram_wr_data : cache_row_t;
    signal ram_wr_select : std_ulogic_vector(ROW_SIZE - 1 downto 0);

    -- PLRU output interface
    type plru_out_t is array(0 to NUM_LINES-1) of std_ulogic_vector(WAY_BITS-1 downto 0);
    signal plru_victim : plru_out_t;
    signal replace_way : way_t;

    -- Wishbone read/write/cache write formatting signals
    signal bus_sel     : std_ulogic_vector(7 downto 0);

    -- TLB signals
    signal tlb_tag_way : tlb_way_tags_t;
    signal tlb_pte_way : tlb_way_ptes_t;
    signal tlb_valid_way : tlb_way_valids_t;
    signal tlb_req_index : tlb_index_sig_t;
    signal tlb_read_valid : std_ulogic;
    signal tlb_hit : std_ulogic;
    signal tlb_hit_way : tlb_way_sig_t;
    signal pte : tlb_pte_t;
    signal ra : real_addr_t;
    signal valid_ra : std_ulogic;
    signal perm_attr : perm_attr_t;
    signal rc_ok : std_ulogic;
    signal perm_ok : std_ulogic;
    signal access_ok : std_ulogic;
    signal tlb_miss : std_ulogic;

    -- TLB PLRU output interface
    type tlb_plru_out_t is array(tlb_index_t) of std_ulogic_vector(TLB_WAY_BITS-1 downto 0);
    signal tlb_plru_victim : tlb_plru_out_t;

    signal snoop_tag_set : cache_tags_set_t;
    signal snoop_valid   : std_ulogic;
    signal snoop_wrtag   : cache_tag_t;
    signal snoop_index   : index_t;

    --
    -- Helper functions to decode incoming requests
    --

    -- Return the cache line index (tag index) for an address
    function get_index(addr: std_ulogic_vector) return index_t is
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
    function is_last_row_wb_addr(addr: wishbone_addr_type; last: row_in_line_t) return boolean is
    begin
	return unsigned(addr(LINE_OFF_BITS - ROW_OFF_BITS - 1 downto 0)) = last;
    end;

    -- Returns whether this is the last row of a line
    function is_last_row(row: row_t; last: row_in_line_t) return boolean is
    begin
        return get_row_of_line(row) = last;
    end;

    -- Return the address of the next row in the current cache line
    function next_row_wb_addr(addr: wishbone_addr_type) return std_ulogic_vector is
	variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
	variable result  : wishbone_addr_type;
    begin
	-- Is there no simpler way in VHDL to generate that 3 bits adder ?
	row_idx := addr(ROW_LINEBITS - 1 downto 0);
	row_idx := std_ulogic_vector(unsigned(row_idx) + 1);
	result := addr;
	result(ROW_LINEBITS - 1 downto 0) := row_idx;
	return result;
    end;

    -- Return the next row in the current cache line. We use a dedicated
    -- function in order to limit the size of the generated adder to be
    -- only the bits within a cache line (3 bits with default settings)
    --
    function next_row(row: row_t) return row_t is
       variable row_v  : std_ulogic_vector(ROW_BITS-1 downto 0);
       variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
       variable result : std_ulogic_vector(ROW_BITS-1 downto 0);
    begin
       row_v := std_ulogic_vector(row);
       row_idx := row_v(ROW_LINEBITS-1 downto 0);
       row_v(ROW_LINEBITS-1 downto 0) := std_ulogic_vector(unsigned(row_idx) + 1);
       return unsigned(row_v);
    end;

    -- Get the tag value from the address
    function get_tag(addr: std_ulogic_vector) return cache_tag_t is
    begin
        return addr(REAL_ADDR_BITS - 1 downto SET_SIZE_BITS);
    end;

    -- Read a tag from a tag memory row
    function read_tag(way: integer; tagset: cache_tags_set_t) return cache_tag_t is
    begin
	return tagset(way * TAG_WIDTH + TAG_BITS - 1 downto way * TAG_WIDTH);
    end;

    -- Read a TLB tag from a TLB tag memory row
    function read_tlb_tag(way: tlb_way_t; tags: tlb_way_tags_t) return tlb_tag_t is
        variable j : integer;
    begin
        j := way * TLB_EA_TAG_BITS;
        return tags(j + TLB_EA_TAG_BITS - 1 downto j);
    end;

    -- Write a TLB tag to a TLB tag memory row
    procedure write_tlb_tag(way: tlb_way_t; tags: inout tlb_way_tags_t;
                            tag: tlb_tag_t) is
        variable j : integer;
    begin
        j := way * TLB_EA_TAG_BITS;
        tags(j + TLB_EA_TAG_BITS - 1 downto j) := tag;
    end;

    -- Read a PTE from a TLB PTE memory row
    function read_tlb_pte(way: tlb_way_t; ptes: tlb_way_ptes_t) return tlb_pte_t is
        variable j : integer;
    begin
        j := way * TLB_PTE_BITS;
        return ptes(j + TLB_PTE_BITS - 1 downto j);
    end;

    procedure write_tlb_pte(way: tlb_way_t; ptes: inout tlb_way_ptes_t; newpte: tlb_pte_t) is
        variable j : integer;
    begin
        j := way * TLB_PTE_BITS;
        ptes(j + TLB_PTE_BITS - 1 downto j) := newpte;
    end;

begin

    assert LINE_SIZE mod ROW_SIZE = 0 report "LINE_SIZE not multiple of ROW_SIZE" severity FAILURE;
    assert ispow2(LINE_SIZE)    report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES)    report "NUM_LINES not power of 2" severity FAILURE;
    assert ispow2(ROW_PER_LINE) and ROW_PER_LINE > 1
        report "ROW_PER_LINE not power of 2 greater than 1" severity FAILURE;
    assert (ROW_BITS = INDEX_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (LINE_OFF_BITS = ROW_OFF_BITS + ROW_LINEBITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS = TAG_BITS + INDEX_BITS + LINE_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS = TAG_BITS + ROW_BITS + ROW_OFF_BITS)
	report "geometry bits don't add up" severity FAILURE;
    assert (64 = wishbone_data_bits)
	report "Can't yet handle a wishbone width that isn't 64-bits" severity FAILURE;
    assert SET_SIZE_BITS <= TLB_LG_PGSZ report "Set indexed by virtual address" severity FAILURE;

    -- Latch the request in r0.req as long as we're not stalling
    stage_0 : process(clk)
        variable r : reg_stage_0_t;
    begin
        if rising_edge(clk) then
            assert (d_in.valid and m_in.valid) = '0' report
                "request collision loadstore vs MMU";
            if m_in.valid = '1' then
                r.req.valid := '1';
                r.req.load := not (m_in.tlbie or m_in.tlbld);
                r.req.dcbz := '0';
                r.req.nc := '0';
                r.req.reserve := '0';
                r.req.virt_mode := '0';
                r.req.priv_mode := '1';
                r.req.addr := m_in.addr;
                r.req.data := m_in.pte;
                r.req.byte_sel := (others => '1');
                r.tlbie := m_in.tlbie;
                r.doall := m_in.doall;
                r.tlbld := m_in.tlbld;
                r.mmu_req := '1';
                r.d_valid := '1';
            else
                r.req := d_in;
                r.req.data := (others => '0');
                r.tlbie := '0';
                r.doall := '0';
                r.tlbld := '0';
                r.mmu_req := '0';
                r.d_valid := '0';
            end if;
            if r.req.valid = '1' and r.doall = '0' then
                assert not is_X(r.req.addr) severity failure;
            end if;
            if rst = '1' then
                r0_full <= '0';
            elsif r1.full = '0' and d_in.hold = '0' then
                r0 <= r;
                r0_full <= r.req.valid;
            elsif r0.d_valid = '0' then
                -- Sample data the cycle after a request comes in from loadstore1.
                -- If this request is already moving into r1 then the data will get
                -- put directly into req.data in the dcache_slow process below.
                r0.req.data <= d_in.data;
                r0.d_valid <= r0.req.valid;
            end if;
        end if;
    end process;

    -- we don't yet handle collisions between loadstore1 requests and MMU requests
    m_out.stall <= '0';

    -- Hold off the request in r0 when r1 has an uncompleted request
    r0_stall <= r1.full or d_in.hold;
    r0_valid <= r0_full and not r1.full and not d_in.hold;
    stall_out <= r1.full;

    events <= ev;

    -- TLB
    -- Operates in the second cycle on the request latched in r0.req.
    -- TLB updates write the entry at the end of the second cycle.
    tlb_read : process(clk)
        variable index : tlb_index_t;
        variable addrbits : std_ulogic_vector(TLB_SET_BITS - 1 downto 0);
        variable valid : std_ulogic;
    begin
        if rising_edge(clk) then
            if m_in.valid = '1' then
                addrbits := m_in.addr(TLB_LG_PGSZ + TLB_SET_BITS - 1 downto TLB_LG_PGSZ);
                valid := not (m_in.tlbie and m_in.doall);
            else
                addrbits := d_in.addr(TLB_LG_PGSZ + TLB_SET_BITS - 1 downto TLB_LG_PGSZ);
                valid := d_in.valid;
            end if;
            -- If we have any op and the previous op isn't finished,
            -- then keep the same output for next cycle.
            if r0_stall = '0' and valid = '1' then
                assert not is_X(addrbits);
                index := to_integer(unsigned(addrbits));
                tlb_valid_way <= dtlb_valids(index);
                tlb_tag_way <= dtlb_tags(index);
                tlb_pte_way <= dtlb_ptes(index);
            end if;
            if rst = '1' then
                tlb_read_valid <= '0';
            elsif r0_stall = '0' then
                tlb_read_valid <= valid;
            end if;
        end if;
    end process;

    -- Generate TLB PLRUs
    maybe_tlb_plrus: if TLB_NUM_WAYS > 1 generate
    begin
	tlb_plrus: for i in 0 to TLB_SET_SIZE - 1 generate
	    -- TLB PLRU interface
	    signal tlb_plru_acc    : std_ulogic_vector(TLB_WAY_BITS-1 downto 0);
	    signal tlb_plru_acc_en : std_ulogic;
	    signal tlb_plru_out    : std_ulogic_vector(TLB_WAY_BITS-1 downto 0);
	begin
	    tlb_plru : entity work.plru
		generic map (
		    BITS => TLB_WAY_BITS
		    )
		port map (
		    clk => clk,
		    rst => rst,
		    acc => tlb_plru_acc,
		    acc_en => tlb_plru_acc_en,
		    lru => tlb_plru_out
		    );

	    process(all)
	    begin
		-- PLRU interface
		if not is_X(r1.tlb_hit_index) and r1.tlb_hit_index = i then
		    tlb_plru_acc_en <= r1.tlb_hit;
                    assert not is_X(r1.tlb_hit_way);
		else
		    tlb_plru_acc_en <= '0';
		end if;
		tlb_plru_acc <= std_ulogic_vector(r1.tlb_hit_way);
		tlb_plru_victim(i) <= tlb_plru_out;
	    end process;
	end generate;
    end generate;

    tlb_search : process(all)
        variable hitway : tlb_way_sig_t;
        variable hit : std_ulogic;
        variable eatag : tlb_tag_t;
    begin
        tlb_req_index <= unsigned(r0.req.addr(TLB_LG_PGSZ + TLB_SET_BITS - 1
                                              downto TLB_LG_PGSZ));
        hitway := to_unsigned(0, TLB_WAY_BITS);
        hit := '0';
        eatag := r0.req.addr(63 downto TLB_LG_PGSZ + TLB_SET_BITS);
        for i in tlb_way_t loop
            if tlb_read_valid = '1' and tlb_valid_way(i) = '1' and
                read_tlb_tag(i, tlb_tag_way) = eatag then
                hitway := to_unsigned(i, TLB_WAY_BITS);
                hit := '1';
            end if;
        end loop;
        tlb_hit <= hit and r0_valid;
        tlb_hit_way <= hitway;
        if tlb_hit = '1' then
            pte <= read_tlb_pte(to_integer(hitway), tlb_pte_way);
        else
            pte <= (others => '0');
        end if;
        valid_ra <= tlb_hit or not r0.req.virt_mode;
        tlb_miss <= r0_valid and r0.req.virt_mode and not tlb_hit;
        if r0.req.virt_mode = '1' then
            ra <= pte(REAL_ADDR_BITS - 1 downto TLB_LG_PGSZ) &
                  r0.req.addr(TLB_LG_PGSZ - 1 downto ROW_OFF_BITS) &
                  (ROW_OFF_BITS-1 downto 0 => '0');
            perm_attr <= extract_perm_attr(pte);
        else
            ra <= r0.req.addr(REAL_ADDR_BITS - 1 downto ROW_OFF_BITS) &
                  (ROW_OFF_BITS-1 downto 0 => '0');
            perm_attr <= real_mode_perm_attr;
        end if;
    end process;

    tlb_update : process(clk)
        variable tlbie : std_ulogic;
        variable tlbwe : std_ulogic;
        variable repl_way : tlb_way_sig_t;
        variable eatag : tlb_tag_t;
        variable tagset : tlb_way_tags_t;
        variable pteset : tlb_way_ptes_t;
    begin
        if rising_edge(clk) then
            tlbie := r0_valid and r0.tlbie;
            tlbwe := r0_valid and r0.tlbld;
            ev.dtlb_miss_resolved <= tlbwe;
            if rst = '1' or (tlbie = '1' and r0.doall = '1') then
                -- clear all valid bits at once
                for i in tlb_index_t loop
                    dtlb_valids(i) <= (others => '0');
                end loop;
            elsif tlbie = '1' then
                if tlb_hit = '1' then
                    assert not is_X(tlb_req_index);
                    assert not is_X(tlb_hit_way);
                    dtlb_valids(to_integer(tlb_req_index))(to_integer(tlb_hit_way)) <= '0';
                end if;
            elsif tlbwe = '1' then
                assert not is_X(tlb_req_index);
                if tlb_hit = '1' then
                    repl_way := tlb_hit_way;
                else
                    assert not is_X(tlb_plru_victim(to_integer(tlb_req_index)));
                    repl_way := unsigned(tlb_plru_victim(to_integer(tlb_req_index)));
                end if;
                assert not is_X(repl_way);
                eatag := r0.req.addr(63 downto TLB_LG_PGSZ + TLB_SET_BITS);
                tagset := tlb_tag_way;
                write_tlb_tag(to_integer(repl_way), tagset, eatag);
                dtlb_tags(to_integer(tlb_req_index)) <= tagset;
                pteset := tlb_pte_way;
                write_tlb_pte(to_integer(repl_way), pteset, r0.req.data);
                dtlb_ptes(to_integer(tlb_req_index)) <= pteset;
                dtlb_valids(to_integer(tlb_req_index))(to_integer(repl_way)) <= '1';
            end if;
        end if;
    end process;

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

	    process(all)
	    begin
		-- PLRU interface
		if not is_X(r1.hit_index) and r1.hit_index = to_unsigned(i, INDEX_BITS) then
		    plru_acc_en <= r1.cache_hit;
		else
		    plru_acc_en <= '0';
		end if;
		plru_acc <= std_ulogic_vector(r1.hit_way);
		plru_victim(i) <= plru_out;
	    end process;
	end generate;
    end generate;

    -- Cache tag RAM read port
    cache_tag_read : process(clk)
        variable index : index_t;
        variable valid : std_ulogic;
    begin
        if rising_edge(clk) then
            if r0_stall = '1' then
                index := req_index;
                valid := r0.req.valid and not (r0.tlbie or r0.tlbld);
            elsif m_in.valid = '1' then
                index := get_index(m_in.addr);
                valid := not (m_in.tlbie or m_in.tlbld);
            else
                index := get_index(d_in.addr);
                valid := d_in.valid;
            end if;
            if valid = '1' then
                cache_tag_set <= cache_tags(to_integer(index));
            else
                cache_tag_set <= (others => '0');
            end if;
        end if;
    end process;

    -- Cache tag RAM second read port, for snooping
    cache_tag_read_2 : process(clk)
        variable addr : real_addr_t;
    begin
        if rising_edge(clk) then
            -- Don't snoop our own cycles
            snoop_valid <= '0';
            if not (r1.wb.cyc = '1' and wishbone_in.stall = '0') then
                if (snoop_in.cyc and snoop_in.stb and snoop_in.we) = '1' then
                    snoop_valid <= '1';
                    addr := addr_to_real(wb_to_addr(snoop_in.adr));
                    assert not is_X(addr);
                    snoop_tag_set <= cache_tags(to_integer(get_index(addr)));
                    snoop_wrtag <= get_tag(addr);
                    snoop_index <= get_index(addr);
                end if;
            end if;
        end if;
    end process;

    -- Cache request parsing and hit detection
    dcache_request : process(all)
        variable req_row     : row_t;
        variable rindex      : index_t;
        variable is_hit      : std_ulogic;
        variable hit_way     : way_t;
        variable op          : op_t;
        variable opsel       : std_ulogic_vector(2 downto 0);
        variable go          : std_ulogic;
        variable nc          : std_ulogic;
        variable s_hit       : std_ulogic;
        variable s_tag       : cache_tag_t;
        variable s_pte       : tlb_pte_t;
        variable s_ra        : real_addr_t;
        variable hit_set     : std_ulogic_vector(TLB_NUM_WAYS - 1 downto 0);
        variable hit_way_set : hit_way_set_t;
        variable rel_matches : std_ulogic_vector(TLB_NUM_WAYS - 1 downto 0);
        variable rel_match   : std_ulogic;
        variable fwd_matches : std_ulogic_vector(TLB_NUM_WAYS - 1 downto 0);
        variable fwd_match   : std_ulogic;
    begin
	-- Extract line, row and tag from request
        rindex := get_index(r0.req.addr);
        req_index <= rindex;
        req_row := get_row(r0.req.addr);
        req_tag <= get_tag(ra);

        go := r0_valid and not (r0.tlbie or r0.tlbld) and not r1.ls_error;
        if is_X(r0.req.addr) then
            go := '0';
        end if;
        if go = '1' then
            assert not is_X(r1.forward_tag);
        end if;

	-- Test if pending request is a hit on any way
        -- In order to make timing in virtual mode, when we are using the TLB,
        -- we compare each way with each of the real addresses from each way of
        -- the TLB, and then decide later which match to use.
        hit_way := to_unsigned(0, WAY_BITS);
        is_hit := '0';
        rel_match := '0';
        fwd_match := '0';
        if r0.req.virt_mode = '1' then
            rel_matches := (others => '0');
            fwd_matches := (others => '0');
            for j in tlb_way_t loop
                hit_way_set(j) := to_unsigned(0, WAY_BITS);
                s_hit := '0';
                s_pte := read_tlb_pte(j, tlb_pte_way);
                s_ra := s_pte(REAL_ADDR_BITS - 1 downto TLB_LG_PGSZ) &
                        r0.req.addr(TLB_LG_PGSZ - 1 downto 0);
                s_tag := get_tag(s_ra);
                if go = '1' then
                    assert not is_X(s_tag);
                end if;
                for i in 0 to NUM_WAYS-1 loop
                    if go = '1' and cache_valids(to_integer(rindex))(i) = '1' and
                        read_tag(i, cache_tag_set) = s_tag and
                        tlb_valid_way(j) = '1' then
                        hit_way_set(j) := to_unsigned(i, WAY_BITS);
                        s_hit := '1';
                    end if;
                end loop;
                hit_set(j) := s_hit;
                if go = '1' and not is_X(r1.reload_tag) and s_tag = r1.reload_tag then
                    rel_matches(j) := '1';
                end if;
                if go = '1' and s_tag = r1.forward_tag then
                    fwd_matches(j) := '1';
                end if;
            end loop;
            if tlb_hit = '1' and go = '1' then
                assert not is_X(tlb_hit_way);
                is_hit := hit_set(to_integer(tlb_hit_way));
                hit_way := hit_way_set(to_integer(tlb_hit_way));
                rel_match := rel_matches(to_integer(tlb_hit_way));
                fwd_match := fwd_matches(to_integer(tlb_hit_way));
            end if;
        else
            s_tag := get_tag(r0.req.addr);
            if go = '1' then
                assert not is_X(s_tag);
            end if;
            for i in 0 to NUM_WAYS-1 loop
                if go = '1' and cache_valids(to_integer(rindex))(i) = '1' and
                    read_tag(i, cache_tag_set) = s_tag then
                    hit_way := to_unsigned(i, WAY_BITS);
                    is_hit := '1';
                end if;
            end loop;
            if go = '1' and not is_X(r1.reload_tag) and s_tag = r1.reload_tag then
                rel_match := '1';
            end if;
            if go = '1' and s_tag = r1.forward_tag then
                fwd_match := '1';
            end if;
        end if;
        req_same_tag <= rel_match;
        fwd_same_tag <= fwd_match;

        -- Whether to use forwarded data for a load or not
        use_forward_st <= '0';
        use_forward_rl <= '0';
        if rel_match = '1' then
            assert not is_X(r1.store_row);
            assert not is_X(req_row);
        end if;
        if rel_match = '1' and r1.store_row = req_row then
            -- Use the forwarding path if this cycle is a write to this row
            use_forward_st <= r1.write_bram;
            if r1.state = RELOAD_WAIT_ACK and wishbone_in.ack = '1' then
                use_forward_rl <= '1';
            end if;
        end if;
        use_forward2 <= '0';
        if fwd_match = '1' then
            assert not is_X(r1.forward_row);
            if is_X(req_row) then
                report "req_row=" & to_hstring(req_row) & " addr=" & to_hstring(r0.req.addr) & " go=" & std_ulogic'image(go);
            end if;
            assert not is_X(req_row);
        end if;
        if fwd_match = '1' and r1.forward_row = req_row then
            use_forward2 <= r1.forward_valid;
        end if;

        -- The way to replace on a miss
        if r1.write_tag = '1' then
            assert not is_X(r1.store_index);
            replace_way <= unsigned(plru_victim(to_integer(r1.store_index)));
        else
            replace_way <= r1.store_way;
        end if;

        -- See if the request matches the line currently being reloaded
        if r1.state = RELOAD_WAIT_ACK and rel_match = '1' then
            assert not is_X(rindex);
            assert not is_X(r1.store_index);
        end if;
        if r1.state = RELOAD_WAIT_ACK and rel_match = '1' and
            rindex = r1.store_index then
            -- Ignore is_hit from above, because a load miss writes the new tag
            -- but doesn't clear the valid bit on the line before refilling it.
            -- For a store, consider this a hit even if the row isn't valid
            -- since it will be by the time we perform the store.
            -- For a load, check the appropriate row valid bit; but also,
            -- if use_forward_rl is 1 then we can consider this a hit.
            is_hit := not r0.req.load or r1.rows_valid(to_integer(req_row(ROW_LINEBITS-1 downto 0))) or
                      use_forward_rl;
            hit_way := replace_way;
        end if;

	-- The way that matched on a hit	       
	req_hit_way <= hit_way;

        -- work out whether we have permission for this access
        -- NB we don't yet implement AMR, thus no KUAP
        rc_ok <= perm_attr.reference and (r0.req.load or perm_attr.changed);
        perm_ok <= (r0.req.priv_mode or not perm_attr.priv) and
                   (perm_attr.wr_perm or (r0.req.load and perm_attr.rd_perm));
        access_ok <= valid_ra and perm_ok and rc_ok;

	-- Combine the request and cache hit status to decide what
	-- operation needs to be done
	--
        nc := r0.req.nc or perm_attr.nocache;
        op := OP_NONE;
        if go = '1' then
            if access_ok = '0' then
                op := OP_BAD;
            elsif cancel_store = '1' then
                op := OP_STCX_FAIL;
            else
                opsel := r0.req.load & nc & is_hit;
                case opsel is
                    when "101" => op := OP_LOAD_HIT;
                    when "100" => op := OP_LOAD_MISS;
                    when "110" => op := OP_LOAD_NC;
                    when "001" => op := OP_STORE_HIT;
                    when "000" => op := OP_STORE_MISS;
                    when "010" => op := OP_STORE_MISS;
                    when "011" => op := OP_BAD;
                    when "111" => op := OP_BAD;
                    when others => op := OP_NONE;
                end case;
            end if;
        end if;
	req_op <= op;
        req_go <= go;

        -- Version of the row number that is valid one cycle earlier
        -- in the cases where we need to read the cache data BRAM.
        -- If we're stalling then we need to keep reading the last
        -- row requested.
        if r0_stall = '0' then
            if m_in.valid = '1' then
                early_req_row <= get_row(m_in.addr);
                early_rd_valid <= not (m_in.tlbie or m_in.tlbld);
            else
                early_req_row <= get_row(d_in.addr);
                early_rd_valid <= d_in.valid and d_in.load;
            end if;
        else
            early_req_row <= req_row;
            early_rd_valid <= r0.req.valid and r0.req.load;
        end if;
    end process;

    -- Wire up wishbone request latch out of stage 1
    wishbone_out <= r1.wb;

    -- Handle load-with-reservation and store-conditional instructions
    reservation_comb: process(all)
    begin
        cancel_store <= '0';
        set_rsrv <= '0';
        clear_rsrv <= '0';
        if r0_valid = '1' and r0.req.reserve = '1' then
            -- XXX generate alignment interrupt if address is not aligned
            -- XXX or if r0.req.nc = '1'
            if r0.req.load = '1' then
                -- load with reservation
                set_rsrv <= '1';
            else
                -- store conditional
                clear_rsrv <= '1';
                if reservation.valid = '0' or
                    r0.req.addr(63 downto LINE_OFF_BITS) /= reservation.addr then
                    cancel_store <= '1';
                end if;
            end if;
        end if;
    end process;

    reservation_reg: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                reservation.valid <= '0';
            elsif r0_valid = '1' and access_ok = '1' then
                if clear_rsrv = '1' then
                    reservation.valid <= '0';
                elsif set_rsrv = '1' then
                    reservation.valid <= '1';
                    reservation.addr <= r0.req.addr(63 downto LINE_OFF_BITS);
                end if;
            end if;
        end if;
    end process;

    -- Return data for loads & completion control logic
    --
    writeback_control: process(all)
    begin
	d_out.valid <= r1.ls_valid;
	d_out.data <= r1.data_out;
        d_out.store_done <= not r1.stcx_fail;
        d_out.error <= r1.ls_error;
        d_out.cache_paradox <= r1.cache_paradox;

        -- Outputs to MMU
        m_out.done <= r1.mmu_done;
        m_out.err <= r1.mmu_error;
        m_out.data <= r1.data_out;

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
	assert (r1.slow_valid and r1.stcx_fail) /= '1' report
	    "unexpected slow_valid collision with stcx_fail"
	    severity FAILURE;
	assert ((r1.slow_valid or r1.stcx_fail) and r1.hit_load_valid) /= '1' report
	    "unexpected hit_load_delayed collision with slow_valid"
	    severity FAILURE;

        if r1.mmu_req = '0' then
            -- Request came from loadstore1...
            -- Load hit case is the standard path
            if r1.hit_load_valid = '1' then
                report "completing load hit data=" & to_hstring(r1.data_out);
            end if;

            -- error cases complete without stalling
            if r1.ls_error = '1' then
                report "completing ld/st with error";
            end if;

            -- Slow ops (load miss, NC, stores)
            if r1.slow_valid = '1' then
                report "completing store or load miss data=" & to_hstring(r1.data_out);
            end if;

        else
            -- Request came from MMU
            if r1.hit_load_valid = '1' then
                report "completing load hit to MMU, data=" & to_hstring(m_out.data);
            end if;

            -- error cases complete without stalling
            if r1.mmu_error = '1' then
                report "completing MMU ld with error";
            end if;

            -- Slow ops (i.e. load miss)
            if r1.slow_valid = '1' then
                report "completing MMU load miss, data=" & to_hstring(m_out.data);
            end if;
        end if;

    end process;

    -- RAM write data and select multiplexers
    ram_wr_data <= r1.req.data when r1.write_bram = '1' else
                   wishbone_in.dat when r1.dcbz = '0' else
                   (others => '0');
    ram_wr_select <= r1.req.byte_sel when r1.write_bram = '1' else
                     (others => '1');

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
	signal wr_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
	signal wr_data  : std_ulogic_vector(wishbone_data_bits-1 downto 0);
	signal wr_sel   : std_ulogic_vector(ROW_SIZE-1 downto 0);
	signal wr_sel_m : std_ulogic_vector(ROW_SIZE-1 downto 0);
	signal dout     : cache_row_t;
    begin
	way: entity work.cache_ram
	    generic map (
		ROW_BITS => ROW_BITS,
		WIDTH => wishbone_data_bits,
		ADD_BUF => false
		)
	    port map (
		clk     => clk,
		rd_en   => do_read,
		rd_addr => rd_addr,
		rd_data => dout,
		wr_sel  => wr_sel_m,
		wr_addr => wr_addr,
		wr_data => ram_wr_data
		);
	process(all)
	begin
	    -- Cache hit reads
	    do_read <= early_rd_valid;
            rd_addr <= std_ulogic_vector(early_req_row);
	    cache_out(i) <= dout;

	    -- Write mux:
	    --
	    -- Defaults to wishbone read responses (cache refill),
	    --
	    -- For timing, the mux on wr_data/sel/addr is not dependent on anything
	    -- other than the current state.
	    --
            wr_addr <= std_ulogic_vector(r1.store_row);

            wr_sel_m <= (others => '0');
            if r1.write_bram = '1' or
                (r1.state = RELOAD_WAIT_ACK and wishbone_in.ack = '1') then
                assert not is_X(replace_way);
                if to_unsigned(i, WAY_BITS) = replace_way then
                    wr_sel_m <= ram_wr_select;
                end if;
            end if;

        end process;
    end generate;

    --
    -- Cache hit synchronous machine for the easy case. This handles load hits.
    -- It also handles error cases (TLB miss, cache paradox)
    --
    dcache_fast_hit : process(clk)
        variable j        : integer;
        variable sel      : std_ulogic_vector(1 downto 0);
        variable data_out : std_ulogic_vector(63 downto 0);
    begin
        if rising_edge(clk) then
            if req_op /= OP_NONE then
                report "op:" & op_t'image(req_op) &
                    " addr:" & to_hstring(r0.req.addr) &
                    " nc:" & std_ulogic'image(r0.req.nc) &
                    " idx:" & to_hstring(req_index) &
                    " tag:" & to_hstring(req_tag) &
                    " way: " & to_hstring(req_hit_way);
            end if;
            if r0_valid = '1' then
                r1.mmu_req <= r0.mmu_req;
            end if;

            -- Bypass/forwarding multiplexer for load data.
            -- Use the bypass if are reading the row of BRAM that was written 0 or 1
            -- cycles ago, including for the slow_valid = 1 cases (i.e. completing a
            -- load miss or a non-cacheable load), which are handled via the r1.full case.
            for i in 0 to 7 loop
                if r1.full = '1' or use_forward_rl = '1' then
                    sel := '0' & r1.dcbz;
                elsif use_forward_st = '1' and r1.req.byte_sel(i) = '1' then
                    sel := "01";
                elsif use_forward2 = '1' and r1.forward_sel(i) = '1' then
                    sel := "10";
                else
                    sel := "11";
                end if;
                j := i * 8;
                case sel is
                    when "00" =>
                        data_out(j + 7 downto j) := wishbone_in.dat(j + 7 downto j);
                    when "01" =>
                        data_out(j + 7 downto j) := r1.req.data(j + 7 downto j);
                    when "10" =>
                        data_out(j + 7 downto j) := r1.forward_data(j + 7 downto j);
                    when others =>
                        if is_X(req_hit_way) then
                            data_out(j + 7 downto j) := (others => 'X');
                        else
                            data_out(j + 7 downto j) := cache_out(to_integer(req_hit_way))(j + 7 downto j);
                        end if;
                end case;
            end loop;
            r1.data_out <= data_out;

            r1.forward_data <= ram_wr_data;
            r1.forward_tag <= r1.reload_tag;
            r1.forward_row <= r1.store_row;
            r1.forward_sel <= ram_wr_select;
            r1.forward_valid <= r1.write_bram;
            if r1.state = RELOAD_WAIT_ACK and wishbone_in.ack = '1' then
                r1.forward_valid <= '1';
            end if;

            -- Fast path for load/store hits. Set signals for the writeback controls.
            r1.hit_way <= req_hit_way;
            r1.hit_index <= req_index;
	    if req_op = OP_LOAD_HIT then
		r1.hit_load_valid <= '1';
	    else
		r1.hit_load_valid <= '0';
	    end if;
            if req_op = OP_LOAD_HIT or req_op = OP_STORE_HIT then
                r1.cache_hit <= '1';
            else
                r1.cache_hit <= '0';
            end if;

            if req_op = OP_BAD then
                report "Signalling ld/st error valid_ra=" & std_ulogic'image(valid_ra) &
                    " rc_ok=" & std_ulogic'image(rc_ok) & " perm_ok=" & std_ulogic'image(perm_ok);
                r1.ls_error <= not r0.mmu_req;
                r1.mmu_error <= r0.mmu_req;
                r1.cache_paradox <= access_ok;
            else
                r1.ls_error <= '0';
                r1.mmu_error <= '0';
                r1.cache_paradox <= '0';
            end if;

            if req_op = OP_STCX_FAIL then
                r1.stcx_fail <= '1';
            else
                r1.stcx_fail <= '0';
            end if;

            -- Record TLB hit information for updating TLB PLRU
            r1.tlb_hit <= tlb_hit;
            r1.tlb_hit_way <= tlb_hit_way;
            r1.tlb_hit_index <= tlb_req_index;

	end if;
    end process;

    --
    -- Memory accesses are handled by this state machine:
    --
    --   * Cache load miss/reload (in conjunction with "rams")
    --   * Load hits for non-cachable forms
    --   * Stores (the collision case is handled in "rams")
    --
    -- All wishbone requests generation is done here. This machine
    -- operates at stage 1.
    --
    dcache_slow : process(clk)
        variable stbs_done : boolean;
        variable req       : mem_access_request_t;
        variable acks      : unsigned(2 downto 0);
    begin
        if rising_edge(clk) then
            ev.dcache_refill <= '0';
            ev.load_miss <= '0';
            ev.store_miss <= '0';
            ev.dtlb_miss <= tlb_miss;

	    -- On reset, clear all valid bits to force misses
            if rst = '1' then
		for i in 0 to NUM_LINES-1 loop
		    cache_valids(i) <= (others => '0');
		end loop;
                r1.state <= IDLE;
                r1.full <= '0';
		r1.slow_valid <= '0';
                r1.wb.cyc <= '0';
                r1.wb.stb <= '0';
                r1.ls_valid <= '0';
                r1.mmu_done <= '0';

		-- Not useful normally but helps avoiding tons of sim warnings
		r1.wb.adr <= (others => '0');
            else
		-- One cycle pulses reset
		r1.slow_valid <= '0';
                r1.write_bram <= '0';
                r1.inc_acks <= '0';
                r1.dec_acks <= '0';

                r1.ls_valid <= '0';
                -- complete tlbies and TLB loads in the third cycle
                r1.mmu_done <= r0_valid and (r0.tlbie or r0.tlbld);
                if req_op = OP_LOAD_HIT or req_op = OP_STCX_FAIL then
                    if r0.mmu_req = '0' then
                        r1.ls_valid <= '1';
                    else
                        r1.mmu_done <= '1';
                    end if;
                end if;

                -- Do invalidations from snooped stores to memory
                if snoop_valid = '1' then
                    assert not is_X(snoop_tag_set);
                    assert not is_X(snoop_wrtag);
                end if;
                for i in 0 to NUM_WAYS-1 loop
                    if snoop_valid = '1' and read_tag(i, snoop_tag_set) = snoop_wrtag then
                        assert not is_X(snoop_index);
                        cache_valids(to_integer(snoop_index))(i) <= '0';
                    end if;
                end loop;

                if r1.write_tag = '1' then
                    -- Store new tag in selected way
                    assert not is_X(r1.store_index);
                    assert not is_X(replace_way);
                    for i in 0 to NUM_WAYS-1 loop
                        if to_unsigned(i, WAY_BITS) = replace_way then
                            cache_tags(to_integer(r1.store_index))((i + 1) * TAG_WIDTH - 1 downto i * TAG_WIDTH) <=
                                (TAG_WIDTH - 1 downto TAG_BITS => '0') & r1.reload_tag;
                        end if;
                    end loop;
                    r1.store_way <= replace_way;
                    r1.write_tag <= '0';
                end if;

                -- Take request from r1.req if there is one there,
                -- else from req_op, ra, etc.
                if r1.full = '1' then
                    req := r1.req;
                else
                    req.op := req_op;
                    req.valid := req_go;
                    req.mmu_req := r0.mmu_req;
                    req.dcbz := r0.req.dcbz;
                    req.real_addr := ra;
                    -- Force data to 0 for dcbz
                    if r0.req.dcbz = '1' then
                        req.data := (others => '0');
                    elsif r0.d_valid = '1' then
                        req.data := r0.req.data;
                    else
                        req.data := d_in.data;
                    end if;
                    -- Select all bytes for dcbz and for cacheable loads
                    if r0.req.dcbz = '1' or (r0.req.load = '1' and r0.req.nc = '0' and perm_attr.nocache = '0') then
                        req.byte_sel := (others => '1');
                    else
                        req.byte_sel := r0.req.byte_sel;
                    end if;
                    req.hit_way := req_hit_way;
                    req.same_tag := req_same_tag;

                    -- Store the incoming request from r0, if it is a slow request
                    -- Note that r1.full = 1 implies req_op = OP_NONE
                    if req_op = OP_LOAD_MISS or req_op = OP_LOAD_NC or
                        req_op = OP_STORE_MISS or req_op = OP_STORE_HIT then
                        r1.req <= req;
                        r1.full <= '1';
                    end if;
                end if;

		-- Main state machine
		case r1.state is
                when IDLE =>
                    r1.wb.adr <= addr_to_wb(req.real_addr);
                    r1.wb.sel <= req.byte_sel;
                    r1.wb.dat <= req.data;
                    r1.dcbz <= req.dcbz;

                    -- Keep track of our index and way for subsequent stores.
                    r1.store_index <= get_index(req.real_addr);
                    r1.store_row <= get_row(req.real_addr);
                    r1.end_row_ix <= get_row_of_line(get_row(req.real_addr)) - 1;
                    r1.reload_tag <= get_tag(req.real_addr);
                    r1.req.same_tag <= '1';

                    if req.op = OP_STORE_HIT then
                        r1.store_way <= req.hit_way;
                    end if;

                    -- Reset per-row valid bits, ready for handling OP_LOAD_MISS
                    for i in 0 to ROW_PER_LINE - 1 loop
                        r1.rows_valid(i) <= '0';
                    end loop;

                    case req.op is
                    when OP_LOAD_HIT =>
                        -- stay in IDLE state

                    when OP_LOAD_MISS =>
			-- Normal load cache miss, start the reload machine
			--
			report "cache miss real addr:" & to_hstring(req.real_addr) &
			    " idx:" & to_hstring(get_index(req.real_addr)) &
			    " tag:" & to_hstring(get_tag(req.real_addr));

			-- Start the wishbone cycle
			r1.wb.we  <= '0';
			r1.wb.cyc <= '1';
			r1.wb.stb <= '1';

			-- Track that we had one request sent
			r1.state <= RELOAD_WAIT_ACK;
                        r1.write_tag <= '1';
                        ev.load_miss <= '1';

		    when OP_LOAD_NC =>
                        r1.wb.cyc <= '1';
                        r1.wb.stb <= '1';
			r1.wb.we <= '0';
			r1.state <= NC_LOAD_WAIT_ACK;

                    when OP_STORE_HIT | OP_STORE_MISS =>
                        if req.dcbz = '0' then
                            r1.state <= STORE_WAIT_ACK;
                            r1.acks_pending <= to_unsigned(1, 3);
                            r1.full <= '0';
                            r1.slow_valid <= '1';
                            if req.mmu_req = '0' then
                                r1.ls_valid <= '1';
                            else
                                r1.mmu_done <= '1';
                            end if;
                            if req.op = OP_STORE_HIT then
                                r1.write_bram <= '1';
                            end if;
                        else
                            -- dcbz is handled much like a load miss except
                            -- that we are writing to memory instead of reading
                            r1.state <= RELOAD_WAIT_ACK;
                            if req.op = OP_STORE_MISS then
                                r1.write_tag <= '1';
                            end if;
                        end if;
                        r1.wb.we <= '1';
                        r1.wb.cyc <= '1';
                        r1.wb.stb <= '1';
                        if req.op = OP_STORE_MISS then
                            ev.store_miss <= '1';
                        end if;

		    -- OP_NONE and OP_BAD do nothing
                    -- OP_BAD & OP_STCX_FAIL were handled above already
		    when OP_NONE =>
                    when OP_BAD =>
                    when OP_STCX_FAIL =>
		    end case;

                when RELOAD_WAIT_ACK =>
		    -- If we are still sending requests, was one accepted ?
                    if wishbone_in.stall = '0' and r1.wb.stb = '1' then
			-- That was the last word ? We are done sending. Clear stb.
                        assert not is_X(r1.wb.adr);
                        assert not is_X(r1.end_row_ix);
			if is_last_row_wb_addr(r1.wb.adr, r1.end_row_ix) then
			    r1.wb.stb <= '0';
			end if;

			-- Calculate the next row address
			r1.wb.adr <= next_row_wb_addr(r1.wb.adr);
		    end if;

		    -- Incoming acks processing
		    if wishbone_in.ack = '1' then
                        r1.rows_valid(to_integer(r1.store_row(ROW_LINEBITS-1 downto 0))) <= '1';
                        -- If this is the data we were looking for, we can
                        -- complete the request next cycle.
                        -- Compare the whole address in case the request in
                        -- r1.req is not the one that started this refill.
                        -- (Cases where req comes from r0 are handled as a load
                        -- hit.)
                        if r1.full = '1' then
                            assert not is_X(r1.store_row);
                            assert not is_X(r1.req.real_addr);
                        end if;
			if r1.full = '1' and r1.req.same_tag = '1' and
                            ((r1.dcbz = '1' and req.dcbz = '1') or r1.req.op = OP_LOAD_MISS) and
                            r1.store_row = get_row(r1.req.real_addr) then
                            r1.full <= '0';
                            r1.slow_valid <= '1';
                            if r1.mmu_req = '0' then
                                r1.ls_valid <= '1';
                            else
                                r1.mmu_done <= '1';
                            end if;
			end if;

			-- Check for completion
                        assert not is_X(r1.store_row);
                        assert not is_X(r1.end_row_ix);
			if is_last_row(r1.store_row, r1.end_row_ix) then
			    -- Complete wishbone cycle
			    r1.wb.cyc <= '0';

			    -- Cache line is now valid
                            assert not is_X(r1.store_index);
                            assert not is_X(r1.store_way);
			    cache_valids(to_integer(r1.store_index))(to_integer(r1.store_way)) <= '1';

                            ev.dcache_refill <= not r1.dcbz;
                            r1.state <= IDLE;
			end if;

			-- Increment store row counter
			r1.store_row <= next_row(r1.store_row);
		    end if;

                when STORE_WAIT_ACK =>
		    stbs_done := r1.wb.stb = '0';
                    acks := r1.acks_pending;
                    if r1.inc_acks /= r1.dec_acks then
                        if r1.inc_acks = '1' then
                            acks := acks + 1;
                        else
                            acks := acks - 1;
                        end if;
                    end if;
                    r1.acks_pending <= acks;
		    -- Clear stb when slave accepted request
                    if wishbone_in.stall = '0' then
                        -- See if there is another store waiting to be done
                        -- which is in the same real page.
                        if req.valid = '1' then
                            r1.wb.adr(SET_SIZE_BITS - ROW_OFF_BITS - 1 downto 0) <=
                                req.real_addr(SET_SIZE_BITS - 1 downto ROW_OFF_BITS);
                            r1.wb.dat <= req.data;
                            r1.wb.sel <= req.byte_sel;
                        end if;
                        assert not is_X(acks);
                        if acks < 7 and req.same_tag = '1' and req.dcbz = '0' and
                            (req.op = OP_STORE_MISS or req.op = OP_STORE_HIT) then
                            r1.wb.stb <= '1';
                            stbs_done := false;
                            r1.store_way <= req.hit_way;
                            r1.store_row <= get_row(req.real_addr);
                            if req.op = OP_STORE_HIT then
                                r1.write_bram <= '1';
                            end if;
                            r1.full <= '0';
                            r1.slow_valid <= '1';
                            -- Store requests never come from the MMU
                            r1.ls_valid <= '1';
                            stbs_done := false;
                            r1.inc_acks <= '1';
                        else
                            r1.wb.stb <= '0';
                            stbs_done := true;
                        end if;
		    end if;

		    -- Got ack ? See if complete.
		    if wishbone_in.ack = '1' then
                        assert not is_X(acks);
                        if stbs_done and acks = 1 then
                            r1.state <= IDLE;
                            r1.wb.cyc <= '0';
                            r1.wb.stb <= '0';
                        end if;
                        r1.dec_acks <= '1';
		    end if;

                when NC_LOAD_WAIT_ACK =>
		    -- Clear stb when slave accepted request
                    if wishbone_in.stall = '0' then
			r1.wb.stb <= '0';
		    end if;

		    -- Got ack ? complete.
		    if wishbone_in.ack = '1' then
                        r1.state <= IDLE;
                        r1.full <= '0';
			r1.slow_valid <= '1';
                        if r1.mmu_req = '0' then
                            r1.ls_valid <= '1';
                        else
                            r1.mmu_done <= '1';
                        end if;
			r1.wb.cyc <= '0';
			r1.wb.stb <= '0';
		    end if;
                end case;
	    end if;
	end if;
    end process;

    dc_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(19 downto 0);
    begin
        dcache_log: process(clk)
        begin
            if rising_edge(clk) then
                log_data <= r1.wb.adr(2 downto 0) &
                            wishbone_in.stall &
                            wishbone_in.ack &
                            r1.wb.stb & r1.wb.cyc &
                            d_out.error &
                            d_out.valid &
                            std_ulogic_vector(to_unsigned(op_t'pos(req_op), 3)) &
                            stall_out &
                            std_ulogic_vector(resize(tlb_hit_way, 3)) &
                            valid_ra &
                            std_ulogic_vector(to_unsigned(state_t'pos(r1.state), 3));
            end if;
        end process;
        log_out <= log_data;
    end generate;
end;
