library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;
use work.sim_console.all;

entity litedram_wrapper is
    generic (
	DRAM_ABITS     : positive;
	DRAM_ALINES    : positive
	);
    port(
	-- LiteDRAM generates the system clock and reset
	-- from the input clkin
	clk_in          : in std_ulogic;
	rst             : in std_ulogic;
	system_clk      : out std_ulogic;
	system_reset    : out std_ulogic;
	core_alt_reset  : out std_ulogic;
	pll_locked      : out std_ulogic;

	-- Wishbone ports:
	wb_in           : in wishbone_master_out;
	wb_out          : out wishbone_slave_out;
	wb_ctrl_in      : in wb_io_master_out;
	wb_ctrl_out     : out wb_io_slave_out;
	wb_ctrl_is_csr  : in std_ulogic;
	wb_ctrl_is_init : in std_ulogic;

	-- Init core serial debug
	serial_tx     : out std_ulogic;
	serial_rx     : in std_ulogic;

	-- Misc
	init_done     : out std_ulogic;
	init_error    : out std_ulogic;

	-- DRAM wires
	ddram_a       : out std_ulogic_vector(DRAM_ALINES-1 downto 0);
	ddram_ba      : out std_ulogic_vector(2 downto 0);
	ddram_ras_n   : out std_ulogic;
	ddram_cas_n   : out std_ulogic;
	ddram_we_n    : out std_ulogic;
	ddram_cs_n    : out std_ulogic;
	ddram_dm      : out std_ulogic_vector(1 downto 0);
	ddram_dq      : inout std_ulogic_vector(15 downto 0);
	ddram_dqs_p   : inout std_ulogic_vector(1 downto 0);
	ddram_dqs_n   : inout std_ulogic_vector(1 downto 0);
	ddram_clk_p   : out std_ulogic;
	ddram_clk_n   : out std_ulogic;
	ddram_cke     : out std_ulogic;
	ddram_odt     : out std_ulogic;
	ddram_reset_n : out std_ulogic
	);
end entity litedram_wrapper;

architecture behaviour of litedram_wrapper is

    component litedram_core port (
	clk                            : in std_ulogic;
	rst                            : in std_ulogic;
	pll_locked                     : out std_ulogic;
	ddram_a                        : out std_ulogic_vector(DRAM_ALINES-1 downto 0);
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
	user_port_native_0_cmd_addr    : in std_ulogic_vector(DRAM_ABITS-1 downto 0);
	user_port_native_0_wdata_valid : in std_ulogic;
	user_port_native_0_wdata_ready : out std_ulogic;
	user_port_native_0_wdata_we    : in std_ulogic_vector(15 downto 0);
	user_port_native_0_wdata_data  : in std_ulogic_vector(127 downto 0);
	user_port_native_0_rdata_valid : out std_ulogic;
	user_port_native_0_rdata_ready : in std_ulogic;
	user_port_native_0_rdata_data  : out std_ulogic_vector(127 downto 0)
	);
    end component;
    
    signal user_port0_cmd_valid		: std_ulogic;
    signal user_port0_cmd_ready		: std_ulogic;
    signal user_port0_cmd_we		: std_ulogic;
    signal user_port0_cmd_addr		: std_ulogic_vector(DRAM_ABITS-1 downto 0);
    signal user_port0_wdata_valid	: std_ulogic;
    signal user_port0_wdata_ready	: std_ulogic;
    signal user_port0_wdata_we		: std_ulogic_vector(15 downto 0);
    signal user_port0_wdata_data	: std_ulogic_vector(127 downto 0);
    signal user_port0_rdata_valid	: std_ulogic;
    signal user_port0_rdata_ready	: std_ulogic;
    signal user_port0_rdata_data	: std_ulogic_vector(127 downto 0);

    signal ad3                          : std_ulogic;

    signal wb_ctrl_adr                  : std_ulogic_vector(29 downto 0);
    signal wb_ctrl_dat_w                : std_ulogic_vector(31 downto 0);
    signal wb_ctrl_dat_r                : std_ulogic_vector(31 downto 0);
    signal wb_ctrl_sel                  : std_ulogic_vector(3 downto 0);
    signal wb_ctrl_cyc                  : std_ulogic;
    signal wb_ctrl_stb                  : std_ulogic;
    signal wb_ctrl_ack                  : std_ulogic;
    signal wb_ctrl_we                   : std_ulogic;

    signal wb_init_in                   : wb_io_master_out;
    signal wb_init_out                  : wb_io_slave_out;

    type state_t is (CMD, MWRITE, MREAD);
    signal state : state_t;

    constant INIT_RAM_SIZE : integer := 16384;
    constant INIT_RAM_ABITS :integer := 14;
    constant INIT_RAM_FILE : string := "litedram_core.init";

    type ram_t is array(0 to (INIT_RAM_SIZE / 4) - 1) of std_logic_vector(31 downto 0);

    impure function init_load_ram(name : string) return ram_t is
	file ram_file : text open read_mode is name;
	variable temp_word : std_logic_vector(63 downto 0);
	variable temp_ram : ram_t := (others => (others => '0'));
	variable ram_line : line;
    begin
	for i in 0 to (INIT_RAM_SIZE/8)-1 loop
	    exit when endfile(ram_file);
	    readline(ram_file, ram_line);
	    hread(ram_line, temp_word);
	    temp_ram(i*2) := temp_word(31 downto 0);
	    temp_ram(i*2+1) := temp_word(63 downto 32);
	end loop;
	return temp_ram;
    end function;

    signal init_ram : ram_t := init_load_ram(INIT_RAM_FILE);

    attribute ram_style : string;
    attribute ram_style of init_ram: signal is "block";

