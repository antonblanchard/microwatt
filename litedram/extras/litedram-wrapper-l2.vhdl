library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;
use work.utils.all;
use work.helpers.all;

entity litedram_wrapper is
    generic (
	DRAM_ABITS      : positive;
	DRAM_ALINES     : natural;
	DRAM_DLINES     : natural;
	DRAM_PORT_WIDTH : positive;

        -- Pseudo-ROM payload
        PAYLOAD_SIZE      : natural;    
        PAYLOAD_FILE      : string;

        -- L2 cache --

        -- Line size in bytes
        LINE_SIZE         : positive := 128;
        -- Number of lines in a set
        NUM_LINES         : positive := 64;
        -- Number of ways
        NUM_WAYS          : positive := 4;
        -- Max number of stores in the queue
        STOREQ_DEPTH      : positive := 8;
        -- Don't send loads until all pending stores acked in litedram
        NO_LS_OVERLAP     : boolean  := false;

        -- Debug
        LITEDRAM_TRACE    : boolean  := false;
        TRACE             : boolean  := false
        );
    port(
        -- LiteDRAM generates the system clock and reset
        -- from the input clkin
        clk_in          : in std_ulogic;
        rst             : in std_ulogic;
        system_clk      : out std_ulogic;
        system_reset    : out std_ulogic;
        core_alt_reset  : out std_ulogic;
        pll_locked      : out std_ulogic;

        -- Wishbone ports:
        wb_in           : in wishbone_master_out;
        wb_out          : out wishbone_slave_out;
        wb_ctrl_in      : in wb_io_master_out;
        wb_ctrl_out     : out wb_io_slave_out;
        wb_ctrl_is_csr  : in std_ulogic;
        wb_ctrl_is_init : in std_ulogic;

        -- Misc
        init_done     : out std_ulogic;
        init_error    : out std_ulogic;

        -- DRAM wires
        ddram_a       : out std_ulogic_vector(DRAM_ALINES-1 downto 0);
        ddram_ba      : out std_ulogic_vector(2 downto 0);
        ddram_ras_n   : out std_ulogic;
        ddram_cas_n   : out std_ulogic;
        ddram_we_n    : out std_ulogic;
        ddram_cs_n    : out std_ulogic;
        ddram_dm      : out std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_dq      : inout std_ulogic_vector(DRAM_DLINES-1 downto 0);
        ddram_dqs_p   : inout std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_dqs_n   : inout std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_clk_p   : out std_ulogic;
        ddram_clk_n   : out std_ulogic;
        ddram_cke     : out std_ulogic;
        ddram_odt     : out std_ulogic;
        ddram_reset_n : out std_ulogic
        );
end entity litedram_wrapper;

