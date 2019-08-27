-- Sim console UART, provides the same interface as potato UART by
-- Kristian Klomsten Skordal.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;
use work.sim_console.all;

--! @brief Simple UART module.
--! The following registers are defined:
--! |--------------------|--------------------------------------------|
--! | Address            | Description                                |
--! |--------------------|--------------------------------------------|
--! | 0x00               | Transmit register (write-only)             |
--! | 0x08               | Receive register (read-only)               |
--! | 0x10               | Status register (read-only)                |
--! | 0x18               | Sample clock divisor register (dummy)      |
--! | 0x20               | Interrupt enable register (read/write)     |
--! |--------------------|--------------------------------------------|
--!
--! The status register contains the following bits:
--! - Bit 0: receive buffer empty
--! - Bit 1: transmit buffer empty
--! - Bit 2: receive buffer full
--! - Bit 3: transmit buffer full
--!
--! Interrupts are enabled by setting the corresponding bit in the interrupt
--! enable register. The following bits are available:
--! - Bit 0: data received (receive buffer not empty)
--! - Bit 1: ready to send data (transmit buffer empty)
entity sim_uart is
    port(
	clk : in std_logic;
	reset : in std_logic;

	-- Wishbone ports:
	wishbone_in : in wishbone_master_out;
	wishbone_out : out wishbone_slave_out
	);
end entity sim_uart;

architecture behaviour of sim_uart is

    signal sample_clk_divisor : std_logic_vector(7 downto 0);

    -- IRQ enable signals:
    signal irq_recv_enable, irq_tx_ready_enable : std_logic := '0';

    -- Wishbone signals:
    type wb_state_type is (IDLE, WRITE_ACK, READ_ACK);
    signal wb_state : wb_state_type;
    signal wb_ack : std_logic; --! Wishbone acknowledge signal

begin

    wishbone_out.ack <= wb_ack and wishbone_in.cyc and wishbone_in.stb;

    wishbone: process(clk)
	variable sim_tmp : std_logic_vector(63 downto 0);
    begin
	if rising_edge(clk) then
	    if reset = '1' then
		wb_ack <= '0';
		wb_state <= IDLE;
		sample_clk_divisor <= (others => '0');
		irq_recv_enable <= '0';
		irq_tx_ready_enable <= '0';
	    else
		case wb_state is
		when IDLE =>
		    if wishbone_in.cyc = '1' and wishbone_in.stb = '1' then
			if wishbone_in.we = '1' then -- Write to register
			    if wishbone_in.adr(11 downto 0) = x"000" then
				report "FOO !";
				sim_console_write(wishbone_in.dat);
			    elsif wishbone_in.adr(11 downto 0) = x"018" then
				sample_clk_divisor <= wishbone_in.dat(7 downto 0);
			    elsif wishbone_in.adr(11 downto 0) = x"020" then
				irq_recv_enable <= wishbone_in.dat(0);
				irq_tx_ready_enable <= wishbone_in.dat(1);
			    end if;
			    wb_ack <= '1';
			    wb_state <= WRITE_ACK;
			else -- Read from register
			    if wishbone_in.adr(11 downto 0) = x"008" then
				sim_console_read(sim_tmp);
				wishbone_out.dat <= sim_tmp;
			    elsif wishbone_in.adr(11 downto 0) = x"010" then
				sim_console_poll(sim_tmp);
				wishbone_out.dat <= x"000000000000000" & '0' &
						    sim_tmp(0) & '1' & not sim_tmp(0);
			    elsif wishbone_in.adr(11 downto 0) = x"018" then
				wishbone_out.dat <= x"00000000000000" & sample_clk_divisor;
			    elsif wishbone_in.adr(11 downto 0) = x"020" then
				wishbone_out.dat <= (0 => irq_recv_enable,
						     1 => irq_tx_ready_enable,
						     others => '0');
			    else
				wishbone_out.dat <= (others => '0');
			    end if;
			    wb_ack <= '1';
			    wb_state <= READ_ACK;
			end if;
		    end if;
		when WRITE_ACK|READ_ACK =>
		    if wishbone_in.stb = '0' then
			wb_ack <= '0';
			wb_state <= IDLE;
		    end if;
		end case;
	    end if;
	end if;
	end process wishbone;

end architecture behaviour;
