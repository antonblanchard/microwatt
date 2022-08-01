library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.decode_types.all;

entity pmu is
    port (
        clk   : in  std_ulogic;
        rst   : in  std_ulogic;
        p_in  : in  Execute1ToPMUType;
        p_out : out PMUToExecute1Type
        );
end entity pmu;

architecture behaviour of pmu is

    -- MMCR0 bit numbers
    constant MMCR0_FC      : integer := 63 - 32;
    constant MMCR0_FCS     : integer := 63 - 33;
    constant MMCR0_FCP     : integer := 63 - 34;
    constant MMCR0_FCM1    : integer := 63 - 35;
    constant MMCR0_FCM0    : integer := 63 - 36;
    constant MMCR0_PMAE    : integer := 63 - 37;
    constant MMCR0_FCECE   : integer := 63 - 38;
    constant MMCR0_TBSEL   : integer := 63 - 40;
    constant MMCR0_TBEE    : integer := 63 - 41;
    constant MMCR0_BHRBA   : integer := 63 - 42;
    constant MMCR0_EBE     : integer := 63 - 43;
    constant MMCR0_PMCC    : integer := 63 - 45;
    constant MMCR0_PMC1CE  : integer := 63 - 48;
    constant MMCR0_PMCjCE  : integer := 63 - 49;
    constant MMCR0_TRIGGER : integer := 63 - 50;
    constant MMCR0_FCPC    : integer := 63 - 51;
    constant MMCR0_PMAQ    : integer := 63 - 52;
    constant MMCR0_PMCCEXT : integer := 63 - 54;
    constant MMCR0_CC56RUN : integer := 63 - 55;
    constant MMCR0_PMAO    : integer := 63 - 56;
    constant MMCR0_FC1_4   : integer := 63 - 58;
    constant MMCR0_FC5_6   : integer := 63 - 59;
    constant MMCR0_FC1_4W  : integer := 63 - 62;

    -- MMCR2 bit numbers
    constant MMCR2_FC0S    : integer := 63 - 0;
    constant MMCR2_FC0P0   : integer := 63 - 1;
    constant MMCR2_FC0M1   : integer := 63 - 3;
    constant MMCR2_FC0M0   : integer := 63 - 4;
    constant MMCR2_FC0WAIT : integer := 63 - 5;
    constant MMCR2_FC1S    : integer := 54 - 0;
    constant MMCR2_FC1P0   : integer := 54 - 1;
    constant MMCR2_FC1M1   : integer := 54 - 3;
    constant MMCR2_FC1M0   : integer := 54 - 4;
    constant MMCR2_FC1WAIT : integer := 54 - 5;
    constant MMCR2_FC2S    : integer := 45 - 0;
    constant MMCR2_FC2P0   : integer := 45 - 1;
    constant MMCR2_FC2M1   : integer := 45 - 3;
    constant MMCR2_FC2M0   : integer := 45 - 4;
    constant MMCR2_FC2WAIT : integer := 45 - 5;
    constant MMCR2_FC3S    : integer := 36 - 0;
    constant MMCR2_FC3P0   : integer := 36 - 1;
    constant MMCR2_FC3M1   : integer := 36 - 3;
    constant MMCR2_FC3M0   : integer := 36 - 4;
    constant MMCR2_FC3WAIT : integer := 36 - 5;
    constant MMCR2_FC4S    : integer := 27 - 0;
    constant MMCR2_FC4P0   : integer := 27 - 1;
    constant MMCR2_FC4M1   : integer := 27 - 3;
    constant MMCR2_FC4M0   : integer := 27 - 4;
    constant MMCR2_FC4WAIT : integer := 27 - 5;
    constant MMCR2_FC5S    : integer := 18 - 0;
    constant MMCR2_FC5P0   : integer := 18 - 1;
    constant MMCR2_FC5M1   : integer := 18 - 3;
    constant MMCR2_FC5M0   : integer := 18 - 4;
    constant MMCR2_FC5WAIT : integer := 18 - 5;
    constant MMCR2_FC6S    : integer :=  9 - 0;
    constant MMCR2_FC6P0   : integer :=  9 - 1;
    constant MMCR2_FC6M1   : integer :=  9 - 3;
    constant MMCR2_FC6M0   : integer :=  9 - 4;
    constant MMCR2_FC6WAIT : integer :=  9 - 5;

    -- MMCRA bit numbers
    constant MMCRA_TECX    : integer := 63 - 36;
    constant MMCRA_TECM    : integer := 63 - 44;
    constant MMCRA_TECE    : integer := 63 - 47;
    constant MMCRA_TS      : integer := 63 - 51;
    constant MMCRA_TE      : integer := 63 - 55;
    constant MMCRA_ES      : integer := 63 - 59;
    constant MMCRA_SM      : integer := 63 - 62;
    constant MMCRA_SE      : integer := 63 - 63;

    -- SIER bit numbers
    constant SIER_SAMPPR   : integer := 63 - 38;
    constant SIER_SIARV    : integer := 63 - 41;
    constant SIER_SDARV    : integer := 63 - 42;
    constant SIER_TE       : integer := 63 - 43;
    constant SIER_SITYPE   : integer := 63 - 48;
    constant SIER_SICACHE  : integer := 63 - 51;
    constant SIER_SITAKBR  : integer := 63 - 52;
    constant SIER_SIMISPR  : integer := 63 - 53;
    constant SIER_SIMISPRI : integer := 63 - 55;
    constant SIER_SIDERAT  : integer := 63 - 56;
    constant SIER_SIDAXL   : integer := 63 - 59;
    constant SIER_SIDSAI   : integer := 63 - 62;
    constant SIER_SICMPL   : integer := 63 - 63;

    type pmc_array is array(1 to 6) of std_ulogic_vector(31 downto 0);
    signal pmcs  : pmc_array;
    signal mmcr0 : std_ulogic_vector(31 downto 0);
    signal mmcr1 : std_ulogic_vector(63 downto 0);
    signal mmcr2 : std_ulogic_vector(63 downto 0);
    signal mmcra : std_ulogic_vector(63 downto 0);
    signal siar  : std_ulogic_vector(63 downto 0);
    signal sdar  : std_ulogic_vector(63 downto 0);
    signal sier  : std_ulogic_vector(63 downto 0);

    signal doinc : std_ulogic_vector(1 to 6);
    signal doalert : std_ulogic;
    signal doevent : std_ulogic;

    signal prev_tb : std_ulogic_vector(3 downto 0);

