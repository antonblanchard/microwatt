library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity register_file is
    generic (
        SIM : boolean := false;
        HAS_FPU : boolean := true;
        -- Non-zero to enable log data collection
        LOG_LENGTH : natural := 0
        );
    port(
        clk           : in std_logic;
        stall         : in std_ulogic;

        d1_in         : in Decode1ToRegisterFileType;
        d_in          : in Decode2ToRegisterFileType;
        d_out         : out RegisterFileToDecode2Type;

        w_in          : in WritebackToRegisterFileType;

        dbg_gpr_req   : in std_ulogic;
        dbg_gpr_ack   : out std_ulogic;
        dbg_gpr_addr  : in gspr_index_t;
        dbg_gpr_data  : out std_ulogic_vector(63 downto 0);

        -- debug
        sim_dump      : in std_ulogic;
        sim_dump_done : out std_ulogic;

        log_out       : out std_ulogic_vector(71 downto 0)
        );
end entity register_file;

architecture behaviour of register_file is
    component Microwatt_FP_DFFRFile port (
        CLK : in std_ulogic;

        R1  : in std_ulogic_vector(5 downto 0);
        R2  : in std_ulogic_vector(5 downto 0);
        R3  : in std_ulogic_vector(5 downto 0);

        D1  : out std_ulogic_vector(63 downto 0);
        D2  : out std_ulogic_vector(63 downto 0);
        D3  : out std_ulogic_vector(63 downto 0);

        WE  : in std_ulogic;
        RW  : in std_ulogic_vector(5 downto 0);
        DW  : in std_ulogic_vector(63 downto 0)
    );
    end component;

    signal addr_1_reg : gspr_index_t;
    signal addr_2_reg : gspr_index_t;
    signal addr_3_reg : gspr_index_t;
    signal addr_1_stalled: gspr_index_t;
    signal addr_2_stalled: gspr_index_t;
    signal addr_3_stalled: gspr_index_t;
    signal fwd_1 : std_ulogic;
    signal fwd_2 : std_ulogic;
    signal fwd_3 : std_ulogic;
    signal data_1 : std_ulogic_vector(63 downto 0);
    signal data_2 : std_ulogic_vector(63 downto 0);
    signal data_3 : std_ulogic_vector(63 downto 0);
    signal prev_write_data : std_ulogic_vector(63 downto 0);

begin
    register_file_0 : Microwatt_FP_DFFRFile
        port map (
            CLK => clk,

            R1  => addr_1_stalled,
            R2  => addr_2_stalled,
            R3  => addr_3_stalled,

            D1  => data_1,
            D2  => data_2,
            D3  => data_3,

            WE  => w_in.write_enable,
            RW  => w_in.write_reg,
            DW  => w_in.write_data
            );

    -- asynchronous handling of stall signal
     addr_1_stalled <= addr_1_reg when stall = '1' else d1_in.reg_1_addr;
     addr_2_stalled <= addr_2_reg when stall = '1' else d1_in.reg_2_addr;
     addr_3_stalled <= addr_3_reg when stall = '1' else d1_in.reg_3_addr;

    -- synchronous reads and writes
    register_write_0: process(clk)
        variable a_addr, b_addr, c_addr : gspr_index_t;
        variable w_addr : gspr_index_t;
    begin
        if rising_edge(clk) then
            if w_in.write_enable = '1' then
                w_addr := w_in.write_reg;
                if w_addr(5) = '1' then
                    report "Writing FPR " & to_hstring(w_addr(4 downto 0)) & " " & to_hstring(w_in.write_data);
                else
                    report "Writing GPR " & to_hstring(w_addr) & " " & to_hstring(w_in.write_data);
                end if;
                assert not(is_x(w_in.write_data)) and not(is_x(w_in.write_reg)) severity failure;
            end if;

            a_addr := d1_in.reg_1_addr;
            b_addr := d1_in.reg_2_addr;
            c_addr := d1_in.reg_3_addr;
            if stall = '1' then
                a_addr := addr_1_reg;
                b_addr := addr_2_reg;
                c_addr := addr_3_reg;
            else
                addr_1_reg <= a_addr;
                addr_2_reg <= b_addr;
                addr_3_reg <= c_addr;
            end if;

            fwd_1 <= '0';
            fwd_2 <= '0';
            fwd_3 <= '0';
            if w_in.write_enable = '1' then
                if w_addr = a_addr then
                    fwd_1 <= '1';
                end if;
                if w_addr = b_addr then
                    fwd_2 <= '1';
                end if;
                if w_addr = c_addr then
                    fwd_3 <= '1';
                end if;
            end if;

            prev_write_data <= w_in.write_data;
        end if;
    end process register_write_0;

    -- asynchronous forwarding of write data
    register_read_0: process(all)
        variable out_data_1 : std_ulogic_vector(63 downto 0);
        variable out_data_2 : std_ulogic_vector(63 downto 0);
        variable out_data_3 : std_ulogic_vector(63 downto 0);
    begin
        out_data_1 := data_1;
        out_data_2 := data_2;
        out_data_3 := data_3;
        if fwd_1 = '1' then
            out_data_1 := prev_write_data;
        end if;
        if fwd_2 = '1' then
            out_data_2 := prev_write_data;
        end if;
        if fwd_3 = '1' then
            out_data_3 := prev_write_data;
        end if;

        if d_in.read1_enable = '1' then
            report "Reading GPR " & to_hstring(addr_1_reg) & " " & to_hstring(out_data_1);
        end if;
        if d_in.read2_enable = '1' then
            report "Reading GPR " & to_hstring(addr_2_reg) & " " & to_hstring(out_data_2);
        end if;
        if d_in.read3_enable = '1' then
            report "Reading GPR " & to_hstring(addr_3_reg) & " " & to_hstring(out_data_3);
        end if;

        d_out.read1_data <= out_data_1;
        d_out.read2_data <= out_data_2;
        d_out.read3_data <= out_data_3;
    end process register_read_0;

    dbg_gpr_ack <= '0';
    dbg_gpr_data <= (others => '0');
    sim_dump_done <= '0';
    log_out <= (others => '0');

end architecture behaviour;
