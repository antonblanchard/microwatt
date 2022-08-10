library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

-- Signed 33b x 33b multiplier giving 64-bit product, with no addend,
-- with fixed 1-cycle latency.

entity multiply_32s is
    port (
        clk   : in std_logic;
        stall : in std_ulogic;

        m_in  : in MultiplyInputType;
        m_out : out MultiplyOutputType
        );
end entity multiply_32s;

architecture behaviour of multiply_32s is
    type reg_type is record
        valid     : std_ulogic;
        data      : signed(65 downto 0);
    end record;
    constant reg_type_init : reg_type := (valid => '0', data => (others => '0'));

    signal r, rin : reg_type := reg_type_init;
begin
    multiply_0: process(clk)
    begin
        if rising_edge(clk) and stall = '0' then
            r <= rin;
        end if;
    end process;

    multiply_1: process(all)
        variable v : reg_type;
        variable d : std_ulogic_vector(63 downto 0);
	variable ov : std_ulogic;
    begin
        v.valid := m_in.valid;
        v.data := signed((m_in.is_signed and m_in.data1(31)) & m_in.data1(31 downto 0)) *
                  signed((m_in.is_signed and m_in.data2(31)) & m_in.data2(31 downto 0));

        d := std_ulogic_vector(r.data(63 downto 0));

        ov := (or d(63 downto 31)) and not (and d(63 downto 31));

        m_out.result <= 64x"0" & d;
        m_out.overflow <= ov;
        m_out.valid <= r.valid;

        rin <= v;
    end process;
end architecture behaviour;
