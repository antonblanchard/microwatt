library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.crhelpers.all;
use work.ppc_fx_insns.all;
use work.sim_console.all;

entity execute1 is
	generic (
		SIM   : boolean := false
	);
	port (
		clk   : in std_logic;

		e_in  : in Decode2ToExecute1Type;
		f_out : out Execute1ToFetch1Type;
		e_out : out Execute1ToExecute2Type;

		terminate_out : out std_ulogic
	);
end entity execute1;

architecture behaviour of execute1 is
	signal e: Decode2ToExecute1Type := Decode2ToExecute1Init;
	signal ctrl: ctrl_t := (carry => '0', others => (others => '0'));
	signal ctrl_tmp: ctrl_t := (carry => '0', others => (others => '0'));
begin
	execute1_0: process(clk)
	begin
		if rising_edge(clk) then
			e <= e_in;
			ctrl <= ctrl_tmp;
		end if;
	end process;

	execute1_1: process(all)
		variable result : std_ulogic_vector(63 downto 0);
		variable result_with_carry : std_ulogic_vector(64 downto 0);
		variable result_en : integer;
		variable crnum : integer;
	begin
		result := (others => '0');
		result_with_carry := (others => '0');
		result_en := 0;

		e_out <= Execute1ToExecute2Init;
		f_out <= Execute1ToFetch1TypeInit;
		ctrl_tmp <= ctrl;
		-- FIXME: run at 512MHz not core freq
		ctrl_tmp.tb <= std_ulogic_vector(unsigned(ctrl.tb) + 1);

		terminate_out <= '0';

		if e.valid = '1' then
			e_out.valid <= '1';
			e_out.write_reg <= e.write_reg;

			report "execute " & to_hstring(e.nia);

			case_0: case e.insn_type is

				when OP_ILLEGAL =>
					terminate_out <= '1';
					report "illegal";
				when OP_NOP =>
					-- Do nothing
				when OP_ADD =>
					result := ppc_add(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_ADDC =>
					result_with_carry := ppc_adde(e.read_data1, e.read_data2, ctrl.carry and e.input_carry);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64) and e.output_carry;
					result_en := 1;
				when OP_AND =>
					result := ppc_and(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_ANDC =>
					result := ppc_andc(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_B =>
					f_out.redirect <= '1';
					f_out.redirect_nia <= std_ulogic_vector(signed(e.nia) + signed(e.read_data2));
				when OP_BC =>
					if e.const1(4-2) = '0' then
						ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
					end if;
					if ppc_bc_taken(e.const1(4 downto 0), e.const2(4 downto 0), e.cr, ctrl.ctr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= std_ulogic_vector(signed(e.nia) + signed(e.read_data2));
					end if;
				when OP_BCLR =>
					if e.const1(4-2) = '0' then
						ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
					end if;
					if ppc_bc_taken(e.const1(4 downto 0), e.const2(4 downto 0), e.cr, ctrl.ctr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= ctrl.lr(63 downto 2) & "00";
					end if;
				when OP_BCCTR =>
					if ppc_bcctr_taken(e.const1(4 downto 0), e.const2(4 downto 0), e.cr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= ctrl.ctr(63 downto 2) & "00";
					end if;
				when OP_CMPB =>
					result := ppc_cmpb(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_CMP =>
					e_out.write_cr_enable <= '1';
					crnum := to_integer(unsigned(e.const1(2 downto 0)));
					e_out.write_cr_mask <= num_to_fxm(crnum);
					e_out.write_cr_data <= (others => '0');
					e_out.write_cr_data((4*(7-crnum)+3) downto (4*(7-crnum))) <= ppc_cmp(e.const2(0), e.read_data1, e.read_data2);
				when OP_CMPL =>
					e_out.write_cr_enable <= '1';
					crnum := to_integer(unsigned(e.const1(2 downto 0)));
					e_out.write_cr_mask <= num_to_fxm(crnum);
					e_out.write_cr_data <= (others => '0');
					e_out.write_cr_data((4*(7-crnum)+3) downto (4*(7-crnum))) <= ppc_cmpl(e.const2(0), e.read_data1, e.read_data2);
				when OP_CNTLZW =>
					result := ppc_cntlzw(e.read_data1);
					result_en := 1;
				when OP_CNTTZW =>
					result := ppc_cnttzw(e.read_data1);
					result_en := 1;
				when OP_CNTLZD =>
					result := ppc_cntlzd(e.read_data1);
					result_en := 1;
				when OP_CNTTZD =>
					result := ppc_cnttzd(e.read_data1);
					result_en := 1;
				when OP_EXTSB =>
					result := ppc_extsb(e.read_data1);
					result_en := 1;
				when OP_EXTSH =>
					result := ppc_extsh(e.read_data1);
					result_en := 1;
				when OP_EXTSW =>
					result := ppc_extsw(e.read_data1);
					result_en := 1;
				when OP_EQV =>
					result := ppc_eqv(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_ISEL =>
					crnum := to_integer(unsigned(e.const1));
					if e.cr(31-crnum) = '1' then
						result := e.read_data1;
					else
						result := e.read_data2;
					end if;
					result_en := 1;
				when OP_MFCTR =>
					result := ctrl.ctr;
					result_en := 1;
				when OP_MFLR =>
					result := ctrl.lr;
					result_en := 1;
				when OP_MFTB =>
					result := ctrl.tb;
					result_en := 1;
				when OP_MTCTR =>
					ctrl_tmp.ctr <= e.read_data1;
				when OP_MTLR =>
					ctrl_tmp.lr <= e.read_data1;
				when OP_MFCR =>
					result := x"00000000" & e.cr;
					result_en := 1;
				when OP_MFOCRF =>
					crnum := fxm_to_num(e.const1(7 downto 0));
					result := (others => '0');
					result((4*(7-crnum)+3) downto (4*(7-crnum))) := e.cr((4*(7-crnum)+3) downto (4*(7-crnum)));
					result_en := 1;
				when OP_MTCRF =>
					e_out.write_cr_enable <= '1';
					e_out.write_cr_mask <= e.const1(7 downto 0);
					e_out.write_cr_data <= e.read_data1(31 downto 0);
				when OP_MTOCRF =>
					e_out.write_cr_enable <= '1';
					-- We require one hot priority encoding here
					crnum := fxm_to_num(e.const1(7 downto 0));
					e_out.write_cr_mask <= num_to_fxm(crnum);
					e_out.write_cr_data <= e.read_data1(31 downto 0);
				when OP_NAND =>
					result := ppc_nand(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_NEG =>
					result := ppc_neg(e.read_data1);
					result_en := 1;
				when OP_NOR =>
					result := ppc_nor(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_OR =>
					result := ppc_or(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_ORC =>
					result := ppc_orc(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_POPCNTB =>
					result := ppc_popcntb(e.read_data1);
					result_en := 1;
				when OP_POPCNTW =>
					result := ppc_popcntw(e.read_data1);
					result_en := 1;
				when OP_POPCNTD =>
					result := ppc_popcntd(e.read_data1);
					result_en := 1;
				when OP_PRTYD =>
					result := ppc_prtyd(e.read_data1);
					result_en := 1;
				when OP_PRTYW =>
					result := ppc_prtyw(e.read_data1);
					result_en := 1;
				when OP_RLDCL =>
					result := ppc_rldcl(e.read_data1, e.read_data2, e.const2(5 downto 0));
					result_en := 1;
				when OP_RLDCR =>
					result := ppc_rldcr(e.read_data1, e.read_data2, e.const2(5 downto 0));
					result_en := 1;
				when OP_RLDICL =>
					result := ppc_rldicl(e.read_data1, e.const1(5 downto 0), e.const2(5 downto 0));
					result_en := 1;
				when OP_RLDICR =>
					result := ppc_rldicr(e.read_data1, e.const1(5 downto 0), e.const2(5 downto 0));
					result_en := 1;
				when OP_RLWNM =>
					result := ppc_rlwnm(e.read_data1, e.read_data2, e.const2(4 downto 0), e.const3(4 downto 0));
					result_en := 1;
				when OP_RLWINM =>
					result := ppc_rlwinm(e.read_data1, e.const1(4 downto 0), e.const2(4 downto 0), e.const3(4 downto 0));
					result_en := 1;
				when OP_RLDIC =>
					result := ppc_rldic(e.read_data1, e.const1(5 downto 0), e.const2(5 downto 0));
					result_en := 1;
				when OP_RLDIMI =>
					result := ppc_rldimi(e.read_data1, e.read_data2, e.const1(5 downto 0), e.const2(5 downto 0));
					result_en := 1;
				when OP_RLWIMI =>
					result := ppc_rlwimi(e.read_data1, e.read_data2, e.const1(4 downto 0), e.const2(4 downto 0), e.const3(4 downto 0));
					result_en := 1;
				when OP_SLD =>
					result := ppc_sld(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_SLW =>
					result := ppc_slw(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_SRAW =>
					result_with_carry := ppc_sraw(e.read_data1, e.read_data2);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRAWI =>
					result_with_carry := ppc_srawi(e.read_data1, e.const1(5 downto 0));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRAD =>
					result_with_carry := ppc_srad(e.read_data1, e.read_data2);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRADI =>
					result_with_carry := ppc_sradi(e.read_data1, e.const1(5 downto 0));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRD =>
					result := ppc_srd(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_SRW =>
					result := ppc_srw(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_SUBF =>
					result := ppc_subf(e.read_data1, e.read_data2);
					result_en := 1;
				when OP_SUBFC =>
					result_with_carry := ppc_subfe(e.read_data1, e.read_data2, ctrl.carry or not(e.input_carry));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64) and e.output_carry;
					result_en := 1;
				when OP_XOR =>
					result := ppc_xor(e.read_data1, e.read_data2);
					result_en := 1;

				-- sim console
				when OP_SIM_READ =>
					if SIM = true then
						sim_console_read(result);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_SIM_POLL =>
					if SIM = true then
						sim_console_poll(result);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_SIM_WRITE =>
					if SIM = true then
						sim_console_write(e.read_data1);
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_SIM_CONFIG =>
					if SIM = true then
						result := x"0000000000000001";
					else
						result := x"0000000000000000";
					end if;
					result_en := 1;

				when OP_TDI =>
					-- Keep our test cases happy for now, ignore trap instructions
					report "OP_TDI FIXME";

				when OP_DIVDU =>
					if SIM = true then
						result := ppc_divdu(e.read_data1, e.read_data2);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_DIVD =>
					if SIM = true then
						result := ppc_divd(e.read_data1, e.read_data2);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_DIVWU =>
					if SIM = true then
						result := ppc_divwu(e.read_data1, e.read_data2);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when OP_DIVW =>
					if SIM = true then
						result := ppc_divw(e.read_data1, e.read_data2);
						result_en := 1;
					else
						terminate_out <= '1';
						report "illegal";
					end if;
				when others =>
					terminate_out <= '1';
					report "illegal";
			end case;

			if e.lr = '1' then
				ctrl_tmp.lr <= std_ulogic_vector(unsigned(e.nia) + 4);
			end if;

			if result_en = 1 then
				e_out.write_data <= result;
				e_out.write_enable <= '1';
				e_out.rc <= e.rc;
			end if;
		end if;
	end process;
end architecture behaviour;
