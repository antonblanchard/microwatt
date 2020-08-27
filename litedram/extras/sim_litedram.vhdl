library ieee;
use ieee.std_logic_1164.all;

package sim_litedram is
    -- WB req format:
    -- 73 .. 71 : cti(2..0)
    -- 70 .. 69 : bte(1..0)
    -- 68 .. 65 : sel(3..0)
    -- 64       : we
    -- 63       : stb
    -- 62       : cyc
    -- 61 .. 32 : addr(29..0)
    -- 31 ..  0 : write_data(31..0)
    --
    procedure litedram_set_wb(req : in std_ulogic_vector(73 downto 0));
    attribute foreign of litedram_set_wb : procedure is "VHPIDIRECT litedram_set_wb";

    -- WB rsp format:
    -- 35       : init_error;
    -- 34       : init_done;
    -- 33       : err
    -- 32       : ack
    -- 31 ..  0 : read_data(31..0)
    --
    procedure litedram_get_wb(rsp : out std_ulogic_vector(35 downto 0));
    attribute foreign of litedram_get_wb : procedure is "VHPIDIRECT litedram_get_wb";

    -- User req format:
    -- 171        : cmd_valid
    -- 170        : cmd_we
    -- 169        : wdata_valid
    -- 168        : rdata_ready
    -- 167 .. 144 : cmd_addr(23..0)
    -- 143 .. 128 : wdata_we(15..0)
    -- 127 ..   0 : wdata_data(127..0)
    --
    procedure litedram_set_user(req: in std_ulogic_vector(171 downto 0));
    attribute foreign of litedram_set_user : procedure is "VHPIDIRECT litedram_set_user";

    -- User rsp format:
    -- 130        : cmd_ready
    -- 129        : wdata_ready
    -- 128        : rdata_valid
    -- 127 ..   0 : rdata_data(127..0)
    
    procedure litedram_get_user(req: in std_ulogic_vector(130 downto 0));
    attribute foreign of litedram_get_user : procedure is "VHPIDIRECT litedram_get_user";
    
    procedure litedram_clock;
    attribute foreign of litedram_clock : procedure is "VHPIDIRECT litedram_clock";

    procedure litedram_init(trace: integer);
    attribute foreign of litedram_init : procedure is "VHPIDIRECT litedram_init";
end sim_litedram;

package body sim_litedram is
    procedure litedram_set_wb(req : in  std_ulogic_vector(73 downto 0)) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
    procedure litedram_get_wb(rsp : out std_ulogic_vector(35 downto 0)) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
    procedure litedram_set_user(req: in std_ulogic_vector(171 downto 0)) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
    procedure litedram_get_user(req: in std_ulogic_vector(130 downto 0)) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
    procedure litedram_clock is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
    procedure litedram_init(trace: integer) is
    begin
        assert false report "VHPI" severity failure;
    end procedure;
end sim_litedram;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.sim_litedram.all;

