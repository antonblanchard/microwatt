library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;

-- 2 cycle LSU
-- We calculate the address in the first cycle

entity loadstore1 is
    port (
        clk   : in std_ulogic;
        rst   : in std_ulogic;

        l_in  : in Execute1ToLoadstore1Type;
        e_out : out Loadstore1ToExecute1Type;
        l_out : out Loadstore1ToWritebackType;

        d_out : out Loadstore1ToDcacheType;
        d_in  : in DcacheToLoadstore1Type;

        m_out : out Loadstore1ToMmuType;
        m_in  : in MmuToLoadstore1Type;

        dc_stall  : in std_ulogic;

        log_out : out std_ulogic_vector(9 downto 0)
        );
end loadstore1;

-- Note, we don't currently use the stall output from the dcache because
-- we know it can take two requests without stalling when idle, we are
-- its only user, and we know it never stalls when idle.

architecture behave of loadstore1 is

    -- State machine for unaligned loads/stores
    type state_t is (IDLE,              -- ready for instruction
                     SECOND_REQ,        -- send 2nd request of unaligned xfer
                     ACK_WAIT,          -- waiting for ack from dcache
                     LD_UPDATE,         -- writing rA with computed addr on load
                     MMU_LOOKUP,        -- waiting for MMU to look up translation
                     TLBIE_WAIT,        -- waiting for MMU to finish doing a tlbie
                     SPR_CMPLT          -- complete a mf/tspr operation
                     );

    type reg_stage_t is record
        -- latch most of the input request
        load         : std_ulogic;
        tlbie        : std_ulogic;
        dcbz         : std_ulogic;
        mfspr        : std_ulogic;
	addr         : std_ulogic_vector(63 downto 0);
	store_data   : std_ulogic_vector(63 downto 0);
	load_data    : std_ulogic_vector(63 downto 0);
	write_reg    : gpr_index_t;
	length       : std_ulogic_vector(3 downto 0);
	byte_reverse : std_ulogic;
	sign_extend  : std_ulogic;
	update       : std_ulogic;
	update_reg   : gpr_index_t;
	xerc         : xer_common_t;
        reserve      : std_ulogic;
        rc           : std_ulogic;
        nc           : std_ulogic;              -- non-cacheable access
        virt_mode    : std_ulogic;
        priv_mode    : std_ulogic;
        state        : state_t;
        dwords_done  : std_ulogic;
        first_bytes  : std_ulogic_vector(7 downto 0);
        second_bytes : std_ulogic_vector(7 downto 0);
        dar          : std_ulogic_vector(63 downto 0);
        dsisr        : std_ulogic_vector(31 downto 0);
        instr_fault  : std_ulogic;
        sprval       : std_ulogic_vector(63 downto 0);
    end record;

    type byte_sel_t is array(0 to 7) of std_ulogic;
    subtype byte_trim_t is std_ulogic_vector(1 downto 0);
    type trim_ctl_t is array(0 to 7) of byte_trim_t;

    signal r, rin : reg_stage_t;
    signal lsu_sum : std_ulogic_vector(63 downto 0);

    signal log_data : std_ulogic_vector(9 downto 0);

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

    -- Calculate byte enables
    -- This returns 16 bits, giving the select signals for two transfers,
    -- to account for unaligned loads or stores
    function xfer_data_sel(size : in std_logic_vector(3 downto 0);
                           address : in std_logic_vector(2 downto 0))
	return std_ulogic_vector is
        variable longsel : std_ulogic_vector(15 downto 0);
    begin
        longsel := "00000000" & length_to_sel(size);
        return std_ulogic_vector(shift_left(unsigned(longsel),
					    to_integer(unsigned(address))));
    end function xfer_data_sel;

