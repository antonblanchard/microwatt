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

		d_in  : in Decode1ToDecode2Type;

		e_out : out Decode2ToExecute1Type;
		m_out : out Decode2ToMultiplyType;
		l_out : out Decode2ToLoadstore1Type;

		r_in  : in RegisterFileToDecode2Type;
		r_out : out Decode2ToRegisterFileType;

		c_in  : in CrFileToDecode2Type;
		c_out : out Decode2ToCrFileType
	);
end entity decode2;

architecture behaviour of decode2 is
	signal d        : Decode1ToDecode2Type;

	type decode_input_reg_t is record
		reg_valid : std_ulogic;
		reg       : std_ulogic_vector(4 downto 0);
		data      : std_ulogic_vector(63 downto 0);
	end record;

	function decode_input_reg_a (t : input_reg_a_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		case t is
		when RA =>
			return ('1', insn_ra(insn_in), reg_data);
		when RA_OR_ZERO =>
			return ('1', insn_ra(insn_in), ra_or_zero(reg_data, insn_ra(insn_in)));
		when RS =>
			return ('1', insn_rs(insn_in), reg_data);
		when NONE =>
			return ('0', (others => '0'), (others => '0'));
		end case;
	end;

	function decode_input_reg_b (t : input_reg_b_t; insn_in : std_ulogic_vector(31 downto 0);
				     reg_data : std_ulogic_vector(63 downto 0)) return decode_input_reg_t is
	begin
		case t is
		when RB =>
			return ('1', insn_rb(insn_in), reg_data);
		when RS =>
			return ('1', insn_rs(insn_in), reg_data);
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

	function decode_const_a (t : constant_a_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
	begin
		case t is
		when SH =>
			return "00" & insn_sh(insn_in);
		when SH32 =>
			return "000" & insn_sh32(insn_in);
		when FXM =>
			return insn_fxm(insn_in);
		when BO =>
			return "000" & insn_bo(insn_in);
		when BF =>
			return "00000" & insn_bf(insn_in);
		when TOO =>
			return "000" & insn_to(insn_in);
		when BC =>
			return "000" & insn_bc(insn_in);
		when NONE =>
			return "00000000";
		end case;
	end;

	function decode_const_b (t : constant_b_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
	begin
		case t is
		when MB =>
			return insn_mb(insn_in);
		when ME =>
			return insn_me(insn_in);
		when MB32 =>
			return "0" & insn_mb32(insn_in);
		when BI =>
			return "0" & insn_bi(insn_in);
		when L =>
			return "00000" & insn_l(insn_in);
		when NONE =>
			return "000000";
		end case;
	end;

	function decode_const_c (t : constant_c_t; insn_in : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
	begin
		case t is
		when ME32 =>
			return insn_me32(insn_in);
		when BH =>
			return "000" & insn_bh(insn_in);
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
			d <= d_in;
		end if;
	end process;

	r_out.read1_reg <= insn_ra(d.insn) when (d.decode.input_reg_a = RA) else
			   insn_ra(d.insn) when d.decode.input_reg_a = RA_OR_ZERO else
			   insn_rs(d.insn) when d.decode.input_reg_a = RS else
			   (others => '0');

	r_out.read2_reg <= insn_rb(d.insn) when d.decode.input_reg_b = RB else
			   insn_rs(d.insn) when d.decode.input_reg_b = RS else
			   (others => '0');

	r_out.read3_reg <= insn_rs(d.insn) when d.decode.input_reg_c = RS else
			   (others => '0');

	decode2_1: process(all)
		variable mul_a : std_ulogic_vector(63 downto 0);
		variable mul_b : std_ulogic_vector(63 downto 0);
		variable decoded_reg_a : decode_input_reg_t;
		variable decoded_reg_b : decode_input_reg_t;
		variable decoded_reg_c : decode_input_reg_t;
	begin
		e_out <= Decode2ToExecute1Init;
		l_out <= Decode2ToLoadStore1Init;
		m_out <= Decode2ToMultiplyInit;

		mul_a := (others => '0');
		mul_b := (others => '0');

		--e_out.input_cr <= d.decode.input_cr;
		--m_out.input_cr <= d.decode.input_cr;
		--e_out.output_cr <= d.decode.output_cr;

		decoded_reg_a := decode_input_reg_a (d.decode.input_reg_a, d.insn, r_in.read1_data);
		decoded_reg_b := decode_input_reg_b (d.decode.input_reg_b, d.insn, r_in.read2_data);
		decoded_reg_c := decode_input_reg_c (d.decode.input_reg_c, d.insn, r_in.read3_data);

		r_out.read1_enable <= decoded_reg_a.reg_valid;
		r_out.read2_enable <= decoded_reg_b.reg_valid;
		r_out.read3_enable <= decoded_reg_c.reg_valid;

		case d.decode.unit is
		when ALU =>
			e_out.valid <= d.valid;
		when LDST =>
			l_out.valid <= d.valid;
		when MUL =>
			m_out.valid <= d.valid;
		when NONE =>
			e_out.valid <= d.valid;
			e_out.insn_type <= OP_ILLEGAL;
		end case;

		-- execute unit
		e_out.nia <= d.nia;
		e_out.insn_type <= d.decode.insn_type;
		e_out.read_reg1 <= decoded_reg_a.reg;
		e_out.read_data1 <= decoded_reg_a.data;
		e_out.read_reg2 <= decoded_reg_b.reg;
		e_out.read_data2 <= decoded_reg_b.data;
		e_out.write_reg <= decode_output_reg(d.decode.output_reg_a, d.insn);
		e_out.rc <= decode_rc(d.decode.rc, d.insn);
		e_out.cr <= c_in.read_cr_data;
		e_out.input_carry <= d.decode.input_carry;
		e_out.output_carry <= d.decode.output_carry;
		if d.decode.lr then
			e_out.lr <= insn_lk(d.insn);
		end if;
		e_out.const1 <= decode_const_a(d.decode.const_a, d.insn);
		e_out.const2 <= decode_const_b(d.decode.const_b, d.insn);
		e_out.const3 <= decode_const_c(d.decode.const_c, d.insn);

		-- multiply unit
		m_out.nia <= d.nia;
		m_out.insn_type <= d.decode.insn_type;
		mul_a := decoded_reg_a.data;
		mul_b := decoded_reg_b.data;
		m_out.write_reg <= decode_output_reg(d.decode.output_reg_a, d.insn);
		m_out.rc <= decode_rc(d.decode.rc, d.insn);

		if d.decode.mul_32bit = '1' then
			if d.decode.mul_signed = '1' then
				m_out.data1 <= (others => mul_a(31));
				m_out.data1(31 downto 0) <= mul_a(31 downto 0);
				m_out.data2 <= (others => mul_b(31));
				m_out.data2(31 downto 0) <= mul_b(31 downto 0);
			else
				m_out.data1 <= '0' & x"00000000" & mul_a(31 downto 0);
				m_out.data2 <= '0' & x"00000000" & mul_b(31 downto 0);
			end if;
		else
			if d.decode.mul_signed = '1' then
				m_out.data1 <= mul_a(63) & mul_a;
				m_out.data2 <= mul_b(63) & mul_b;
			else
				m_out.data1 <= '0' & mul_a;
				m_out.data2 <= '0' & mul_b;
			end if;
		end if;

		-- load/store unit
		l_out.nia <= d.nia;
		l_out.update_reg <= decoded_reg_a.reg;
		l_out.addr1 <= decoded_reg_a.data;
		l_out.addr2 <= decoded_reg_b.data;
		l_out.data <= decoded_reg_c.data;
		l_out.write_reg <= decode_output_reg(d.decode.output_reg_a, d.insn);

		if d.decode.insn_type = OP_LOAD then
			l_out.load <= '1';
		else
			l_out.load <= '0';
		end if;

		case d.decode.length is
		when is1B =>
			l_out.length <= "0001";
		when is2B =>
			l_out.length <= "0010";
		when is4B =>
			l_out.length <= "0100";
		when is8B =>
			l_out.length <= "1000";
		when NONE =>
			l_out.length <= "0000";
		end case;

		l_out.byte_reverse <= d.decode.byte_reverse;
		l_out.sign_extend <= d.decode.sign_extend;
		l_out.update <= d.decode.update;
	end process;
end architecture behaviour;