entity litedram_core is
    port(
	clk                            : in std_ulogic;
	rst                            : in std_ulogic;
	pll_locked                     : out std_ulogic;
	ddram_a                        : out std_ulogic_vector(0 downto 0);
	ddram_ba                       : out std_ulogic_vector(2 downto 0);
	ddram_ras_n                    : out std_ulogic;
	ddram_cas_n                    : out std_ulogic;
	ddram_we_n                     : out std_ulogic;
	ddram_cs_n                     : out std_ulogic;
	ddram_dm                       : out std_ulogic_vector(1 downto 0);
	ddram_dq                       : inout std_ulogic_vector(15 downto 0);
	ddram_dqs_p                    : inout std_ulogic_vector(1 downto 0);
	ddram_dqs_n                    : inout std_ulogic_vector(1 downto 0);
	ddram_clk_p                    : out std_ulogic;
	ddram_clk_n                    : out std_ulogic;
	ddram_cke                      : out std_ulogic;
	ddram_odt                      : out std_ulogic;
	ddram_reset_n                  : out std_ulogic;
	init_done                      : out std_ulogic;
	init_error                     : out std_ulogic;
	user_clk                       : out std_ulogic;
	user_rst                       : out std_ulogic;
	wb_ctrl_adr                    : in std_ulogic_vector(29 downto 0);
	wb_ctrl_dat_w                  : in std_ulogic_vector(31 downto 0);
	wb_ctrl_dat_r                  : out std_ulogic_vector(31 downto 0);
	wb_ctrl_sel                    : in std_ulogic_vector(3 downto 0);
	wb_ctrl_cyc                    : in std_ulogic;
	wb_ctrl_stb                    : in std_ulogic;
	wb_ctrl_ack                    : out std_ulogic;
	wb_ctrl_we                     : in std_ulogic;
	wb_ctrl_cti                    : in std_ulogic_vector(2 downto 0);
	wb_ctrl_bte                    : in std_ulogic_vector(1 downto 0);
	wb_ctrl_err                    : out std_ulogic;
	user_port_native_0_cmd_valid   : in std_ulogic;
	user_port_native_0_cmd_ready   : out std_ulogic;
	user_port_native_0_cmd_we      : in std_ulogic;
	user_port_native_0_cmd_addr    : in std_ulogic_vector(23 downto 0);
	user_port_native_0_wdata_valid : in std_ulogic;
	user_port_native_0_wdata_ready : out std_ulogic;
	user_port_native_0_wdata_we    : in std_ulogic_vector(15 downto 0);
	user_port_native_0_wdata_data  : in std_ulogic_vector(127 downto 0);
	user_port_native_0_rdata_valid : out std_ulogic;
	user_port_native_0_rdata_ready : in std_ulogic;
	user_port_native_0_rdata_data  : out std_ulogic_vector(127 downto 0)
        );
end entity litedram_core;

architecture behaviour of litedram_core is
    signal idone      : std_ulogic := '0';
    signal ierr       : std_ulogic := '0';
    signal old_wb_cyc : std_ulogic := '1';
begin
    user_rst <= rst;
    user_clk <= clk;
    pll_locked <= '1';
    init_done <= idone;
    init_error <= ierr;

    poll: process(user_clk)
        procedure send_signals is
        begin
            litedram_set_wb(wb_ctrl_cti & wb_ctrl_bte &
                            wb_ctrl_sel & wb_ctrl_we &
                            wb_ctrl_stb & wb_ctrl_cyc &
                            wb_ctrl_adr & wb_ctrl_dat_w);
            litedram_set_user(user_port_native_0_cmd_valid &
                              user_port_native_0_cmd_we &
                              user_port_native_0_wdata_valid &
                              user_port_native_0_rdata_ready &
                              user_port_native_0_cmd_addr &
                              user_port_native_0_wdata_we &
                              user_port_native_0_wdata_data);
        end procedure;

        procedure recv_signals is
            variable wb_response  : std_ulogic_vector(35 downto 0);
            variable ur_response  : std_ulogic_vector(130 downto 0);
        begin
            litedram_get_wb(wb_response);
            wb_ctrl_dat_r <= wb_response(31 downto 0);
            wb_ctrl_ack   <= wb_response(32);
            wb_ctrl_err   <= wb_response(33);
            idone         <= wb_response(34);
            ierr          <= wb_response(35);
            litedram_get_user(ur_response);
            user_port_native_0_cmd_ready   <= ur_response(130);
            user_port_native_0_wdata_ready <= ur_response(129);
            user_port_native_0_rdata_valid <= ur_response(128);
            user_port_native_0_rdata_data  <= ur_response(127 downto 0);
        end procedure;

    begin
        if rising_edge(user_clk) then

            send_signals;
            recv_signals;
            -- Then generate a clock cycle ( 0->1 then 1->0 )
            litedram_clock;
            recv_signals;
        end if;

        if falling_edge(user_clk) then
            send_signals;
            recv_signals;
        end if;
    end process;

end architecture;

library work;
use work.sim_litedram.all;

entity litedram_trace_stub is
end entity;

architecture behaviour of litedram_trace_stub is
begin
    process
    begin
        litedram_init(1);
        wait;
    end process;
end architecture;
