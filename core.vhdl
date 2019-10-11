library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity core is
    generic (
        SIM : boolean := false
        );
    port (
        clk          : in std_logic;
        rst          : in std_logic;

        wishbone_insn_in  : in wishbone_slave_out;
        wishbone_insn_out : out wishbone_master_out;

        wishbone_data_in  : in wishbone_slave_out;
        wishbone_data_out : out wishbone_master_out;

	dmi_addr	: in std_ulogic_vector(3 downto 0);
	dmi_din	        : in std_ulogic_vector(63 downto 0);
	dmi_dout	: out std_ulogic_vector(63 downto 0);
	dmi_req	        : in std_ulogic;
	dmi_wr		: in std_ulogic;
	dmi_ack	        : out std_ulogic;

	terminated_out   : out std_logic
        );
end core;

architecture behave of core is
    -- fetch signals
    signal fetch2_to_decode1: Fetch2ToDecode1Type;

    -- icache signals
    signal fetch1_to_icache : Fetch1ToIcacheType;
    signal icache_to_fetch2 : IcacheToFetch2Type;

    -- decode signals
    signal decode1_to_decode2: Decode1ToDecode2Type;
    signal decode2_to_execute1: Decode2ToExecute1Type;

    -- register file signals
    signal register_file_to_decode2: RegisterFileToDecode2Type;
    signal decode2_to_register_file: Decode2ToRegisterFileType;
    signal writeback_to_register_file: WritebackToRegisterFileType;

    -- CR file signals
    signal decode2_to_cr_file: Decode2ToCrFileType;
    signal cr_file_to_decode2: CrFileToDecode2Type;
    signal writeback_to_cr_file: WritebackToCrFileType;

    -- execute signals
    signal execute1_to_execute2: Execute1ToExecute2Type;
    signal execute2_to_writeback: Execute2ToWritebackType;
    signal execute1_to_fetch1: Execute1ToFetch1Type;

    -- load store signals
    signal decode2_to_loadstore1: Decode2ToLoadstore1Type;
    signal loadstore1_to_loadstore2: Loadstore1ToLoadstore2Type;
    signal loadstore2_to_writeback: Loadstore2ToWritebackType;

    -- multiply signals
    signal decode2_to_multiply: Decode2ToMultiplyType;
    signal multiply_to_writeback: MultiplyToWritebackType;

    -- divider signals
    signal decode2_to_divider: Decode2ToDividerType;
    signal divider_to_writeback: DividerToWritebackType;

    -- local signals
    signal fetch1_stall_in : std_ulogic;
    signal icache_stall_out : std_ulogic;
    signal fetch2_stall_in : std_ulogic;
    signal decode1_stall_in : std_ulogic;
    signal decode2_stall_out : std_ulogic;

    signal flush: std_ulogic;

    signal complete: std_ulogic;
    signal terminate: std_ulogic;
    signal core_rst: std_ulogic;
    signal icache_rst: std_ulogic;

    -- Debug actions
    signal dbg_core_stop: std_ulogic;
    signal dbg_core_rst: std_ulogic;
    signal dbg_icache_rst: std_ulogic;

    -- Debug status
    signal dbg_core_is_stopped: std_ulogic;

