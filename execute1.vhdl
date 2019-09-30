library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.decode_types.all;
use work.common.all;
use work.helpers.all;
use work.crhelpers.all;
use work.ppc_fx_insns.all;

entity execute1 is
	generic (
		SIM   : boolean := false
	);
	port (
		clk   : in std_logic;

		-- asynchronous
		flush_out : out std_ulogic;

		e_in  : in Decode2ToExecute1Type;

		-- asynchronous
		f_out : out Execute1ToFetch1Type;

		e_out : out Execute1ToExecute2Type;

		terminate_out : out std_ulogic
	);
end entity execute1;

architecture behaviour of execute1 is
	type reg_type is record
		--f : Execute1ToFetch1Type;
		e : Execute1ToExecute2Type;
	end record;

	signal r, rin : reg_type;

	signal ctrl: ctrl_t := (carry => '0', others => (others => '0'));
	signal ctrl_tmp: ctrl_t := (carry => '0', others => (others => '0'));
begin
	execute1_0: process(clk)
	begin
		if rising_edge(clk) then
			r <= rin;
			ctrl <= ctrl_tmp;
		end if;
	end process;

	execute1_1: process(all)
		variable v : reg_type;
		variable result : std_ulogic_vector(63 downto 0);
		variable result_with_carry : std_ulogic_vector(64 downto 0);
		variable result_en : integer;
		variable crnum : integer;
		variable lo, hi : integer;
	begin
		result := (others => '0');
		result_with_carry := (others => '0');
		result_en := 0;

		v := r;
		v.e := Execute1ToExecute2Init;
		--v.f := Execute1ToFetch1TypeInit;

		ctrl_tmp <= ctrl;
		-- FIXME: run at 512MHz not core freq
		ctrl_tmp.tb <= std_ulogic_vector(unsigned(ctrl.tb) + 1);

		terminate_out <= '0';
		f_out <= Execute1ToFetch1TypeInit;

		if e_in.valid = '1' then

			v.e.valid := '1';
			v.e.write_reg := e_in.write_reg;

			case_0: case e_in.insn_type is

				when OP_ILLEGAL =>
					terminate_out <= '1';
					report "illegal";
				when OP_NOP =>
					-- Do nothing
				when OP_ADD =>
					result := ppc_add(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_ADDE =>
					result_with_carry := ppc_adde(e_in.read_data1, e_in.read_data2, ctrl.carry and e_in.input_carry);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64) and e_in.output_carry;
					result_en := 1;
				when OP_AND =>
					result := ppc_and(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_ANDC =>
					result := ppc_andc(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_B =>
					f_out.redirect <= '1';
					f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(e_in.read_data2));
				when OP_BC =>
					if e_in.const1(4-2) = '0' then
						ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
					end if;
					if ppc_bc_taken(e_in.const1(4 downto 0), e_in.const2(4 downto 0), e_in.cr, ctrl.ctr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= std_ulogic_vector(signed(e_in.nia) + signed(e_in.read_data2));
					end if;
				when OP_BCLR =>
					if e_in.const1(4-2) = '0' then
						ctrl_tmp.ctr <= std_ulogic_vector(unsigned(ctrl.ctr) - 1);
					end if;
					if ppc_bc_taken(e_in.const1(4 downto 0), e_in.const2(4 downto 0), e_in.cr, ctrl.ctr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= ctrl.lr(63 downto 2) & "00";
					end if;
				when OP_BCCTR =>
					if ppc_bcctr_taken(e_in.const1(4 downto 0), e_in.const2(4 downto 0), e_in.cr) = 1 then
						f_out.redirect <= '1';
						f_out.redirect_nia <= ctrl.ctr(63 downto 2) & "00";
					end if;
				when OP_CMPB =>
					result := ppc_cmpb(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_CMP =>
					v.e.write_cr_enable := '1';
					crnum := to_integer(unsigned(e_in.const1(2 downto 0)));
					v.e.write_cr_mask := num_to_fxm(crnum);
					for i in 0 to 7 loop
						lo := i*4;
						hi := lo + 3;
						v.e.write_cr_data(hi downto lo) := ppc_cmp(e_in.const2(0), e_in.read_data1, e_in.read_data2);
					end loop;
				when OP_CMPL =>
					v.e.write_cr_enable := '1';
					crnum := to_integer(unsigned(e_in.const1(2 downto 0)));
					v.e.write_cr_mask := num_to_fxm(crnum);
					for i in 0 to 7 loop
						lo := i*4;
						hi := lo + 3;
						v.e.write_cr_data(hi downto lo) := ppc_cmpl(e_in.const2(0), e_in.read_data1, e_in.read_data2);
					end loop;
				when OP_CNTLZW =>
					result := ppc_cntlzw(e_in.read_data1);
					result_en := 1;
				when OP_CNTTZW =>
					result := ppc_cnttzw(e_in.read_data1);
					result_en := 1;
				when OP_CNTLZD =>
					result := ppc_cntlzd(e_in.read_data1);
					result_en := 1;
				when OP_CNTTZD =>
					result := ppc_cnttzd(e_in.read_data1);
					result_en := 1;
				when OP_EXTSB =>
					result := ppc_extsb(e_in.read_data1);
					result_en := 1;
				when OP_EXTSH =>
					result := ppc_extsh(e_in.read_data1);
					result_en := 1;
				when OP_EXTSW =>
					result := ppc_extsw(e_in.read_data1);
					result_en := 1;
				when OP_EQV =>
					result := ppc_eqv(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_ISEL =>
					crnum := to_integer(unsigned(e_in.const1));
					if e_in.cr(31-crnum) = '1' then
						result := e_in.read_data1;
					else
						result := e_in.read_data2;
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
					ctrl_tmp.ctr <= e_in.read_data1;
				when OP_MTLR =>
					ctrl_tmp.lr <= e_in.read_data1;
				when OP_MFCR =>
					result := x"00000000" & e_in.cr;
					result_en := 1;
				when OP_MFOCRF =>
					crnum := fxm_to_num(e_in.const1(7 downto 0));
					result := (others => '0');
					for i in 0 to 7 loop
						lo := (7-i)*4;
						hi := lo + 3;
						if crnum = i then
							result(hi downto lo) := e_in.cr(hi downto lo);
						end if;
					end loop;
					result_en := 1;
				when OP_MTCRF =>
					v.e.write_cr_enable := '1';
					v.e.write_cr_mask := e_in.const1(7 downto 0);
					v.e.write_cr_data := e_in.read_data1(31 downto 0);
				when OP_MTOCRF =>
					v.e.write_cr_enable := '1';
					-- We require one hot priority encoding here
					crnum := fxm_to_num(e_in.const1(7 downto 0));
					v.e.write_cr_mask := num_to_fxm(crnum);
					v.e.write_cr_data := e_in.read_data1(31 downto 0);
				when OP_NAND =>
					result := ppc_nand(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_NEG =>
					result := ppc_neg(e_in.read_data1);
					result_en := 1;
				when OP_NOR =>
					result := ppc_nor(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_OR =>
					result := ppc_or(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_ORC =>
					result := ppc_orc(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_POPCNTB =>
					result := ppc_popcntb(e_in.read_data1);
					result_en := 1;
				when OP_POPCNTW =>
					result := ppc_popcntw(e_in.read_data1);
					result_en := 1;
				when OP_POPCNTD =>
					result := ppc_popcntd(e_in.read_data1);
					result_en := 1;
				when OP_PRTYD =>
					result := ppc_prtyd(e_in.read_data1);
					result_en := 1;
				when OP_PRTYW =>
					result := ppc_prtyw(e_in.read_data1);
					result_en := 1;
				when OP_RLDCL =>
					result := ppc_rldcl(e_in.read_data1, e_in.read_data2, e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLDCR =>
					result := ppc_rldcr(e_in.read_data1, e_in.read_data2, e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLDICL =>
					result := ppc_rldicl(e_in.read_data1, e_in.const1(5 downto 0), e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLDICR =>
					result := ppc_rldicr(e_in.read_data1, e_in.const1(5 downto 0), e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLWNM =>
					result := ppc_rlwnm(e_in.read_data1, e_in.read_data2, e_in.const2(4 downto 0), e_in.const3(4 downto 0));
					result_en := 1;
				when OP_RLWINM =>
					result := ppc_rlwinm(e_in.read_data1, e_in.const1(4 downto 0), e_in.const2(4 downto 0), e_in.const3(4 downto 0));
					result_en := 1;
				when OP_RLDIC =>
					result := ppc_rldic(e_in.read_data1, e_in.const1(5 downto 0), e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLDIMI =>
					result := ppc_rldimi(e_in.read_data1, e_in.read_data2, e_in.const1(5 downto 0), e_in.const2(5 downto 0));
					result_en := 1;
				when OP_RLWIMI =>
					result := ppc_rlwimi(e_in.read_data1, e_in.read_data2, e_in.const1(4 downto 0), e_in.const2(4 downto 0), e_in.const3(4 downto 0));
					result_en := 1;
				when OP_SLD =>
					result := ppc_sld(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_SLW =>
					result := ppc_slw(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_SRAW =>
					result_with_carry := ppc_sraw(e_in.read_data1, e_in.read_data2);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRAWI =>
					result_with_carry := ppc_srawi(e_in.read_data1, e_in.const1(5 downto 0));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRAD =>
					result_with_carry := ppc_srad(e_in.read_data1, e_in.read_data2);
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRADI =>
					result_with_carry := ppc_sradi(e_in.read_data1, e_in.const1(5 downto 0));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64);
					result_en := 1;
				when OP_SRD =>
					result := ppc_srd(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_SRW =>
					result := ppc_srw(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_SUBF =>
					result := ppc_subf(e_in.read_data1, e_in.read_data2);
					result_en := 1;
				when OP_SUBFE =>
					result_with_carry := ppc_subfe(e_in.read_data1, e_in.read_data2, ctrl.carry or not(e_in.input_carry));
					result := result_with_carry(63 downto 0);
					ctrl_tmp.carry <= result_with_carry(64) and e_in.output_carry;
					result_en := 1;
				when OP_XOR =>
					result := ppc_xor(e_in.read_data1, e_in.read_data2);
					result_en := 1;

				when OP_SIM_CONFIG =>
					-- bit 0 was used to select the microwatt console, which
					-- we no longer support.
					if SIM = true then
						result := x"0000000000000000";
					else
						result := x"0000000000000000";
					end if;
					result_en := 1;

				when OP_TDI =>
					-- Keep our test cases happy for now, ignore trap instructions
					report "OP_TDI FIXME";

				when others =>
					terminate_out <= '1';
					report "illegal";
			end case;

			if e_in.lr = '1' then
				ctrl_tmp.lr <= std_ulogic_vector(unsigned(e_in.nia) + 4);
			end if;

			if result_en = 1 then
				v.e.write_data := result;
				v.e.write_enable := '1';
				v.e.rc := e_in.rc;
			end if;
		end if;

                -- Update registers
                rin <= v;

		-- update outputs
		--f_out <= r.f;
		e_out <= r.e;
		flush_out <= f_out.redirect;
	end process;
end architecture behaviour;
