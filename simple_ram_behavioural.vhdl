library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

library work;
use work.wishbone_types.all;
use work.simple_ram_behavioural_helpers.all;

entity mw_soc_memory is
    generic (
        RAM_INIT_FILE  : string;
        MEMORY_SIZE    : integer;
	PIPELINE_DEPTH : integer := 0
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
    signal ret_dat    : wishbone_data_type;

    subtype pipe_idx_t is integer range 0 to PIPELINE_DEPTH-1;
    type pipe_ack_t is array(pipe_idx_t) of std_ulogic;
    type pipe_dat_t is array(pipe_idx_t) of wishbone_data_type;
begin

    pipe_big: if PIPELINE_DEPTH > 1 generate
	signal pipe_ack : pipe_ack_t;
	signal pipe_dat : pipe_dat_t;
    begin
	wishbone_out.stall <= '0';
	wishbone_out.ack <= pipe_ack(0);
	wishbone_out.dat <= pipe_dat(0);

	pipe_big_sync: process(clk)
	begin	
	    if rising_edge(clk) then
		pipe_stages: for i in 0 to PIPELINE_DEPTH-2 loop
		    pipe_ack(i) <= pipe_ack(i+1);
		    pipe_dat(i) <= pipe_dat(i+1);
		end loop;
		pipe_ack(PIPELINE_DEPTH-1) <= ret_ack;
		pipe_dat(PIPELINE_DEPTH-1) <= ret_dat;
	    end if;
	end process;
    end generate;

    pipe_one: if PIPELINE_DEPTH = 1 generate
	signal pipe_ack : std_ulogic;
	signal pipe_dat : wishbone_data_type;
    begin
	wishbone_out.stall <= '0';
	wishbone_out.ack <= pipe_ack;
	wishbone_out.dat <= pipe_dat;

	pipe_one_sync: process(clk)
	begin
	    if rising_edge(clk) then
		pipe_ack <= ret_ack;
		pipe_dat <= ret_dat;
	    end if;
	end process;
    end generate;

    pipe_none: if PIPELINE_DEPTH = 0 generate
    begin
	wishbone_out.ack <= ret_ack;
	wishbone_out.dat <= ret_dat;
	wishbone_out.stall <= wishbone_in.cyc and not ret_ack;
    end generate;
    
    wishbone_process: process(clk)
	variable ret_dat_v : wishbone_data_type;
	variable adr       : std_ulogic_vector(63 downto 0);
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state <= IDLE;
                ret_ack <= '0';
            else
                ret_dat <= x"FFFFFFFFFFFFFFFF";
		ret_ack <= '0';

                -- Active
                if wishbone_in.cyc = '1' then
                    case state is
                        when IDLE =>
                            if wishbone_in.stb = '1' then
				adr := (wishbone_in.adr'left downto 0 => wishbone_in.adr,
					others => '0');
                                -- write
                                if wishbone_in.we = '1' then
                                    assert not(is_x(wishbone_in.dat)) and not(is_x(wishbone_in.adr)) severity failure;
                                    report "RAM writing " & to_hstring(wishbone_in.dat) & " to " & to_hstring(wishbone_in.adr);
                                    behavioural_write(wishbone_in.dat, adr, to_integer(unsigned(wishbone_in.sel)), identifier);
                                    reload <= reload + 1;
                                    ret_ack <= '1';
				    if PIPELINE_DEPTH = 0 then
					state <= ACK;
				    end if;
                                else
                                    behavioural_read(ret_dat_v, adr, to_integer(unsigned(wishbone_in.sel)), identifier, reload);
                                    report "RAM reading from " & to_hstring(wishbone_in.adr) & " returns " & to_hstring(ret_dat_v);
				    ret_dat <= ret_dat_v;
                                    ret_ack <= '1';
				    if PIPELINE_DEPTH = 0 then
					state <= ACK;
				    end if;
                                end if;
                            end if;
                        when ACK =>
                            state <= IDLE;
                    end case;
                else
                    state <= IDLE;
                end if;
            end if;
        end if;
    end process;
end behave;