begin

    -- alternate core reset address set when DRAM is not initialized.
    core_alt_reset <= not init_done;

    -- BRAM Memory slave. TODO: Pipeline it with an output buffer
    -- to improve timing
    init_ram_0: process(system_clk)
	variable adr : integer;
    begin
	if rising_edge(system_clk) then
	    wb_init_out.ack <= '0';
	    if (wb_init_in.cyc and wb_init_in.stb) = '1' then
		adr := to_integer((unsigned(wb_init_in.adr(INIT_RAM_ABITS-1 downto 2))));
		if wb_init_in.we = '0' then
		    wb_init_out.dat <= init_ram(adr);
		else
		    for i in 0 to 3 loop
			if wb_init_in.sel(i) = '1' then
			    init_ram(adr)(((i + 1) * 8) - 1 downto i * 8) <=
				wb_init_in.dat(((i + 1) * 8) - 1 downto i * 8);
			end if;
		    end loop;
		end if;
		wb_init_out.ack <= '1';
	    end if;
	end if;
    end process;

    --
    -- Control bus wishbone: This muxes the wishbone to the CSRs
    -- and an internal small one to the init BRAM
    --

    -- Init DRAM wishbone IN signals
    wb_init_in.adr <= wb_ctrl_in.adr;
    wb_init_in.dat <= wb_ctrl_in.dat;
    wb_init_in.sel <= wb_ctrl_in.sel;
    wb_init_in.we  <= wb_ctrl_in.we;
    wb_init_in.stb <= wb_ctrl_in.stb;
    wb_init_in.cyc <= wb_ctrl_in.cyc and wb_ctrl_is_init;

    -- DRAM CSR IN signals
    wb_ctrl_adr   <= x"0000" & wb_ctrl_in.adr(15 downto 2);
    wb_ctrl_dat_w <= wb_ctrl_in.dat;
    wb_ctrl_sel   <= wb_ctrl_in.sel;
    wb_ctrl_we    <= wb_ctrl_in.we;
    wb_ctrl_cyc   <= wb_ctrl_in.cyc and wb_ctrl_is_csr;
    wb_ctrl_stb   <= wb_ctrl_in.stb and wb_ctrl_is_csr;

    -- Ctrl bus wishbone OUT signals
    wb_ctrl_out.ack   <= wb_ctrl_ack when wb_ctrl_is_csr = '1'
                         else wb_init_out.ack;
    wb_ctrl_out.dat   <= wb_ctrl_dat_r when wb_ctrl_is_csr = '1'
                         else wb_init_out.dat;
    wb_ctrl_out.stall <= wb_init_out.stall when wb_ctrl_is_init else
                         '0' when wb_ctrl_in.cyc = '0' else not wb_ctrl_ack;

    --
    -- Data bus wishbone to LiteDRAM native port
    --
    -- Address bit 3 selects the top or bottom half of the data
    -- bus (64-bit wishbone vs. 128-bit DRAM interface)
    --
    -- XXX TODO: Figure out how to pipeline this
    --
    ad3 <= wb_in.adr(3);

    -- Wishbone port IN signals
    user_port0_cmd_valid   <= wb_in.cyc and wb_in.stb when state = CMD else '0';
    user_port0_cmd_we      <= wb_in.we when state = CMD else '0';
    user_port0_wdata_valid <= '1' when state = MWRITE else '0';
    user_port0_rdata_ready <= '1' when state = MREAD else '0';
    user_port0_cmd_addr    <= wb_in.adr(DRAM_ABITS+3 downto 4);
    user_port0_wdata_data  <= wb_in.dat & wb_in.dat;
    user_port0_wdata_we    <= wb_in.sel & "00000000" when ad3 = '1' else
                              "00000000" & wb_in.sel;

    -- Wishbone OUT signals
    wb_out.ack <= user_port0_wdata_ready when state = MWRITE else
		  user_port0_rdata_valid when state = MREAD else '0';

    wb_out.dat <= user_port0_rdata_data(127 downto 64) when ad3 = '1' else
		  user_port0_rdata_data(63 downto 0);

    -- We don't do pipelining yet.
    wb_out.stall <= '0' when wb_in.cyc = '0' else not wb_out.ack;

    -- DRAM user port State machine
    sm: process(system_clk)
    begin
	
	if rising_edge(system_clk) then
	    if system_reset = '1' then
		state <= CMD;
	    else
		case state is
		when CMD =>
                    if (user_port0_cmd_ready and user_port0_cmd_valid) = '1' then
			state <= MWRITE when wb_in.we = '1' else MREAD;
		    end if;
		when MWRITE =>
		    if user_port0_wdata_ready = '1' then
			state <= CMD;
		    end if;
		when MREAD =>
		    if user_port0_rdata_valid = '1' then
			state <= CMD;
		    end if;
                end case;
	    end if;
	end if;
    end process;

    litedram: litedram_core
	port map(
	    clk => clk_in,
	    rst => rst,
	    pll_locked => pll_locked,
	    ddram_a => ddram_a,
	    ddram_ba => ddram_ba,
	    ddram_ras_n => ddram_ras_n,
	    ddram_cas_n => ddram_cas_n,
	    ddram_we_n => ddram_we_n,
	    ddram_cs_n => ddram_cs_n,
	    ddram_dm => ddram_dm,
	    ddram_dq => ddram_dq,
	    ddram_dqs_p => ddram_dqs_p,
	    ddram_dqs_n => ddram_dqs_n,
	    ddram_clk_p => ddram_clk_p,
	    ddram_clk_n => ddram_clk_n,
	    ddram_cke => ddram_cke,
	    ddram_odt => ddram_odt,
	    ddram_reset_n => ddram_reset_n,
	    init_done => init_done,
	    init_error => init_error,
	    user_clk => system_clk,
	    user_rst => system_reset,
            wb_ctrl_adr => wb_ctrl_adr,
            wb_ctrl_dat_w => wb_ctrl_dat_w,
            wb_ctrl_dat_r => wb_ctrl_dat_r,
            wb_ctrl_sel => wb_ctrl_sel,
            wb_ctrl_cyc => wb_ctrl_cyc,
            wb_ctrl_stb => wb_ctrl_stb,
            wb_ctrl_ack => wb_ctrl_ack,
            wb_ctrl_we => wb_ctrl_we,
            wb_ctrl_cti => "000",
            wb_ctrl_bte => "00",
            wb_ctrl_err => open,
	    user_port_native_0_cmd_valid => user_port0_cmd_valid,
	    user_port_native_0_cmd_ready => user_port0_cmd_ready,
	    user_port_native_0_cmd_we => user_port0_cmd_we,
	    user_port_native_0_cmd_addr => user_port0_cmd_addr,
	    user_port_native_0_wdata_valid => user_port0_wdata_valid,
	    user_port_native_0_wdata_ready => user_port0_wdata_ready,
	    user_port_native_0_wdata_we => user_port0_wdata_we,
	    user_port_native_0_wdata_data => user_port0_wdata_data,
	    user_port_native_0_rdata_valid => user_port0_rdata_valid,
	    user_port_native_0_rdata_ready => user_port0_rdata_ready,
	    user_port_native_0_rdata_data => user_port0_rdata_data
	    );

end architecture behaviour;
