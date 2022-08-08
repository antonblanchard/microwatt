library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

entity multiply is
    generic (
        PIPELINE_DEPTH : natural := 3
        );
    port (
        clk   : in std_logic;

        m_in  : in MultiplyInputType;
        m_out : out MultiplyOutputType
        );
end entity multiply;

architecture behaviour of multiply is
    signal m: MultiplyInputType := MultiplyInputInit;

    type multiply_pipeline_stage is record
        valid     : std_ulogic;
        data      : unsigned(127 downto 0);
    end record;
    constant MultiplyPipelineStageInit : multiply_pipeline_stage := (valid => '0',
								     data => (others => '0'));

    type multiply_pipeline_type is array(0 to PIPELINE_DEPTH-1) of multiply_pipeline_stage;
    constant MultiplyPipelineInit : multiply_pipeline_type := (others => MultiplyPipelineStageInit);

    type reg_type is record
        multiply_pipeline : multiply_pipeline_type;
    end record;

    signal r, rin : reg_type := (multiply_pipeline => MultiplyPipelineInit);
    signal overflow : std_ulogic;
    signal ovf_in   : std_ulogic;
begin
    multiply_0: process(clk)
    begin
        if rising_edge(clk) then
            m <= m_in;
            r <= rin;
            overflow <= ovf_in;
        end if;
    end process;

    multiply_1: process(all)
        variable v : reg_type;
        variable a, b : std_ulogic_vector(64 downto 0);
        variable prod : std_ulogic_vector(129 downto 0);
        variable d : std_ulogic_vector(127 downto 0);
        variable d2 : std_ulogic_vector(63 downto 0);
	variable ov : std_ulogic;
    begin
        v := r;
        a := (m.is_signed and m.data1(63)) & m.data1;
        b := (m.is_signed and m.data2(63)) & m.data2;
        prod := std_ulogic_vector(signed(a) * signed(b));
        v.multiply_pipeline(0).valid := m.valid;
        if m.subtract = '1' then
            v.multiply_pipeline(0).data := unsigned(m.addend) - unsigned(prod(127 downto 0));
        else
            v.multiply_pipeline(0).data := unsigned(m.addend) + unsigned(prod(127 downto 0));
        end if;

        loop_0: for i in 1 to PIPELINE_DEPTH-1 loop
            v.multiply_pipeline(i) := r.multiply_pipeline(i-1);
        end loop;

        d := std_ulogic_vector(v.multiply_pipeline(PIPELINE_DEPTH-1).data);
        ov := (or d(127 downto 63)) and not (and d(127 downto 63));
        ovf_in <= ov;

        m_out.result <= d;
        m_out.overflow <= overflow;
        m_out.valid <= v.multiply_pipeline(PIPELINE_DEPTH-1).valid;

        rin <= v;
    end process;
end architecture behaviour;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity short_multiply is
    port (
        clk   : in std_ulogic;

        a_in  : in std_ulogic_vector(15 downto 0);
        b_in  : in std_ulogic_vector(15 downto 0);
        m_out : out std_ulogic_vector(31 downto 0)
        );
end entity short_multiply;

architecture behaviour of short_multiply is
begin
    m_out <= std_ulogic_vector(signed(a_in) * signed(b_in));
end architecture behaviour;
