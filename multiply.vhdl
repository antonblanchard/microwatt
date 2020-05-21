library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity multiply is
    generic (
        PIPELINE_DEPTH : natural := 4
        );
    port (
        clk   : in std_logic;

        m_in  : in Execute1ToMultiplyType;
        m_out : out MultiplyToExecute1Type
        );
end entity multiply;

architecture behaviour of multiply is
    signal m: Execute1ToMultiplyType := Execute1ToMultiplyInit;

    type multiply_pipeline_stage is record
        valid     : std_ulogic;
        data      : unsigned(127 downto 0);
	is_32bit  : std_ulogic;
        neg_res   : std_ulogic;
    end record;
    constant MultiplyPipelineStageInit : multiply_pipeline_stage := (valid => '0',
								     is_32bit => '0', neg_res => '0',
								     data => (others => '0'));

    type multiply_pipeline_type is array(0 to PIPELINE_DEPTH-1) of multiply_pipeline_stage;
    constant MultiplyPipelineInit : multiply_pipeline_type := (others => MultiplyPipelineStageInit);

    type reg_type is record
        multiply_pipeline : multiply_pipeline_type;
    end record;

    signal r, rin : reg_type := (multiply_pipeline => MultiplyPipelineInit);
begin
    multiply_0: process(clk)
    begin
        if rising_edge(clk) then
            m <= m_in;
            r <= rin;
        end if;
    end process;

    multiply_1: process(all)
        variable v : reg_type;
        variable d : std_ulogic_vector(127 downto 0);
        variable d2 : std_ulogic_vector(63 downto 0);
	variable ov : std_ulogic;
    begin
        v.multiply_pipeline(0).valid := m.valid;
        v.multiply_pipeline(0).data := unsigned(m.data1) * unsigned(m.data2);
        v.multiply_pipeline(0).is_32bit := m.is_32bit;
        v.multiply_pipeline(0).neg_res := m.neg_result;

        loop_0: for i in 1 to PIPELINE_DEPTH-1 loop
            v.multiply_pipeline(i) := r.multiply_pipeline(i-1);
        end loop;

        if v.multiply_pipeline(PIPELINE_DEPTH-1).neg_res = '0' then
            d := std_ulogic_vector(v.multiply_pipeline(PIPELINE_DEPTH-1).data);
        else
            d := std_ulogic_vector(- signed(v.multiply_pipeline(PIPELINE_DEPTH-1).data));
        end if;

        ov := '0';
        if v.multiply_pipeline(PIPELINE_DEPTH-1).is_32bit = '1' then
            ov := (or d(63 downto 31)) and not (and d(63 downto 31));
        else
            ov := (or d(127 downto 63)) and not (and d(127 downto 63));
        end if;

        m_out.result <= d;
        m_out.overflow <= ov;
        m_out.valid <= v.multiply_pipeline(PIPELINE_DEPTH-1).valid;

        rin <= v;
    end process;
end architecture behaviour;
