library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;
use work.crhelpers.all;
use work.ppc_fx_insns.all;

-- 2 cycle ALU
-- We handle rc form instructions here

entity execute2 is
	port (
		clk   : in std_ulogic;

		e_in  : in Execute1ToExecute2Type;
		e_out : out Execute2ToWritebackType
	);
end execute2;

architecture behave of execute2 is
	signal r, rin : Execute2ToWritebackType;
begin
	execute2_0: process(clk)
	begin
		if rising_edge(clk) then
			r <= rin;
		end if;
	end process;

	execute2_1: process(all)
		variable v : Execute2ToWritebackType;
	begin
		v := rin;

		v.valid := e_in.valid;
		v.write_enable := e_in.write_enable;
		v.write_reg := e_in.write_reg;
		v.write_data := e_in.write_data;
		v.write_cr_enable := e_in.write_cr_enable;
		v.write_cr_mask := e_in.write_cr_mask;
		v.write_cr_data := e_in.write_cr_data;

		if e_in.valid = '1' and e_in.rc = '1' then
			v.write_cr_enable := '1';
			v.write_cr_mask := num_to_fxm(0);
			v.write_cr_data := ppc_cmpi('1', e_in.write_data, x"0000") & x"0000000";
		end if;

		-- Update registers
		rin <= v;

		-- Update outputs
		e_out <= v;
	end process;
end;
