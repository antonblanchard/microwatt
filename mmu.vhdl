library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

-- Radix MMU
-- Supports 4-level trees as in arch 3.0B, but not the two-step translation for
-- guests under a hypervisor (i.e. there is no gRA -> hRA translation).

entity mmu is
    port (
        clk   : in std_ulogic;
        rst   : in std_ulogic;

        l_in  : in Loadstore1ToMmuType;
        l_out : out MmuToLoadstore1Type;

        d_out : out MmuToDcacheType;
        d_in  : in DcacheToMmuType;

        i_out : out MmuToITLBType
        );
end mmu;

architecture behave of mmu is

    type state_t is (IDLE,
                     DO_TLBIE,
                     PART_TBL_READ,
                     PART_TBL_WAIT,
                     PART_TBL_DONE,
                     PROC_TBL_READ,
                     PROC_TBL_WAIT,
                     SEGMENT_CHECK,
                     TLBWAIT,
                     RADIX_LOOKUP,
                     RADIX_READ_WAIT,
                     RADIX_LOAD_TLB,
                     RADIX_FINISH
                     );

    type reg_stage_t is record
        -- latched request from loadstore1
        valid     : std_ulogic;
        iside     : std_ulogic;
        store     : std_ulogic;
        priv      : std_ulogic;
        addr      : std_ulogic_vector(63 downto 0);
        inval_all : std_ulogic;
        -- config SPRs
        ptcr      : std_ulogic_vector(63 downto 0);
        pid       : std_ulogic_vector(11 downto 0);
        -- internal state
        state     : state_t;
        done      : std_ulogic;
        err       : std_ulogic;
        prtbl     : std_ulogic_vector(63 downto 0);
        ptb_valid : std_ulogic;
        pgtbl0    : std_ulogic_vector(63 downto 0);
        pt0_valid : std_ulogic;
        pgtbl3    : std_ulogic_vector(63 downto 0);
        pt3_valid : std_ulogic;
        shift     : unsigned(5 downto 0);
        mask_size : unsigned(4 downto 0);
        pgbase    : std_ulogic_vector(55 downto 0);
        pde       : std_ulogic_vector(63 downto 0);
        invalid   : std_ulogic;
        badtree   : std_ulogic;
        segerror  : std_ulogic;
        perm_err  : std_ulogic;
        rc_error  : std_ulogic;
        wr_tlbram : std_ulogic;
        tlbie_req : std_ulogic;
        is_mtspr  : std_ulogic;
    end record;

    signal r, rin : reg_stage_t;

    signal addrsh  : std_ulogic_vector(15 downto 0);
    signal mask    : std_ulogic_vector(15 downto 0);
    signal finalmask : std_ulogic_vector(43 downto 0);

    -- Small page (4k) TLB, 256 entries, 4-way set associative.
    -- This is implemented using a 512 x 64 bit RAM, divided
    -- into 64 blocks of 8 words, each block containing a set of
    -- 4 entries.
    -- In each block, word 0 contains a valid bit, 12-bit PID,
    -- and 3 bits of address tag for each of the 4 entries.
    -- (This allows us to do invalidate-all or invalidate-by-PID
    -- in 64 cycles instead of 256.)
    -- Word 1 contains 32 bits of address tag for entries 0 and 1,
    -- and word 2 contains the same for entries 2 and 3.
    -- Words 4 to 7 contain the PTE value for entries 0 to 3,
    -- Word 3 is currently unused.
    -- EAs are expected to be in a 4PB (52-bit) space per PID
    -- (ignoring the quadrant bits); anything outside that
    -- doesn't get cached.
    constant TLB_WIDTH : natural := 64;
    constant TLB_DEPTH : natural := 256;
    constant TLB_HASH_BITS : natural := 6;
    constant TLB_ADDR_BITS : natural := TLB_HASH_BITS + 3;
    subtype tlb_word_t is std_ulogic_vector(TLB_WIDTH - 1 downto 0);
    type tlb_t is array(0 to 2 * TLB_DEPTH - 1) of tlb_word_t;
    signal tlb : tlb_t;
    subtype tlb_index_t is integer range 0 to 2**TLB_HASH_BITS - 1;

    signal tlb_doread  : std_ulogic;
    signal tlb_rdren   : std_ulogic;
    signal tlb_rdaddr  : std_ulogic_vector(TLB_ADDR_BITS - 1 downto 0);
    signal tlb_rddata  : std_ulogic_vector(TLB_WIDTH - 1 downto 0);
    signal tlb_rdreg   : std_ulogic_vector(TLB_WIDTH - 1 downto 0);
    signal tlb_wren    : std_ulogic_vector(3 downto 0);
    signal tlb_wraddr  : std_ulogic_vector(TLB_ADDR_BITS - 1 downto 0);
    signal tlb_wrdata  : std_ulogic_vector(TLB_WIDTH - 1 downto 0);

    type tlb_state_t is (IDLE,
                         SEARCH1, SEARCH2, SEARCH3, SEARCH4,
                         RDPTE,
                         WAITW, WRPTE1, WRPTE2,
                         INVAL1, INVAL2);
    type mmu_tlb_reg_t is record
        state       : tlb_state_t;
        addr        : std_ulogic_vector(39 downto 0);
        bad_ea      : std_ulogic;
        pid         : std_ulogic_vector(11 downto 0);
        hash_4k     : std_ulogic_vector(TLB_HASH_BITS - 1 downto 0);
        is_tlbie    : std_ulogic;
        may_hit     : std_ulogic_vector(3 downto 0);
        hit         : std_ulogic;
        miss        : std_ulogic;
        hit_way     : std_ulogic_vector(1 downto 0);
        repl_way    : std_ulogic_vector(1 downto 0);
        update_plru : std_ulogic;
        tlbie_done  : std_ulogic;
        inval_all   : std_ulogic;
        wr_hash     : std_ulogic_vector(TLB_HASH_BITS - 1 downto 0);
    end record;
    constant mmu_tlb_reg_init : mmu_tlb_reg_t := (
        state   => IDLE, addr => 40x"0", pid => 12x"0",
        hash_4k => (others => '0'), wr_hash => (others => '0'),
        may_hit => "0000", hit_way => "00", repl_way => "00",
        others  => '0');
    signal tr, trin : mmu_tlb_reg_t;

    -- TLB PLRU array
    type tlb_plru_array is array(tlb_index_t) of std_ulogic_vector(2 downto 0);
    signal tlb_plru_ram    : tlb_plru_array;
    signal tlb_plru_cur    : std_ulogic_vector(2 downto 0);
    signal tlb_plru_upd    : std_ulogic_vector(2 downto 0);
    signal tlb_plru_victim : std_ulogic_vector(1 downto 0);

    function addr_hash_4k(ea: std_ulogic_vector(63 downto 0);
                          pid: std_ulogic_vector(11 downto 0)) return std_ulogic_vector is
        variable h : std_ulogic_vector(TLB_HASH_BITS - 1 downto 0);
    begin
        -- Make this a bit different to the hashes used in the dcache and icache
        h := ea(17 downto 12) xor ea(23 downto 18) xor ea(51 downto 46) xor
             pid(5 downto 0);
        return h;
    end;

    function find_first_zero(x: std_ulogic_vector(3 downto 0)) return std_ulogic_vector is
    begin
        for i in 0 to 2 loop
            if x(i) = '0' then
                return std_ulogic_vector(to_unsigned(i, 2));
            end if;
        end loop;
        return "11";
    end;

    function check_perm(pte: std_ulogic_vector(63 downto 0); priv: std_ulogic;
                        iside: std_ulogic; store: std_ulogic) return std_ulogic is
        variable ok: std_ulogic;
    begin
        ok := '0';
        if priv = '1' or pte(3) = '0' then
            if iside = '0' then
                ok := pte(1) or (pte(2) and not store);
            else
                -- no IAMR, so no KUEP support for now
                -- deny execute permission if cache inhibited
                ok := pte(0) and not pte(5);
            end if;
        end if;
        return ok;
    end;

