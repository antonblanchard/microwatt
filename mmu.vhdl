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
                     TLBIE_WAIT,
                     RADIX_LOOKUP_0
                     );

    type reg_stage_t is record
        -- latched request from loadstore1
        valid     : std_ulogic;
        addr      : std_ulogic_vector(63 downto 0);
        state     : state_t;
    end record;

    signal r, rin : reg_stage_t;

begin

    mmu_0: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                r.state <= IDLE;
                r.valid <= '0';
            else
                if rin.valid = '1' then
                    report "MMU got tlb miss for " & to_hstring(rin.addr);
                end if;
                if l_out.done = '1' then
                    report "MMU completing miss with error=" & std_ulogic'image(l_out.error);
                end if;
                r <= rin;
            end if;
        end if;
    end process;

    mmu_1: process(all)
        variable v : reg_stage_t;
        variable dcreq : std_ulogic;
        variable done : std_ulogic;
        variable err  : std_ulogic;
    begin
        v.valid := l_in.valid;
        v.addr := l_in.addr;
        v.state := r.state;
        dcreq := '0';
        done := '0';
        err := '0';

        case r.state is
        when IDLE =>
            if l_in.valid = '1' then
                if l_in.tlbie = '1' then
                    dcreq := '1';
                    v.state := TLBIE_WAIT;
                else
                    v.state := RADIX_LOOKUP_0;
                end if;
            end if;

        when TLBIE_WAIT =>
            if d_in.done = '1' then
                done := '1';
                v.state := IDLE;
            end if;

        when RADIX_LOOKUP_0 =>
            done := '1';
            err := '1';
            v.state := IDLE;
        end case;

        -- update registers
        rin <= v;

        -- drive outputs
        l_out.done <= done;
        l_out.error <= err;

        d_out.valid <= dcreq;
        d_out.tlbie <= l_in.tlbie;
        d_out.addr <= l_in.addr;
        d_out.pte <= l_in.rs;
    end process;
end;
