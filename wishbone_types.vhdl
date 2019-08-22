library ieee;
use ieee.std_logic_1164.all;

package wishbone_types is
	constant wishbone_addr_bits : integer := 64;
	constant wishbone_data_bits : integer := 64;

	subtype wishbone_addr_type is std_ulogic_vector(wishbone_addr_bits-1 downto 0);
	subtype wishbone_data_type is std_ulogic_vector(wishbone_data_bits-1 downto 0);

	type wishbone_master_out is record
		adr : wishbone_addr_type;
		dat : wishbone_data_type;
		cyc : std_ulogic;
		stb : std_ulogic;
		sel : std_ulogic_vector(7 downto 0);
		we  : std_ulogic;
	end record wishbone_master_out;
	constant wishbone_master_out_init : wishbone_master_out := (cyc => '0', stb => '0', we => '0', others => (others => '0'));

	type wishbone_slave_out is record
		dat : wishbone_data_type;
		ack : std_ulogic;
	end record wishbone_slave_out;
	constant wishbone_slave_out_init : wishbone_slave_out := (ack => '0', others => (others => '0'));

end package wishbone_types;
