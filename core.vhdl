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

        -- Added for debug, ghdl doesn't support external names unfortunately
        registers     : out regfile;
        terminate_out : out std_ulogic
        );
end core;

architecture behave of core is
    -- fetch signals
    signal fetch1_to_fetch2: Fetch1ToFetch2Type;
    signal fetch2_to_decode1: Fetch2ToDecode1Type;

    -- icache signals
    signal fetch2_to_icache : Fetch2ToIcacheType;
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

    -- local signals
    signal fetch1_stall_in : std_ulogic;
    signal fetch2_stall_in : std_ulogic;
    signal fetch2_stall_out : std_ulogic;
    signal decode1_stall_in : std_ulogic;
    signal decode2_stall_out : std_ulogic;

    signal flush: std_ulogic;

    signal complete: std_ulogic;

    signal terminate: std_ulogic;
begin

    terminate_out <= terminate;

    fetch1_0: entity work.fetch1
        generic map (
            RESET_ADDRESS => (others => '0')
            )
        port map (
            clk => clk,
            rst => rst,
            stall_in => fetch1_stall_in,
            flush_in => flush,
            e_in => execute1_to_fetch1,
            f_out => fetch1_to_fetch2
            );

    fetch1_stall_in <= fetch2_stall_out or decode2_stall_out;

    fetch2_0: entity work.fetch2
        port map (
            clk => clk,
            rst => rst,
            stall_in => fetch2_stall_in,
            stall_out => fetch2_stall_out,
            flush_in => flush,
            i_in => icache_to_fetch2,
            i_out => fetch2_to_icache,
            f_in => fetch1_to_fetch2,
            f_out => fetch2_to_decode1
            );

    fetch2_stall_in <= decode2_stall_out;

    icache_0: entity work.icache
        generic map(
            LINE_SIZE_DW => 8,
            NUM_LINES => 16
            )
        port map(
            clk => clk,
            rst => rst,
            i_in => fetch2_to_icache,
            i_out => icache_to_fetch2,
            wishbone_out => wishbone_insn_out,
            wishbone_in => wishbone_insn_in
            );

    decode1_0: entity work.decode1
        port map (
            clk => clk,
            rst => rst,
            stall_in => decode1_stall_in,
            flush_in => flush,
            f_in => fetch2_to_decode1,
            d_out => decode1_to_decode2
            );

    decode1_stall_in <= decode2_stall_out;

    decode2_0: entity work.decode2
        port map (
            clk => clk,
            rst => rst,
            stall_out => decode2_stall_out,
            flush_in => flush,
            complete_in => complete,
            d_in => decode1_to_decode2,
            e_out => decode2_to_execute1,
            l_out => decode2_to_loadstore1,
            m_out => decode2_to_multiply,
            r_in => register_file_to_decode2,
            r_out => decode2_to_register_file,
            c_in => cr_file_to_decode2,
            c_out => decode2_to_cr_file
            );

    register_file_0: entity work.register_file
        port map (
            clk => clk,
            d_in => decode2_to_register_file,
            d_out => register_file_to_decode2,
            w_in => writeback_to_register_file,
            registers_out => registers);

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

    writeback_0: entity work.writeback
        port map (
            clk => clk,
            e_in => execute2_to_writeback,
            l_in => loadstore2_to_writeback,
            m_in => multiply_to_writeback,
            w_out => writeback_to_register_file,
            c_out => writeback_to_cr_file,
            complete_out => complete
            );

end behave;