begin
    -- Synchronous reads and writes to TLB array
    mmu_tlb_ram: process(clk)
    begin
        if rising_edge(clk) then
            if tlb_rdren = '1' then
                tlb_rdreg <= tlb_rddata;
            end if;
            if tlb_doread = '1' then
                tlb_rddata <= tlb(to_integer(unsigned(tlb_rdaddr)));
            end if;
            if tlb_wren /= "0000" then
                for i in 0 to 3 loop
                    if tlb_wren(i) = '1' then
                        tlb(to_integer(unsigned(tlb_wraddr)))(i*16 + 15 downto i*16) <=
                            tlb_wrdata(i*16 + 15 downto i*16);
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- TLB PLRU
    tlb_plru : entity work.plrufn
        generic map (
            BITS => 2
            )
        port map (
            acc      => tr.hit_way,
            tree_in  => tlb_plru_cur,
            tree_out => tlb_plru_upd,
            lru      => tlb_plru_victim
            );

    process(all)
    begin
        if is_X(tr.hash_4k) then
            tlb_plru_cur <= (others => 'X');
        else
            tlb_plru_cur <= tlb_plru_ram(to_integer(unsigned(tr.hash_4k)));
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if tr.update_plru = '1' then
                assert not is_X(tr.hash_4k) severity failure;
                tlb_plru_ram(to_integer(unsigned(tr.hash_4k))) <= tlb_plru_upd;
            end if;
        end if;
    end process;

    -- State machine for doing TLB searches, updates and invalidations
    mmu_tlb_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                tr <= mmu_tlb_reg_init;
            else
                tr <= trin;
            end if;
        end if;
    end process;

    mmu_tlb_1: process(all)
        variable tv : mmu_tlb_reg_t;
        variable isf : std_ulogic_vector(1 downto 0);
        variable is_hit : std_ulogic;
        variable valids : std_ulogic_vector(3 downto 0);
        variable idx : std_ulogic_vector(2 downto 0);
        variable wdat : std_ulogic_vector(15 downto 0);
    begin
        tv := tr;
        tlb_doread <= '0';
        tlb_rdren <= '0';
        tlb_wren <= "0000";
        tlb_wrdata <= (others => '0');
        is_hit := '0';
        idx := "000";
        tv.update_plru := '0';
        case tr.state is
            when IDLE =>
                tv.addr := l_in.addr(51 downto 12);
                tv.pid := (others => '0');
                if l_in.tlbie = '1' then
                    -- PID for tlbie comes from RS
                    tv.pid := l_in.rs(43 downto 32);
                elsif l_in.addr(63) = '0' then
                    -- we currently only implement quadrants 0 and 3
                    tv.pid := r.pid;
                end if;
                tv.bad_ea := (or (l_in.addr(61 downto 52)) or (l_in.addr(63) xor l_in.addr(62)))
                             and not l_in.tlbie;
                tv.hash_4k := addr_hash_4k(l_in.addr, tv.pid);
                tv.wr_hash := tv.hash_4k;
                tv.is_tlbie := l_in.tlbie;
                if l_in.valid = '1' then
                    tv.hit := '0';
                    tv.miss := '0';
                    tv.tlbie_done := '0';
                    tv.inval_all := '0';
                    if l_in.tlbie = '1' then
                        -- decode what type of tlbie this is
                        isf := l_in.addr(11 downto 10);
                        if l_in.slbia = '1' or l_in.ric(0) = '1' then
                            -- no effect on this TLB (flushes L1 TLBs below)
                            tv.tlbie_done := '1';
                        elsif isf(1) = '1' then
                            -- invalidate all
                            tv.inval_all := '1';
                            tv.wr_hash := (others => '0');
                            tv.state := INVAL2;
                        elsif isf(0) = '1' then
                            -- invalidate PID
                            tv.hash_4k := (others => '0');
                            tlb_doread <= '1';
                            tv.state := INVAL1;
                        else
                            -- invalidate single page
                            tlb_doread <= '1';
                            tv.state := SEARCH1;
                        end if;
                    else
                        tlb_doread <= '1';
                        tv.state := SEARCH1;
                    end if;
                end if;
            when SEARCH1 =>
                -- next read word 1 of group
                idx := "001";
                tlb_doread <= '1';
                tlb_rdren <= '1';
                if tr.bad_ea = '0' then
                    tv.state := SEARCH2;
                else
                    tv.miss := '1';
                    tv.tlbie_done := tr.is_tlbie;
                    tv.state := IDLE;
                end if;
            when SEARCH2 =>
                -- tlb_rdreg contains word 0, check for hits/misses
                valids := "0000";
                tv.may_hit := "0000";
                for i in 0 to 3 loop
                    valids(i) := tlb_rdreg(i*16 + 15);
                    if tlb_rdreg(i*16 + 15) = '1' and
                        tlb_rdreg(i*16 + 11 downto i*16) = tr.pid and
                        tlb_rdreg(i*16 + 13 downto i*16 + 12) = tr.addr(7 downto 6) then
                        tv.may_hit(i) := '1';
                    end if;
                end loop;
                -- work out which way to replace in case of a miss
                if valids = "1111" then
                    tv.repl_way := tlb_plru_victim;
                else
                    tv.repl_way := find_first_zero(valids);
                end if;
                -- next read word 2 of group
                idx := "010";
                if tv.may_hit = "0000" then
                    tv.miss := '1';
                    if tr.is_tlbie = '0' then
                        tv.state := WAITW;
                    else
                        tv.tlbie_done := '1';
                        tv.state := IDLE;
                    end if;
                else
                    tlb_doread <= '1';
                    tlb_rdren <= '1';
                    tv.state := SEARCH3;
                end if;
            when SEARCH3 =>
                -- tlb_rdreg contains word 1
                for i in 0 to 1 loop
                    if tr.may_hit(i) = '1' then
                        if tlb_rdreg(i*32 + 31 downto i*32) /= tr.addr(39 downto 8) then
                            tv.may_hit(i) := '0';
                        end if;
                    end if;
                end loop;
                if tv.may_hit(0) = '1' then
                    tv.hit_way := "00";
                    is_hit := '1';
                elsif tv.may_hit(1) = '1' then
                    tv.hit_way := "01";
                    is_hit := '1';
                end if;
                if tr.is_tlbie = '1' then
                    tlb_rdren <= '1';
                    tv.state := SEARCH4;
                elsif is_hit = '1' then
                    tv.state := RDPTE;
                    idx := '1' & tv.hit_way;
                    tlb_doread <= '1';
                elsif tv.may_hit = "0000" then
                    tv.miss := '1';
                    tv.state := WAITW;
                else
                    tlb_rdren <= '1';
                    tv.state := SEARCH4;
                end if;
            when SEARCH4 =>
                -- tlb_rdreg contains word 2
                for i in 0 to 1 loop
                    if tr.may_hit(i+2) = '1' then
                        if tlb_rdreg(i*32 + 31 downto i*32) /= tr.addr(39 downto 8) then
                            tv.may_hit(i+2) := '0';
                        end if;
                    end if;
                end loop;
                if tr.is_tlbie = '1' then
                    -- write zeroes to word 0 where hit(s) detected
                    tlb_wren <= tv.may_hit;
                    tv.tlbie_done := '1';
                    tv.state := IDLE;
                elsif tv.may_hit = "0000" then
                    tv.miss := '1';
                    tv.state := WAITW;
                else
                    tv.hit_way := '1' & not tv.may_hit(2);
                    idx := '1' & tv.hit_way;
                    tlb_doread <= '1';
                    tv.state := RDPTE;
                end if;
            when RDPTE =>
                tv.repl_way := tr.hit_way;
                tlb_rdren <= '1';
                tv.hit := '1';
                tv.update_plru := '1';
                tv.state := WAITW;
            when WAITW =>
                wdat := "10" & tr.addr(7 downto 6) & tr.pid;
                tlb_wrdata <= wdat & wdat & wdat & wdat;
                if r.wr_tlbram = '1' then
                    -- write one 16b section of word 0
                    tlb_wren(to_integer(unsigned(tr.repl_way))) <= '1';
                    tv.hit_way := tv.repl_way;
                    tv.update_plru := '1';
                    tv.state := WRPTE1;
                elsif r.done = '1' or r.err = '1' then
                    tv.state := IDLE;
                end if;
            when WRPTE1 =>
                tlb_wrdata <= tr.addr(39 downto 8) & tr.addr(39 downto 8);
                if tr.repl_way(0) = '1' then
                    tlb_wren <= "1100";
                else
                    tlb_wren <= "0011";
                end if;
                idx := '0' & tr.repl_way(1) & not tr.repl_way(1);
                tv.state := WRPTE2;
            when WRPTE2 =>
                tlb_wrdata <= r.pde;
                tlb_wren <= "1111";
                idx := '1' & tr.repl_way;
                tv.state := IDLE;
            when INVAL1 =>
                tv.hash_4k := 6x"01";
                tv.wr_hash := (others => '0');
                tlb_doread <= '1';
                tlb_rdren <= '1';
                tv.state := INVAL2;
            when INVAL2 =>
                if tr.inval_all = '1' then
                    tlb_wren <= "1111";
                else
                    valids := "0000";
                    for i in 0 to 3 loop
                        if tlb_rdreg(i*16 + 15) = '1' and
                            tlb_rdreg(i*16 + 11 downto i*16) = tr.pid then
                            valids(i) := '1';
                        end if;
                    end loop;
                    tlb_wren <= valids;
                    tlb_doread <= '1';
                    tlb_rdren <= '1';
                end if;
                tv.wr_hash := std_ulogic_vector(unsigned(tr.wr_hash) + 1);
                tv.hash_4k := std_ulogic_vector(unsigned(tv.hash_4k) + 1);
                if tr.wr_hash = 6x"3f" then
                    tv.tlbie_done := '1';
                    tv.state := IDLE;
                end if;
        end case;
        tlb_rdaddr <= tv.hash_4k & idx;
        tlb_wraddr <= tr.wr_hash & idx;
        trin <= tv;
    end process;

    -- Multiplex internal SPR values back to loadstore1, selected
    -- by l_in.sprnf.
    l_out.sprval <= r.ptcr when l_in.sprnf = '1' else x"0000000000000" & r.pid;

    mmu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.valid <= '0';
                r.ptb_valid <= '0';
                r.pt0_valid <= '0';
                r.pt3_valid <= '0';
                r.ptcr <= (others => '0');
                r.pid <= (others => '0');
                r.wr_tlbram <= '0';
            else
                if rin.valid = '1' then
                    report "MMU got tlb miss for " & to_hstring(rin.addr);
                end if;
                if l_out.done = '1' then
                    report "MMU completing op without error";
                end if;
                if l_out.err = '1' then
                    report "MMU completing op with err invalid=" & std_ulogic'image(l_out.invalid) &
                        " badtree=" & std_ulogic'image(l_out.badtree);
                end if;
                if rin.state = RADIX_LOOKUP then
                    report "radix lookup shift=" & integer'image(to_integer(rin.shift)) &
                        " msize=" & integer'image(to_integer(rin.mask_size));
                end if;
                if r.state = RADIX_LOOKUP then
                    report "send load addr=" & to_hstring(d_out.addr) &
                        " addrsh=" & to_hstring(addrsh) & " mask=" & to_hstring(mask);
                end if;
                r <= rin;
            end if;
        end if;
    end process;

    -- Shift address bits 61--12 right by 0--47 bits and
    -- supply the least significant 16 bits of the result.
    addrshifter: process(all)
        variable sh1 : std_ulogic_vector(30 downto 0);
        variable sh2 : std_ulogic_vector(18 downto 0);
        variable result : std_ulogic_vector(15 downto 0);
    begin
        case r.shift(5 downto 4) is
            when "00" =>
                sh1 := r.addr(42 downto 12);
            when "01" =>
                sh1 := r.addr(58 downto 28);
            when others =>
                sh1 := "0000000000000" & r.addr(61 downto 44);
        end case;
        case r.shift(3 downto 2) is
            when "00" =>
                sh2 := sh1(18 downto 0);
            when "01" =>
                sh2 := sh1(22 downto 4);
            when "10" =>
                sh2 := sh1(26 downto 8);
            when others =>
                sh2 := sh1(30 downto 12);
        end case;
        case r.shift(1 downto 0) is
            when "00" =>
                result := sh2(15 downto 0);
            when "01" =>
                result := sh2(16 downto 1);
            when "10" =>
                result := sh2(17 downto 2);
            when others =>
                result := sh2(18 downto 3);
        end case;
        addrsh <= result;
    end process;

    -- generate mask for extracting address fields for PTE address generation
    addrmaskgen: process(all)
        variable m : std_ulogic_vector(15 downto 0);
    begin
        -- mask_count has to be >= 5
        m := x"001f";
        if is_X(r.mask_size) then
            m := (others => 'X');
        else
            for i in 5 to 15 loop
                if i < to_integer(r.mask_size) then
                    m(i) := '1';
                end if;
            end loop;
        end if;
        mask <= m;
    end process;

    -- generate mask for extracting address bits to go in TLB entry
    -- in order to support pages > 4kB
    finalmaskgen: process(all)
        variable m : std_ulogic_vector(43 downto 0);
    begin
        m := (others => '0');
        for i in 0 to 43 loop
            if is_X(r.shift) then
                m(i) := 'X';
            elsif i < to_integer(r.shift) then
                m(i) := '1';
            end if;
        end loop;
        finalmask <= m;
    end process;

    mmu_1: process(all)
        variable v : reg_stage_t;
        variable dcreq : std_ulogic;
        variable tlb_load : std_ulogic;
        variable ptbl_rd : std_ulogic;
        variable prtbl_rd : std_ulogic;
        variable pt_valid : std_ulogic;
        variable effpid : std_ulogic_vector(11 downto 0);
        variable prtable_addr : std_ulogic_vector(63 downto 0);
        variable six : std_ulogic_vector(5 downto 0);
        variable rts : unsigned(5 downto 0);
        variable mbits : unsigned(5 downto 0);
        variable pgtable_addr : std_ulogic_vector(63 downto 0);
        variable pte : std_ulogic_vector(63 downto 0);
        variable tlb_data : std_ulogic_vector(63 downto 0);
        variable nonzero : std_ulogic;
        variable pgtbl : std_ulogic_vector(63 downto 0);
        variable perm_ok : std_ulogic;
        variable rc_ok : std_ulogic;
        variable addr : std_ulogic_vector(63 downto 0);
        variable data : std_ulogic_vector(63 downto 0);
    begin
        v := r;
        v.valid := '0';
        dcreq := '0';
        v.done := '0';
        v.err := '0';
        v.invalid := '0';
        v.badtree := '0';
        v.segerror := '0';
        v.perm_err := '0';
        v.rc_error := '0';
        tlb_load := '0';
        v.tlbie_req := '0';
        v.inval_all := '0';
        ptbl_rd := '0';
        prtbl_rd := '0';

        -- Radix tree data structures in memory are big-endian,
        -- so we need to byte-swap them
        for i in 0 to 7 loop
            data(i * 8 + 7 downto i * 8) := d_in.data((7 - i) * 8 + 7 downto (7 - i) * 8);
        end loop;

        case r.state is
        when IDLE =>
            if l_in.addr(63) = '0' then
                pgtbl := r.pgtbl0;
                pt_valid := r.pt0_valid;
            else
                pgtbl := r.pgtbl3;
                pt_valid := r.pt3_valid;
            end if;
            -- rts == radix tree size, # address bits being translated
            six := '0' & pgtbl(62 downto 61) & pgtbl(7 downto 5);
            rts := unsigned(six);
            -- mbits == # address bits to index top level of tree
            mbits := unsigned('0' & pgtbl(4 downto 0));
            -- set v.shift to rts so that we can use finalmask for the segment check
            v.shift := rts;
            v.mask_size := mbits(4 downto 0);
            v.pgbase := pgtbl(55 downto 8) & x"00";

            if l_in.valid = '1' then
                v.addr := l_in.addr;
                v.iside := l_in.iside;
                v.store := not (l_in.load or l_in.iside);
                v.priv := l_in.priv;
                if l_in.tlbie = '1' then
                    -- Invalidate all iTLB/dTLB entries for tlbie with
                    -- RB[IS] != 0 or RB[AP] != 0, or for slbia
                    v.inval_all := l_in.slbia or l_in.addr(11) or l_in.addr(10) or
                                   l_in.addr(7) or l_in.addr(6) or l_in.addr(5);
                    -- RIC=2 or 3 flushes process table caches.
                    if l_in.ric(1) = '1' then
                        v.pt0_valid := '0';
                        v.pt3_valid := '0';
                        v.ptb_valid := '0';
                    end if;
                    v.tlbie_req := '1';
                    v.state := DO_TLBIE;
                else
                    v.valid := '1';
                    if r.ptb_valid = '0' then
                        -- need to fetch process table base from partition table
                        v.state := PART_TBL_READ;
                    elsif pt_valid = '0' then
                        -- need to fetch process table entry
                        -- set v.shift so we can use finalmask for generating
                        -- the process table entry address
                        v.shift := unsigned('0' & r.prtbl(4 downto 0));
                        v.state := PROC_TBL_READ;
                    elsif mbits = 0 then
                        -- Use RPDS = 0 to disable radix tree walks
                        v.state := RADIX_FINISH;
                        v.invalid := '1';
                    else
                        v.state := SEGMENT_CHECK;
                    end if;
                end if;
            end if;
            v.is_mtspr := l_in.mtspr;
            if l_in.mtspr = '1' then
                -- Move to PID needs to invalidate L1 TLBs and cached
                -- pgtbl0 value.  Move to PTCR does that plus
                -- invalidating the cached pgtbl3 and prtbl values as well.
                if l_in.sprnt = '0' then
                    v.pid := l_in.rs(11 downto 0);
                else
                    v.ptcr := l_in.rs;
                    v.pt3_valid := '0';
                    v.ptb_valid := '0';
                end if;
                v.pt0_valid := '0';
                v.inval_all := '1';
                v.tlbie_req := '1';
                v.state := DO_TLBIE;
            end if;

        when DO_TLBIE =>
            if r.is_mtspr = '1' or tr.tlbie_done = '1' then
                v.state := RADIX_FINISH;
            end if;

        when PART_TBL_READ =>
            dcreq := '1';
            ptbl_rd := '1';
            v.state := PART_TBL_WAIT;

        when PART_TBL_WAIT =>
            if d_in.done = '1' then
                v.prtbl := data;
                v.ptb_valid := '1';
                v.state := PART_TBL_DONE;
            end if;

        when PART_TBL_DONE =>
            v.shift := unsigned('0' & r.prtbl(4 downto 0));
            v.state := PROC_TBL_READ;

        when PROC_TBL_READ =>
            dcreq := '1';
            prtbl_rd := '1';
            v.state := PROC_TBL_WAIT;

        when PROC_TBL_WAIT =>
            if d_in.done = '1' then
                if r.addr(63) = '1' then
                    v.pgtbl3 := data;
                    v.pt3_valid := '1';
                else
                    v.pgtbl0 := data;
                    v.pt0_valid := '1';
                end if;
                -- rts == radix tree size, # address bits being translated
                six := '0' & data(62 downto 61) & data(7 downto 5);
                rts := unsigned(six);
                -- mbits == # address bits to index top level of tree
                mbits := unsigned('0' & data(4 downto 0));
                -- set v.shift to rts so that we can use finalmask for the segment check
                v.shift := rts;
                v.mask_size := mbits(4 downto 0);
                v.pgbase := data(55 downto 8) & x"00";
                if mbits = 0 then
                    v.state := RADIX_FINISH;
                    v.invalid := '1';
                else
                    v.state := SEGMENT_CHECK;
                end if;
            end if;
            if d_in.err = '1' then
                v.state := RADIX_FINISH;
                v.badtree := '1';
            end if;

        when SEGMENT_CHECK =>
            mbits := '0' & r.mask_size;
            v.shift := r.shift + (31 - 12) - mbits;
            nonzero := or(r.addr(61 downto 31) and not finalmask(30 downto 0));
            if r.addr(63) /= r.addr(62) or nonzero = '1' then
                v.state := RADIX_FINISH;
                v.segerror := '1';
            elsif mbits < 5 or mbits > 16 or mbits > (r.shift + (31 - 12)) then
                v.state := RADIX_FINISH;
                v.badtree := '1';
            elsif tr.miss = '1' then
                v.state := RADIX_LOOKUP;
            else
                v.state := TLBWAIT;
            end if;

        when TLBWAIT =>
            v.pde := tlb_rdreg;
            if tr.hit = '1' then
                -- PTE from the TLB entry is in tlb_rdreg
                -- Check permissions; if the access is not permitted,
                -- reread the PTE from memory to verify, because increasing
                -- permission on a PTE doesn't require tlbie.
                -- Note that R must be set in the PTE, otherwise it
                -- wouldn't have been written to the TLB.
                perm_ok := check_perm(tlb_rdreg, r.priv, r.iside, r.store);
                rc_ok := tlb_rdreg(7) or not r.store;
                if perm_ok = '1' and rc_ok = '1' then
                    v.shift := to_unsigned(0, 6);
                    v.state := RADIX_LOAD_TLB;
                else
                    v.state := RADIX_LOOKUP;
                end if;
            elsif tr.miss = '1' then
                v.state := RADIX_LOOKUP;
            end if;

        when RADIX_LOOKUP =>
            dcreq := '1';
            v.state := RADIX_READ_WAIT;

        when RADIX_READ_WAIT =>
            if d_in.done = '1' then
                v.pde := data;
                -- test valid bit
                if data(63) = '1' then
                    -- test leaf bit
                    if data(62) = '1' then
                        -- check permissions and RC bits
                        perm_ok := check_perm(data, r.priv, r.iside, r.store);
                        rc_ok := data(8) and (data(7) or not r.store);
                        if perm_ok = '1' and rc_ok = '1' then
                            v.state := RADIX_LOAD_TLB;
                            -- only cache 4k PTEs in our TLB, and only if the
                            -- address is within the standard 52 bit EA space
                            if r.shift = 0 then
                                v.wr_tlbram := '1';
                            end if;
                        else
                            v.state := RADIX_FINISH;
                            v.perm_err := not perm_ok;
                            -- permission error takes precedence over RC error
                            v.rc_error := perm_ok;
                        end if;
                    else
                        mbits := unsigned('0' & data(4 downto 0));
                        if mbits < 5 or mbits > 16 or mbits > r.shift then
                            v.state := RADIX_FINISH;
                            v.badtree := '1';
                        else
                            v.shift := v.shift - mbits;
                            v.mask_size := mbits(4 downto 0);
                            v.pgbase := data(55 downto 8) & x"00";
                            v.state := RADIX_LOOKUP;
                        end if;
                    end if;
                else
                    -- non-present PTE, generate a DSI
                    v.state := RADIX_FINISH;
                    v.invalid := '1';
                end if;
            end if;
            if d_in.err = '1' then
                v.state := RADIX_FINISH;
                v.badtree := '1';
            end if;

        when RADIX_LOAD_TLB =>
            tlb_load := '1';
            v.state := RADIX_FINISH;

        when RADIX_FINISH =>
            v.wr_tlbram := '0';
            v.state := IDLE;

        end case;

        if v.state = RADIX_FINISH then
            v.err := v.invalid or v.badtree or v.segerror or v.perm_err or v.rc_error;
            v.done := not v.err;
        end if;

        if r.addr(63) = '1' then
            effpid := (others => '0');
        else
            effpid := r.pid;
        end if;
        prtable_addr := x"00" & r.prtbl(55 downto 16) &
                        ((r.prtbl(15 downto 12) and not finalmask(3 downto 0)) or
                         (effpid(11 downto 8) and finalmask(3 downto 0))) &
                        effpid(7 downto 0) & "0000";

        pgtable_addr := x"00" & r.pgbase(55 downto 19) &
                        ((r.pgbase(18 downto 3) and not mask) or (addrsh and mask)) &
                        "000";
        pte := x"00" &
               ((r.pde(55 downto 12) and not finalmask) or (r.addr(55 downto 12) and finalmask))
               & r.pde(11 downto 0);

        -- update registers
        rin <= v;

        -- drive outputs
        if r.tlbie_req = '1' then
            addr := r.addr;
            tlb_data := (others => '0');
        elsif tlb_load = '1' then
            addr := r.addr(63 downto 12) & x"000";
            tlb_data := pte;
        elsif ptbl_rd = '1' then
            addr := x"00" & r.ptcr(55 downto 12) & x"008";
            tlb_data := (others => '0');
        elsif prtbl_rd = '1' then
            addr := prtable_addr;
            tlb_data := (others => '0');
        else
            addr := pgtable_addr;
            tlb_data := (others => '0');
        end if;

        l_out.done <= r.done;
        l_out.err <= r.err;
        l_out.invalid <= r.invalid;
        l_out.badtree <= r.badtree;
        l_out.segerr <= r.segerror;
        l_out.perm_error <= r.perm_err;
        l_out.rc_error <= r.rc_error;

        d_out.valid <= dcreq;
        d_out.tlbie <= r.tlbie_req;
        d_out.doall <= r.inval_all;
        d_out.tlbld <= tlb_load and not r.iside;
        d_out.addr <= addr;
        d_out.pte <= tlb_data;

        i_out.tlbld <= tlb_load and r.iside;
        i_out.tlbie <= r.tlbie_req;
        i_out.doall <= r.inval_all;
        i_out.addr <= addr;
        i_out.pte <= tlb_data;

    end process;
end;
