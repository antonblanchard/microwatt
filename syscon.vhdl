-- syscon module, a bunch of misc global system control MMIO registers
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;

entity syscon is
    generic (
	SIG_VALUE     : std_ulogic_vector(63 downto 0) := x"f00daa5500010001";
	CLK_FREQ      : integer;
	HAS_UART      : boolean;
	HAS_DRAM      : boolean;
	BRAM_SIZE     : integer;
	DRAM_SIZE     : integer
	);
    port (
	clk : in std_ulogic;
	rst : in std_ulogic;

	-- Wishbone ports:
	wishbone_in : in wb_io_master_out;
	wishbone_out : out wb_io_slave_out;

	-- System control ports
	dram_at_0  : out std_ulogic;
	core_reset : out std_ulogic;
	soc_reset  : out std_ulogic
	);
end entity syscon;


architecture behaviour of syscon is
    -- Register address bits
    constant SYS_REG_BITS       : positive := 3;

    -- Register addresses (matches wishbone addr downto 3, ie, 8 bytes per reg)
    constant SYS_REG_SIG	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "000";
    constant SYS_REG_INFO	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "001";
    constant SYS_REG_BRAMINFO	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "010";
    constant SYS_REG_DRAMINFO	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "011";
    constant SYS_REG_CLKINFO	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "100";
    constant SYS_REG_CTRL	: std_ulogic_vector(SYS_REG_BITS-1 downto 0) := "101";

    -- Muxed reg read signal
    signal reg_out	: std_ulogic_vector(63 downto 0);

    -- INFO register bits
    constant SYS_REG_INFO_HAS_UART    : integer := 0;
    constant SYS_REG_INFO_HAS_DRAM    : integer := 1;

    -- BRAMINFO contains the BRAM size in the bottom 52 bits
    -- DRAMINFO contains the DRAM size if any in the bottom 52 bits
    -- (both have reserved top bits for future use)
    -- CLKINFO contains the CLK frequency is HZ in the bottom 40 bits

    -- CTRL register bits
    constant SYS_REG_CTRL_BITS       : positive := 3;
    constant SYS_REG_CTRL_DRAM_AT_0  : integer := 0;
    constant SYS_REG_CTRL_CORE_RESET : integer := 1;
    constant SYS_REG_CTRL_SOC_RESET  : integer := 2;

    -- Ctrl register
    signal reg_ctrl	: std_ulogic_vector(SYS_REG_CTRL_BITS-1 downto 0);
    signal reg_ctrl_out	: std_ulogic_vector(63 downto 0);

    -- Others
    signal reg_info      : std_ulogic_vector(63 downto 0);
    signal reg_braminfo  : std_ulogic_vector(63 downto 0);
    signal reg_draminfo  : std_ulogic_vector(63 downto 0);
    signal reg_clkinfo   : std_ulogic_vector(63 downto 0);
    signal info_has_dram : std_ulogic;
    signal info_has_uart : std_ulogic;
    signal info_clk      : std_ulogic_vector(39 downto 0);
begin

    -- Generated output signals
    dram_at_0 <= reg_ctrl(SYS_REG_CTRL_DRAM_AT_0);
    soc_reset <= reg_ctrl(SYS_REG_CTRL_SOC_RESET);
    core_reset <= reg_ctrl(SYS_REG_CTRL_CORE_RESET);

    -- All register accesses are single cycle
    wishbone_out.ack <= wishbone_in.cyc and wishbone_in.stb;
    wishbone_out.stall <= '0';

    -- Info register is hard wired
    info_has_uart <= '1' when HAS_UART else '0';
    info_has_dram <= '1' when HAS_DRAM else '0';
    info_clk <= std_ulogic_vector(to_unsigned(CLK_FREQ, 40));
    reg_info <= (0 => info_has_uart,
		 1 => info_has_dram,
		 others => '0');
    reg_braminfo <= x"000" & std_ulogic_vector(to_unsigned(BRAM_SIZE, 52));
    reg_draminfo <= x"000" & std_ulogic_vector(to_unsigned(DRAM_SIZE, 52)) when HAS_DRAM
		    else (others => '0');
    reg_clkinfo <= (39 downto 0 => info_clk,
		    others => '0');

    -- Control register read composition
    reg_ctrl_out <= (63 downto SYS_REG_CTRL_BITS => '0',
		    SYS_REG_CTRL_BITS-1 downto 0 => reg_ctrl);

    -- Register read mux
    with wishbone_in.adr(SYS_REG_BITS+2 downto 3) select reg_out <=
	SIG_VALUE	when SYS_REG_SIG,
	reg_info        when SYS_REG_INFO,
	reg_braminfo    when SYS_REG_BRAMINFO,
	reg_draminfo    when SYS_REG_DRAMINFO,
	reg_clkinfo     when SYS_REG_CLKINFO,
	reg_ctrl_out	when SYS_REG_CTRL,
	(others => '0') when others;
    wishbone_out.dat <= reg_out(63 downto 32) when wishbone_in.adr(2) = '1' else
                        reg_out(31 downto 0);

    -- Register writes
    regs_write: process(clk)
    begin
	if rising_edge(clk) then
	    if (rst) then
		reg_ctrl <= (others => '0');
	    else
		if wishbone_in.cyc and wishbone_in.stb and wishbone_in.we then
                    -- Change this if CTRL ever has more than 32 bits
		    if wishbone_in.adr(SYS_REG_BITS+2 downto 3) = SYS_REG_CTRL and
                        wishbone_in.adr(2) = '0' then
			reg_ctrl(SYS_REG_CTRL_BITS-1 downto 0) <=
			    wishbone_in.dat(SYS_REG_CTRL_BITS-1 downto 0);
		    end if;
		end if;

                -- Reset auto-clear
                if reg_ctrl(SYS_REG_CTRL_SOC_RESET) = '1' then
                    reg_ctrl(SYS_REG_CTRL_SOC_RESET) <= '0';
                end if;
                if reg_ctrl(SYS_REG_CTRL_CORE_RESET) = '1' then
                    reg_ctrl(SYS_REG_CTRL_CORE_RESET) <= '0';
                end if;
	    end if;
	end if;
    end process;

end architecture behaviour;
