library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.wishbone_types.all;

entity fetch2 is
	port(
		clk          : in std_ulogic;
		rst          : in std_ulogic;

		stall_in     : in std_ulogic;
		stall_out    : out std_ulogic;

		flush_in     : in std_ulogic;

		-- instruction memory interface
		wishbone_in  : in wishbone_slave_out;
		wishbone_out : out wishbone_master_out;

		f_in         : in Fetch1ToFetch2Type;

		f_out        : out Fetch2ToDecode1Type
	);
end entity fetch2;

architecture behaviour of fetch2 is
	type state_type is (IDLE, JUST_IDLE, WAIT_ACK, WAIT_ACK_THROWAWAY);

	type reg_internal_type is record
		state     : state_type;
		nia       : std_ulogic_vector(63 downto 0);
		w         : wishbone_master_out;
		-- Trivial 64B cache
		cache     : std_ulogic_vector(63 downto 0);
		tag       : std_ulogic_vector(60 downto 0);
		tag_valid : std_ulogic;
	end record;

	function wishbone_fetch(nia : std_ulogic_vector(63 downto 0)) return wishbone_master_out is
		variable w : wishbone_master_out;
	begin
		assert nia(2 downto 0) = "000";

		w.adr := nia;
		w.dat := (others => '0');
		w.cyc := '1';
		w.stb := '1';
		w.sel := "11111111";
		w.we  := '0';

		return w;
	end;

	signal r, rin         : Fetch2ToDecode1Type;
	signal r_int, rin_int : reg_internal_type;
begin
	regs : process(clk)
	begin
		if rising_edge(clk) then
			-- Output state remains unchanged on stall, unless we are flushing
			if rst = '1' or flush_in = '1' or stall_in = '0' then
				r <= rin;
			end if;
			r_int <= rin_int;
		end if;
	end process;

	comb : process(all)
		variable v     : Fetch2ToDecode1Type;
		variable v_int : reg_internal_type;
	begin
		v := r;
		v_int := r_int;

		v.valid := '0';
		v.nia := f_in.nia;

		case v_int.state is
		when IDLE | JUST_IDLE =>
			v_int.state := IDLE;

			if (v_int.tag_valid = '1') and (v_int.tag = f_in.nia(63 downto 3)) then
				v.valid := '1';
				if f_in.nia(2) = '0' then
					v.insn := v_int.cache(31 downto 0);
				else
					v.insn := v_int.cache(63 downto 32);
				end if;
			else
				v_int.state := WAIT_ACK;
				v_int.nia := f_in.nia;
				v_int.w := wishbone_fetch(f_in.nia(63 downto 3) & "000");
			end if;

		when WAIT_ACK =>
			if wishbone_in.ack = '1' then
				v_int.state := IDLE;
				v_int.w := wishbone_master_out_init;
				v_int.cache := wishbone_in.dat;
				v_int.tag := v_int.nia(63 downto 3);
				v_int.tag_valid := '1';

				v.valid := '1';
				if v_int.nia(2) = '0' then
					v.insn := v_int.cache(31 downto 0);
				else
					v.insn := v_int.cache(63 downto 32);
				end if;
			end if;

		when WAIT_ACK_THROWAWAY =>
			if wishbone_in.ack = '1' then
				-- Should we put the returned data in the cache? We went to the
				-- trouble of fetching it and it might be useful in the future

				v_int.w := wishbone_master_out_init;

				-- We need to stall fetch1 for one more cycle, so transition through JUST_IDLE
				v_int.state := JUST_IDLE;
			end if;
		end case;

		stall_out <= '0';
		if v_int.state /= IDLE then
			stall_out <= '1';
		end if;

		if flush_in = '1' then
			v.valid := '0';

			-- Throw away in flight data
			if v_int.state = WAIT_ACK then
				v_int.state := WAIT_ACK_THROWAWAY;
			end if;
		end if;

		if rst = '1' then
			v := Fetch2ToDecode1Init;

			v_int.state := IDLE;
			v_int.nia := (others => '0');
			v_int.w := wishbone_master_out_init;
			v_int.cache := (others => '0');
			v_int.tag := (others => '0');
			v_int.tag_valid := '0';
		end if;

		-- Update registers
		rin_int <= v_int;
		rin <= v;

		-- Update outputs
		f_out <= r;
		wishbone_out <= r_int.w;
	end process;
end architecture behaviour;