begin

    core_rst <= dbg_core_rst or rst;

    fetch1_0: entity work.fetch1
        generic map (
            RESET_ADDRESS => (others => '0')
            )
        port map (
            clk => clk,
            rst => core_rst,
            stall_in => fetch1_stall_in,
            flush_in => flush,
	    stop_in => dbg_core_stop,
            e_in => execute1_to_fetch1,
            i_out => fetch1_to_icache
            );

    fetch1_stall_in <= icache_stall_out or decode2_stall_out;

    icache_0: entity work.icache
        generic map(
            LINE_SIZE => 64,
            NUM_LINES => 16,
	    NUM_WAYS => 2
            )
        port map(
            clk => clk,
            rst => icache_rst,
            i_in => fetch1_to_icache,
            i_out => icache_to_fetch2,
            flush_in => flush,
	    stall_out => icache_stall_out,
            wishbone_out => wishbone_insn_out,
            wishbone_in => wishbone_insn_in
            );

    icache_rst <= rst or dbg_icache_rst;

    fetch2_0: entity work.fetch2
        port map (
            clk => clk,
            rst => core_rst,
            stall_in => fetch2_stall_in,
            flush_in => flush,
            i_in => icache_to_fetch2,
            f_out => fetch2_to_decode1
            );

    fetch2_stall_in <= decode2_stall_out;

    decode1_0: entity work.decode1
        port map (
            clk => clk,
            rst => core_rst,
            stall_in => decode1_stall_in,
            flush_in => flush,
            f_in => fetch2_to_decode1,
            d_out => decode1_to_decode2
            );

    decode1_stall_in <= decode2_stall_out;

    decode2_0: entity work.decode2
        port map (
            clk => clk,
            rst => core_rst,
            stall_out => decode2_stall_out,
            flush_in => flush,
            complete_in => complete,
	    stopped_out => dbg_core_is_stopped,
            d_in => decode1_to_decode2,
            e_out => decode2_to_execute1,
            l_out => decode2_to_loadstore1,
            m_out => decode2_to_multiply,
            d_out => decode2_to_divider,
            r_in => register_file_to_decode2,
            r_out => decode2_to_register_file,
            c_in => cr_file_to_decode2,
            c_out => decode2_to_cr_file
            );

    register_file_0: entity work.register_file
        generic map (
            SIM => SIM
            )
        port map (
            clk => clk,
            d_in => decode2_to_register_file,
            d_out => register_file_to_decode2,
            w_in => writeback_to_register_file,
	    sim_dump => terminate
	    );

    cr_file_0: entity work.cr_file
        port map (
            clk => clk,
            d_in => decode2_to_cr_file,
            d_out => cr_file_to_decode2,
            w_in => writeback_to_cr_file
            );

    execute1_0: entity work.execute1
        generic map (
            SIM => SIM
            )
        port map (
            clk => clk,
            flush_out => flush,
            e_in => decode2_to_execute1,
            f_out => execute1_to_fetch1,
            e_out => execute1_to_execute2,
            terminate_out => terminate
            );

    execute2_0: entity work.execute2
        port map (
            clk => clk,
            e_in => execute1_to_execute2,
            e_out => execute2_to_writeback
            );

    loadstore1_0: entity work.loadstore1
        port map (
            clk => clk,
            l_in => decode2_to_loadstore1,
            l_out => loadstore1_to_loadstore2
            );

    loadstore2_0: entity work.loadstore2
        port map (
            clk => clk,
            l_in => loadstore1_to_loadstore2,
            w_out => loadstore2_to_writeback,
            m_in => wishbone_data_in,
            m_out => wishbone_data_out
            );

    multiply_0: entity work.multiply
        port map (
            clk => clk,
            m_in => decode2_to_multiply,
            m_out => multiply_to_writeback
            );

    divider_0: entity work.divider
        port map (
            clk => clk,
            rst => core_rst,
            d_in => decode2_to_divider,
            d_out => divider_to_writeback
            );

    writeback_0: entity work.writeback
        port map (
            clk => clk,
            e_in => execute2_to_writeback,
            l_in => loadstore2_to_writeback,
            m_in => multiply_to_writeback,
            d_in => divider_to_writeback,
            w_out => writeback_to_register_file,
            c_out => writeback_to_cr_file,
            complete_out => complete
            );

    debug_0: entity work.core_debug
	port map (
	    clk => clk,
	    rst => rst,
	    dmi_addr => dmi_addr,
	    dmi_din => dmi_din,
	    dmi_dout => dmi_dout,
	    dmi_req => dmi_req,
	    dmi_wr => dmi_wr,
	    dmi_ack => dmi_ack,
	    core_stop => dbg_core_stop,
	    core_rst => dbg_core_rst,
	    icache_rst => dbg_icache_rst,
	    terminate => terminate,
	    core_stopped => dbg_core_is_stopped,
	    nia => fetch1_to_icache.nia,
	    terminated_out => terminated_out
	    );

end behave;
