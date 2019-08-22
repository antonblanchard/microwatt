library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;

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

	alias insn_rs   : std_ulogic_vector(4 downto 0) is d.insn(25 downto 21);
	alias insn_rt   : std_ulogic_vector(4 downto 0) is d.insn(25 downto 21);
	alias insn_ra   : std_ulogic_vector(4 downto 0) is d.insn(20 downto 16);
	alias insn_rb   : std_ulogic_vector(4 downto 0) is d.insn(15 downto 11);
	alias insn_si   : std_ulogic_vector(15 downto 0) is d.insn(15 downto 0);
	alias insn_ui   : std_ulogic_vector(15 downto 0) is d.insn(15 downto 0);
	alias insn_l    : std_ulogic is d.insn(21);
	alias insn_sh32 : std_ulogic_vector(4 downto 0) is d.insn(15 downto 11);
	alias insn_mb32 : std_ulogic_vector(4 downto 0) is d.insn(10 downto 6);
	alias insn_me32 : std_ulogic_vector(4 downto 0) is d.insn(5 downto 1);
	alias insn_li   : std_ulogic_vector(23 downto 0) is d.insn(25 downto 2);
	alias insn_lk   : std_ulogic is d.insn(0);
	alias insn_rc   : std_ulogic is d.insn(0);
	alias insn_bd   : std_ulogic_vector(13 downto 0) is d.insn(15 downto 2);
	alias insn_bf   : std_ulogic_vector(2 downto 0) is d.insn(25 downto 23);
	alias insn_fxm  : std_ulogic_vector(7 downto 0) is d.insn(19 downto 12);
	alias insn_bo   : std_ulogic_vector(4 downto 0) is d.insn(25 downto 21);
	alias insn_bi   : std_ulogic_vector(4 downto 0) is d.insn(20 downto 16);
	alias insn_bh   : std_ulogic_vector(1 downto 0) is d.insn(12 downto 11);
	alias insn_d    : std_ulogic_vector(15 downto 0) is d.insn(15 downto 0);
	alias insn_ds   : std_ulogic_vector(13 downto 0) is d.insn(15 downto 2);
	alias insn_to   : std_ulogic_vector(4 downto 0) is d.insn(25 downto 21);
	alias insn_bc   : std_ulogic_vector(4 downto 0) is d.insn(10 downto 6);

	-- can't use an alias for these
	signal insn_sh  : std_ulogic_vector(5 downto 0);
	signal insn_me  : std_ulogic_vector(5 downto 0);
	signal insn_mb  : std_ulogic_vector(5 downto 0);
