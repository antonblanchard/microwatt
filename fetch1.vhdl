library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils.all;
use work.common.all;

entity fetch1 is
    generic(
	RESET_ADDRESS     : std_logic_vector(63 downto 0) := (others => '0');
	ALT_RESET_ADDRESS : std_logic_vector(63 downto 0) := (others => '0');
        TLB_SIZE          : positive := 64;        -- L1 ITLB number of entries (direct mapped)
        HAS_BTC           : boolean := true
	);
    port(
	clk           : in std_ulogic;
	rst           : in std_ulogic;

	-- Control inputs:
	stall_in      : in std_ulogic;
	flush_in      : in std_ulogic;
        inval_btc     : in std_ulogic;
	stop_in       : in std_ulogic;
	alt_reset_in  : in std_ulogic;
        m_in          : in MmuToITLBType;

	-- redirect from writeback unit
	w_in          : in WritebackToFetch1Type;

        -- redirect from decode1
        d_in          : in Decode1ToFetch1Type;

	-- Request to icache
	i_out         : out Fetch1ToIcacheType;

        -- outputs to logger
        log_out       : out std_ulogic_vector(42 downto 0)
	);
end entity fetch1;

architecture behaviour of fetch1 is
    type reg_internal_t is record
        mode_32bit: std_ulogic;
        rd_is_niap4: std_ulogic;
        tlbcheck: std_ulogic;
        tlbstall: std_ulogic;
        next_nia: std_ulogic_vector(63 downto 0);
    end record;

    -- Mini effective to real translation cache
    type erat_t is record
        epn0: std_ulogic_vector(63 - MIN_LG_PGSZ downto 0);
        epn1: std_ulogic_vector(63 - MIN_LG_PGSZ downto 0);
        rpn0: std_ulogic_vector(REAL_ADDR_BITS - MIN_LG_PGSZ - 1 downto 0);
        rpn1: std_ulogic_vector(REAL_ADDR_BITS - MIN_LG_PGSZ - 1 downto 0);
        priv0: std_ulogic;
        priv1: std_ulogic;
        valid: std_ulogic_vector(1 downto 0);
        mru: std_ulogic;        -- '1' => entry 1 most recently used
    end record;

    signal r, r_next : Fetch1ToIcacheType;
    signal r_int, r_next_int : reg_internal_t;
    signal advance_nia : std_ulogic;
    signal log_nia : std_ulogic_vector(42 downto 0);

    signal erat : erat_t;
    signal erat_hit : std_ulogic;
    signal erat_sel : std_ulogic;

    constant BTC_ADDR_BITS : integer := 10;
    constant BTC_TAG_BITS : integer := 62 - BTC_ADDR_BITS;
    constant BTC_TARGET_BITS : integer := 62;
    constant BTC_SIZE : integer := 2 ** BTC_ADDR_BITS;
    constant BTC_WIDTH : integer := BTC_TAG_BITS + BTC_TARGET_BITS + 2;
    type btc_mem_type is array (0 to BTC_SIZE - 1) of std_ulogic_vector(BTC_WIDTH - 1 downto 0);

    signal btc_rd_addr : unsigned(BTC_ADDR_BITS - 1 downto 0);
    signal btc_rd_data : std_ulogic_vector(BTC_WIDTH - 1 downto 0) := (others => '0');
    signal btc_rd_valid : std_ulogic := '0';

    -- L1 ITLB.
    constant TLB_BITS : natural := log2(TLB_SIZE);
    constant TLB_EA_TAG_BITS : natural := 64 - (MIN_LG_PGSZ + TLB_BITS);
    constant TLB_PTE_BITS : natural := 64;

    subtype tlb_index_t is integer range 0 to TLB_SIZE - 1;
    type tlb_valids_t is array(tlb_index_t) of std_ulogic;
    subtype tlb_tag_t is std_ulogic_vector(TLB_EA_TAG_BITS - 1 downto 0);
    type tlb_tags_t is array(tlb_index_t) of tlb_tag_t;
    subtype tlb_pte_t is std_ulogic_vector(TLB_PTE_BITS - 1 downto 0);
    type tlb_ptes_t is array(tlb_index_t) of tlb_pte_t;

    signal itlb_valids : tlb_valids_t;
    signal itlb_tags : tlb_tags_t;
    signal itlb_ptes : tlb_ptes_t;

    -- Values read from above arrays on a clock edge
    signal itlb_valid : std_ulogic;
    signal itlb_ttag : tlb_tag_t;
    signal itlb_pte : tlb_pte_t;
    signal itlb_hit : std_ulogic;

    -- Simple hash for direct-mapped TLB index
    function hash_ea(addr: std_ulogic_vector(63 downto 0)) return std_ulogic_vector is
        variable hash : std_ulogic_vector(TLB_BITS - 1 downto 0);
    begin
        hash := addr(MIN_LG_PGSZ + TLB_BITS - 1 downto MIN_LG_PGSZ)
                xor addr(MIN_LG_PGSZ + 2 * TLB_BITS - 1 downto MIN_LG_PGSZ + TLB_BITS)
                xor addr(MIN_LG_PGSZ + 3 * TLB_BITS - 1 downto MIN_LG_PGSZ + 2 * TLB_BITS);
        return hash;
    end;