begin
    -- Calculate the address in the first cycle
    lsu_sum <= std_ulogic_vector(unsigned(l_in.addr1) + unsigned(l_in.addr2)) when l_in.valid = '1' else (others => '0');

    loadstore1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
            else
                r <= rin;
            end if;
        end if;
    end process;

    loadstore1_1: process(all)
        variable v : reg_stage_t;
        variable brev_lenm1 : unsigned(2 downto 0);
        variable byte_offset : unsigned(2 downto 0);
        variable j : integer;
        variable k : unsigned(2 downto 0);
        variable kk : unsigned(3 downto 0);
        variable long_sel : std_ulogic_vector(15 downto 0);
        variable byte_sel : std_ulogic_vector(7 downto 0);
        variable req : std_ulogic;
        variable busy : std_ulogic;
        variable addr : std_ulogic_vector(63 downto 0);
        variable wdata : std_ulogic_vector(63 downto 0);
        variable write_enable : std_ulogic;
        variable do_update : std_ulogic;
        variable two_dwords : std_ulogic;
        variable done : std_ulogic;
        variable data_permuted : std_ulogic_vector(63 downto 0);
        variable data_trimmed : std_ulogic_vector(63 downto 0);
        variable use_second : byte_sel_t;
        variable trim_ctl : trim_ctl_t;
        variable negative : std_ulogic;
        variable sprn : std_ulogic_vector(9 downto 0);
        variable exception : std_ulogic;
        variable next_addr : std_ulogic_vector(63 downto 0);
        variable mmureq : std_ulogic;
        variable dsisr : std_ulogic_vector(31 downto 0);
        variable mmu_mtspr : std_ulogic;
        variable itlb_fault : std_ulogic;
    begin
        v := r;
        req := '0';
        byte_sel := (others => '0');
        addr := lsu_sum;
        v.mfspr := '0';
        mmu_mtspr := '0';
        itlb_fault := '0';
        sprn := std_ulogic_vector(to_unsigned(decode_spr_num(l_in.insn), 10));
        dsisr := (others => '0');
        mmureq := '0';

        write_enable := '0';
        do_update := '0';
        two_dwords := or (r.second_bytes);

        -- load data formatting
        byte_offset := unsigned(r.addr(2 downto 0));
        brev_lenm1 := "000";
        if r.byte_reverse = '1' then
            brev_lenm1 := unsigned(r.length(2 downto 0)) - 1;
        end if;

        -- shift and byte-reverse data bytes
        for i in 0 to 7 loop
            kk := ('0' & (to_unsigned(i, 3) xor brev_lenm1)) + ('0' & byte_offset);
            use_second(i) := kk(3);
            j := to_integer(kk(2 downto 0)) * 8;
            data_permuted(i * 8 + 7 downto i * 8) := d_in.data(j + 7 downto j);
        end loop;

        -- Work out the sign bit for sign extension.
        -- Assumes we are not doing both sign extension and byte reversal,
        -- in that for unaligned loads crossing two dwords we end up
        -- using a bit from the second dword, whereas for a byte-reversed
        -- (i.e. big-endian) load the sign bit would be in the first dword.
        negative := (r.length(3) and data_permuted(63)) or
                    (r.length(2) and data_permuted(31)) or
                    (r.length(1) and data_permuted(15)) or
                    (r.length(0) and data_permuted(7));

        -- trim and sign-extend
        for i in 0 to 7 loop
            if i < to_integer(unsigned(r.length)) then
                if two_dwords = '1' then
                    trim_ctl(i) := '1' & not use_second(i);
                else
                    trim_ctl(i) := not use_second(i) & '0';
                end if;
            else
                trim_ctl(i) := '0' & (negative and r.sign_extend);
            end if;
            case trim_ctl(i) is
                when "11" =>
                    data_trimmed(i * 8 + 7 downto i * 8) := r.load_data(i * 8 + 7 downto i * 8);
                when "10" =>
                    data_trimmed(i * 8 + 7 downto i * 8) := data_permuted(i * 8 + 7 downto i * 8);
                when "01" =>
                    data_trimmed(i * 8 + 7 downto i * 8) := x"FF";
                when others =>
                    data_trimmed(i * 8 + 7 downto i * 8) := x"00";
            end case;
        end loop;

        -- compute (addr + 8) & ~7 for the second doubleword when unaligned
        next_addr := std_ulogic_vector(unsigned(r.addr(63 downto 3)) + 1) & "000";

        done := '0';
        exception := '0';
        case r.state is
        when IDLE =>

        when SECOND_REQ =>
            addr := next_addr;
            byte_sel := r.second_bytes;
            req := '1';
            v.state := ACK_WAIT;

        when ACK_WAIT =>
            if d_in.valid = '1' then
                if d_in.error = '1' then
                    -- dcache will discard the second request if it
                    -- gets an error on the 1st of two requests
                    if r.dwords_done = '1' then
                        addr := next_addr;
                    else
                        addr := r.addr;
                    end if;
                    if d_in.cache_paradox = '1' then
                        -- signal an interrupt straight away
                        exception := '1';
                        dsisr(63 - 38) := not r.load;
                        -- XXX there is no architected bit for this
                        dsisr(63 - 35) := d_in.cache_paradox;
                        v.state := IDLE;
                    else
                        -- Look up the translation for TLB miss
                        -- and also for permission error and RC error
                        -- in case the PTE has been updated.
                        mmureq := '1';
                        v.state := MMU_LOOKUP;
                    end if;
                else
                    if two_dwords = '1' and r.dwords_done = '0' then
                        v.dwords_done := '1';
                        if r.load = '1' then
                            v.load_data := data_permuted;
                        end if;
                    else
                        write_enable := r.load;
                        if r.load = '1' and r.update = '1' then
                            -- loads with rA update need an extra cycle
                            v.state := LD_UPDATE;
                        else
                            -- stores write back rA update in this cycle
                            do_update := r.update;
                            done := '1';
                            v.state := IDLE;
                        end if;
                    end if;
                end if;
            end if;

        when MMU_LOOKUP =>
            if r.dwords_done = '1' then
                addr := next_addr;
                byte_sel := r.second_bytes;
            else
                addr := r.addr;
                byte_sel := r.first_bytes;
            end if;
            if m_in.done = '1' then
                if m_in.invalid = '0' and m_in.perm_error = '0' and m_in.rc_error = '0' and
                    m_in.badtree = '0' and m_in.segerr = '0' then
                    if r.instr_fault = '0' then
                        -- retry the request now that the MMU has installed a TLB entry
                        req := '1';
                        if two_dwords = '1' and r.dwords_done = '0' then
                            v.state := SECOND_REQ;
                        else
                            v.state := ACK_WAIT;
                        end if;
                    else
                        -- nothing to do, the icache retries automatically
                        done := '1';
                        v.state := IDLE;
                    end if;
                else
                    exception := '1';
                    dsisr(63 - 33) := m_in.invalid;
                    dsisr(63 - 36) := m_in.perm_error;
                    dsisr(63 - 38) := not r.load;
                    dsisr(63 - 44) := m_in.badtree;
                    dsisr(63 - 45) := m_in.rc_error;
                    v.state := IDLE;
                end if;
            end if;

        when TLBIE_WAIT =>
            if m_in.done = '1' then
                -- tlbie is finished
                done := '1';
                v.state := IDLE;
            end if;

        when LD_UPDATE =>
            do_update := '1';
            v.state := IDLE;
            done := '1';

        when SPR_CMPLT =>
            done := '1';
            v.state := IDLE;

        end case;

        busy := '1';
        if r.state = IDLE or done = '1' then
            busy := '0';
        end if;

        -- Note that l_in.valid is gated with busy inside execute1
        if l_in.valid = '1' then
            v.addr := lsu_sum;
            v.load := '0';
            v.dcbz := '0';
            v.tlbie := '0';
            v.instr_fault := '0';
            v.dwords_done := '0';
            v.write_reg := l_in.write_reg;
            v.length := l_in.length;
            v.byte_reverse := l_in.byte_reverse;
            v.sign_extend := l_in.sign_extend;
            v.update := l_in.update;
            v.update_reg := l_in.update_reg;
            v.xerc := l_in.xerc;
            v.reserve := l_in.reserve;
            v.rc := l_in.rc;
            v.nc := l_in.ci;
            v.virt_mode := l_in.virt_mode;
            v.priv_mode := l_in.priv_mode;

            -- XXX Temporary hack. Mark the op as non-cachable if the address
            -- is the form 0xc------- for a real-mode access.
            if lsu_sum(31 downto 28) = "1100" and l_in.virt_mode = '0' then
                v.nc := '1';
            end if;

            -- Do length_to_sel and work out if we are doing 2 dwords
            long_sel := xfer_data_sel(l_in.length, v.addr(2 downto 0));
            byte_sel := long_sel(7 downto 0);
            v.first_bytes := byte_sel;
            v.second_bytes := long_sel(15 downto 8);

            -- Do byte reversing and rotating for stores in the first cycle
            byte_offset := unsigned(lsu_sum(2 downto 0));
            brev_lenm1 := "000";
            if l_in.byte_reverse = '1' then
                brev_lenm1 := unsigned(l_in.length(2 downto 0)) - 1;
            end if;
            for i in 0 to 7 loop
                k := (to_unsigned(i, 3) xor brev_lenm1) + byte_offset;
                j := to_integer(k) * 8;
                v.store_data(j + 7 downto j) := l_in.data(i * 8 + 7 downto i * 8);
            end loop;

            case l_in.op is
                when OP_STORE =>
                    req := '1';
                when OP_LOAD =>
                    req := '1';
                    v.load := '1';
                when OP_DCBZ =>
                    req := '1';
                    v.dcbz := '1';
                when OP_TLBIE =>
                    mmureq := '1';
                    v.tlbie := '1';
                    v.state := TLBIE_WAIT;
                when OP_MFSPR =>
                    v.mfspr := '1';
                    -- partial decode on SPR number should be adequate given
                    -- the restricted set that get sent down this path
                    if sprn(9) = '0' and sprn(5) = '0' then
                        if sprn(0) = '0' then
                            v.sprval := x"00000000" & r.dsisr;
                        else
                            v.sprval := r.dar;
                        end if;
                    else
                        -- reading one of the SPRs in the MMU
                        v.sprval := m_in.sprval;
                    end if;
                    v.state := SPR_CMPLT;
                when OP_MTSPR =>
                    if sprn(9) = '0' and sprn(5) = '0' then
                        if sprn(0) = '0' then
                            v.dsisr := l_in.data(31 downto 0);
                        else
                            v.dar := l_in.data;
                        end if;
                        v.state := SPR_CMPLT;
                    else
                        -- writing one of the SPRs in the MMU
                        mmu_mtspr := '1';
                        v.state := TLBIE_WAIT;
                    end if;
                when OP_FETCH_FAILED =>
                    -- send it to the MMU to do the radix walk
                    addr := l_in.nia;
                    v.addr := l_in.nia;
                    v.instr_fault := '1';
                    mmureq := '1';
                    v.state := MMU_LOOKUP;
                when others =>
                    assert false report "unknown op sent to loadstore1";
            end case;

            if req = '1' then
                if long_sel(15 downto 8) = "00000000" then
                    v.state := ACK_WAIT;
                else
                    v.state := SECOND_REQ;
                end if;
            end if;
        end if;

        -- Update outputs to dcache
        d_out.valid <= req;
        d_out.load <= v.load;
        d_out.dcbz <= v.dcbz;
        d_out.nc <= v.nc;
        d_out.reserve <= v.reserve;
        d_out.addr <= addr;
        d_out.data <= v.store_data;
        d_out.byte_sel <= byte_sel;
        d_out.virt_mode <= v.virt_mode;
        d_out.priv_mode <= v.priv_mode;

        -- Update outputs to MMU
        m_out.valid <= mmureq;
        m_out.iside <= v.instr_fault;
        m_out.load <= r.load;
        m_out.priv <= r.priv_mode;
        m_out.tlbie <= v.tlbie;
        m_out.mtspr <= mmu_mtspr;
        m_out.sprn <= sprn;
        m_out.addr <= addr;
        m_out.slbia <= l_in.insn(7);
        m_out.rs <= l_in.data;

        -- Update outputs to writeback
        -- Multiplex either cache data to the destination GPR or
        -- the address for the rA update.
        l_out.valid <= done;
        if r.mfspr = '1' then
            l_out.write_enable <= '1';
            l_out.write_reg <= r.write_reg;
            l_out.write_data <= r.sprval;
        elsif do_update = '1' then
            l_out.write_enable <= '1';
            l_out.write_reg <= r.update_reg;
            l_out.write_data <= r.addr;
        else
            l_out.write_enable <= write_enable;
            l_out.write_reg <= r.write_reg;
            l_out.write_data <= data_trimmed;
        end if;
        l_out.xerc <= r.xerc;
        l_out.rc <= r.rc and done;
        l_out.store_done <= d_in.store_done;

        -- update exception info back to execute1
        e_out.busy <= busy;
        e_out.exception <= exception;
        e_out.instr_fault <= r.instr_fault;
        e_out.invalid <= m_in.invalid;
        e_out.badtree <= m_in.badtree;
        e_out.perm_error <= m_in.perm_error;
        e_out.rc_error <= m_in.rc_error;
        e_out.segment_fault <= m_in.segerr;
        if exception = '1' and r.instr_fault = '0' then
            v.dar := addr;
            if m_in.segerr = '0' then
                v.dsisr := dsisr;
            end if;
        end if;

        -- Update registers
        rin <= v;

    end process;

    ls1_log: process(clk)
    begin
        if rising_edge(clk) then
            log_data <= e_out.busy &
                        e_out.exception &
                        l_out.valid &
                        m_out.valid &
                        d_out.valid &
                        m_in.done &
                        r.dwords_done &
                        std_ulogic_vector(to_unsigned(state_t'pos(r.state), 3));
        end if;
    end process;
    log_out <= log_data;
end;
