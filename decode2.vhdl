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
		stall_in : in std_ulogic;
		stall_out : out std_ulogic;

		stopped_out : out std_ulogic;

		flush_in: in std_ulogic;

		d_in  : in Decode1ToDecode2Type;

		e_out : out Decode2ToExecute1Type;
                d_out : out Decode2ToDividerType;
		l_out : out Decode2ToLoadstore1Type;

		r_in  : in RegisterFileToDecode2Type;
		r_out : out Decode2ToRegisterFileType;

		c_in  : in CrFileToDecode2Type;
		c_out : out Decode2ToCrFileType
	);
end entity decode2;

architecture behaviour of decode2 is
	type reg_type is record
		e : Decode2ToExecute1Type;
                d : Decode2ToDividerType;
		l : Decode2ToLoadstore1Type;
	end record;

	signal r, rin : reg_type;

	type decode_input_reg_t is record
		reg_valid : std_ulogic;
		reg       : gspr_index_t;
		data      : std_ulogic_vector(63 downto 0);
	end record;

	type decode_output_reg_t is record
		reg_valid : std_ulogic;
		reg       : gspr_index_t;
	end record;

	function decode_input_reg_a (t : input_reg_a_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0);
				     ispr : gspr_index_t) return decode_input_reg_t is
	begin
		if t = RA or (t = RA_OR_ZERO and insn_ra(insn_in) /= "00000") then
		    assert is_fast_spr(ispr) = '0' report "Decode A says GPR but ISPR says SPR:" &
			to_hstring(ispr) severity failure;
		    return ('1', gpr_to_gspr(insn_ra(insn_in)), reg_data);
		elsif t = SPR then
		    -- ISPR must be either a valid fast SPR number or all 0 for a slow SPR.
		    -- If it's all 0, we don't treat it as a dependency as slow SPRs
		    -- operations are single issue.
		    --
		    assert is_fast_spr(ispr) =  '1' or ispr = "000000"
			report "Decode A says SPR but ISPR is invalid:" &
			to_hstring(ispr) severity failure;
		    return (is_fast_spr(ispr), ispr, reg_data);
		else
			return ('0', (others => '0'), (others => '0'));
		end if;
	end;

	function decode_input_reg_b (t : input_reg_b_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0);
				     ispr : gspr_index_t) return decode_input_reg_t is
	begin
		case t is
		when RB =>
		    assert is_fast_spr(ispr) = '0' report "Decode B says GPR but ISPR says SPR:" &
			to_hstring(ispr) severity failure;
		    return ('1', gpr_to_gspr(insn_rb(insn_in)), reg_data);
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
		when CONST_SH =>
			return ('0', (others => '0'), x"00000000000000" & "00" & insn_in(1) & insn_in(15 downto 11));
		when CONST_SH32 =>
			return ('0', (others => '0'), x"00000000000000" & "000" & insn_in(15 downto 11));
		when SPR =>
		    -- ISPR must be either a valid fast SPR number or all 0 for a slow SPR.
		    -- If it's all 0, we don't treat it as a dependency as slow SPRs
		    -- operations are single issue.
		    assert is_fast_spr(ispr) = '1' or ispr = "000000"
			report "Decode B says SPR but ISPR is invalid:" &
			to_hstring(ispr) severity failure;
		    return (is_fast_spr(ispr), ispr, reg_data);
		when NONE =>
			return ('0', (others => '0'), (others => '0'));
		end case;
	end;

	function decode_input_reg_c (t : input_reg_c_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		case t is
		when RS =>
			return ('1', gpr_to_gspr(insn_rs(insn_in)), reg_data);
		when NONE =>
			return ('0', (others => '0'), (others => '0'));
		end case;
	end;

	function decode_output_reg (t : output_reg_a_t; insn_in : std_ulogic_vector(31 downto 0);
				    ispr : gspr_index_t) return decode_output_reg_t is
	begin
		case t is
		when RT =>
		    return ('1', gpr_to_gspr(insn_rt(insn_in)));
		when RA =>
		    return ('1', gpr_to_gspr(insn_ra(insn_in)));
		when SPR =>
		    -- ISPR must be either a valid fast SPR number or all 0 for a slow SPR.
		    -- If it's all 0, we don't treat it as a dependency as slow SPRs
		    -- operations are single issue.
		    assert is_fast_spr(ispr) = '1' or ispr = "000000"
			report "Decode B says SPR but ISPR is invalid:" &
			to_hstring(ispr) severity failure;
		    return (is_fast_spr(ispr), ispr);
		when NONE =>
		    return ('0', "000000");
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

	-- For now, use "rc" in the decode table to decide whether oe exists.
	-- This is not entirely correct architecturally: For mulhd and
	-- mulhdu, the OE field is reserved. It remains to be seen what an
	-- actual POWER9 does if we set it on those instructions, for now we
	-- test that further down when assigning to the multiplier oe input.
	--
	function decode_oe (t : rc_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic is
	begin
		case t is
		when RC =>
			return insn_oe(insn_in);
		when OTHERS =>
			return '0';
		end case;
	end;

	-- issue control signals
	signal control_valid_in : std_ulogic;
	signal control_valid_out : std_ulogic;
	signal control_sgl_pipe : std_logic;

	signal gpr_write_valid : std_ulogic;
	signal gpr_write : gspr_index_t;

	signal gpr_a_read_valid : std_ulogic;
	signal gpr_a_read :gspr_index_t;

	signal gpr_b_read_valid : std_ulogic;
	signal gpr_b_read : gspr_index_t;

	signal gpr_c_read_valid : std_ulogic;
	signal gpr_c_read : gpr_index_t;

	signal cr_write_valid : std_ulogic;
begin
	control_0: entity work.control
	generic map (
		PIPELINE_DEPTH => 1
	)
	port map (
		clk         => clk,
		rst         => rst,

		complete_in => complete_in,
		valid_in    => control_valid_in,
		stall_in    => stall_in,
		flush_in    => flush_in,
		sgl_pipe_in => control_sgl_pipe,
		stop_mark_in => d_in.stop_mark,

		gpr_write_valid_in => gpr_write_valid,
		gpr_write_in       => gpr_write,

		gpr_a_read_valid_in  => gpr_a_read_valid,
		gpr_a_read_in        => gpr_a_read,

		gpr_b_read_valid_in  => gpr_b_read_valid,
		gpr_b_read_in        => gpr_b_read,

		gpr_c_read_valid_in  => gpr_c_read_valid,
		gpr_c_read_in        => gpr_c_read,

		cr_read_in           => d_in.decode.input_cr,
		cr_write_in           => cr_write_valid,

		valid_out   => control_valid_out,
		stall_out   => stall_out,
		stopped_out => stopped_out
	);

	decode2_0: process(clk)
	begin
		if rising_edge(clk) then
			if rin.e.valid = '1' or rin.l.valid = '1' or rin.d.valid = '1' then
				report "execute " & to_hstring(rin.e.nia);
			end if;
			r <= rin;
		end if;
	end process;

	r_out.read1_reg <= gpr_or_spr_to_gspr(insn_ra(d_in.insn), d_in.ispr1);
	r_out.read2_reg <= gpr_or_spr_to_gspr(insn_rb(d_in.insn), d_in.ispr2);
	r_out.read3_reg <= insn_rs(d_in.insn);

	c_out.read <= d_in.decode.input_cr;

	decode2_1: process(all)
		variable v : reg_type;
		variable mul_a : std_ulogic_vector(63 downto 0);
		variable mul_b : std_ulogic_vector(63 downto 0);
		variable decoded_reg_a : decode_input_reg_t;
		variable decoded_reg_b : decode_input_reg_t;
		variable decoded_reg_c : decode_input_reg_t;
		variable decoded_reg_o : decode_output_reg_t;
                variable signed_division: std_ulogic;
                variable length : std_ulogic_vector(3 downto 0);
	begin
		v := r;

		v.e := Decode2ToExecute1Init;
		v.l := Decode2ToLoadStore1Init;
                v.d := Decode2ToDividerInit;

		mul_a := (others => '0');
		mul_b := (others => '0');

		--v.e.input_cr := d_in.decode.input_cr;
		--v.e.output_cr := d_in.decode.output_cr;
    
		decoded_reg_a := decode_input_reg_a (d_in.decode.input_reg_a, d_in.insn, r_in.read1_data, d_in.ispr1);
		decoded_reg_b := decode_input_reg_b (d_in.decode.input_reg_b, d_in.insn, r_in.read2_data, d_in.ispr2);
		decoded_reg_c := decode_input_reg_c (d_in.decode.input_reg_c, d_in.insn, r_in.read3_data);
		decoded_reg_o := decode_output_reg (d_in.decode.output_reg_a, d_in.insn, d_in.ispr1);

		r_out.read1_enable <= decoded_reg_a.reg_valid;
		r_out.read2_enable <= decoded_reg_b.reg_valid;
		r_out.read3_enable <= decoded_reg_c.reg_valid;

		case d_in.decode.length is
		when is1B =>
			length := "0001";
		when is2B =>
			length := "0010";
		when is4B =>
			length := "0100";
		when is8B =>
			length := "1000";
		when NONE =>
			length := "0000";
		end case;

		-- execute unit
		v.e.nia := d_in.nia;
		v.e.insn_type := d_in.decode.insn_type;
		v.e.read_reg1 := decoded_reg_a.reg;
		v.e.read_data1 := decoded_reg_a.data;
		v.e.read_reg2 := decoded_reg_b.reg;
		v.e.read_data2 := decoded_reg_b.data;
                v.e.read_data3 := decoded_reg_c.data;
		v.e.write_reg := decoded_reg_o.reg;
		v.e.rc := decode_rc(d_in.decode.rc, d_in.insn);
		v.e.oe := decode_oe(d_in.decode.rc, d_in.insn);
		v.e.cr := c_in.read_cr_data;
		v.e.xerc := c_in.read_xerc_data;
                v.e.invert_a := d_in.decode.invert_a;
                v.e.invert_out := d_in.decode.invert_out;
		v.e.input_carry := d_in.decode.input_carry;
		v.e.output_carry := d_in.decode.output_carry;
		v.e.is_32bit := d_in.decode.is_32bit;
		v.e.is_signed := d_in.decode.is_signed;
		if d_in.decode.lr = '1' then
			v.e.lr := insn_lk(d_in.insn);
		end if;
                v.e.insn := d_in.insn;
                v.e.data_len := length;

                -- divide unit
                -- PPC divide and modulus instruction words have these bits in
                -- the bottom 11 bits: o1dns 010t1 r
                -- where o = OE for div instrs, signedness for mod instrs
                --       d = 1 for div*, 0 for mod*
                --       n = 1 for normal, 0 for extended (dividend << 32/64)
                --       s = 1 for signed, 0 for unsigned (for div*)
                --       t = 1 for 32-bit, 0 for 64-bit
                --       r = RC bit (record condition code)
		v.d.write_reg := gspr_to_gpr(decoded_reg_o.reg);
                v.d.is_modulus := not d_in.insn(8);
                v.d.is_32bit := d_in.insn(2);
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
		v.d.xerc := c_in.read_xerc_data;
		v.d.oe := decode_oe(d_in.decode.rc, d_in.insn);

		-- load/store unit
		v.l.update_reg := gspr_to_gpr(decoded_reg_a.reg);
		v.l.addr1 := decoded_reg_a.data;
		v.l.addr2 := decoded_reg_b.data;
		v.l.data := decoded_reg_c.data;
		v.l.write_reg := gspr_to_gpr(decoded_reg_o.reg);

		if d_in.decode.insn_type = OP_LOAD then
			v.l.load := '1';
		else
			v.l.load := '0';
		end if;

                v.l.length := length;
		v.l.byte_reverse := d_in.decode.byte_reverse;
		v.l.sign_extend := d_in.decode.sign_extend;
		v.l.update := d_in.decode.update;
		v.l.xerc := c_in.read_xerc_data;

		-- issue control
		control_valid_in <= d_in.valid;
		control_sgl_pipe <= d_in.decode.sgl_pipe;

		gpr_write_valid <= decoded_reg_o.reg_valid;
		gpr_write <= decoded_reg_o.reg;

		gpr_a_read_valid <= decoded_reg_a.reg_valid;
		gpr_a_read <= decoded_reg_a.reg;

		gpr_b_read_valid <= decoded_reg_b.reg_valid;
		gpr_b_read <= decoded_reg_b.reg;

		gpr_c_read_valid <= decoded_reg_c.reg_valid;
		gpr_c_read <= gspr_to_gpr(decoded_reg_c.reg);

                cr_write_valid <= d_in.decode.output_cr or decode_rc(d_in.decode.rc, d_in.insn);

		v.e.valid := '0';
                v.d.valid := '0';
		v.l.valid := '0';
		case d_in.decode.unit is
		when ALU =>
			v.e.valid := control_valid_out;
		when LDST =>
			v.l.valid := control_valid_out;
                when DIV =>
                        v.d.valid := control_valid_out;
		when NONE =>
			v.e.valid := control_valid_out;
			v.e.insn_type := OP_ILLEGAL;
		end case;

		if rst = '1' then
			v.e := Decode2ToExecute1Init;
			v.l := Decode2ToLoadStore1Init;
                        v.d := Decode2ToDividerInit;
		end if;

		-- Update registers
		rin <= v;

		-- Update outputs
		e_out <= r.e;
		l_out <= r.l;
                d_out <= r.d;
	end process;
end architecture behaviour;