begin

    regs : process(clk)
    begin
	if rising_edge(clk) then
            log_nia <= r.nia(63) & r.nia(43 downto 2);
	    if r /= r_next and advance_nia = '1' then
		report "fetch1 rst:" & std_ulogic'image(rst) &
                    " IR:" & std_ulogic'image(r_next.virt_mode) &
                    " P:" & std_ulogic'image(r_next.priv_mode) &
                    " E:" & std_ulogic'image(r_next.big_endian) &
                    " 32:" & std_ulogic'image(r_next_int.mode_32bit) &
                    " I:" & std_ulogic'image(w_in.interrupt) &
		    " R:" & std_ulogic'image(w_in.redirect) & std_ulogic'image(d_in.redirect) &
		    " S:" & std_ulogic'image(stall_in) &
		    " T:" & std_ulogic'image(stop_in) &
		    " nia:" & to_hstring(r_next.nia) &
                    " req:" & std_ulogic'image(r_next.req) &
                    " FF:" & std_ulogic'image(r_next.fetch_fail);
	    end if;
            if advance_nia = '1' then
                r <= r_next;
                r_int <= r_next_int;
            end if;
            -- always send the up-to-date stop mark and req
            r.stop_mark <= stop_in;
            r.req <= r_next.req;
            r.fetch_fail <= r_next.fetch_fail;
            r_int.tlbcheck <= r_next_int.tlbcheck;
            r_int.tlbstall <= r_next_int.tlbstall;
	end if;
    end process;
    log_out <= log_nia;

    btc : if HAS_BTC generate
        signal btc_memory : btc_mem_type;
        attribute ram_style : string;
        attribute ram_style of btc_memory : signal is "block";

        signal btc_valids : std_ulogic_vector(BTC_SIZE - 1 downto 0);
        -- attribute ram_style of btc_valids : signal is "distributed";

        signal btc_wr : std_ulogic;
        signal btc_wr_data : std_ulogic_vector(BTC_WIDTH - 1 downto 0);
        signal btc_wr_addr : std_ulogic_vector(BTC_ADDR_BITS - 1 downto 0);
    begin
        btc_wr_data <= w_in.br_taken &
                       r.virt_mode &
                       w_in.br_nia(63 downto BTC_ADDR_BITS + 2) &
                       w_in.redirect_nia(63 downto 2);
        btc_wr_addr <= w_in.br_nia(BTC_ADDR_BITS + 1 downto 2);
        btc_wr <= w_in.br_last;

        btc_ram : process(clk)
            variable raddr : unsigned(BTC_ADDR_BITS - 1 downto 0);
        begin
            if rising_edge(clk) then
                if advance_nia = '1' then
		    if is_X(btc_rd_addr) then
			btc_rd_data <= (others => 'X');
			btc_rd_valid <= 'X';
		    else
			btc_rd_data <= btc_memory(to_integer(btc_rd_addr));
			btc_rd_valid <= btc_valids(to_integer(btc_rd_addr));
		    end if;
                end if;
                if btc_wr = '1' then
		    assert not is_X(btc_wr_addr) report "Writing to unknown address" severity FAILURE;
                    btc_memory(to_integer(unsigned(btc_wr_addr))) <= btc_wr_data;
                end if;
                if inval_btc = '1' or rst = '1' then
                    btc_valids <= (others => '0');
                elsif btc_wr = '1' then
		    assert not is_X(btc_wr_addr) report "Writing to unknown address" severity FAILURE;
                    btc_valids(to_integer(unsigned(btc_wr_addr))) <= '1';
                end if;
            end if;
        end process;
    end generate;

    erat_sync : process(clk)
    begin
        if rising_edge(clk) then
            if rst /= '0' or m_in.tlbie = '1' then
                erat.valid <= "00";
                erat.mru <= '0';
            else
                if erat_hit = '1' then
                    erat.mru <= erat_sel;
                end if;
                if m_in.tlbld = '1' then
                    erat.epn0 <= m_in.addr(63 downto MIN_LG_PGSZ);
                    erat.rpn0 <= m_in.pte(REAL_ADDR_BITS-1 downto MIN_LG_PGSZ);
                    erat.priv0 <= m_in.pte(3);
                    erat.valid(0) <= '1';
                    erat.valid(1) <= '0';
                    erat.mru <= '0';
                elsif r_int.tlbcheck = '1' and itlb_hit = '1' then
                    if erat.mru = '0' then
                        erat.epn1 <= r.nia(63 downto MIN_LG_PGSZ);
                        erat.rpn1 <= itlb_pte(REAL_ADDR_BITS-1 downto MIN_LG_PGSZ);
                        erat.priv1 <= itlb_pte(3);
                        erat.valid(1) <= '1';
                    else
                        erat.epn0 <= r.nia(63 downto MIN_LG_PGSZ);
                        erat.rpn0 <= itlb_pte(REAL_ADDR_BITS-1 downto MIN_LG_PGSZ);
                        erat.priv0 <= itlb_pte(3);
                        erat.valid(0) <= '1';
                    end if;
                    erat.mru <= not erat.mru;
                end if;
            end if;
        end if;
    end process;

    -- Read TLB using the NIA for the next cycle
    itlb_read : process(clk)
	variable tlb_req_index : std_ulogic_vector(TLB_BITS - 1 downto 0);
    begin
        if rising_edge(clk) then
            if advance_nia = '1' then
                tlb_req_index := hash_ea(r_next.nia);
                if is_X(tlb_req_index) then
                    itlb_pte <= (others => 'X');
                    itlb_ttag <= (others => 'X');
		    itlb_valid <= 'X';
                else
                    itlb_pte <= itlb_ptes(to_integer(unsigned(tlb_req_index)));
                    itlb_ttag <= itlb_tags(to_integer(unsigned(tlb_req_index)));
		    itlb_valid <= itlb_valids(to_integer(unsigned(tlb_req_index)));
                end if;
            end if;
        end if;
    end process;

    -- TLB hit detection
    itlb_lookup : process(all)
    begin
        itlb_hit <= '0';
        if itlb_ttag = r.nia(63 downto MIN_LG_PGSZ + TLB_BITS) then
            itlb_hit <= itlb_valid;
        end if;
    end process;

    -- iTLB update
    itlb_update: process(clk)
	variable wr_index : std_ulogic_vector(TLB_BITS - 1 downto 0);
    begin
        if rising_edge(clk) then
            wr_index := hash_ea(m_in.addr);
            if rst = '1' or (m_in.tlbie = '1' and m_in.doall = '1') then
                -- clear all valid bits
                for i in tlb_index_t loop
                    itlb_valids(i) <= '0';
                end loop;
            elsif m_in.tlbie = '1' then
		assert not is_X(wr_index) report "icache index invalid on write" severity FAILURE;
                -- clear entry regardless of hit or miss
                itlb_valids(to_integer(unsigned(wr_index))) <= '0';
            elsif m_in.tlbld = '1' then
		assert not is_X(wr_index) report "icache index invalid on write" severity FAILURE;
                itlb_tags(to_integer(unsigned(wr_index))) <= m_in.addr(63 downto MIN_LG_PGSZ + TLB_BITS);
                itlb_ptes(to_integer(unsigned(wr_index))) <= m_in.pte;
                itlb_valids(to_integer(unsigned(wr_index))) <= '1';
            end if;
            --ev.itlb_miss_resolved <= m_in.tlbld and not rst;
        end if;
    end process;

    comb : process(all)
	variable v : Fetch1ToIcacheType;
	variable v_int : reg_internal_t;
        variable next_nia : std_ulogic_vector(63 downto 0);
        variable m32 : std_ulogic;
        variable ehit, esel : std_ulogic;
        variable eaa_priv : std_ulogic;
    begin
	v := r;
	v_int := r_int;
        v.predicted := '0';
        v.pred_ntaken := '0';
        v.req := not stop_in;
        v_int.tlbstall := r_int.tlbcheck;
        v_int.tlbcheck := '0';

        if r_int.tlbcheck = '1' and itlb_hit = '0' then
            v.fetch_fail := '1';
        end if;

        -- Combinatorial computation of the CIA for the next cycle.
        -- Needs to be simple so the result can be used for RAM
        -- and TLB access in the icache.
        -- If we are stalled, this still advances, and the assumption
        -- is that it will not be used.
        m32 := r_int.mode_32bit;
        if w_in.redirect = '1' then
            next_nia := w_in.redirect_nia(63 downto 2) & "00";
            m32 := w_in.mode_32bit;
            v.virt_mode := w_in.virt_mode;
            v.priv_mode := w_in.priv_mode;
            v.big_endian := w_in.big_endian;
            v_int.mode_32bit := w_in.mode_32bit;
            v.fetch_fail := '0';
        elsif d_in.redirect = '1' then
            next_nia := d_in.redirect_nia(63 downto 2) & "00";
            v.fetch_fail := '0';
        elsif r_int.tlbstall = '1' then
            -- this case is needed so that the correct icache tags are read
            next_nia := r.nia;
        else
            next_nia := r_int.next_nia;
        end if;
        if m32 = '1' then
            next_nia(63 downto 32) := (others => '0');
        end if;
        v.nia := next_nia;

        v_int.next_nia := std_ulogic_vector(unsigned(next_nia) + 4);

        -- Use v_int.next_nia as the BTC read address before it gets possibly
        -- overridden with the reset or interrupt address or the predicted branch
        -- target address, in order to improve timing.  If it gets overridden then
        -- rd_is_niap4 gets cleared to indicate that the BTC data doesn't apply.
        btc_rd_addr <= unsigned(v_int.next_nia(BTC_ADDR_BITS + 1 downto 2));
        v_int.rd_is_niap4 := '1';

        -- If the last NIA value went down with a stop mark, it didn't get
        -- executed, and hence we shouldn't increment NIA.
        advance_nia <= rst or w_in.interrupt or w_in.redirect or d_in.redirect or
                       (not r.stop_mark and not (r.req and stall_in));
        -- reduce metavalue warnings in sim
        if is_X(rst) then
            advance_nia <= '1';
        end if;

        -- Translate next_nia to real if possible, otherwise we have to stall
        -- and look up the TLB.
        ehit := '0';
        esel := '0';
        eaa_priv := '1';
        if next_nia(63 downto MIN_LG_PGSZ) = erat.epn1 and erat.valid(1) = '1' then
            ehit := '1';
            esel := '1';
        end if;
        if next_nia(63 downto MIN_LG_PGSZ) = erat.epn0 and erat.valid(0) = '1' then
            ehit := '1';
        end if;
        if v.virt_mode = '0' then
            v.rpn := v.nia(REAL_ADDR_BITS - 1 downto MIN_LG_PGSZ);
            eaa_priv := '1';
        elsif esel = '1' then
            v.rpn := erat.rpn1;
            eaa_priv := erat.priv1;
        else
            v.rpn := erat.rpn0;
            eaa_priv := erat.priv0;
        end if;
        if advance_nia = '1' and ehit = '0' and v.virt_mode = '1' and
                r_int.tlbcheck = '0' and v.fetch_fail = '0' then
            v_int.tlbstall := '1';
            v_int.tlbcheck := '1';
        end if;
        if ehit = '1' or v.virt_mode = '0' then
            if eaa_priv = '1' and v.priv_mode = '0' then
                v.fetch_fail := '1';
            else
                v.fetch_fail := '0';
            end if;
        end if;
        erat_hit <= ehit and advance_nia;
        erat_sel <= esel;

	if rst /= '0' then
	    if alt_reset_in = '1' then
		v_int.next_nia :=  ALT_RESET_ADDRESS;
	    else
		v_int.next_nia :=  RESET_ADDRESS;
	    end if;
        elsif w_in.interrupt = '1' then
            v_int.next_nia := w_in.intr_vec(63 downto 2) & "00";
        end if;
	if rst /= '0' or w_in.interrupt = '1' then
            v.req := '0';
            v.virt_mode := w_in.alt_intr and not rst;
            v.priv_mode := '1';
            v.big_endian := '0';
            v_int.mode_32bit := '0';
            v_int.rd_is_niap4 := '0';
            v_int.tlbstall := '0';
            v_int.tlbcheck := '0';
            v.fetch_fail := '0';
        end if;
        if v.fetch_fail = '1' then
            v_int.tlbstall := '1';
        end if;
        if v_int.tlbstall = '1' then
            v.req := '0';
        end if;

        -- If there is a valid entry in the BTC which corresponds to the next instruction,
        -- use that to predict the address of the instruction after that.
        -- (w_in.redirect = '0' and d_in.redirect = '0' and r_int.tlbstall = '0')
        -- implies v.nia = r_int.next_nia.
        -- r_int.rd_is_niap4 implies r_int.next_nia is the address used to read the BTC.
	if v.req = '1' and w_in.redirect = '0' and d_in.redirect = '0' and r_int.tlbstall = '0' and 
                btc_rd_valid = '1' and r_int.rd_is_niap4 = '1' and
                btc_rd_data(BTC_WIDTH - 2) = r.virt_mode and
                btc_rd_data(BTC_WIDTH - 3 downto BTC_TARGET_BITS)
                    = r_int.next_nia(BTC_TAG_BITS + BTC_ADDR_BITS + 1 downto BTC_ADDR_BITS + 2) then
            v.predicted := btc_rd_data(BTC_WIDTH - 1);
            v.pred_ntaken := not btc_rd_data(BTC_WIDTH - 1);
            if btc_rd_data(BTC_WIDTH - 1) = '1' then
                v_int.next_nia := btc_rd_data(BTC_TARGET_BITS - 1 downto 0) & "00";
                v_int.rd_is_niap4 := '0';
            end if;
        end if;

	r_next <= v;
	r_next_int <= v_int;

	-- Update outputs to the icache
	i_out <= r;
        i_out.next_nia <= next_nia;
        i_out.next_rpn <= v.rpn;

    end process;

end architecture behaviour;
