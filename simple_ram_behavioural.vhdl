library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;
use work.simple_ram_behavioural_helpers.all;

entity mw_soc_memory is
    generic (
        RAM_INIT_FILE : string;
        MEMORY_SIZE   : integer
        );

    port (
        clk          : in std_ulogic;
        rst          : in std_ulogic;

        wishbone_in  : in wishbone_master_out;
        wishbone_out : out wishbone_slave_out
        );
end mw_soc_memory;

architecture behave of mw_soc_memory is
    type wishbone_state_t is (IDLE, ACK);

    signal state      : wishbone_state_t := IDLE;
    signal ret_ack    : std_ulogic := '0';
    signal identifier : integer := behavioural_initialize(filename => RAM_INIT_FILE, size => MEMORY_SIZE);
    signal reload     : integer := 0;
begin
    wishbone_process: process(clk)
        variable ret_dat: std_ulogic_vector(63 downto 0) := (others => '0');
	variable adr: std_ulogic_vector(63 downto 0);
    begin
        wishbone_out.ack <= ret_ack and wishbone_in.cyc and wishbone_in.stb;
        wishbone_out.dat <= ret_dat;

        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                ret_ack <= '0';
            else
                ret_dat := x"FFFFFFFFFFFFFFFF";

                -- Active
                if wishbone_in.cyc = '1' then
                    case state is
                        when IDLE =>
                            if wishbone_in.stb = '1' then
                                -- write
				adr := (wishbone_in.adr'left downto 0 => wishbone_in.adr, others => '0');
                                if wishbone_in.we = '1' then
                                    assert not(is_x(wishbone_in.dat)) and not(is_x(wishbone_in.adr)) severity failure;
                                    report "RAM writing " & to_hstring(wishbone_in.dat) & " to " & to_hstring(wishbone_in.adr);
                                    behavioural_write(wishbone_in.dat, adr, to_integer(unsigned(wishbone_in.sel)), identifier);
                                    reload <= reload + 1;
                                    ret_ack <= '1';
                                    state <= ACK;
                                else
                                    behavioural_read(ret_dat, adr, to_integer(unsigned(wishbone_in.sel)), identifier, reload);
                                    report "RAM reading from " & to_hstring(wishbone_in.adr) & " returns " & to_hstring(ret_dat);
                                    ret_ack <= '1';
                                    state <= ACK;
                                end if;
                            end if;
                        when ACK =>
                            ret_ack <= '0';
                            state <= IDLE;
                    end case;
                else
                    ret_ack <= '0';
                    state <= IDLE;
                end if;
            end if;
        end if;
    end process;
end behave;
