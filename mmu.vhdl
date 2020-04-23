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
        d_in  : in DcacheToMmuType
        );
end mmu;

architecture behave of mmu is

    type state_t is (IDLE,
                     TLB_WAIT,
                     RADIX_LOOKUP,
                     RADIX_READ_WAIT,
                     RADIX_LOAD_TLB,
                     RADIX_NO_TRANS,
                     RADIX_BAD_TREE
                     );

    type reg_stage_t is record
        -- latched request from loadstore1
        valid     : std_ulogic;
        addr      : std_ulogic_vector(63 downto 0);
        -- internal state
        state     : state_t;
        pgtbl0    : std_ulogic_vector(63 downto 0);
        shift     : unsigned(5 downto 0);
        mask_size : unsigned(4 downto 0);
        pgbase    : std_ulogic_vector(55 downto 0);
        pde       : std_ulogic_vector(63 downto 0);
    end record;

    signal r, rin : reg_stage_t;

    signal addrsh  : std_ulogic_vector(15 downto 0);
    signal mask    : std_ulogic_vector(15 downto 0);
    signal finalmask : std_ulogic_vector(43 downto 0);

begin
    -- Multiplex internal SPR values back to loadstore1, selected
    -- by l_in.sprn.  Easy when there's only one...
    l_out.sprval <= r.pgtbl0;

    mmu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.valid <= '0';
                r.pgtbl0 <= (others => '0');
            else
                if rin.valid = '1' then
                    report "MMU got tlb miss for " & to_hstring(rin.addr);
                end if;
                if l_out.done = '1' then
                    report "MMU completing op with invalid=" & std_ulogic'image(l_out.invalid) &
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
        for i in 5 to 15 loop
            if i < to_integer(r.mask_size) then
                m(i) := '1';
            end if;
        end loop;
        mask <= m;
    end process;

    -- generate mask for extracting address bits to go in TLB entry
    -- in order to support pages > 4kB
    finalmaskgen: process(all)
        variable m : std_ulogic_vector(43 downto 0);
    begin
        m := (others => '0');
        for i in 0 to 43 loop
            if i < to_integer(r.shift) then
                m(i) := '1';
            end if;
        end loop;
        finalmask <= m;
    end process;

    mmu_1: process(all)
        variable v : reg_stage_t;
        variable dcreq : std_ulogic;
        variable done : std_ulogic;
        variable invalid : std_ulogic;
        variable badtree : std_ulogic;
        variable tlb_load : std_ulogic;
        variable tlbie_req : std_ulogic;
        variable rts : unsigned(5 downto 0);
        variable mbits : unsigned(5 downto 0);
        variable pgtable_addr : std_ulogic_vector(63 downto 0);
        variable pte : std_ulogic_vector(63 downto 0);
        variable data : std_ulogic_vector(63 downto 0);
    begin
        v := r;
        v.valid := '0';
        dcreq := '0';
        done := '0';
        invalid := '0';
        badtree := '0';
        tlb_load := '0';
        tlbie_req := '0';

        -- Radix tree data structures in memory are big-endian,
        -- so we need to byte-swap them
        for i in 0 to 7 loop
            data(i * 8 + 7 downto i * 8) := d_in.data((7 - i) * 8 + 7 downto (7 - i) * 8);
        end loop;

        case r.state is
        when IDLE =>
            -- rts == radix tree size, # address bits being translated
            rts := unsigned('0' & r.pgtbl0(62 downto 61) & r.pgtbl0(7 downto 5)) + (31 - 12);
            -- mbits == # address bits to index top level of tree
            mbits := unsigned('0' & r.pgtbl0(4 downto 0));
            v.shift := rts - mbits;
            v.mask_size := mbits(4 downto 0);
            v.pgbase := r.pgtbl0(55 downto 8) & x"00";

            if l_in.valid = '1' then
                v.addr := l_in.addr;
                if l_in.tlbie = '1' then
                    dcreq := '1';
                    tlbie_req := '1';
                    v.state := TLB_WAIT;
                else
                    v.valid := '1';
                    -- for now, take RPDS = 0 to disable radix translation
                    if mbits = 0 then
                        v.state := RADIX_NO_TRANS;
                    elsif mbits < 5 or mbits > 16 or mbits > rts then
                        v.state := RADIX_BAD_TREE;
                    else
                        v.state := RADIX_LOOKUP;
                    end if;
                end if;
            end if;
            if l_in.mtspr = '1' then
                v.pgtbl0 := l_in.rs;
            end if;

        when TLB_WAIT =>
            if d_in.done = '1' then
                done := '1';
                v.state := IDLE;
            end if;

        when RADIX_LOOKUP =>
            dcreq := '1';
            v.state := RADIX_READ_WAIT;

        when RADIX_READ_WAIT =>
            if d_in.done = '1' then
                if d_in.err = '0' then
                    v.pde := data;
                    -- test valid bit
                    if data(63) = '1' then
                        -- test leaf bit
                        if data(62) = '1' then
                            v.state := RADIX_LOAD_TLB;
                        else
                            mbits := unsigned('0' & data(4 downto 0));
                            if mbits < 5 or mbits > 16 or mbits > r.shift then
                                v.state := RADIX_BAD_TREE;
                            else
                                v.shift := v.shift - mbits;
                                v.mask_size := mbits(4 downto 0);
                                v.pgbase := data(55 downto 8) & x"00";
                                v.state := RADIX_LOOKUP;
                            end if;
                        end if;
                    else
                        -- non-present PTE, generate a DSI
                        v.state := RADIX_NO_TRANS;
                    end if;
                else
                    v.state := RADIX_BAD_TREE;
                end if;
            end if;

        when RADIX_LOAD_TLB =>
            tlb_load := '1';
            dcreq := '1';
            v.state := TLB_WAIT;

        when RADIX_NO_TRANS =>
            done := '1';
            invalid := '1';
            v.state := IDLE;

        when RADIX_BAD_TREE =>
            done := '1';
            badtree := '1';
            v.state := IDLE;
        end case;

        pgtable_addr := x"00" & r.pgbase(55 downto 19) &
                        ((r.pgbase(18 downto 3) and not mask) or (addrsh and mask)) &
                        "000";
        pte := x"00" &
               ((r.pde(55 downto 12) and not finalmask) or (r.addr(55 downto 12) and finalmask))
               & r.pde(11 downto 0);

        -- update registers
        rin <= v;

        -- drive outputs
        l_out.done <= done;
        l_out.invalid <= invalid;
        l_out.badtree <= badtree;

        d_out.valid <= dcreq;
        d_out.tlbie <= tlbie_req;
        d_out.tlbld <= tlb_load;
        if tlbie_req = '1' then
            d_out.addr <= l_in.addr;
            d_out.pte <= l_in.rs;
        elsif tlb_load = '1' then
            d_out.addr <= r.addr(63 downto 12) & x"000";
            d_out.pte <= pte;
        else
            d_out.addr <= pgtable_addr;
            d_out.pte <= (others => '0');
        end if;
    end process;
end;
