library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.insn_helpers.all;

entity decode2 is
        generic (
                EX1_BYPASS : boolean := true
        );
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

		r_in  : in RegisterFileToDecode2Type;
		r_out : out Decode2ToRegisterFileType;

		c_in  : in CrFileToDecode2Type;
		c_out : out Decode2ToCrFileType
	);
end entity decode2;

architecture behaviour of decode2 is
	type reg_type is record
		e : Decode2ToExecute1Type;
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
		variable ret : decode_input_reg_t;
	begin
		case t is
		when RB =>
		    assert is_fast_spr(ispr) = '0' report "Decode B says GPR but ISPR says SPR:" &
			to_hstring(ispr) severity failure;
		    ret := ('1', gpr_to_gspr(insn_rb(insn_in)), reg_data);
		when CONST_UI =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(unsigned(insn_ui(insn_in)), 64)));
		when CONST_SI =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_si(insn_in)), 64)));
		when CONST_SI_HI =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_si(insn_in)) & x"0000", 64)));
		when CONST_UI_HI =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(unsigned(insn_si(insn_in)) & x"0000", 64)));
		when CONST_LI =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_li(insn_in)) & "00", 64)));
		when CONST_BD =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_bd(insn_in)) & "00", 64)));
		when CONST_DS =>
			ret := ('0', (others => '0'), std_ulogic_vector(resize(signed(insn_ds(insn_in)) & "00", 64)));
                when CONST_M1 =>
			ret := ('0', (others => '0'), x"FFFFFFFFFFFFFFFF");
		when CONST_SH =>
			ret := ('0', (others => '0'), x"00000000000000" & "00" & insn_in(1) & insn_in(15 downto 11));
		when CONST_SH32 =>
			ret := ('0', (others => '0'), x"00000000000000" & "000" & insn_in(15 downto 11));
		when SPR =>
		    -- ISPR must be either a valid fast SPR number or all 0 for a slow SPR.
		    -- If it's all 0, we don't treat it as a dependency as slow SPRs
		    -- operations are single issue.
		    assert is_fast_spr(ispr) = '1' or ispr = "000000"
			report "Decode B says SPR but ISPR is invalid:" &
			to_hstring(ispr) severity failure;
		    ret := (is_fast_spr(ispr), ispr, reg_data);
		when NONE =>
			ret := ('0', (others => '0'), (others => '0'));
		end case;

		return ret;
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
        signal gpr_bypassable  : std_ulogic;

	signal gpr_a_read_valid : std_ulogic;
	signal gpr_a_read :gspr_index_t;
        signal gpr_a_bypass : std_ulogic;

	signal gpr_b_read_valid : std_ulogic;
	signal gpr_b_read : gspr_index_t;
        signal gpr_b_bypass : std_ulogic;

	signal gpr_c_read_valid : std_ulogic;
	signal gpr_c_read : gpr_index_t;
        signal gpr_c_bypass : std_ulogic;

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
                gpr_bypassable     => gpr_bypassable,

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
		stopped_out => stopped_out,

                gpr_bypass_a => gpr_a_bypass,
                gpr_bypass_b => gpr_b_bypass,
                gpr_bypass_c => gpr_c_bypass
	);

	decode2_0: process(clk)
	begin
		if rising_edge(clk) then
			if rin.e.valid = '1' then
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
                variable length : std_ulogic_vector(3 downto 0);
	begin
		v := r;

		v.e := Decode2ToExecute1Init;

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
                v.e.unit := d_in.decode.unit;
		v.e.insn_type := d_in.decode.insn_type;
		v.e.read_reg1 := decoded_reg_a.reg;
		v.e.read_data1 := decoded_reg_a.data;
                v.e.bypass_data1 := gpr_a_bypass;
		v.e.read_reg2 := decoded_reg_b.reg;
		v.e.read_data2 := decoded_reg_b.data;
                v.e.bypass_data2 := gpr_b_bypass;
                v.e.read_data3 := decoded_reg_c.data;
                v.e.bypass_data3 := gpr_c_bypass;
		v.e.write_reg := decoded_reg_o.reg;
		v.e.rc := decode_rc(d_in.decode.rc, d_in.insn);
                if not (d_in.decode.insn_type = OP_MUL_H32 or d_in.decode.insn_type = OP_MUL_H64) then
                        v.e.oe := decode_oe(d_in.decode.rc, d_in.insn);
                end if;
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
		v.e.byte_reverse := d_in.decode.byte_reverse;
		v.e.sign_extend := d_in.decode.sign_extend;
		v.e.update := d_in.decode.update;
                v.e.reserve := d_in.decode.reserve;

		-- issue control
		control_valid_in <= d_in.valid;
		control_sgl_pipe <= d_in.decode.sgl_pipe;

		gpr_write_valid <= decoded_reg_o.reg_valid;
		gpr_write <= decoded_reg_o.reg;
                gpr_bypassable <= '0';
                if EX1_BYPASS and d_in.decode.unit = ALU then
                        gpr_bypassable <= '1';
                end if;

		gpr_a_read_valid <= decoded_reg_a.reg_valid;
		gpr_a_read <= decoded_reg_a.reg;

		gpr_b_read_valid <= decoded_reg_b.reg_valid;
		gpr_b_read <= decoded_reg_b.reg;

		gpr_c_read_valid <= decoded_reg_c.reg_valid;
		gpr_c_read <= gspr_to_gpr(decoded_reg_c.reg);

                cr_write_valid <= d_in.decode.output_cr or decode_rc(d_in.decode.rc, d_in.insn);

		v.e.valid := control_valid_out;
		if d_in.decode.unit = NONE then
			v.e.insn_type := OP_ILLEGAL;
		end if;

		if rst = '1' then
			v.e := Decode2ToExecute1Init;
		end if;

		-- Update registers
		rin <= v;

		-- Update outputs
		e_out <= r.e;
	end process;
end architecture behaviour;
