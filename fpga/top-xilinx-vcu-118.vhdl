-- VCU118 Debug Top-Level - Add heartbeat LED and basic diagnostics

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY unisim;
USE unisim.vcomponents.ALL;

LIBRARY work;
USE work.wishbone_types.ALL;

ENTITY toplevel IS
    GENERIC (
        MEMORY_SIZE : INTEGER := 16384; -- This can go up a lot more
        DRAM_SIZE : INTEGER := 268435456;
        RAM_INIT_FILE : STRING := "firmware.hex";
        RESET_LOW : BOOLEAN := false; -- VCU118 reset button is active-high
        CLK_INPUT : POSITIVE := 125000000; -- Match physical clock
        CLK_FREQUENCY : POSITIVE := 125000000; -- Same as input (no PLL)
        HAS_FPU : BOOLEAN := true;
        HAS_BTC : BOOLEAN := true;
        ICACHE_NUM_LINES : NATURAL := 64;
        LOG_LENGTH : NATURAL := 512;
        DISABLE_FLATTEN_CORE : BOOLEAN := false;
        UART_IS_16550 : BOOLEAN := true;
        NO_BRAM : BOOLEAN := false;
        USE_LITEDRAM : BOOLEAN := false;
        HAS_SPI_FLASH: BOOLEAN := false
    );
    PORT (
        -- VCU118 differential clock input
        ext_clk_p : IN STD_ULOGIC;
        ext_clk_n : IN STD_ULOGIC;

        -- VCU118 reset button
        ext_rst : IN STD_ULOGIC;

        -- UART0 signals
        uart0_txd : OUT STD_ULOGIC;
        uart0_rxd : IN STD_ULOGIC;

        -- Debug LEDs (use some GPIO LEDs from VCU118)
        debug_led0 : OUT STD_ULOGIC; -- Heartbeat - clock working
        debug_led1 : OUT STD_ULOGIC; -- Reset state
        debug_led2 : OUT STD_ULOGIC; -- SoC running
        debug_led3 : OUT STD_ULOGIC; -- UART activity
        debug_led4 : OUT STD_ULOGIC; -- Init done
        debug_led5 : OUT STD_ULOGIC -- Init error

    );
END ENTITY toplevel;

ARCHITECTURE behaviour OF toplevel IS

    -- Reset signals
    SIGNAL soc_rst : STD_ULOGIC;
    SIGNAL pll_rst : STD_ULOGIC;

    -- Internal clock signals
    SIGNAL system_clk : STD_ULOGIC;
    SIGNAL system_clk_locked : STD_ULOGIC;

    -- Single-ended clock from differential input
    SIGNAL ext_clk_single : STD_ULOGIC;

    -- Debug signals
    SIGNAL heartbeat_counter : unsigned(27 DOWNTO 0) := (OTHERS => '0');
    SIGNAL uart_activity : STD_ULOGIC := '0';
    SIGNAL uart_activity_counter : unsigned(23 DOWNTO 0) := (OTHERS => '0');
    SIGNAL soc_run_out : STD_ULOGIC;
     SIGNAL soc_run_outs : STD_ULOGIC_VECTOR(0 DOWNTO 0);  -- Add run_outs signal for NCPUS=1
    SIGNAL init_done : STD_ULOGIC;
    SIGNAL init_error : STD_ULOGIC;
    -- Dummy DRAM wishbone interface (not used when USE_LITEDRAM = false)
    SIGNAL wb_dram_in : wishbone_master_out;
    SIGNAL wb_dram_out : wishbone_slave_out;
    SIGNAL wb_ext_io_in : wb_io_master_out;
    SIGNAL wb_ext_io_out : wb_io_slave_out;
    SIGNAL wb_ext_is_dram_csr : STD_ULOGIC;
    SIGNAL wb_ext_is_dram_init : STD_ULOGIC;
    function get_bram_size return natural is
    begin
        if USE_LITEDRAM and NO_BRAM then
            return 0;
        else
            return MEMORY_SIZE;
        end if;
    end function;
    function get_payload_size return natural is
    begin
        if USE_LITEDRAM and NO_BRAM then
            return MEMORY_SIZE;
        else
            return 0;
        end if;
    end function;
    
    constant BRAM_SIZE    : natural := get_bram_size;
    constant PAYLOAD_SIZE : natural := get_payload_size;