architecture behaviour of litedram_wrapper is

    component litedram_core port (
        clk                            : in std_ulogic;
        rst                            : in std_ulogic;
        pll_locked                     : out std_ulogic;
        ddram_a                        : out std_ulogic_vector(DRAM_ALINES-1 downto 0);
        ddram_ba                       : out std_ulogic_vector(2 downto 0);
        ddram_ras_n                    : out std_ulogic;
        ddram_cas_n                    : out std_ulogic;
        ddram_we_n                     : out std_ulogic;
        ddram_cs_n                     : out std_ulogic;
        ddram_dm                       : out std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_dq                       : inout std_ulogic_vector(DRAM_DLINES-1 downto 0);
        ddram_dqs_p                    : inout std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_dqs_n                    : inout std_ulogic_vector(DRAM_DLINES/8-1 downto 0);
        ddram_clk_p                    : out std_ulogic;
        ddram_clk_n                    : out std_ulogic;
        ddram_cke                      : out std_ulogic;
        ddram_odt                      : out std_ulogic;
        ddram_reset_n                  : out std_ulogic;
        init_done                      : out std_ulogic;
        init_error                     : out std_ulogic;
        user_clk                       : out std_ulogic;
        user_rst                       : out std_ulogic;
        wb_ctrl_adr                    : in std_ulogic_vector(29 downto 0);
        wb_ctrl_dat_w                  : in std_ulogic_vector(31 downto 0);
        wb_ctrl_dat_r                  : out std_ulogic_vector(31 downto 0);
        wb_ctrl_sel                    : in std_ulogic_vector(3 downto 0);
        wb_ctrl_cyc                    : in std_ulogic;
        wb_ctrl_stb                    : in std_ulogic;
        wb_ctrl_ack                    : out std_ulogic;
        wb_ctrl_we                     : in std_ulogic;
        wb_ctrl_cti                    : in std_ulogic_vector(2 downto 0);
        wb_ctrl_bte                    : in std_ulogic_vector(1 downto 0);
        wb_ctrl_err                    : out std_ulogic;
        user_port_native_0_cmd_valid   : in std_ulogic;
        user_port_native_0_cmd_ready   : out std_ulogic;
        user_port_native_0_cmd_we      : in std_ulogic;
        user_port_native_0_cmd_addr    : in std_ulogic_vector(DRAM_ABITS-1 downto 0);
        user_port_native_0_wdata_valid : in std_ulogic;
        user_port_native_0_wdata_ready : out std_ulogic;
        user_port_native_0_wdata_we    : in std_ulogic_vector(DRAM_PORT_WIDTH/8-1 downto 0);
        user_port_native_0_wdata_data  : in std_ulogic_vector(DRAM_PORT_WIDTH-1 downto 0);
        user_port_native_0_rdata_valid : out std_ulogic;
        user_port_native_0_rdata_ready : in std_ulogic;
        user_port_native_0_rdata_data  : out std_ulogic_vector(DRAM_PORT_WIDTH-1 downto 0)
        );
    end component;
    
    signal user_port0_cmd_valid         : std_ulogic;
    signal user_port0_cmd_ready         : std_ulogic;
    signal user_port0_cmd_we            : std_ulogic;
    signal user_port0_cmd_addr          : std_ulogic_vector(DRAM_ABITS-1 downto 0);
    signal user_port0_wdata_valid       : std_ulogic;
    signal user_port0_wdata_ready       : std_ulogic;
    signal user_port0_wdata_we          : std_ulogic_vector(DRAM_PORT_WIDTH/8-1 downto 0);
    signal user_port0_wdata_data        : std_ulogic_vector(DRAM_PORT_WIDTH-1 downto 0);
    signal user_port0_rdata_valid       : std_ulogic;
    signal user_port0_rdata_ready       : std_ulogic;
    signal user_port0_rdata_data        : std_ulogic_vector(DRAM_PORT_WIDTH-1 downto 0);

    signal wb_ctrl_adr                  : std_ulogic_vector(29 downto 0);
    signal wb_ctrl_dat_w                : std_ulogic_vector(31 downto 0);
    signal wb_ctrl_dat_r                : std_ulogic_vector(31 downto 0);
    signal wb_ctrl_sel                  : std_ulogic_vector(3 downto 0);
    signal wb_ctrl_cyc                  : std_ulogic := '0';
    signal wb_ctrl_stb                  : std_ulogic;
    signal wb_ctrl_ack                  : std_ulogic;
    signal wb_ctrl_we                   : std_ulogic;

    signal wb_init_in                   : wb_io_master_out;
    signal wb_init_out                  : wb_io_slave_out;

    -- DRAM data port width
    constant DRAM_DBITS                 : natural := DRAM_PORT_WIDTH;
    -- DRAM data port sel bits
    constant DRAM_SBITS                 : natural := (DRAM_DBITS / 8);

    -- WB geometry (just a few shortcuts)
    constant WBL                        : positive := wb_in.dat'length;
    constant WBSL                       : positive := wb_in.sel'length;

    -- Select a WB word inside DRAM port width
    constant WB_WORD_COUNT              : positive := DRAM_DBITS/WBL;
    constant WB_WSEL_BITS               : positive := log2(WB_WORD_COUNT);
    constant WB_WSEL_RIGHT              : positive := log2(WBL/8);

    -- BRAM organisation: We never access more than wishbone_data_bits at
    -- a time so to save resources we make the array only that wide, and
    -- use consecutive indices for to make a cache "line"
    --
    -- ROW_SIZE is the width in bytes of the BRAM, ie, litedram port width
    constant ROW_SIZE      : natural := DRAM_DBITS / 8;
    -- ROW_PER_LINE is the number of row (litedram transactions) in a line
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
    -- REAL_ADDR_BITS is the number of real address bits that we store
    constant REAL_ADDR_BITS : positive := DRAM_ABITS + ROW_OFF_BITS;
    -- INDEX_BITS is the number if bits to select a cache line
    constant INDEX_BITS    : natural := log2(NUM_LINES);
    -- SET_SIZE_BITS is the log base 2 of the set size
    constant SET_SIZE_BITS : natural := LINE_OFF_BITS + INDEX_BITS;
    -- TAG_BITS is the number of bits of the tag part of the address
    constant TAG_BITS      : natural := REAL_ADDR_BITS - SET_SIZE_BITS;
    -- WAY_BITS is the number of bits to select a way
    constant WAY_BITS      : natural := log2(NUM_WAYS);

    subtype row_t is integer range 0 to BRAM_ROWS-1;
    subtype index_t is integer range 0 to NUM_LINES-1;
    subtype way_t is integer range 0 to NUM_WAYS-1;
    subtype row_in_line_t is unsigned(ROW_LINEBITS-1 downto 0);

    -- The cache data BRAM organized as described above for each way
    subtype cache_row_t is std_ulogic_vector(DRAM_DBITS-1 downto 0);

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

    -- "Temporary" valid bits for the rows of the currently refilled line
    type row_per_line_valid_t is array(0 to ROW_PER_LINE - 1) of std_ulogic;

    -- Storage. Hopefully "cache_rows" is a BRAM, the rest is LUTs
    signal cache_tags   : cache_tags_array_t;
    signal cache_valids : cache_valids_t;

    attribute ram_style : string;
    attribute ram_style of cache_tags : signal is "distributed";

    --
    -- Store queue signals
    --
    -- We store a single wishbone dword per entry (64-bit)
    -- along with the wishbone sel bits and the necessary address
    -- bits to select which part of DRAM port to write to.
    constant STOREQ_BITS  : positive := WBL + WBSL + WB_WSEL_BITS;

    signal storeq_rd_ready : std_ulogic;
    signal storeq_rd_valid : std_ulogic;
    signal storeq_rd_data  : std_ulogic_vector(STOREQ_BITS-1 downto 0);
    signal storeq_wr_ready : std_ulogic;
    signal storeq_wr_valid : std_ulogic;
    signal storeq_wr_data  : std_ulogic_vector(STOREQ_BITS-1 downto 0);

    --
    -- Cache management signals
    --

    -- Cache state machine
    type state_t is (IDLE,             -- Normal load hit processing
                     REFILL_CLR_TAG,   -- Cache refill clear tag
                     REFILL_WAIT_ACK); -- Cache refill wait ack
    signal state : state_t;

    -- Latched WB request
    signal wb_req   : wishbone_master_out := wishbone_master_out_init;
    -- Stashed WB request
    signal wb_stash : wishbone_master_out := wishbone_master_out_init;

    -- Read pipeline (to handle cache RAM latency)
    signal read_ack_0  : std_ulogic := '0';
    signal read_ack_1  : std_ulogic := '0';
    signal read_wsl_0  : std_ulogic_vector(WB_WSEL_BITS-1 downto 0) := (others => '0');
    signal read_wsl_1  : std_ulogic_vector(WB_WSEL_BITS-1 downto 0) := (others => '0');
    signal read_way_0  : way_t;
    signal read_way_1  : way_t;

    -- Store ack pipeline
    signal store_ack_0 : std_ulogic := '0';
    signal store_ack_1 : std_ulogic := '0';

    -- Async signals decoding latched request
    type req_op_t is (OP_NONE,
                      OP_LOAD_HIT,
                      OP_LOAD_MISS,
                      OP_STORE_HIT,
                      OP_STORE_MISS,
                      OP_STORE_DELAYED);

    signal req_index    : index_t;
    signal req_row      : row_t;
    signal req_hit_way  : way_t;
    signal req_tag      : cache_tag_t;
    signal req_op       : req_op_t;
    signal req_laddr    : std_ulogic_vector(REAL_ADDR_BITS-1 downto 0);
    signal req_wsl      : std_ulogic_vector(WB_WSEL_BITS-1 downto 0);
    signal req_we       : std_ulogic_vector(DRAM_SBITS-1 downto 0);
    signal req_wdata    : std_ulogic_vector(DRAM_DBITS-1 downto 0);
    signal stall        : std_ulogic;

    -- Line refill command signals and latches
    signal refill_cmd_valid : std_ulogic;
    signal refill_cmd_addr  : std_ulogic_vector(DRAM_ABITS-1 downto 0);
    signal refill_way       : way_t;
    signal refill_index     : index_t;
    signal refill_row       : row_t;
    signal refill_end_row   : row_in_line_t;
    signal refill_rows_vlid : row_per_line_valid_t;

    -- Cache RAM interface
    type cache_ram_out_t is array(way_t) of cache_row_t;
    signal cache_out   : cache_ram_out_t;

    -- PLRU output interface
    type plru_out_t is array(index_t) of std_ulogic_vector(WAY_BITS-1 downto 0);
    signal plru_victim : plru_out_t;

    --
    -- Helper functions to decode incoming requests
    --

    -- Return the cache line index (tag index) for an address
    function get_index(addr: wishbone_addr_type) return index_t is
    begin
        return to_integer(unsigned(addr(SET_SIZE_BITS - 1 downto LINE_OFF_BITS)));
    end;

    -- Return the cache row index (data memory) for an address
    function get_row(addr: std_ulogic_vector(REAL_ADDR_BITS-1 downto 0)) return row_t is
    begin
        return to_integer(unsigned(addr(SET_SIZE_BITS - 1 downto ROW_OFF_BITS)));
    end;

    -- Return the index of a row within a line
    function get_row_of_line(row: row_t) return row_in_line_t is
	variable row_v : unsigned(ROW_BITS-1 downto 0);
    begin
	row_v := to_unsigned(row, ROW_BITS);
        return row_v(ROW_LINEBITS-1 downto 0);
    end;
    -- Returns whether this is the last row of a line. It takes a DRAM address
    function is_last_row_addr(addr: std_ulogic_vector(REAL_ADDR_BITS-1 downto ROW_OFF_BITS);
                              last: row_in_line_t)
        return boolean is
    begin
        return unsigned(addr(LINE_OFF_BITS-1 downto ROW_OFF_BITS)) = last;
    end;

    -- Returns whether this is the last row of a line
    function is_last_row(row: row_t; last: row_in_line_t) return boolean is
    begin
        return get_row_of_line(row) = last;
    end;

    -- Return the address of the next row in the current cache line. It takes a
    -- DRAM address
    function next_row_addr(addr: std_ulogic_vector(REAL_ADDR_BITS-1 downto ROW_OFF_BITS))
        return std_ulogic_vector is
        variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
        variable result  : std_ulogic_vector(REAL_ADDR_BITS-1 downto ROW_OFF_BITS);
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
       variable row_v  : std_ulogic_vector(ROW_BITS-1 downto 0);
       variable row_idx : std_ulogic_vector(ROW_LINEBITS-1 downto 0);
       variable result : std_ulogic_vector(ROW_BITS-1 downto 0);
    begin
       row_v := std_ulogic_vector(to_unsigned(row, ROW_BITS));
       row_idx := row_v(ROW_LINEBITS-1 downto 0);
       row_v(ROW_LINEBITS-1 downto 0) := std_ulogic_vector(unsigned(row_idx) + 1);
       return to_integer(unsigned(row_v));
    end;

    -- Get the tag value from the address
    function get_tag(addr: wishbone_addr_type) return cache_tag_t is
    begin
        return addr(REAL_ADDR_BITS - 1 downto SET_SIZE_BITS);
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

    -- Sanity checks
    assert LINE_SIZE mod ROW_SIZE = 0 report "LINE_SIZE not multiple of ROW_SIZE" severity FAILURE;
    assert ispow2(LINE_SIZE)    report "LINE_SIZE not power of 2" severity FAILURE;
    assert ispow2(NUM_LINES)    report "NUM_LINES not power of 2" severity FAILURE;
    assert ispow2(ROW_PER_LINE) report "ROW_PER_LINE not power of 2" severity FAILURE;
    assert (ROW_BITS = INDEX_BITS + ROW_LINEBITS)
        report "geometry bits don't add up" severity FAILURE;
    assert (LINE_OFF_BITS = ROW_OFF_BITS + ROW_LINEBITS)
        report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS = TAG_BITS + INDEX_BITS + LINE_OFF_BITS)
        report "geometry bits don't add up" severity FAILURE;
    assert (REAL_ADDR_BITS = TAG_BITS + ROW_BITS + ROW_OFF_BITS)
        report "geometry bits don't add up" severity FAILURE;

    -- alternate core reset address set when DRAM is not initialized.
    core_alt_reset <= not init_done;

    -- Init code BRAM memory slave 
    init_ram_0: entity work.dram_init_mem
        generic map(
            EXTRA_PAYLOAD_FILE => PAYLOAD_FILE,
            EXTRA_PAYLOAD_SIZE => PAYLOAD_SIZE
            )
        port map(
            clk => system_clk,
            wb_in => wb_init_in,
            wb_out => wb_init_out
            );

    --
    -- Control bus wishbone: This muxes the wishbone to the CSRs
    -- and an internal small one to the init BRAM
    --

    -- Init DRAM wishbone IN signals
    wb_init_in.adr <= wb_ctrl_in.adr;
    wb_init_in.dat <= wb_ctrl_in.dat;
    wb_init_in.sel <= wb_ctrl_in.sel;
    wb_init_in.we  <= wb_ctrl_in.we;
    wb_init_in.stb <= wb_ctrl_in.stb;
    wb_init_in.cyc <= wb_ctrl_in.cyc and wb_ctrl_is_init;

    -- DRAM CSR IN signals. Extra latch to help with timing
    csr_latch: process(system_clk)
    begin
        if rising_edge(system_clk) then
            if system_reset = '1' then
                wb_ctrl_cyc <= '0';
                wb_ctrl_stb <= '0';
            else
                -- XXX Maybe only update addr when cyc = '1' to save power ?
                wb_ctrl_adr   <= x"0000" & wb_ctrl_in.adr(15 downto 2);
                wb_ctrl_dat_w <= wb_ctrl_in.dat;
                wb_ctrl_sel   <= wb_ctrl_in.sel;
                wb_ctrl_we    <= wb_ctrl_in.we;
                wb_ctrl_cyc   <= wb_ctrl_in.cyc and wb_ctrl_is_csr;
                wb_ctrl_stb   <= wb_ctrl_in.stb and wb_ctrl_is_csr;

                -- Clear stb on ack otherwise the memory will latch
                -- the write twice which breaks levelling. On the next
                -- cycle we will latch an updated stb that takes the
                -- ack into account.
                if wb_ctrl_ack = '1' then
                    wb_ctrl_stb <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Ctrl bus wishbone OUT signals. XXX Consider adding latch on
    -- CSR response to help timing
    wb_ctrl_out.ack   <= wb_ctrl_ack when wb_ctrl_is_csr = '1'
                         else wb_init_out.ack;
    wb_ctrl_out.dat   <= wb_ctrl_dat_r when wb_ctrl_is_csr = '1'
                         else wb_init_out.dat;
    wb_ctrl_out.stall <= wb_init_out.stall when wb_ctrl_is_init else
                         '0' when wb_ctrl_in.cyc = '0' else not wb_ctrl_ack;


    -- Generate a cache RAM for each way
    rams: for i in 0 to NUM_WAYS-1 generate
        signal do_read  : std_ulogic;
        signal do_write : std_ulogic;
        signal rd_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
        signal wr_addr  : std_ulogic_vector(ROW_BITS-1 downto 0);
        signal wr_data  : std_ulogic_vector(DRAM_DBITS-1 downto 0);
        signal wr_sel   : std_ulogic_vector(ROW_SIZE-1 downto 0);
        signal wr_sel_m : std_ulogic_vector(ROW_SIZE-1 downto 0);
        signal dout     : cache_row_t;
   begin
        way: entity work.cache_ram
            generic map (
                ROW_BITS => ROW_BITS,
                WIDTH    => DRAM_DBITS,
                ADD_BUF  => true
                )
            port map (
                clk     => system_clk,
                rd_en   => do_read,
                rd_addr => rd_addr,
                rd_data => dout,
                wr_sel  => wr_sel_m,
                wr_addr => wr_addr,
                wr_data => wr_data
                );
        process(all)
        begin
            --
            -- Read port
            --
            do_read <= '1';
            cache_out(i) <= dout;
            rd_addr <= std_ulogic_vector(to_unsigned(req_row, ROW_BITS));

            --
            -- Write mux: cache refills from DRAM or writes from Wishbone
            --
            if req_op = OP_STORE_HIT and req_hit_way = i then
                -- Write from wishbone
                wr_addr <= std_ulogic_vector(to_unsigned(req_row, ROW_BITS));
                wr_data <= req_wdata;
                wr_sel  <= req_we;
            else
                -- Refill from DRAM
                wr_data <= user_port0_rdata_data;
                wr_sel  <= (others => '1');
                wr_addr <= std_ulogic_vector(to_unsigned(refill_row, ROW_BITS));
            end if;

            --
            -- Write enable logic
            --
            do_write <= '0';
            if req_op = OP_STORE_HIT and req_hit_way = i then
                do_write <= '1';
            elsif user_port0_rdata_valid = '1' and refill_way = i then
                do_write <= '1';
            end if;

            -- Mask write selects with do_write since BRAM doesn't always
            -- have a global write-enable (Vivado generates TDP instead
            -- of SDP when using one, thus doubling cache BRAM usage).
            for i in 0 to ROW_SIZE-1 loop
                wr_sel_m(i) <= wr_sel(i) and do_write;
            end loop;

            if TRACE and rising_edge(system_clk) then
                if do_write = '1' then
                    report "cache write way:" & integer'image(i) &
                        " addr:" & to_hstring(wr_addr) &
                        " sel:" & to_hstring(wr_sel_m) &
                        " data:" & to_hstring(wr_data);
                end if;
            end if;
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
                    clk => system_clk,
                    rst => system_reset,
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

    --
    -- Wishbone request interface:
    --
    --  - Incoming wishbone request latch (to help with timing)
    --  - Read response pipeline (to match BRAM output buffer delay)
    --  - Stall generation
    --
    -- XXX TODO: Properly handle cyc drops before all acks are sent...
    --
    request_latch: process(system_clk)
    begin
        if rising_edge(system_clk) then

            -- Implement a stash buffer. If we are stalled and stash is
            -- free, fill it up. This will generate a WB stall on the
            -- next cycle.
            if stall = '1' and wb_out.stall = '0' and wb_in.cyc = '1' and wb_in.stb = '1' then
                 wb_stash <= wb_in;
                 if TRACE then
                     report "stashed wb req ! addr:" & to_hstring(wb_in.adr) &
                         " we:" & std_ulogic'image(wb_in.we) &
                         " sel:" & to_hstring(wb_in.sel);
                 end if;
            end if;

            -- We aren't stalled, see what we can do
            if stall = '0' then
                if wb_stash.cyc = '1' then
                    -- Something in stash ! use it and clear stash
                    wb_req <= wb_stash;
                    wb_stash.cyc <= '0';
                    if TRACE then
                        report "unstashed wb req ! addr:" & to_hstring(wb_stash.adr) &
                            " we:" & std_ulogic'image(wb_stash.we) &
                            " sel:" & to_hstring(wb_stash.sel);
                    end if;
                else
                    -- Grab request from WB
                    if wb_in.cyc = '1' then
                        wb_req <= wb_in;
                    else
                        wb_req.cyc <= wb_in.cyc;
                        wb_req.stb <= wb_in.stb;
                    end if;

                    if TRACE then
                        if wb_in.cyc = '1' and wb_in.stb = '1' then
                            report "latch new wb req ! addr:" & to_hstring(wb_in.adr) &
                                " we:" & std_ulogic'image(wb_in.we) &
                                " sel:" & to_hstring(wb_in.sel);
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -- Stall when stash is full
    wb_out.stall <= wb_stash.cyc;

    --
    -- Read response pipeline
    --
    read_pipe: process(system_clk)
    begin
        if rising_edge(system_clk) then
            read_ack_0 <= '1' when req_op = OP_LOAD_HIT else '0';
            read_wsl_0 <= req_wsl;
            read_way_0 <= req_hit_way;

            read_ack_1 <= read_ack_0;
            read_wsl_1 <= read_wsl_0;
            read_way_1 <= read_way_0;

            if TRACE then
                if req_op = OP_LOAD_HIT then
                    report "Load hit addr:" & to_hstring(wb_req.adr) &
                        " idx:" & integer'image(req_index) &
                        " tag:" & to_hstring(req_tag) &
                        " way:" & integer'image(req_hit_way);
                elsif req_op = OP_LOAD_MISS then
                    report "Load miss addr:" & to_hstring(wb_req.adr);
                end if;
                if read_ack_0 = '1' then
                    report "read data:" & to_hstring(cache_out(read_way_0));
                end if;
            end if;
        end if;
    end process;

    --
    -- Store acks pipeline
    --
    store_ack_pipe: process(system_clk)
    begin
        if rising_edge(system_clk) then
            store_ack_1 <= store_ack_0;
        end if;
    end process;

    --
    -- Wishbone response generation
    --

    wb_rseponse: process(all)
        variable rdata        : std_ulogic_vector(DRAM_DBITS-1 downto 0);
        variable store_done   : std_ulogic;
        variable accept_store : std_ulogic;
        variable wsel         : natural range 0 to WB_WORD_COUNT-1;
    begin
        -- Can we accept a store ? This is set when the store queue & command
        -- queue are not full.
        --
        -- This does *not* mean that we will accept the store, there are other
        -- reasons to delay them (see OP_STORE_DELAYED).
        --
        -- A store is fully accepted when *both* req_op is not OP_STORE_DELAYED
        -- and accept_store is '1'.
        --
        -- The reason for this split is to avoid a circular dependency inside
        -- LiteDRAM, since cmd_ready from litedram is driven from cmd_valid (*)
        -- we don't want to generate cmd_valid from cmd_ready. So we generate
        -- it instead from all the *other* conditions that make a store valid.
        --
        -- (*) It's my understanding that user_port0_cmd_ready from LiteDRAM is
        -- ombinational from user_port0_cmd_valid along with a bunch of other
        -- internal signals. IE. we won't know that LiteDRAM cannot accept a
        -- command until we try to send one.
        --
        accept_store := user_port0_cmd_ready and storeq_wr_ready;

        -- Generate stalls. For stores we stall if we can't accept it.
        -- For loads, we stall if we are going to take a load miss or
        -- are in the middle of a refill and it isn't a partial hit.
        if req_op = OP_STORE_MISS or req_op = OP_STORE_HIT then
            stall <= not accept_store;
        elsif req_op = OP_LOAD_MISS or req_op = OP_STORE_DELAYED then
            stall <= '1';
        else
            stall <= '0';
        end if;
        
        -- Data out mux
        rdata := cache_out(read_way_1);

        -- Hard wired for 64-bit wishbone
        wsel := to_integer(unsigned(read_wsl_1));
        wb_out.dat <= rdata((wsel+1)*WBL-1 downto wsel*WBL);

        -- Early-complete stores on wishbone.
        if req_op = OP_STORE_HIT or req_op = OP_STORE_MISS then
            store_done := accept_store;
        else
            store_done := '0';
        end if;

        -- Pipeline store acks
        store_ack_0 <= store_done;

        -- Generate Wishbone ACKs on read hits and store complete
        --
        -- This can happen on store right behind loads ! This is why
        -- we delay a store when a load ack is in the pipeline in the
        -- request decoder below.
        --
        wb_out.ack <= read_ack_1 or store_ack_1;
        assert read_ack_1 = '0' or store_ack_1 = '0' report
            "Read ack and store ack collision !"
            severity failure;
    end process;

    --
    -- Cache request decode
    --
    request_decode: process(all)
        variable valid       : boolean;
        variable is_hit      : boolean;
        variable store_delay : boolean;
        variable hit_way     : way_t;
    begin
        -- Extract line, row and tag from request
        req_index <= get_index(wb_req.adr);
        req_row <= get_row(wb_req.adr(REAL_ADDR_BITS-1 downto 0));
        req_tag <= get_tag(wb_req.adr);

        -- Calculate address of beginning of cache row, will be
        -- used for cache miss processing if needed
        req_laddr <= wb_req.adr(REAL_ADDR_BITS - 1 downto ROW_OFF_BITS) &
                     (ROW_OFF_BITS-1 downto 0 => '0');


        -- Do we have a valid request in the WB latch ?
        valid := wb_req.cyc = '1' and wb_req.stb = '1';

        -- Store signals (hard wired for 64-bit wishbone at the moment)
        req_wsl <= wb_req.adr(WB_WSEL_RIGHT+WB_WSEL_BITS-1 downto WB_WSEL_RIGHT);
        for i in 0 to WB_WORD_COUNT-1 loop
            if to_integer(unsigned(req_wsl)) = i then
                req_we(WBSL*(i+1)-1 downto WBSL*i) <= wb_req.sel;
            else
                req_we(WBSL*(i+1)-1 downto WBSL*i) <= x"00";
            end if;
            req_wdata(WBL*(i+1)-1 downto WBL*i) <= wb_req.dat;
        end loop;

        -- Test if pending request is a hit on any way
        hit_way := 0;
        is_hit := false;
        for i in way_t loop
            if valid and
                (cache_valids(req_index)(i) = '1' or
                 (state = REFILL_WAIT_ACK and
                  req_index = refill_index and i = refill_way and
                  refill_rows_vlid(req_row mod ROW_PER_LINE) = '1')) then
                if read_tag(i, cache_tags(req_index)) = req_tag then
                    hit_way := i;
                    is_hit := true;
                end if;
            end if;
        end loop;

        -- We need to delay stores under some circumstances to avoid
        -- collisions with the refill machine.
        --
        -- Corner case !!! The read acks pipeline takes two extra cycles
        -- which means a store ack can collide with a previous load hit
        -- ack. Thus we stall stores if we have a load ack pending.
        --
        if read_ack_0 = '1' or read_ack_1 = '1' then
            -- Clash with pending read acks, delay..
            store_delay := true;
        elsif state /= IDLE then
            -- If the reload machine is active, we cannot accept a store
            -- for now.
            --
            -- We could improve this a bit by allowing stores if we have sent
            -- all the requests down to litedram (we are only waiting for the
            -- responses) *and* either of those conditions is true:
            --
            -- * It's a miss (doesn't require a write to BRAM) and isn't
            --   for the line being reloaded (otherwise we might reload
            --   stale data into the cache).
            -- * It's a hit on a different way than the one being reloaded
            --   in which case there is no conflict for BRAM access.
            --
            -- Otherwise we delay it...
            --
            store_delay := true;
        else
            store_delay := false;
        end if;

        -- Generate the req op. We only allow OP_LOAD_* when in the
        -- IDLE state as our PLRU and ACK generation rely on this,
        -- stores are allowed in IDLE state.
        --
        req_op <= OP_NONE;
        if valid then
            if wb_req.we = '1' then
                if store_delay then
                    req_op <= OP_STORE_DELAYED;
                elsif is_hit then
                    req_op <= OP_STORE_HIT;
                else
                    req_op <= OP_STORE_MISS;
                end if;
            else
                if is_hit then
                    req_op <= OP_LOAD_HIT;
                else
                    req_op <= OP_LOAD_MISS;
                end if;
            end if;
        end if;
        req_hit_way <= hit_way;
   end process;

    --
    -- Store queue
    --
    -- For now, queue up to 16 stores
    store_queue: entity work.sync_fifo
	generic map (
	    DEPTH => STOREQ_DEPTH,
	    WIDTH => STOREQ_BITS
	    )
        port map (
            clk      => system_clk,
            reset    => system_reset,
            rd_ready => storeq_rd_ready,
            rd_valid => storeq_rd_valid,
            rd_data  => storeq_rd_data,
            wr_ready => storeq_wr_ready,
            wr_valid => storeq_wr_valid,
            wr_data  => storeq_wr_data
            );

    storeq_control : process(all)
        variable stq_data : wishbone_data_type;
        variable stq_sel  : wishbone_sel_type;
        variable stq_wsl  : std_ulogic_vector(WB_WSEL_BITS-1 downto 0);
    begin
        storeq_wr_data <= wb_req.dat & wb_req.sel &
                          wb_req.adr(WB_WSEL_RIGHT+WB_WSEL_BITS-1 downto WB_WSEL_RIGHT);

        -- Only queue stores if we can also send a command
        if req_op = OP_STORE_HIT or req_op = OP_STORE_MISS then
            storeq_wr_valid <= user_port0_cmd_ready;
        else
            storeq_wr_valid <= '0';
        end if;

        -- Store signals (hard wired for 64-bit wishbone at the moment)
        stq_data := storeq_rd_data(storeq_rd_data'left downto WBSL+WB_WSEL_BITS);
        stq_sel  := storeq_rd_data(WBSL+WB_WSEL_BITS-1 downto WB_WSEL_BITS);
        stq_wsl  := storeq_rd_data(WB_WSEL_BITS-1      downto 0);
        for i in 0 to WB_WORD_COUNT-1 loop
            if to_integer(unsigned(stq_wsl)) = i then
                user_port0_wdata_we(WBSL*(i+1)-1 downto WBSL*i) <= stq_sel;
            else
                user_port0_wdata_we(WBSL*(i+1)-1 downto WBSL*i) <= x"00";
            end if;
            user_port0_wdata_data(WBL*(i+1)-1 downto WBL*i) <= stq_data;
        end loop;

        -- Note: Current litedram ignores user_port0_wdata_valid. We
        -- must make sure to always have the data available at the
        -- output of the store queue when we send the write command.
        --
        -- Thankfully this is always the case with this design.
        --
        user_port0_wdata_valid <= storeq_rd_valid;
        storeq_rd_ready        <= user_port0_wdata_ready;

        if TRACE then
            if rising_edge(system_clk) then
                if req_op = OP_STORE_HIT then
                    report "Store hit to:" &
                        to_hstring(wb_req.adr(DRAM_ABITS+3 downto 0)) &
                        " data:" & to_hstring(req_wdata) &
                        " we:" & to_hstring(req_we) &
                        " V:" & std_ulogic'image(user_port0_cmd_ready);
                else
                    report "Store miss to:" &
                        to_hstring(wb_req.adr(DRAM_ABITS+3 downto 0)) &
                        " data:" & to_hstring(req_wdata) &
                        " we:" & to_hstring(req_we) &
                        " V:" & std_ulogic'image(user_port0_cmd_ready);
                end if;
                if storeq_wr_valid = '1' and storeq_wr_ready = '1' then
                    report "storeq push " & to_hstring(storeq_wr_data);
                end if;
                if storeq_rd_valid = '1' and storeq_rd_ready = '1' then
                    report "storeq pop " & to_hstring(storeq_rd_data);
                end if;
            end if;
        end if;
    end process;

    -- LiteDRAM command mux
    dram_commands: process(all)
    begin
        if req_op = OP_STORE_HIT or req_op = OP_STORE_MISS then
            -- For stores, forward signals directly. Only send command if
            -- the FIFO can accept a store.
            user_port0_cmd_addr  <= wb_req.adr(DRAM_ABITS+ROW_OFF_BITS-1 downto ROW_OFF_BITS);
            user_port0_cmd_we    <= '1';
            user_port0_cmd_valid <= storeq_wr_ready;
        else
            -- For loads, we route via a latch controlled by the refill machine
            user_port0_cmd_addr  <= refill_cmd_addr;
            user_port0_cmd_valid <= refill_cmd_valid;
            user_port0_cmd_we    <= '0';
        end if;

        -- Note: litedram  ignores this signal and assumes we are
        -- always ready to accept read data.
        user_port0_rdata_ready <= '1'; -- Always 1
    end process;

    -- LiteDRAM refill machine
    --
    -- This handles the cache line refills
    --
    refill_machine : process(system_clk)
        variable tagset      : cache_tags_set_t;
        variable cmds_done   : boolean;
        variable wait_qdrain : boolean;
    begin
        if rising_edge(system_clk) then
            -- On reset, clear all valid bits to force misses
            if system_reset = '1' then
                for i in index_t loop
                    cache_valids(i) <= (others => '0');
                end loop;
                state <= IDLE;
                refill_cmd_valid <= '0';
            else
                -- Main state machine
                case state is
                when IDLE =>
                    assert refill_cmd_valid = '0' report "refill cmd valid in IDLE state !"
                        severity failure;

                    -- Reset per-row valid flags, only used in WAIT_ACK
                    for i in 0 to ROW_PER_LINE - 1 loop
                        refill_rows_vlid(i) <= '0';
                    end loop;

                    -- If NO_LS_OVERLAP is set, disallow a load miss if the store
                    -- queue still has data in it.
                    wait_qdrain := false;
                    if NO_LS_OVERLAP then
                        wait_qdrain := storeq_rd_valid = '1';
                    end if;

                    -- We need to read a cache line
                    if req_op = OP_LOAD_MISS and not wait_qdrain then
                        -- Grab way to replace
                        refill_way <= to_integer(unsigned(plru_victim(req_index)));

                        -- Keep track of our index and way for subsequent stores
                        refill_index   <= req_index;
                        refill_row     <= get_row(req_laddr);
                        refill_end_row <= get_row_of_line(get_row(req_laddr)) - 1;

                        -- Prep for first DRAM read
                        --
                        -- XXX TODO: We could start a cycle early here by using
                        -- combo logic to generate the first command in
                        -- "dram_commands". In fact, we could make refill_cmd_addr
                        -- only contain the "counter" bits and wire it with the
                        -- other bits from req_laddr.
                        refill_cmd_addr    <= req_laddr(DRAM_ABITS+ROW_OFF_BITS-1 downto ROW_OFF_BITS);
                        refill_cmd_valid   <= '1';

                        if TRACE then
                            report "refill addr " & to_hstring(req_laddr);
                        end if;

                        -- Track that we had one request sent
                        state <= REFILL_CLR_TAG;
                    end if;

                when REFILL_CLR_TAG | REFILL_WAIT_ACK =>

                    -- Delayed tag clearing to help timing on PLRU output
                    if state = REFILL_CLR_TAG then
                        -- Force misses on that way while refilling that line
                        cache_valids(req_index)(refill_way) <= '0';

                        -- Store new tag in selected way
                        for i in 0 to NUM_WAYS-1 loop
                            if i = refill_way then
                                tagset := cache_tags(refill_index);
                                write_tag(i, tagset, req_tag);
                                cache_tags(refill_index) <= tagset;
                            end if;
                        end loop;
                        state <= REFILL_WAIT_ACK;
                    end if;

                    -- Commands are all sent if user_port0_cmd_valid is 0
                    cmds_done := refill_cmd_valid = '0';

                    -- If we are still sending requests, was one accepted ?
                    if user_port0_cmd_ready = '1' and not cmds_done then
                        -- That was the last word ? We are done sending. Clear
                        -- command valid and set cmds_done so we can handle an
                        -- eventual last ack on the same cycle.
                        --
                        if TRACE then
                            report "got refill cmd ack !";
                        end if;
                        if is_last_row_addr(refill_cmd_addr, refill_end_row) then
                            refill_cmd_valid <= '0';
                            cmds_done := true;
                            if TRACE then
                                report "all refill cmds done !";
                            end if;
                        else
                            -- Calculate the next row address
                            refill_cmd_addr <= next_row_addr(refill_cmd_addr);
                            if TRACE then
                                report "refill addr " &
                                    to_hstring(next_row_addr(refill_cmd_addr));
                            end if;
                        end if;
                    end if;

                    -- Incoming read data processing
                    if user_port0_rdata_valid = '1' then
                        if TRACE then
                            report "got refill data ack !";
                        end if;

                        -- Mark partial line valid
                        refill_rows_vlid(refill_row mod ROW_PER_LINE) <= '1';

                        -- Check for completion
                        if cmds_done and is_last_row(refill_row, refill_end_row) then
                            if TRACE then
                                report "all refill data done !";
                            end if;
                            -- Cache line is now valid
                            cache_valids(refill_index)(refill_way) <= '1';
                            -- We are done
                            state <= IDLE;
                        end if;

                        -- Increment store row counter
                        refill_row <= next_row(refill_row);
                    end if;
                end case;
            end if;
        end if;
    end process;

    may_trace: if LITEDRAM_TRACE generate
        component litedram_trace_stub
        end component;
    begin
        litedram_trace: litedram_trace_stub;
    end generate;
    
    litedram: litedram_core
        port map(
            clk => clk_in,
            rst => rst,
            pll_locked => pll_locked,
            ddram_a => ddram_a,
            ddram_ba => ddram_ba,
            ddram_ras_n => ddram_ras_n,
            ddram_cas_n => ddram_cas_n,
            ddram_we_n => ddram_we_n,
            ddram_cs_n => ddram_cs_n,
            ddram_dm => ddram_dm,
            ddram_dq => ddram_dq,
            ddram_dqs_p => ddram_dqs_p,
            ddram_dqs_n => ddram_dqs_n,
            ddram_clk_p => ddram_clk_p,
            ddram_clk_n => ddram_clk_n,
            ddram_cke => ddram_cke,
            ddram_odt => ddram_odt,
            ddram_reset_n => ddram_reset_n,
            init_done => init_done,
            init_error => init_error,
            user_clk => system_clk,
            user_rst => system_reset,
            wb_ctrl_adr => wb_ctrl_adr,
            wb_ctrl_dat_w => wb_ctrl_dat_w,
            wb_ctrl_dat_r => wb_ctrl_dat_r,
            wb_ctrl_sel => wb_ctrl_sel,
            wb_ctrl_cyc => wb_ctrl_cyc,
            wb_ctrl_stb => wb_ctrl_stb,
            wb_ctrl_ack => wb_ctrl_ack,
            wb_ctrl_we => wb_ctrl_we,
            wb_ctrl_cti => "000",
            wb_ctrl_bte => "00",
            wb_ctrl_err => open,
            user_port_native_0_cmd_valid => user_port0_cmd_valid,
            user_port_native_0_cmd_ready => user_port0_cmd_ready,
            user_port_native_0_cmd_we => user_port0_cmd_we,
            user_port_native_0_cmd_addr => user_port0_cmd_addr,
            user_port_native_0_wdata_valid => user_port0_wdata_valid,
            user_port_native_0_wdata_ready => user_port0_wdata_ready,
            user_port_native_0_wdata_we => user_port0_wdata_we,
            user_port_native_0_wdata_data => user_port0_wdata_data,
            user_port_native_0_rdata_valid => user_port0_rdata_valid,
            user_port_native_0_rdata_ready => user_port0_rdata_ready,
            user_port_native_0_rdata_data => user_port0_rdata_data
            );

end architecture behaviour;
