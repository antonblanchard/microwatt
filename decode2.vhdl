library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.insn_helpers.all;

entity decode2 is
	port (
		clk   : in std_ulogic;
		rst   : in std_ulogic;

		complete_in : in std_ulogic;
		stall_out : out std_ulogic;

		stopped_out : out std_ulogic;

		flush_in: in std_ulogic;

		d_in  : in Decode1ToDecode2Type;

		e_out : out Decode2ToExecute1Type;
		m_out : out Decode2ToMultiplyType;
                d_out : out Decode2ToDividerType;
		l_out : out Decode2ToLoadstore1Type;

		r_in  : in RegisterFileToDecode2Type;
		r_out : out Decode2ToRegisterFileType;

		c_in  : in CrFileToDecode2Type;
		c_out : out Decode2ToCrFileType
	);
end entity decode2;

architecture behaviour of decode2 is
	type state_type is (IDLE, WAIT_FOR_PREV_TO_COMPLETE, WAIT_FOR_CURR_TO_COMPLETE);

	type reg_internal_type is record
		state : state_type;
		outstanding : integer;
	end record;

	type reg_type is record
		e : Decode2ToExecute1Type;
		m : Decode2ToMultiplyType;
                d : Decode2ToDividerType;
		l : Decode2ToLoadstore1Type;
	end record;

	signal r_int, rin_int : reg_internal_type;
	signal r, rin : reg_type;

	type decode_input_reg_t is record
		reg_valid : std_ulogic;
		reg       : std_ulogic_vector(4 downto 0);
		data      : std_ulogic_vector(63 downto 0);
	end record;

	function decode_input_reg_a (t : input_reg_a_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		if t = RA or (t = RA_OR_ZERO and insn_ra(insn_in) /= "00000") then
			return ('1', insn_ra(insn_in), reg_data);
		else
			return ('0', (others => '0'), (others => '0'));
		end if;
	end;

	function decode_input_reg_b (t : input_reg_b_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		case t is
		when RB =>
			return ('1', insn_rb(insn_in), reg_data);
		when CONST_UI =>
			return ('0', (others => '0'), std_ulogic_vector(resize(unsigned(insn_ui(insn_in)), 64)));
		when CONST_SI =>
			return ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_si(insn_in)), 64)));
		when CONST_SI_HI =>
			return ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_si(insn_in)) & x"0000", 64)));
		when CONST_UI_HI =>
			return ('0', (others => '0'), std_ulogic_vector(resize(unsigned(insn_si(insn_in)) & x"0000", 64)));
		when CONST_LI =>
			return ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_li(insn_in)) & "00", 64)));
		when CONST_BD =>
			return ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_bd(insn_in)) & "00", 64)));
		when CONST_DS =>
			return ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_ds(insn_in)) & "00", 64)));
                when CONST_M1 =>
                        return ('0', (others => '0'), x"FFFFFFFFFFFFFFFF");
		when NONE =>
			return ('0', (others => '0'), (others => '0'));
		end case;
	end;

	function decode_input_reg_c (t : input_reg_c_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		case t is
		when RS =>
			return ('1', insn_rs(insn_in), reg_data);
		when NONE =>
			return ('0', (others => '0'), (others => '0'));
		end case;
	end;

	function decode_output_reg (t : output_reg_a_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
	begin
		case t is
		when RT =>
			return insn_rt(insn_in);
		when RA =>
			return insn_ra(insn_in);
		when NONE =>
			return "00000";
		end case;
	end;

	function decode_rc (t : rc_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic is
	begin
		case t is
		when RC =>
			return insn_rc(insn_in);
		when ONE =>
			return '1';
		when NONE =>
			return '0';
		end case;
	end;
begin

	decode2_0: process(clk)
	begin
		if rising_edge(clk) then
			assert r_int.outstanding <= 1 report "Outstanding bad " & integer'image(r_int.outstanding) severity failure;

			if rin.e.valid = '1' or rin.l.valid = '1' or rin.m.valid = '1' or rin.d.valid = '1' then
				report "execute " & to_hstring(rin.e.nia);
			end if;
			r <= rin;
			r_int <= rin_int;
		end if;
	end process;

	r_out.read1_reg <= insn_ra(d_in.insn);
	r_out.read2_reg <= insn_rb(d_in.insn);
	r_out.read3_reg <= insn_rs(d_in.insn);

	c_out.read <= d_in.decode.input_cr;

	decode2_1: process(all)
		variable v : reg_type;
		variable v_int : reg_internal_type;
		variable mul_a : std_ulogic_vector(63 downto 0);
		variable mul_b : std_ulogic_vector(63 downto 0);
		variable decoded_reg_a : decode_input_reg_t;
		variable decoded_reg_b : decode_input_reg_t;
		variable decoded_reg_c : decode_input_reg_t;
                variable signed_division: std_ulogic;
		variable is_valid : std_ulogic;
	begin
		v := r;
		v_int := r_int;

		v.e := Decode2ToExecute1Init;
		v.l := Decode2ToLoadStore1Init;
		v.m := Decode2ToMultiplyInit;
                v.d := Decode2ToDividerInit;

		mul_a := (others => '0');
		mul_b := (others => '0');

		--v.e.input_cr := d_in.decode.input_cr;
		--v.m.input_cr := d_in.decode.input_cr;
		--v.e.output_cr := d_in.decode.output_cr;

		decoded_reg_a := decode_input_reg_a (d_in.decode.input_reg_a, d_in.insn, r_in.read1_data);
		decoded_reg_b := decode_input_reg_b (d_in.decode.input_reg_b, d_in.insn, r_in.read2_data);
		decoded_reg_c := decode_input_reg_c (d_in.decode.input_reg_c, d_in.insn, r_in.read3_data);

		r_out.read1_enable <= decoded_reg_a.reg_valid;
		r_out.read2_enable <= decoded_reg_b.reg_valid;
		r_out.read3_enable <= decoded_reg_c.reg_valid;

		-- execute unit
		v.e.nia := d_in.nia;
		v.e.insn_type := d_in.decode.insn_type;
		v.e.read_reg1 := decoded_reg_a.reg;
		v.e.read_data1 := decoded_reg_a.data;
		v.e.read_reg2 := decoded_reg_b.reg;
		v.e.read_data2 := decoded_reg_b.data;
                v.e.read_data3 := decoded_reg_c.data;
		v.e.write_reg := decode_output_reg(d_in.decode.output_reg_a, d_in.insn);
		v.e.rc := decode_rc(d_in.decode.rc, d_in.insn);
		v.e.cr := c_in.read_cr_data;
                v.e.invert_a := d_in.decode.invert_a;
		v.e.input_carry := d_in.decode.input_carry;
		v.e.output_carry := d_in.decode.output_carry;
		if d_in.decode.lr = '1' then
			v.e.lr := insn_lk(d_in.insn);
		end if;
                v.e.insn := d_in.insn;

		-- multiply unit
		v.m.insn_type := d_in.decode.insn_type;
		mul_a := decoded_reg_a.data;
		mul_b := decoded_reg_b.data;
		v.m.write_reg := decode_output_reg(d_in.decode.output_reg_a, d_in.insn);
		v.m.rc := decode_rc(d_in.decode.rc, d_in.insn);

		if d_in.decode.mul_32bit = '1' then
			if d_in.decode.mul_signed = '1' then
				v.m.data1 := (others => mul_a(31));
				v.m.data1(31 downto 0) := mul_a(31 downto 0);
				v.m.data2 := (others => mul_b(31));
				v.m.data2(31 downto 0) := mul_b(31 downto 0);
			else
				v.m.data1 := '0' & x"00000000" & mul_a(31 downto 0);
				v.m.data2 := '0' & x"00000000" & mul_b(31 downto 0);
			end if;
		else
			if d_in.decode.mul_signed = '1' then
				v.m.data1 := mul_a(63) & mul_a;
				v.m.data2 := mul_b(63) & mul_b;
			else
				v.m.data1 := '0' & mul_a;
				v.m.data2 := '0' & mul_b;
			end if;
		end if;

                -- divide unit
                -- PPC divide and modulus instruction words have these bits in
                -- the bottom 11 bits: o1dns 010t1 r
                -- where o = OE for div instrs, signedness for mod instrs
                --       d = 1 for div*, 0 for mod*
                --       n = 1 for normal, 0 for extended (dividend << 32/64)
                --       s = 1 for signed, 0 for unsigned (for div*)
                --       t = 1 for 32-bit, 0 for 64-bit
                --       r = RC bit (record condition code)
		v.d.write_reg := decode_output_reg(d_in.decode.output_reg_a, d_in.insn);
                v.d.is_modulus := not d_in.insn(8);
                v.d.is_32bit := not d_in.insn(2);
                if d_in.insn(8) = '1' then
                        signed_division := d_in.insn(6);
                else
                        signed_division := d_in.insn(10);
                end if;
                v.d.is_signed := signed_division;
                if d_in.insn(2) = '0' then
                        -- 64-bit forms
                        if d_in.insn(8) = '1' and d_in.insn(7) = '0' then
                                v.d.is_extended := '1';
                        end if;
                        v.d.dividend := decoded_reg_a.data;
                        v.d.divisor := decoded_reg_b.data;
                else
                        -- 32-bit forms
                        if d_in.insn(8) = '1' and d_in.insn(7) = '0' then   -- extended forms
                                v.d.dividend := decoded_reg_a.data(31 downto 0) & x"00000000";
                        elsif signed_division = '1' and decoded_reg_a.data(31) = '1' then
                                -- sign extend to 64 bits
                                v.d.dividend := x"ffffffff" & decoded_reg_a.data(31 downto 0);
                        else
                                v.d.dividend := x"00000000" & decoded_reg_a.data(31 downto 0);
                        end if;
                        if signed_division = '1' and decoded_reg_b.data(31) = '1' then
                                v.d.divisor := x"ffffffff" & decoded_reg_b.data(31 downto 0);
                        else
                                v.d.divisor := x"00000000" & decoded_reg_b.data(31 downto 0);
                        end if;
                end if;
                v.d.rc := decode_rc(d_in.decode.rc, d_in.insn);

		-- load/store unit
		v.l.update_reg := decoded_reg_a.reg;
		v.l.addr1 := decoded_reg_a.data;
		v.l.addr2 := decoded_reg_b.data;
		v.l.data := decoded_reg_c.data;
		v.l.write_reg := decode_output_reg(d_in.decode.output_reg_a, d_in.insn);

		if d_in.decode.insn_type = OP_LOAD then
			v.l.load := '1';
		else
			v.l.load := '0';
		end if;

		case d_in.decode.length is
		when is1B =>
			v.l.length := "0001";
		when is2B =>
			v.l.length := "0010";
		when is4B =>
			v.l.length := "0100";
		when is8B =>
			v.l.length := "1000";
		when NONE =>
			v.l.length := "0000";
		end case;

		v.l.byte_reverse := d_in.decode.byte_reverse;
		v.l.sign_extend := d_in.decode.sign_extend;
		v.l.update := d_in.decode.update;

		-- single issue

		if complete_in = '1' then
			v_int.outstanding := v_int.outstanding - 1;
		end if;

		-- state machine to handle instructions that must be single
		-- through the pipeline.
		stall_out <= '0';
		is_valid := d_in.valid;

		-- Handle debugger stop
		stopped_out <= '0';
		if d_in.stop_mark = '1' and v_int.outstanding = 0 then
		    stopped_out <= '1';
		end if;

		case v_int.state is
		when IDLE =>
			if (flush_in = '0') and (is_valid = '1') and (d_in.decode.sgl_pipe = '1') then
				if v_int.outstanding /= 0 then
					v_int.state := WAIT_FOR_PREV_TO_COMPLETE;
					stall_out <= '1';
					is_valid := '0';
				else
					-- send insn out and wait on it to complete
					v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
				end if;
			end if;

		when WAIT_FOR_PREV_TO_COMPLETE =>
			if v_int.outstanding = 0 then
				-- send insn out and wait on it to complete
				v_int.state := WAIT_FOR_CURR_TO_COMPLETE;
			else
				stall_out <= '1';
				is_valid := '0';
			end if;

		when WAIT_FOR_CURR_TO_COMPLETE =>
			if v_int.outstanding = 0 then
				v_int.state := IDLE;
			else
				stall_out <= '1';
				is_valid := '0';
			end if;
		end case;

		v.e.valid := '0';
		v.m.valid := '0';
                v.d.valid := '0';
		v.l.valid := '0';
		case d_in.decode.unit is
		when ALU =>
			v.e.valid := is_valid;
		when LDST =>
			v.l.valid := is_valid;
		when MUL =>
			v.m.valid := is_valid;
                when DIV =>
                        v.d.valid := is_valid;
		when NONE =>
			v.e.valid := is_valid;
			v.e.insn_type := OP_ILLEGAL;
		end case;

		if flush_in = '1' then
			v.e.valid := '0';
			v.m.valid := '0';
                        v.d.valid := '0';
			v.l.valid := '0';
		end if;

		-- track outstanding instructions
		if v.e.valid = '1' or v.l.valid = '1' or v.m.valid = '1' or v.d.valid = '1' then
			v_int.outstanding := v_int.outstanding + 1;
		end if;

		if rst = '1' then
			v_int.state := IDLE;
			v_int.outstanding := 0;
			v.e := Decode2ToExecute1Init;
			v.l := Decode2ToLoadStore1Init;
			v.m := Decode2ToMultiplyInit;
                        v.d := Decode2ToDividerInit;
		end if;

		-- Update registers
		rin <= v;
		rin_int <= v_int;

		-- Update outputs
		e_out <= r.e;
		l_out <= r.l;
		m_out <= r.m;
                d_out <= r.d;
	end process;
end architecture behaviour;
