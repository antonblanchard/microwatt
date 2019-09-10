library IEEE;
use IEEE.std_logic_1164.all;

package vcomponents is

    -- Global JTAG signals. Xilinx implementation hooks that up to
    -- their internal JTAG tap, we just expose them for the testbench
    -- to use. These are used by our BSCANE2 block.
    --
    type glob_jtag_t is record
	reset	: std_logic;
	tck	: std_logic;
	tdo	: std_logic;
	tdi	: std_logic;
	tms	: std_logic;
	sel	: std_logic_vector(4 downto 1);
	capture	: std_logic;
	shift	: std_logic;
	update	: std_logic;
	runtest : std_logic;
    end record glob_jtag_t;
    signal glob_jtag : glob_jtag_t;

    component BSCANE2 is
	generic(jtag_chain: integer);
	port(capture	: out std_logic;
	     drck	: out std_logic;
	     reset	: out std_logic;
	     runtest	: out std_logic;
	     sel	: out std_logic;
	     shift	: out std_logic;
	     tck	: out std_logic;
	     tdi	: out std_logic;
	     tms	: out std_logic;
	     update	: out std_logic;
	     tdo	: in std_logic
	     );
    end component BSCANE2;
    
    component BUFG is
	port(I	: in std_logic;
	     O	: out std_logic
	     );
    end component BUFG;
end package vcomponents;
