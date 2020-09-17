library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.insn_helpers.all;
use work.helpers.all;

-- 2 cycle LSU
-- We calculate the address in the first cycle

entity loadstore1 is
    generic (
        HAS_FPU : boolean := true;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
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
                     FPR_CONV,          -- converting double to float for store
                     SECOND_REQ,        -- send 2nd request of unaligned xfer
                     ACK_WAIT,          -- waiting for ack from dcache
                     MMU_LOOKUP,        -- waiting for MMU to look up translation
                     TLBIE_WAIT,        -- waiting for MMU to finish doing a tlbie
                     FINISH_LFS,        -- write back converted SP data for lfs*
                     COMPLETE           -- extra cycle to complete an operation
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
	write_reg    : gspr_index_t;
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
        last_dword   : std_ulogic;
        first_bytes  : std_ulogic_vector(7 downto 0);
        second_bytes : std_ulogic_vector(7 downto 0);
        dar          : std_ulogic_vector(63 downto 0);
        dsisr        : std_ulogic_vector(31 downto 0);
        instr_fault  : std_ulogic;
        align_intr   : std_ulogic;
        sprval       : std_ulogic_vector(63 downto 0);
        busy         : std_ulogic;
        wait_dcache  : std_ulogic;
        wait_mmu     : std_ulogic;
        do_update    : std_ulogic;
        extra_cycle  : std_ulogic;
        mode_32bit   : std_ulogic;
        load_sp      : std_ulogic;
        ld_sp_data   : std_ulogic_vector(31 downto 0);
        ld_sp_nz     : std_ulogic;
        ld_sp_lz     : std_ulogic_vector(5 downto 0);
        st_sp_data   : std_ulogic_vector(31 downto 0);
    end record;

    type byte_sel_t is array(0 to 7) of std_ulogic;
    subtype byte_trim_t is std_ulogic_vector(1 downto 0);
    type trim_ctl_t is array(0 to 7) of byte_trim_t;

    signal r, rin : reg_stage_t;
    signal lsu_sum : std_ulogic_vector(63 downto 0);

    signal store_sp_data : std_ulogic_vector(31 downto 0);
    signal load_dp_data  : std_ulogic_vector(63 downto 0);

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

    -- 23-bit right shifter for DP -> SP float conversions
    function shifter_23r(frac: std_ulogic_vector(22 downto 0); shift: unsigned(4 downto 0))
        return std_ulogic_vector is
        variable fs1   : std_ulogic_vector(22 downto 0);
        variable fs2   : std_ulogic_vector(22 downto 0);
    begin
        case shift(1 downto 0) is
            when "00" =>
                fs1 := frac;
            when "01" =>
                fs1 := '0' & frac(22 downto 1);
            when "10" =>
                fs1 := "00" & frac(22 downto 2);
            when others =>
                fs1 := "000" & frac(22 downto 3);
        end case;
        case shift(4 downto 2) is
            when "000" =>
                fs2 := fs1;
            when "001" =>
                fs2 := x"0" & fs1(22 downto 4);
            when "010" =>
                fs2 := x"00" & fs1(22 downto 8);
            when "011" =>
                fs2 := x"000" & fs1(22 downto 12);
            when "100" =>
                fs2 := x"0000" & fs1(22 downto 16);
            when others =>
                fs2 := x"00000" & fs1(22 downto 20);
        end case;
        return fs2;
    end;

    -- 23-bit left shifter for SP -> DP float conversions
    function shifter_23l(frac: std_ulogic_vector(22 downto 0); shift: unsigned(4 downto 0))
        return std_ulogic_vector is
        variable fs1   : std_ulogic_vector(22 downto 0);
        variable fs2   : std_ulogic_vector(22 downto 0);
    begin
        case shift(1 downto 0) is
            when "00" =>
                fs1 := frac;
            when "01" =>
                fs1 := frac(21 downto 0) & '0';
            when "10" =>
                fs1 := frac(20 downto 0) & "00";
            when others =>
                fs1 := frac(19 downto 0) & "000";
        end case;
        case shift(4 downto 2) is
            when "000" =>
                fs2 := fs1;
            when "001" =>
                fs2 := fs1(18 downto 0) & x"0" ;
            when "010" =>
                fs2 := fs1(14 downto 0) & x"00";
            when "011" =>
                fs2 := fs1(10 downto 0) & x"000";
            when "100" =>
                fs2 := fs1(6 downto 0) & x"0000";
            when others =>
                fs2 := fs1(2 downto 0) & x"00000";
        end case;
        return fs2;
    end;

begin
    -- Calculate the address in the first cycle
    lsu_sum <= std_ulogic_vector(unsigned(l_in.addr1) + unsigned(l_in.addr2)) when l_in.valid = '1' else (others => '0');

    loadstore1_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.busy <= '0';
                r.do_update <= '0';
            else
                r <= rin;
            end if;
        end if;
    end process;

    ls_fp_conv: if HAS_FPU generate
        -- Convert DP data to SP for stfs
        dp_to_sp: process(all)
            variable exp   : unsigned(10 downto 0);
            variable frac  : std_ulogic_vector(22 downto 0);
            variable shift : unsigned(4 downto 0);
        begin
            store_sp_data(31) <= l_in.data(63);
            store_sp_data(30 downto 0) <= (others => '0');
            exp := unsigned(l_in.data(62 downto 52));
            if exp > 896 then
                store_sp_data(30) <= l_in.data(62);
                store_sp_data(29 downto 0) <= l_in.data(58 downto 29);
            elsif exp >= 874 then
                -- denormalization required
                frac := '1' & l_in.data(51 downto 30);
                shift := 0 - exp(4 downto 0);
                store_sp_data(22 downto 0) <= shifter_23r(frac, shift);
            end if;
        end process;

        -- Convert SP data to DP for lfs
        sp_to_dp: process(all)
            variable exp     : unsigned(7 downto 0);
            variable exp_dp  : unsigned(10 downto 0);
            variable exp_nz  : std_ulogic;
            variable exp_ao  : std_ulogic;
            variable frac    : std_ulogic_vector(22 downto 0);
            variable frac_shift : unsigned(4 downto 0);
        begin
            frac := r.ld_sp_data(22 downto 0);
            exp := unsigned(r.ld_sp_data(30 downto 23));
            exp_nz := or (r.ld_sp_data(30 downto 23));
            exp_ao := and (r.ld_sp_data(30 downto 23));
            frac_shift := (others => '0');
            if exp_ao = '1' then
                exp_dp := to_unsigned(2047, 11);    -- infinity or NaN
            elsif exp_nz = '1' then
                exp_dp := 896 + resize(exp, 11);    -- finite normalized value
            elsif r.ld_sp_nz = '0' then
                exp_dp := to_unsigned(0, 11);       -- zero
            else
                -- denormalized SP operand, need to normalize
                exp_dp := 896 - resize(unsigned(r.ld_sp_lz), 11);
                frac_shift := unsigned(r.ld_sp_lz(4 downto 0)) + 1;
            end if;
            load_dp_data(63) <= r.ld_sp_data(31);
            load_dp_data(62 downto 52) <= std_ulogic_vector(exp_dp);
            load_dp_data(51 downto 29) <= shifter_23l(frac, frac_shift);
            load_dp_data(28 downto 0) <= (others => '0');
        end process;
    end generate;

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
        variable maddr : std_ulogic_vector(63 downto 0);
        variable wdata : std_ulogic_vector(63 downto 0);
        variable write_enable : std_ulogic;
        variable do_update : std_ulogic;
        variable done : std_ulogic;
        variable data_permuted : std_ulogic_vector(63 downto 0);
        variable data_trimmed : std_ulogic_vector(63 downto 0);
        variable store_data : std_ulogic_vector(63 downto 0);
        variable data_in : std_ulogic_vector(63 downto 0);
        variable byte_rev : std_ulogic;
        variable length : std_ulogic_vector(3 downto 0);
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
        variable misaligned : std_ulogic;
        variable fp_reg_conv : std_ulogic;
        variable lfs_done : std_ulogic;
    begin
        v := r;
        req := '0';
        v.mfspr := '0';
        mmu_mtspr := '0';
        itlb_fault := '0';
        sprn := std_ulogic_vector(to_unsigned(decode_spr_num(l_in.insn), 10));
        dsisr := (others => '0');
        mmureq := '0';
        fp_reg_conv := '0';

        write_enable := '0';
        lfs_done := '0';

        do_update := r.do_update;
        v.do_update := '0';

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
        -- For unaligned loads crossing two dwords, the sign bit is in the
        -- first dword for big-endian (byte_reverse = 1), or the second dword
        -- for little-endian.
        if r.dwords_done = '1' and r.byte_reverse = '1' then
            negative := (r.length(3) and r.load_data(63)) or
                        (r.length(2) and r.load_data(31)) or
                        (r.length(1) and r.load_data(15)) or
                        (r.length(0) and r.load_data(7));
        else
            negative := (r.length(3) and data_permuted(63)) or
                        (r.length(2) and data_permuted(31)) or
                        (r.length(1) and data_permuted(15)) or
                        (r.length(0) and data_permuted(7));
        end if;

        -- trim and sign-extend
        for i in 0 to 7 loop
            if i < to_integer(unsigned(r.length)) then
                if r.dwords_done = '1' then
                    trim_ctl(i) := '1' & not use_second(i);
                else
                    trim_ctl(i) := "10";
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

        if HAS_FPU then
            -- Single-precision FP conversion
            v.st_sp_data := store_sp_data;
            v.ld_sp_data := data_trimmed(31 downto 0);
            v.ld_sp_nz := or (data_trimmed(22 downto 0));
            v.ld_sp_lz := count_left_zeroes(data_trimmed(22 downto 0));
        end if;

        -- Byte reversing and rotating for stores.
        -- Done in the first cycle (when l_in.valid = 1) for integer stores
        -- and DP float stores, and in the second cycle for SP float stores.
        store_data := r.store_data;
        if l_in.valid = '1' or (HAS_FPU and r.state = FPR_CONV) then
            if HAS_FPU and r.state = FPR_CONV then
                data_in := x"00000000" & r.st_sp_data;
                byte_offset := unsigned(r.addr(2 downto 0));
                byte_rev := r.byte_reverse;
                length := r.length;
            else
                data_in := l_in.data;
                byte_offset := unsigned(lsu_sum(2 downto 0));
                byte_rev := l_in.byte_reverse;
                length := l_in.length;
            end if;
            brev_lenm1 := "000";
            if byte_rev = '1' then
                brev_lenm1 := unsigned(length(2 downto 0)) - 1;
            end if;
            for i in 0 to 7 loop
                k := (to_unsigned(i, 3) - byte_offset) xor brev_lenm1;
                j := to_integer(k) * 8;
                store_data(i * 8 + 7 downto i * 8) := data_in(j + 7 downto j);
            end loop;
        end if;
        v.store_data := store_data;

        -- compute (addr + 8) & ~7 for the second doubleword when unaligned
        next_addr := std_ulogic_vector(unsigned(r.addr(63 downto 3)) + 1) & "000";

        -- Busy calculation.
        -- We need to minimize the delay from clock to busy valid because it
        -- gates the start of execution of the next instruction.
        busy := r.busy and not ((r.wait_dcache and d_in.valid) or (r.wait_mmu and m_in.done));
        v.busy := busy;

        done := '0';
        if r.state /= IDLE and busy = '0' then
            done := '1';
        end if;
        exception := '0';

        if r.dwords_done = '1' or r.state = SECOND_REQ then
            addr := next_addr;
            byte_sel := r.second_bytes;
        else
            addr := r.addr;
            byte_sel := r.first_bytes;
        end if;
        if r.mode_32bit = '1' then
            addr(63 downto 32) := (others => '0');
        end if;
        maddr := addr;

        case r.state is
        when IDLE =>

        when FPR_CONV =>
            req := '1';
            if r.second_bytes /= "00000000" then
                v.state := SECOND_REQ;
            else
                v.state := ACK_WAIT;
            end if;

        when SECOND_REQ =>
            req := '1';
            v.state := ACK_WAIT;
            v.last_dword := '0';

        when ACK_WAIT =>
            if d_in.error = '1' then
                -- dcache will discard the second request if it
                -- gets an error on the 1st of two requests
                if d_in.cache_paradox = '1' then
                    -- signal an interrupt straight away
                    exception := '1';
                    dsisr(63 - 38) := not r.load;
                    -- XXX there is no architected bit for this
                    dsisr(63 - 35) := d_in.cache_paradox;
                else
                    -- Look up the translation for TLB miss
                    -- and also for permission error and RC error
                    -- in case the PTE has been updated.
                    mmureq := '1';
                    v.state := MMU_LOOKUP;
                end if;
            end if;
            if d_in.valid = '1' then
                if r.last_dword = '0' then
                    v.dwords_done := '1';
                    v.last_dword := '1';
                    if r.load = '1' then
                        v.load_data := data_permuted;
                    end if;
                else
                    write_enable := r.load and not r.load_sp;
                    if HAS_FPU and r.load_sp = '1' then
                        -- SP to DP conversion takes a cycle
                        -- Write back rA update in this cycle if needed
                        do_update := r.update;
                        v.state := FINISH_LFS;
                    elsif r.extra_cycle = '1' then
                        -- loads with rA update need an extra cycle
                        v.state := COMPLETE;
                        v.do_update := r.update;
                    else
                        -- stores write back rA update in this cycle
                        do_update := r.update;
                    end if;
                    v.busy := '0';
                end if;
            end if;
            -- r.wait_dcache gets set one cycle after we come into ACK_WAIT state,
            -- which is OK because the dcache always takes at least two cycles.
            v.wait_dcache := r.last_dword and not r.extra_cycle;

        when MMU_LOOKUP =>
            if m_in.done = '1' then
                if r.instr_fault = '0' then
                    -- retry the request now that the MMU has installed a TLB entry
                    req := '1';
                    if r.last_dword = '0' then
                        v.state := SECOND_REQ;
                    else
                        v.state := ACK_WAIT;
                    end if;
                end if;
            end if;
            if m_in.err = '1' then
                exception := '1';
                dsisr(63 - 33) := m_in.invalid;
                dsisr(63 - 36) := m_in.perm_error;
                dsisr(63 - 38) := not r.load;
                dsisr(63 - 44) := m_in.badtree;
                dsisr(63 - 45) := m_in.rc_error;
            end if;

        when TLBIE_WAIT =>

        when FINISH_LFS =>
            lfs_done := '1';

        when COMPLETE =>
            exception := r.align_intr;

        end case;

        if done = '1' or exception = '1' then
            v.state := IDLE;
            v.busy := '0';
        end if;

        -- Note that l_in.valid is gated with busy inside execute1
        if l_in.valid = '1' then
            v.addr := lsu_sum;
            v.mode_32bit := l_in.mode_32bit;
            v.load := '0';
            v.dcbz := '0';
            v.tlbie := '0';
            v.instr_fault := '0';
            v.align_intr := '0';
            v.dwords_done := '0';
            v.last_dword := '1';
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
            v.load_sp := '0';
            v.wait_dcache := '0';
            v.wait_mmu := '0';
            v.do_update := '0';
            v.extra_cycle := '0';

            addr := lsu_sum;
            if l_in.mode_32bit = '1' then
                addr(63 downto 32) := (others => '0');
            end if;
            maddr := l_in.addr2;    -- address from RB for tlbie

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

            -- check alignment for larx/stcx
            misaligned := or (std_ulogic_vector(unsigned(l_in.length(2 downto 0)) - 1) and addr(2 downto 0));
            v.align_intr := l_in.reserve and misaligned;

            case l_in.op is
                when OP_STORE =>
                    req := '1';
                when OP_LOAD =>
                    req := '1';
                    v.load := '1';
                    -- Allow an extra cycle for RA update on loads
                    v.extra_cycle := l_in.update;
                when OP_DCBZ =>
                    v.align_intr := v.nc;
                    req := '1';
                    v.dcbz := '1';
                when OP_FPSTORE =>
                    if HAS_FPU then
                        if l_in.is_32bit = '1' then
                            v.state := FPR_CONV;
                            fp_reg_conv := '1';
                        else
                            req := '1';
                        end if;
                    end if;
                when OP_FPLOAD =>
                    if HAS_FPU then
                        v.load := '1';
                        req := '1';
                        -- Allow an extra cycle for SP->DP precision conversion
                        -- or RA update
                        v.extra_cycle := l_in.update;
                        if l_in.is_32bit = '1' then
                            v.load_sp := '1';
                            v.extra_cycle := '1';
                        end if;
                    end if;
                when OP_TLBIE =>
                    mmureq := '1';
                    v.tlbie := '1';
                    v.state := TLBIE_WAIT;
                    v.wait_mmu := '1';
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
                    v.state := COMPLETE;
                when OP_MTSPR =>
                    if sprn(9) = '0' and sprn(5) = '0' then
                        if sprn(0) = '0' then
                            v.dsisr := l_in.data(31 downto 0);
                        else
                            v.dar := l_in.data;
                        end if;
                        v.state := COMPLETE;
                    else
                        -- writing one of the SPRs in the MMU
                        mmu_mtspr := '1';
                        v.state := TLBIE_WAIT;
                        v.wait_mmu := '1';
                    end if;
                when OP_FETCH_FAILED =>
                    -- send it to the MMU to do the radix walk
                    maddr := l_in.nia;
                    v.instr_fault := '1';
                    mmureq := '1';
                    v.state := MMU_LOOKUP;
                    v.wait_mmu := '1';
                when others =>
                    assert false report "unknown op sent to loadstore1";
            end case;

            if req = '1' then
                if v.align_intr = '1' then
                    v.state := COMPLETE;
                elsif long_sel(15 downto 8) = "00000000" then
                    v.state := ACK_WAIT;
                else
                    v.state := SECOND_REQ;
                end if;
            end if;

            v.busy := req or mmureq or mmu_mtspr or fp_reg_conv;
        end if;

        -- Update outputs to dcache
        d_out.valid <= req and not v.align_intr;
        d_out.load <= v.load;
        d_out.dcbz <= v.dcbz;
        d_out.nc <= v.nc;
        d_out.reserve <= v.reserve;
        d_out.addr <= addr;
        d_out.data <= store_data;
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
        m_out.addr <= maddr;
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
            l_out.write_reg <= gpr_to_gspr(r.update_reg);
            l_out.write_data <= r.addr;
        elsif lfs_done = '1' then
            l_out.write_enable <= '1';
            l_out.write_reg <= r.write_reg;
            l_out.write_data <= load_dp_data;
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
        e_out.alignment <= r.align_intr;
        e_out.instr_fault <= r.instr_fault;
        e_out.invalid <= m_in.invalid;
        e_out.badtree <= m_in.badtree;
        e_out.perm_error <= m_in.perm_error;
        e_out.rc_error <= m_in.rc_error;
        e_out.segment_fault <= m_in.segerr;
        if exception = '1' and r.instr_fault = '0' then
            v.dar := addr;
            if m_in.segerr = '0' and r.align_intr = '0' then
                v.dsisr := dsisr;
            end if;
        end if;

        -- Update registers
        rin <= v;

    end process;

    l1_log: if LOG_LENGTH > 0 generate
        signal log_data : std_ulogic_vector(9 downto 0);
    begin
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
    end generate;

end;