begin
    -- mfspr mux
    with p_in.spr_num(3 downto 0) select p_out.spr_val <=
        32x"0" & pmcs(1) when "0011",
        32x"0" & pmcs(2) when "0100",
        32x"0" & pmcs(3) when "0101",
        32x"0" & pmcs(4) when "0110",
        32x"0" & pmcs(5) when "0111",
        32x"0" & pmcs(6) when "1000",
        32x"0" & mmcr0   when "1011",
        mmcr1            when "1110",
        mmcr2            when "0001",
        mmcra            when "0010",
        siar             when "1100",
        sdar             when "1101",
        sier             when "0000",
        64x"0"           when others;

    p_out.intr <= mmcr0(MMCR0_PMAO);

    pmu_1: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                mmcr0 <= 32x"80000000";
            else
                for i in 1 to 6 loop
                    if p_in.mtspr = '1' and to_integer(unsigned(p_in.spr_num(3 downto 0))) = i + 2 then
                        pmcs(i) <= p_in.spr_val(31 downto 0);
                    elsif doinc(i) = '1' then
                        pmcs(i) <= std_ulogic_vector(unsigned(pmcs(i)) + 1);
                    end if;
                end loop;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "1011" then
                    mmcr0 <= p_in.spr_val(31 downto 0);
                    mmcr0(MMCR0_BHRBA) <= '0';          -- no BHRB yet
                    mmcr0(MMCR0_EBE) <= '0';            -- no EBBs yet
                else
                    if doalert = '1' then
                        mmcr0(MMCR0_PMAE) <= '0';
                        mmcr0(MMCR0_PMAO) <= '1';
                        mmcr0(MMCR0_PMAQ) <= '0';
                    end if;
                    if doevent = '1' and mmcr0(MMCR0_FCECE) = '1' and mmcr0(MMCR0_TRIGGER) = '0' then
                        mmcr0(MMCR0_FC) <= '1';
                    end if;
                    if (doevent = '1' or pmcs(1)(31) = '1') and mmcr0(MMCR0_TRIGGER) = '1' then
                        mmcr0(MMCR0_TRIGGER) <= '0';
                    end if;
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "1110" then
                    mmcr1 <= p_in.spr_val;
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "0001" then
                    mmcr2 <= p_in.spr_val;
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "0010" then
                    mmcra <= p_in.spr_val;
                    -- we don't support random sampling yet
                    mmcra(MMCRA_SE) <= '0';
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "1100" then
                    siar <= p_in.spr_val;
                elsif doalert = '1' then
                    siar <= p_in.nia;
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "1101" then
                    sdar <= p_in.spr_val;
                elsif doalert = '1' then
                    sdar <= p_in.addr;
                end if;
                if p_in.mtspr = '1' and p_in.spr_num(3 downto 0) = "0000" then
                    sier <= p_in.spr_val;
                elsif doalert = '1' then
                    sier <= (others => '0');
                    sier(SIER_SAMPPR) <= p_in.pr_msr;
                    sier(SIER_SIARV) <= '1';
                    sier(SIER_SDARV) <= p_in.addr_v;
                end if;
            end if;
            prev_tb <= p_in.tbbits;
        end if;
    end process;

    pmu_2: process(all)
        variable tbdiff : std_ulogic_vector(3 downto 0);
        variable tbbit  : std_ulogic;
        variable freeze : std_ulogic;
        variable event  : std_ulogic;
        variable j      : integer;
        variable inc    : std_ulogic_vector(1 to 6);
        variable fc14wo : std_ulogic;
    begin
        event := '0';

        -- Check for timebase events
        tbdiff := p_in.tbbits and not prev_tb;
        if is_X(mmcr0) then
            tbbit := 'X';
        else
            tbbit := tbdiff(3 - to_integer(unsigned(mmcr0(MMCR0_TBSEL + 1 downto MMCR0_TBSEL))));
        end if;
        if tbbit = '1' and mmcr0(MMCR0_TBEE) = '1' then
            event := '1';
        end if;

        -- Check for counter negative events
        if mmcr0(MMCR0_PMC1CE) = '1' and pmcs(1)(31) = '1' then
            event := '1';
        end if;
        if mmcr0(MMCR0_PMCjCE) = '1' and
            (pmcs(2)(31) or pmcs(3)(31) or pmcs(4)(31)) = '1' then
            event := '1';
        end if;
        if mmcr0(MMCR0_PMCjCE) = '1' and
            mmcr0(MMCR0_PMCC + 1 downto MMCR0_PMCC) /= "11" and
            (pmcs(5)(31) or pmcs(6)(31)) = '1' then
            event := '1';
        end if;

        -- Event selection
        inc := (others => '0');
        fc14wo := '0';
        case mmcr1(31 downto 24) is
            when x"f0" =>
                inc(1) := '1';
                fc14wo := '1';          -- override MMCR0[FC1_4WAIT]
            when x"f2" | x"fe" =>
                inc(1) := p_in.occur.instr_complete;
            when x"f4" =>
                inc(1) := p_in.occur.fp_complete;
            when x"f6" =>
                inc(1) := p_in.occur.itlb_miss;
            when x"f8" =>
                inc(1) := p_in.occur.no_instr_avail;
            when x"fa" =>
                inc(1) := p_in.run;
            when x"fc" =>
                inc(1) := p_in.occur.ld_complete;
            when others =>
        end case;

        case mmcr1(23 downto 16) is
            when x"f0" =>
                inc(2) := p_in.occur.st_complete;
            when x"f2" =>
                inc(2) := p_in.occur.dispatch;
            when x"f4" =>
                inc(2) := p_in.run;
            when x"f6" =>
                inc(2) := p_in.occur.dtlb_miss_resolved;
            when x"f8" =>
                inc(2) := p_in.occur.ext_interrupt;
            when x"fa" =>
                inc(2) := p_in.occur.br_taken_complete;
            when x"fc" =>
                inc(2) := p_in.occur.icache_miss;
            when x"fe" =>
                inc(2) := p_in.occur.dc_miss_resolved;
            when others =>
        end case;

        case mmcr1(15 downto 8) is
            when x"f0" =>
                inc(3) := p_in.occur.dc_store_miss;
            when x"f2" =>
                inc(3) := p_in.occur.dispatch;
            when x"f4" =>
                inc(3) := p_in.occur.instr_complete and p_in.run;
            when x"f6" =>
                inc(3) := p_in.occur.dc_ld_miss_resolved;
            when x"f8" =>
                inc(3) := tbbit;
            when x"fe" =>
                inc(3) := p_in.occur.dtlb_miss;
            when others =>
        end case;

        case mmcr1(7 downto 0) is
            when x"f0" =>
                inc(4) := p_in.occur.dc_load_miss;
            when x"f2" =>
                inc(4) := p_in.occur.dispatch;
            when x"f4" =>
                inc(4) := p_in.run;
            when x"f6" =>
                inc(4) := p_in.occur.br_mispredict;
            when x"f8" =>
                inc(4) := p_in.occur.ipref_discard;
            when x"fa" =>
                inc(4) := p_in.occur.instr_complete and p_in.run;
            when x"fc" =>
                inc(4) := p_in.occur.itlb_miss_resolved;
            when x"fe" =>
                inc(4) := p_in.occur.ld_miss_nocache;
            when others =>
        end case;

        inc(5) := (mmcr0(MMCR0_CC56RUN) or p_in.run) and p_in.occur.instr_complete;
        inc(6) := mmcr0(MMCR0_CC56RUN) or p_in.run;

        -- Evaluate freeze conditions
        freeze := mmcr0(MMCR0_FC) or
                  (mmcr0(MMCR0_FCS) and not p_in.pr_msr) or
                  (mmcr0(MMCR0_FCP) and not mmcr0(MMCR0_FCPC) and p_in.pr_msr) or
                  (not mmcr0(MMCR0_FCP) and mmcr0(MMCR0_FCPC) and p_in.pr_msr) or
                  (mmcr0(MMCR0_FCM1) and p_in.pmm_msr) or
                  (mmcr0(MMCR0_FCM0) and not p_in.pmm_msr);

        if freeze = '1' or mmcr0(MMCR0_FC1_4) = '1' or
            (mmcr0(MMCR0_FC1_4W) = '1' and p_in.run = '0' and fc14wo = '0') then
            inc(1) := '0';
        end if;
        if freeze = '1' or mmcr0(MMCR0_FC1_4) = '1' or
            (mmcr0(MMCR0_FC1_4W) = '1' and p_in.run = '0') then
            inc(2 to 4) := "000";
        end if;
        if freeze = '1' or mmcr0(MMCR0_FC5_6) = '1' then
            inc(5 to 6) := "00";
        end if;
        if mmcr0(MMCR0_TRIGGER) = '1' then
            inc(2 to 6) := "00000";
        end if;
        for i in 1 to 6 loop
            j := (i - 1) * 9;
            if (mmcr2(MMCR2_FC0S - j) = '1' and p_in.pr_msr = '0') or
                (mmcr2(MMCR2_FC0P0 - j) = '1' and p_in.pr_msr = '1') or
                (mmcr2(MMCR2_FC0M1 - j) = '1' and p_in.pmm_msr = '1') or
                (mmcr2(MMCR2_FC0M1 - j) = '1' and p_in.pmm_msr = '1') then
                inc(i) := '0';
            end if;
        end loop;

        -- When MMCR0[PMCC] = "11", PMC5 and PMC6 are not controlled by the
        -- MMCRs and don't generate events, but do continue to count run
        -- instructions and run cycles.
        if mmcr0(MMCR0_PMCC + 1 downto MMCR0_PMCC) = "11" then
            inc(5) := p_in.run and p_in.occur.instr_complete;
            inc(6) := p_in.run;
        end if;

        doinc <= inc;
        doevent <= event;
        doalert <= event and mmcr0(MMCR0_PMAE);
    end process;

end architecture behaviour;
