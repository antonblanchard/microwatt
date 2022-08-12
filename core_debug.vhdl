library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.utils.all;
use work.common.all;

entity core_debug is
    generic (
        -- Length of log buffer
        LOG_LENGTH : natural := 512
        );
    port (
        clk             : in std_logic;
        rst             : in std_logic;

        dmi_addr        : in std_ulogic_vector(3 downto 0);
        dmi_din         : in std_ulogic_vector(63 downto 0);
        dmi_dout        : out std_ulogic_vector(63 downto 0);
        dmi_req         : in std_ulogic;
        dmi_wr          : in std_ulogic;
        dmi_ack         : out std_ulogic;

        -- Debug actions
        core_stop       : out std_ulogic;
        core_rst        : out std_ulogic;
        icache_rst      : out std_ulogic;

        -- Core status inputs
        terminate       : in std_ulogic;
        core_stopped    : in std_ulogic;
        nia             : in std_ulogic_vector(63 downto 0);
        msr             : in std_ulogic_vector(63 downto 0);

        -- GPR/FPR register read port
        dbg_gpr_req     : out std_ulogic;
        dbg_gpr_ack     : in std_ulogic;
        dbg_gpr_addr    : out gspr_index_t;
        dbg_gpr_data    : in std_ulogic_vector(63 downto 0);

        -- SPR register read port for SPRs in execute1
        dbg_spr_req     : out std_ulogic;
        dbg_spr_ack     : in std_ulogic;
        dbg_spr_addr    : out std_ulogic_vector(7 downto 0);
        dbg_spr_data    : in std_ulogic_vector(63 downto 0);

        -- SPR register read port for SPRs in loadstore1 and mmu
        dbg_ls_spr_req  : out std_ulogic;
        dbg_ls_spr_ack  : in std_ulogic;
        dbg_ls_spr_addr : out std_ulogic_vector(1 downto 0);
        dbg_ls_spr_data : in std_ulogic_vector(63 downto 0);

        -- Core logging data
        log_data        : in std_ulogic_vector(255 downto 0);
        log_read_addr   : in std_ulogic_vector(31 downto 0);
        log_read_data   : out std_ulogic_vector(63 downto 0);
        log_write_addr  : out std_ulogic_vector(31 downto 0);

        -- Misc
        terminated_out  : out std_ulogic
        );
end core_debug;