BEGIN
    -- Convert differential clock to single-ended (MUST come before BUFG)
    clk_ibufgds : IBUFGDS
    PORT MAP(
        I => ext_clk_p,
        IB => ext_clk_n,
        O => ext_clk_single
    );
    -- Clock buffering (no PLL for 125MHz passthrough)
    clk_bufg : BUFG
    PORT MAP(
        I => ext_clk_single,
        O => system_clk
    );

    -- Since we're not using a PLL, clock is always "locked"
    system_clk_locked <= '1';

    -- Use the soc_reset entity for proper reset sequencing
    reset_controller : ENTITY work.soc_reset
        GENERIC MAP(
            RESET_LOW => RESET_LOW,
            PLL_RESET_BITS => 18 -- Adjust as needed
        )
        PORT MAP(
            ext_clk => ext_clk_single,
            pll_clk => system_clk,
            pll_locked_in => system_clk_locked,
            ext_rst_in => ext_rst,
            pll_rst_out => pll_rst,
            rst_out => soc_rst
        );
    -- Heartbeat counter for LED - ~0.93Hz at 125MHz (2^27 / 125MHz)
    heartbeat_proc : PROCESS (system_clk)
    BEGIN
        IF rising_edge(system_clk) THEN
            IF soc_rst = '1' THEN
                heartbeat_counter <= (OTHERS => '0');
            ELSE
                heartbeat_counter <= heartbeat_counter + 1;
            END IF;
        END IF;
    END PROCESS;

    -- UART activity detector with timeout
    uart_activity_proc : PROCESS (system_clk)
    BEGIN
        IF rising_edge(system_clk) THEN
            IF soc_rst = '1' THEN
                uart_activity <= '0';
                uart_activity_counter <= (OTHERS => '0');
            ELSE
                 -- Detect any UART transmit activity (start bit = '0')
                IF uart0_txd = '0' THEN
                    uart_activity <= '1';
                    uart_activity_counter <= (OTHERS => '1');
                ELSIF uart_activity_counter /= 0 THEN
                    uart_activity_counter <= uart_activity_counter - 1;
                ELSE
                    uart_activity <= '0';
                END IF;
            END IF;
        END IF;
    END PROCESS;

    -- Debug LED assignments
    debug_led0 <= heartbeat_counter(27); -- Heartbeat - proves clock works
    debug_led1 <= NOT soc_rst; -- ON when system running (not in reset)
    debug_led2 <= soc_run_outs(0); -- SoC run status
    debug_led3 <= uart_activity; -- UART activity indicator
    debug_led4 <= init_done; -- Always '1' for no-DRAM config
    debug_led5 <= init_error; -- Always '0' for no-DRAM config

    -- Conditional DDR4 Generation
    no_litedram_gen : IF NOT USE_LITEDRAM GENERATE

        init_done <= '1';
        init_error <= '0';
        wb_dram_out.dat <= (OTHERS => '0');
        wb_dram_out.ack <= '0';
        wb_dram_out.stall <= '0';
        wb_ext_io_out.dat <= (OTHERS => '0');
        wb_ext_io_out.ack <= '0';
        wb_ext_io_out.stall <= '0';
        wb_ext_is_dram_csr <= '0';
        wb_ext_is_dram_init <= '0';

    END GENERATE no_litedram_gen;

    -- Main SoC
    soc0 : ENTITY work.soc
        GENERIC MAP(
            MEMORY_SIZE => BRAM_SIZE,
            RAM_INIT_FILE => RAM_INIT_FILE,
            HAS_SPI_FLASH => false,
            SIM => false,
            NCPUS => 1,
            CLK_FREQ => CLK_FREQUENCY,
            HAS_FPU => HAS_FPU,
            HAS_BTC => HAS_BTC,
            HAS_DRAM => USE_LITEDRAM,
            DRAM_SIZE => DRAM_SIZE,
            DRAM_INIT_SIZE => 0, -- No DRAM init when not using LiteDRAM
            ICACHE_NUM_LINES => ICACHE_NUM_LINES,
            LOG_LENGTH => LOG_LENGTH,
            DISABLE_FLATTEN_CORE => DISABLE_FLATTEN_CORE,
            UART0_IS_16550 => UART_IS_16550,
            HAS_UART1 => false
            
        )
        PORT MAP(
            system_clk => system_clk,
            rst => soc_rst,
            uart0_txd => uart0_txd,
            uart0_rxd => uart0_rxd,
            -- DRAM wishbone (not used but needs to be connected)
            wb_dram_in => wb_dram_in,
            wb_dram_out => wb_dram_out,
            wb_ext_io_in => wb_ext_io_in,
            wb_ext_io_out => wb_ext_io_out,
            wb_ext_is_dram_csr => wb_ext_is_dram_csr,
            wb_ext_is_dram_init => wb_ext_is_dram_init,
            -- Run status output
            run_outs => soc_run_outs
        );

END ARCHITECTURE behaviour;