begin
	insn_sh <= d.insn(1) & d.insn(15 downto 11);
	insn_me <= d.insn(5) & d.insn(10 downto 6);
	insn_mb <= d.insn(5) & d.insn(10 downto 6);

	decode2_0: process(clk)
	begin
		if rising_edge(clk) then
			d <= d_in;
		end if;
	end process;

	r_out.read1_reg <= insn_ra when (d.decode.input_reg_a = RA) else
			   insn_ra when d.decode.input_reg_a = RA_OR_ZERO else
			   insn_rs when d.decode.input_reg_a = RS else
			   (others => '0');

	r_out.read2_reg <= insn_rb when d.decode.input_reg_b = RB else
			   insn_rs when d.decode.input_reg_b = RS else
			   (others => '0');

	r_out.read3_reg <= insn_rs when d.decode.input_reg_c = RS else
			   (others => '0');

	decode2_1: process(all)
		variable mul_a : std_ulogic_vector(63 downto 0);
		variable mul_b : std_ulogic_vector(63 downto 0);
	begin
		e_out <= Decode2ToExecute1Init;
		l_out <= Decode2ToLoadStore1Init;
		m_out <= Decode2ToMultiplyInit;

		mul_a := (others => '0');
		mul_b := (others => '0');

		e_out.nia <= d.nia;
		l_out.nia <= d.nia;
		m_out.nia <= d.nia;

		--e_out.input_cr <= d.decode.input_cr;
		--m_out.input_cr <= d.decode.input_cr;
		--e_out.output_cr <= d.decode.output_cr;

		e_out.cr <= c_in.read_cr_data;

		e_out.input_carry <= d.decode.input_carry;
		e_out.output_carry <= d.decode.output_carry;

		if d.decode.lr then
			e_out.lr <= insn_lk;
		end if;

		-- XXX This is getting too complicated. Use variables and assign to each unit later

		case d.decode.unit is
		when ALU =>
			e_out.insn_type <= d.decode.insn_type;
			e_out.valid <= d.valid;
		when LDST =>
			l_out.valid <= d.valid;
		when MUL =>
			m_out.insn_type <= d.decode.insn_type;
			m_out.valid <= d.valid;
		when NONE =>
			e_out.insn_type <= OP_ILLEGAL;
			e_out.valid <= d.valid;
		end case;

		-- required for bypassing
		case d.decode.input_reg_a is
		when RA =>
			e_out.read_reg1 <= insn_ra;
			l_out.update_reg <= insn_ra;
		when RA_OR_ZERO =>
			e_out.read_reg1 <= insn_ra;
			l_out.update_reg <= insn_ra;
		when RS =>
			e_out.read_reg1 <= insn_rs;
		when NONE =>
			e_out.read_reg1 <= (others => '0');
			l_out.update_reg <= (others => '0');
		end case;

		-- required for bypassing
		case d.decode.input_reg_b is
		when RB =>
			e_out.read_reg2 <= insn_rb;
		when RS =>
			e_out.read_reg2 <= insn_rs;
		when others =>
			e_out.read_reg2 <= (others => '0');
		end case;

		-- required for bypassing
		--case d.decode.input_reg_c is
		--when RS =>
			--e_out.read_reg3 <= insn_rs;
		--when NONE =>
			--e_out.read_reg3 <= (others => '0');
		--end case;

		case d.decode.input_reg_a is
		when RA =>
			e_out.read_data1 <= r_in.read1_data;
			mul_a := r_in.read1_data;
			l_out.addr1 <= r_in.read1_data;
		when RA_OR_ZERO =>
			e_out.read_data1 <= ra_or_zero(r_in.read1_data, insn_ra);
			l_out.addr1 <= ra_or_zero(r_in.read1_data, insn_ra);
		when RS =>
			e_out.read_data1 <= r_in.read1_data;
		when NONE =>
			e_out.read_data1 <= (others => '0');
			mul_a := (others => '0');
		end case;

		case d.decode.input_reg_b is
		when RB =>
			e_out.read_data2 <= r_in.read2_data;
			mul_b := r_in.read2_data;
			l_out.addr2 <= r_in.read2_data;
		when RS =>
			e_out.read_data2 <= r_in.read2_data;
		when CONST_UI =>
			e_out.read_data2 <= std_ulogic_vector(resize(unsigned(insn_ui), 64));
		when CONST_SI =>
			e_out.read_data2 <= std_ulogic_vector(resize(signed(insn_si), 64));
			l_out.addr2 <= std_ulogic_vector(resize(signed(insn_si), 64));
			mul_b := std_ulogic_vector(resize(signed(insn_si), 64));
		when CONST_SI_HI =>
			e_out.read_data2 <= std_ulogic_vector(resize(signed(insn_si) & x"0000", 64));
		when CONST_UI_HI =>
			e_out.read_data2 <= std_ulogic_vector(resize(unsigned(insn_si) & x"0000", 64));
		when CONST_LI =>
			e_out.read_data2 <= std_ulogic_vector(resize(signed(insn_li) & "00", 64));
		when CONST_BD =>
			e_out.read_data2 <= std_ulogic_vector(resize(signed(insn_bd) & "00", 64));
		when CONST_DS =>
			l_out.addr2 <= std_ulogic_vector(resize(signed(insn_ds) & "00", 64));
		when NONE =>
			e_out.read_data2 <= (others => '0');
			l_out.addr2 <= (others => '0');
			mul_b := (others => '0');
		end case;

		case d.decode.input_reg_c is
		when RS =>
			l_out.data <= r_in.read3_data;
		when NONE =>
			l_out.data <= (others => '0');
		end case;

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

		case d.decode.const_a is
		when SH =>
			e_out.const1(insn_sh'range) <= insn_sh;
		when SH32 =>
			e_out.const1(insn_sh32'range) <= insn_sh32;
		when FXM =>
			e_out.const1(insn_fxm'range) <= insn_fxm;
		when BO =>
			e_out.const1(insn_bo'range)<= insn_bo;
		when BF =>
			e_out.const1(insn_bf'range)<= insn_bf;
		when TOO =>
			e_out.const1(insn_to'range)<= insn_to;
		when BC =>
			e_out.const1(insn_bc'range)<= insn_bc;
		when NONE =>
			e_out.const1 <= (others => '0');
		end case;

		case d.decode.const_b is
		when MB =>
			e_out.const2(insn_mb'range) <= insn_mb;
		when ME =>
			e_out.const2(insn_me'range) <= insn_me;
		when MB32 =>
			e_out.const2(insn_mb32'range) <= insn_mb32;
		when BI =>
			e_out.const2(insn_bi'range) <= insn_bi;
		when L =>
			e_out.const2(0) <= insn_l;
		when NONE =>
			e_out.const2 <= (others => '0');
		end case;

		case d.decode.const_c is
		when ME32 =>
			e_out.const3(insn_me32'range) <= insn_me32;
		when BH =>
			e_out.const3(insn_bh'range) <= insn_bh;
		when NONE =>
			e_out.const3 <= (others => '0');
		end case;

		case d.decode.output_reg_a is
		when RT =>
			e_out.write_reg <= insn_rt;
			l_out.write_reg <= insn_rt;
			m_out.write_reg <= insn_rt;
		when RA =>
			e_out.write_reg <= insn_ra;
			l_out.write_reg <= insn_ra;
		when NONE =>
			e_out.write_reg <= (others => '0');
			l_out.write_reg <= (others => '0');
			m_out.write_reg <= (others => '0');
		end case;

		case d.decode.rc is
		when RC =>
			e_out.rc <= insn_rc;
			m_out.rc <= insn_rc;
		when ONE =>
			e_out.rc <= '1';
			m_out.rc <= '1';
		when NONE =>
			e_out.rc <= '0';
			m_out.rc <= '0';
		end case;

		-- load/store specific signals
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
