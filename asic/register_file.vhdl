library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity register_file is
    generic (
        SIM        : boolean := false;
        HAS_FPU    : boolean := true;
        LOG_LENGTH : natural := 0
        );
    port(
        clk           : in std_logic;

        d_in          : in Decode2ToRegisterFileType;
        d_out         : out RegisterFileToDecode2Type;

        w_in          : in WritebackToRegisterFileType;

        dbg_gpr_req   : in std_ulogic;
        dbg_gpr_ack   : out std_ulogic;
        dbg_gpr_addr  : in gspr_index_t;
        dbg_gpr_data  : out std_ulogic_vector(63 downto 0);

        sim_dump      : in std_ulogic;
        sim_dump_done : out std_ulogic;

        log_out       : out std_ulogic_vector(71 downto 0)
        );
end entity register_file;

architecture behaviour of register_file is
    component Microwatt_FP_DFFRFile port (
        CLK : in std_ulogic;

        R1  : in std_ulogic_vector(6 downto 0);
        R2  : in std_ulogic_vector(6 downto 0);
        R3  : in std_ulogic_vector(6 downto 0);

        D1  : out std_ulogic_vector(63 downto 0);
        D2  : out std_ulogic_vector(63 downto 0);
        D3  : out std_ulogic_vector(63 downto 0);

        WE  : in std_ulogic;
        RW  : in std_ulogic_vector(6 downto 0);
        DW  : in std_ulogic_vector(63 downto 0)
    );
    end component;

    signal d1: std_ulogic_vector(63 downto 0);
    signal d2: std_ulogic_vector(63 downto 0);
    signal d3: std_ulogic_vector(63 downto 0);
begin

    register_file_0 : Microwatt_FP_DFFRFile
        port map (
            CLK => clk,

            R1  => d_in.read1_reg,
            R2  => d_in.read2_reg,
            R3  => d_in.read3_reg,

            D1  => d1,
            D2  => d2,
            D3  => d3,

            WE  => w_in.write_enable,
            RW  => w_in.write_reg,
            DW  => w_in.write_data
            );

    x_state_check: process(clk)
    begin
        if rising_edge(clk) then
            if w_in.write_enable = '1' then
                assert not(is_x(w_in.write_data)) and not(is_x(w_in.write_reg)) severity failure;
            end if;
        end if;
    end process x_state_check;

    -- Forward any written data
    register_read_0: process(all)
    begin
        d_out.read1_data <= d1;
        d_out.read2_data <= d2;
        d_out.read3_data <= d3;

        if w_in.write_enable = '1' then
            if d_in.read1_reg = w_in.write_reg then
                d_out.read1_data <= w_in.write_data;
            end if;
            if d_in.read2_reg = w_in.write_reg then
                d_out.read2_data <= w_in.write_data;
            end if;
            if d_in.read3_reg = w_in.write_reg then
                d_out.read3_data <= w_in.write_data;
            end if;
        end if;
    end process register_read_0;

end architecture behaviour;
