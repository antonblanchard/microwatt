library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.helpers.all;

-- 2 cycle LSU
-- We calculate the address in the first cycle

entity loadstore1 is
    port (
        clk   : in std_ulogic;
        rst   : in std_ulogic;

        l_in  : in Execute1ToLoadstore1Type;
        l_out : out Loadstore1ToWritebackType;

        d_out : out Loadstore1ToDcacheType;
        d_in  : in DcacheToLoadstore1Type;

        dc_stall  : in std_ulogic;
        stall_out : out std_ulogic
        );
end loadstore1;

-- Note, we don't currently use the stall output from the dcache because
-- we know it can take two requests without stalling when idle, we are
-- its only user, and we know it never stalls when idle.

architecture behave of loadstore1 is

    -- State machine for unaligned loads/stores
    type state_t is (IDLE,              -- ready for instruction
                     SECOND_REQ,        -- send 2nd request of unaligned xfer
                     FIRST_ACK_WAIT,    -- waiting for 1st ack from dcache
                     LAST_ACK_WAIT,     -- waiting for last ack from dcache
                     LD_UPDATE          -- writing rA with computed addr on load
                     );

    type reg_stage_t is record
        -- latch most of the input request
	load         : std_ulogic;
	addr         : std_ulogic_vector(63 downto 0);
	data         : std_ulogic_vector(63 downto 0);
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
        state        : state_t;
        second_bytes : std_ulogic_vector(7 downto 0);
    end record;

    signal r, rin : reg_stage_t;
    signal lsu_sum : std_ulogic_vector(63 downto 0);

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
        variable long_sel : std_ulogic_vector(15 downto 0);
        variable byte_sel : std_ulogic_vector(7 downto 0);
        variable req : std_ulogic;
        variable stall : std_ulogic;
        variable addr : std_ulogic_vector(63 downto 0);
        variable wdata : std_ulogic_vector(63 downto 0);
        variable write_enable : std_ulogic;
        variable do_update : std_ulogic;
        variable second_dword : std_ulogic;
        variable done : std_ulogic;
    begin
        v := r;
        req := '0';
        stall := '0';
        done := '0';
        byte_sel := (others => '0');
        addr := lsu_sum;

        write_enable := '0';
        do_update := '0';
        second_dword := '0';

        case r.state is
        when IDLE =>
            if l_in.valid = '1' then
                v.load := l_in.load;
                v.addr := lsu_sum;
                v.data := l_in.data;
                v.write_reg := l_in.write_reg;
                v.length := l_in.length;
                v.byte_reverse := l_in.byte_reverse;
                v.sign_extend := l_in.sign_extend;
                v.update := l_in.update;
                v.update_reg := l_in.update_reg;
                v.xerc := l_in.xerc;
                v.reserve := l_in.reserve;
                v.rc := l_in.rc;

                -- XXX Temporary hack. Mark the op as non-cachable if the address
                -- is the form 0xc-------
                --
                -- This will have to be replaced by a combination of implementing the
                -- proper HV CI load/store instructions and having an MMU to get the I
                -- bit otherwise.
                if lsu_sum(31 downto 28) = "1100" then
                    v.nc := '1';
                else
                    v.nc := '0';
                end if;

                -- Do length_to_sel and work out if we are doing 2 dwords
                long_sel := xfer_data_sel(l_in.length, v.addr(2 downto 0));
                byte_sel := long_sel(7 downto 0);
                v.second_bytes := long_sel(15 downto 8);

                v.addr := lsu_sum;

                -- Do byte reversing and rotating for stores in the first cycle
                if v.load = '0' then
                    byte_offset := unsigned(lsu_sum(2 downto 0));
                    brev_lenm1 := "000";
                    if l_in.byte_reverse = '1' then
                        brev_lenm1 := unsigned(l_in.length(2 downto 0)) - 1;
                    end if;
                    for i in 0 to 7 loop
                        k := (to_unsigned(i, 3) xor brev_lenm1) + byte_offset;
                        j := to_integer(k) * 8;
                        v.data(j + 7 downto j) := l_in.data(i * 8 + 7 downto i * 8);
                    end loop;
                end if;

                req := '1';
                stall := '1';
                if long_sel(15 downto 8) = "00000000" then
                    v.state := LAST_ACK_WAIT;
                else
                    v.state := SECOND_REQ;
                end if;
            end if;

        when SECOND_REQ =>
            -- compute (addr + 8) & ~7 for the second doubleword when unaligned
            addr := std_ulogic_vector(unsigned(r.addr(63 downto 3)) + 1) & "000";
            byte_sel := r.second_bytes;
            req := '1';
            stall := '1';
            v.state := FIRST_ACK_WAIT;

        when FIRST_ACK_WAIT =>
            stall := '1';
            if d_in.valid = '1' then
                write_enable := r.load;
                v.state := LAST_ACK_WAIT;
            end if;

        when LAST_ACK_WAIT =>
            stall := '1';
            second_dword := or (r.second_bytes);
            if d_in.valid = '1' then
                write_enable := r.load;
                if r.load = '1' and r.update = '1' then
                    -- loads with rA update need an extra cycle
                    v.state := LD_UPDATE;
                else
                    -- stores write back rA update in this cycle
                    do_update := r.update;
                    stall := '0';
                    done := '1';
                    v.state := IDLE;
                end if;
            end if;

        when LD_UPDATE =>
            do_update := '1';
            v.state := IDLE;
            done := '1';
        end case;

        -- Update registers
        rin <= v;

        -- Update outputs to dcache
        d_out.valid <= req;
        d_out.load <= v.load;
        d_out.nc <= v.nc;
        d_out.reserve <= v.reserve;
        d_out.addr <= addr;
        d_out.data <= v.data;
        d_out.byte_sel <= byte_sel;

        -- Update outputs to writeback
        -- Multiplex either cache data to the destination GPR or
        -- the address for the rA update.
        l_out.valid <= done;
        if do_update = '1' then
            l_out.write_enable <= '1';
            l_out.write_reg <= r.update_reg;
            l_out.write_data <= r.addr;
            l_out.write_len <= x"8";
            l_out.write_shift <= "000";
            l_out.sign_extend <= '0';
            l_out.byte_reverse <= '0';
            l_out.second_word <= '0';
            l_out.rc <= '0';
            l_out.store_done <= '0';
        else
            l_out.write_enable <= write_enable;
            l_out.write_reg <= r.write_reg;
            l_out.write_data <= d_in.data;
            l_out.write_len <= r.length;
            l_out.write_shift <= r.addr(2 downto 0);
            l_out.sign_extend <= r.sign_extend;
            l_out.byte_reverse <= r.byte_reverse;
            l_out.second_word <= second_dword;
            l_out.rc <= r.rc and done;
            l_out.store_done <= d_in.store_done;
        end if;
        l_out.xerc <= r.xerc;

        stall_out <= stall;

    end process;
end;