architecture behave of core_debug is
        -- DMI needs fixing... make a one clock pulse
    signal dmi_req_1: std_ulogic;

    -- CTRL register (direct actions, write 1 to act, read back 0)
    -- bit     0 : Core stop
    -- bit     1 : Core reset (doesn't clear stop)
    -- bit     2 : Icache reset
    -- bit     3 : Single step
    -- bit     4 : Core start
    constant DBG_CORE_CTRL         : std_ulogic_vector(3 downto 0) := "0000";
    constant DBG_CORE_CTRL_STOP    : integer := 0;
    constant DBG_CORE_CTRL_RESET   : integer := 1;
    constant DBG_CORE_CTRL_ICRESET : integer := 2;
    constant DBG_CORE_CTRL_STEP    : integer := 3;
    constant DBG_CORE_CTRL_START   : integer := 4;

    -- STAT register (read only)
    -- bit    0 : Core stopping (wait til bit 1 set)
    -- bit    1 : Core stopped
    -- bit    2 : Core terminated (clears with start or reset)
    constant DBG_CORE_STAT           : std_ulogic_vector(3 downto 0) := "0001";
    constant DBG_CORE_STAT_STOPPING  : integer := 0;
    constant DBG_CORE_STAT_STOPPED   : integer := 1;
    constant DBG_CORE_STAT_TERM      : integer := 2;

    -- NIA register (read only for now)
    constant DBG_CORE_NIA             : std_ulogic_vector(3 downto 0) := "0010";

    -- MSR (read only)
    constant DBG_CORE_MSR            : std_ulogic_vector(3 downto 0) := "0011";

    -- GSPR register index
    constant DBG_CORE_GSPR_INDEX     : std_ulogic_vector(3 downto 0) := "0100";

    -- GSPR register data
    constant DBG_CORE_GSPR_DATA      : std_ulogic_vector(3 downto 0) := "0101";

    -- Log buffer address and data registers
    constant DBG_CORE_LOG_ADDR       : std_ulogic_vector(3 downto 0) := "0110";
    constant DBG_CORE_LOG_DATA       : std_ulogic_vector(3 downto 0) := "0111";
    constant DBG_CORE_LOG_TRIGGER    : std_ulogic_vector(3 downto 0) := "1000";

    constant LOG_INDEX_BITS : natural := log2(LOG_LENGTH);

    -- Some internal wires
    signal stat_reg : std_ulogic_vector(63 downto 0);

    -- Some internal latches
    signal stopping     : std_ulogic;
    signal do_step      : std_ulogic;
    signal do_reset     : std_ulogic;
    signal do_icreset   : std_ulogic;
    signal terminated   : std_ulogic;
    signal do_gspr_rd   : std_ulogic;
    signal gspr_index   : std_ulogic_vector(7 downto 0);
    signal gspr_data    : std_ulogic_vector(63 downto 0);

    signal spr_index_valid : std_ulogic;

    signal log_dmi_addr        : std_ulogic_vector(31 downto 0) := (others => '0');
    signal log_dmi_data        : std_ulogic_vector(63 downto 0) := (others => '0');
    signal log_dmi_trigger     : std_ulogic_vector(63 downto 0) := (others => '0');
    signal do_log_trigger      : std_ulogic := '0';
    signal do_dmi_log_rd       : std_ulogic;
    signal dmi_read_log_data   : std_ulogic;
    signal dmi_read_log_data_1 : std_ulogic;
    signal log_trigger_delay   : integer range 0 to 255 := 0;

begin
       -- Single cycle register accesses on DMI except for GSPR data
    dmi_ack <= dmi_req when dmi_addr /= DBG_CORE_GSPR_DATA
               else dbg_gpr_ack or dbg_spr_ack or dbg_ls_spr_ack;

    -- Status register read composition
    stat_reg <= (2 => terminated,
                 1 => core_stopped,
                 0 => stopping,
                 others => '0');

    gspr_data <= dbg_gpr_data when gspr_index(5) = '0' else
                 dbg_ls_spr_data when dbg_ls_spr_req = '1' else
                 dbg_spr_data when spr_index_valid = '1' else
                 (others => '0');

    -- DMI read data mux
    with dmi_addr select dmi_dout <=
        stat_reg        when DBG_CORE_STAT,
        nia             when DBG_CORE_NIA,
        msr             when DBG_CORE_MSR,
        gspr_data       when DBG_CORE_GSPR_DATA,
        log_write_addr & log_dmi_addr when DBG_CORE_LOG_ADDR,
        log_dmi_data    when DBG_CORE_LOG_DATA,
        log_dmi_trigger when DBG_CORE_LOG_TRIGGER,
        (others => '0') when others;

    -- DMI writes
    reg_write: process(clk)
    begin
        if rising_edge(clk) then
            -- Reset the 1-cycle "do" signals
            do_step <= '0';
            do_reset <= '0';
            do_icreset <= '0';
            do_dmi_log_rd <= '0';

            if (rst) then
                stopping <= '0';
                terminated <= '0';
                log_trigger_delay <= 0;
                gspr_index <= (others => '0');
                log_dmi_addr <= (others => '0');
            else
                if do_log_trigger = '1' or log_trigger_delay /= 0 then
                    if log_trigger_delay = 255 or
                        (LOG_LENGTH < 1024 and log_trigger_delay = LOG_LENGTH / 4) then
                        log_dmi_trigger(1) <= '1';
                        log_trigger_delay <= 0;
                    else
                        log_trigger_delay <= log_trigger_delay + 1;
                    end if;
                end if;
                -- Edge detect on dmi_req for 1-shot pulses
                dmi_req_1 <= dmi_req;
                if dmi_req = '1' and dmi_req_1 = '0' then
                    if dmi_wr = '1' then
                        report("DMI write to " & to_hstring(dmi_addr));

                        -- Control register actions
                        if dmi_addr = DBG_CORE_CTRL then
                            if dmi_din(DBG_CORE_CTRL_RESET) = '1' then
                                do_reset <= '1';
                                terminated <= '0';
                            end if;
                            if dmi_din(DBG_CORE_CTRL_STOP) = '1' then
                                stopping <= '1';
                            end if;
                            if dmi_din(DBG_CORE_CTRL_STEP) = '1' then
                                do_step <= '1';
                                terminated <= '0';
                            end if;
                            if dmi_din(DBG_CORE_CTRL_ICRESET) = '1' then
                                do_icreset <= '1';
                            end if;
                            if dmi_din(DBG_CORE_CTRL_START) = '1' then
                                stopping <= '0';
                                terminated <= '0';
                            end if;
                        elsif dmi_addr = DBG_CORE_GSPR_INDEX then
                            gspr_index <= dmi_din(7 downto 0);
                        elsif dmi_addr = DBG_CORE_LOG_ADDR then
                            log_dmi_addr <= dmi_din(31 downto 0);
                            do_dmi_log_rd <= '1';
                        elsif dmi_addr = DBG_CORE_LOG_TRIGGER then
                            log_dmi_trigger <= dmi_din;
                        end if;
                    else
                        report("DMI read from " & to_string(dmi_addr));
                    end if;

                elsif dmi_read_log_data = '0' and dmi_read_log_data_1 = '1' then
                    -- Increment log_dmi_addr after the end of a read from DBG_CORE_LOG_DATA
                    log_dmi_addr(LOG_INDEX_BITS + 1 downto 0) <=
                        std_ulogic_vector(unsigned(log_dmi_addr(LOG_INDEX_BITS+1 downto 0)) + 1);
                    do_dmi_log_rd <= '1';
                end if;
                dmi_read_log_data_1 <= dmi_read_log_data;
                if dmi_req = '1' and dmi_addr = DBG_CORE_LOG_DATA then
                    dmi_read_log_data <= '1';
                else
                    dmi_read_log_data <= '0';
                end if;

                -- Set core stop on terminate. We'll be stopping some time *after*
                -- the offending instruction, at least until we can do back flushes
                -- that preserve NIA which we can't just yet.
                if terminate = '1' then
                    stopping <= '1';
                    terminated <= '1';
                end if;
            end if;
        end if;
    end process;

    gspr_access: process(clk)
        variable valid : std_ulogic;
        variable sel : spr_selector;
        variable isram : std_ulogic;
        variable raddr : ramspr_index;
        variable odd : std_ulogic;
    begin
        if rising_edge(clk) then
            dbg_gpr_req <= '0';
            dbg_spr_req <= '0';
            dbg_ls_spr_req <= '0';
            if rst = '0' and dmi_req = '1' and dmi_addr = DBG_CORE_GSPR_DATA then
                if gspr_index(5) = '0' then
                    dbg_gpr_req <= '1';
                elsif gspr_index(4 downto 2) = "111" then
                    dbg_ls_spr_req <= '1';
                else
                    dbg_spr_req <= '1';
                end if;
            end if;

            -- Map 0 - 0x1f to GPRs, 0x20 - 0x3f to SPRs, and 0x40 - 0x5f to FPRs
            dbg_gpr_addr <= gspr_index(6) & gspr_index(4 downto 0);
            dbg_ls_spr_addr <= gspr_index(1 downto 0);

            -- For SPRs, use the same mapping as when the fast SPRs were in the GPR file
            valid := '1';
            sel := "000";
            isram := '1';
            raddr := (others => '0');
            odd := '0';
            case gspr_index(4 downto 0) is
                when 5x"00" =>
                    raddr := RAMSPR_LR;
                when 5x"01" =>
                    odd := '1';
                    raddr := RAMSPR_CTR;
                when 5x"02" | 5x"03" =>
                    odd := gspr_index(0);
                    raddr := RAMSPR_SRR0;
                when 5x"04" | 5x"05" =>
                    odd := gspr_index(0);
                    raddr := RAMSPR_HSRR0;
                when 5x"06" | 5x"07" =>
                    odd := gspr_index(0);
                    raddr := RAMSPR_SPRG0;
                when 5x"08" | 5x"09" =>
                    odd := gspr_index(0);
                    raddr := RAMSPR_SPRG2;
                when 5x"0a" | 5x"0b" =>
                    odd := gspr_index(0);
                    raddr := RAMSPR_HSPRG0;
                when 5x"0c" =>
                    isram := '0';
                    sel := SPRSEL_XER;
                when 5x"0d" =>
                    raddr := RAMSPR_TAR;
                when others =>
                    valid := '0';
            end case;
            dbg_spr_addr <= isram & sel & std_ulogic_vector(raddr) & odd;
            spr_index_valid <= valid;
        end if;
    end process;

    -- Core control signals generated by the debug module
    core_stop <= stopping and not do_step;
    core_rst <= do_reset;
    icache_rst <= do_icreset;
    terminated_out <= terminated;

    -- Logging RAM
    maybe_log: if LOG_LENGTH > 0 generate
        subtype log_ptr_t is unsigned(LOG_INDEX_BITS - 1 downto 0);
        type log_array_t is array(0 to LOG_LENGTH - 1) of std_ulogic_vector(255 downto 0);
        signal log_array          : log_array_t;
        signal log_rd_ptr         : log_ptr_t;
        signal log_wr_ptr         : log_ptr_t;
        signal log_toggle         : std_ulogic;
        signal log_wr_enable      : std_ulogic;
        signal log_rd_ptr_latched : log_ptr_t;
        signal log_rd             : std_ulogic_vector(255 downto 0);
        signal log_dmi_reading    : std_ulogic;
        signal log_dmi_read_done  : std_ulogic;

        function select_dword(data : std_ulogic_vector(255 downto 0);
                              addr : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
            variable firstbit : integer;
        begin
            assert not is_X(addr);
            firstbit := to_integer(unsigned(addr(1 downto 0))) * 64;
            return data(firstbit + 63 downto firstbit);
        end;

        attribute ram_style : string;
        attribute ram_style of log_array : signal is "block";
        attribute ram_decomp : string;
        attribute ram_decomp of log_array : signal is "power";

    begin
        -- Use MSB of read addresses to stop the logging
        log_wr_enable <= not (log_read_addr(31) or log_dmi_addr(31) or log_dmi_trigger(1));

        log_ram: process(clk)
        begin
            if rising_edge(clk) then
                if log_wr_enable = '1' then
                    assert not is_X(log_wr_ptr);
                    log_array(to_integer(log_wr_ptr)) <= log_data;
                end if;
                if is_X(log_rd_ptr_latched) then
                    log_rd <= (others => 'X');
                else
                    log_rd <= log_array(to_integer(log_rd_ptr_latched));
                end if;
            end if;
        end process;


        log_buffer: process(clk)
            variable b : integer;
            variable data : std_ulogic_vector(255 downto 0);
        begin
            if rising_edge(clk) then
                if rst = '1' then
                    log_wr_ptr <= (others => '0');
                    log_toggle <= '0';
                    log_rd_ptr_latched <= (others => '0');
                elsif log_wr_enable = '1' then
                    if log_wr_ptr = to_unsigned(LOG_LENGTH - 1, LOG_INDEX_BITS) then
                        log_toggle <= not log_toggle;
                    end if;
                    log_wr_ptr <= log_wr_ptr + 1;
                end if;
                if do_dmi_log_rd = '1' then
                    log_rd_ptr_latched <= unsigned(log_dmi_addr(LOG_INDEX_BITS + 1 downto 2));
                else
                    log_rd_ptr_latched <= unsigned(log_read_addr(LOG_INDEX_BITS + 1 downto 2));
                end if;
                if log_dmi_read_done = '1' then
                    log_dmi_data <= select_dword(log_rd, log_dmi_addr);
                else
                    log_read_data <= select_dword(log_rd, log_read_addr);
                end if;
                log_dmi_read_done <= log_dmi_reading;
                log_dmi_reading <= do_dmi_log_rd;
                do_log_trigger <= '0';
                if log_data(42) = log_dmi_trigger(63) and
                    log_data(41 downto 0) = log_dmi_trigger(43 downto 2) and
                    log_dmi_trigger(0) = '1' then
                    do_log_trigger <= '1';
                end if;
            end if;
        end process;
        log_write_addr(LOG_INDEX_BITS - 1 downto 0) <= std_ulogic_vector(log_wr_ptr);
        log_write_addr(LOG_INDEX_BITS) <= '1';
        log_write_addr(31 downto LOG_INDEX_BITS + 1) <= (others => '0');
    end generate;

    no_log: if LOG_LENGTH = 0 generate
    begin
        log_read_data <= (others => '0');
        log_write_addr <= x"00000001";
    end generate;

end behave;

