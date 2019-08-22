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
	signal e: Execute1ToExecute2Type;
begin
	execute2_0: process(clk)
	begin
		if (rising_edge(clk)) then
			e <= e_in;
		end if;
	end process;

	execute2_1: process(all)
	begin
		e_out.valid <= e.valid;
		e_out.write_enable <= e.write_enable;
		e_out.write_reg <= e.write_reg;
		e_out.write_data <= e.write_data;
		e_out.write_cr_enable <= e.write_cr_enable;
		e_out.write_cr_mask <= e.write_cr_mask;
		e_out.write_cr_data <= e.write_cr_data;

		if e.valid = '1' and e.rc = '1' then
			e_out.write_cr_enable <= '1';
			e_out.write_cr_mask <= num_to_fxm(0);
			e_out.write_cr_data <= ppc_cmpi('1', e.write_data, x"0000") & x"0000000";
		end if;
	end process;
end;
