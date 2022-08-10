library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

library unisim;
use unisim.vcomponents.all;

-- Signed 33b x 33b multiplier giving 64-bit product, with no addend.

entity multiply_32s is
    port (
        clk   : in std_logic;
        stall : in std_ulogic;

        m_in  : in MultiplyInputType;
        m_out : out MultiplyOutputType
        );
end entity multiply_32s;

architecture behaviour of multiply_32s is
    signal clocken : std_ulogic;
    signal data1 : std_ulogic_vector(52 downto 0);
    signal data2 : std_ulogic_vector(34 downto 0);
    signal m00_p, m01_p : std_ulogic_vector(47 downto 0);
    signal m00_pc : std_ulogic_vector(47 downto 0);
    signal m10_p, m11_p : std_ulogic_vector(47 downto 0);
    signal m10_pc : std_ulogic_vector(47 downto 0);
    signal p0_pat, p0_patb : std_ulogic;
    signal p1_pat, p1_patb : std_ulogic;
    signal product_lo : std_ulogic_vector(22 downto 0);

begin
    -- sign extend if signed
    data1(31 downto 0)  <= m_in.data1(31 downto 0);
    data1(52 downto 32) <= (others => m_in.is_signed and m_in.data1(31));
    data2(31 downto 0)  <= m_in.data2(31 downto 0);
    data2(34 downto 32) <= (others => m_in.is_signed and m_in.data2(31));

    clocken <= m_in.valid and not stall;

    m00: DSP48E1
        generic map (
            ACASCREG => 0,
            ALUMODEREG => 0,
            AREG => 0,
            BCASCREG => 0,
            BREG => 0,
            CARRYINREG => 0,
            CARRYINSELREG => 0,
            CREG => 0,
            INMODEREG => 0,
            MREG => 0,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => "0000000" & data1(22 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & data2(16 downto 0),
            BCIN => (others => '0'),
            C => (others => '0'),
            CARRYCASCIN => '0',
            CARRYIN => '0',
            CARRYINSEL => "000",
            CEA1 => '0',
            CEA2 => '0',
            CEAD => '0',
            CEALUMODE => '0',
            CEB1 => '0',
            CEB2 => '0',
            CEC => '0',
            CECARRYIN => '0',
            CECTRL => '0',
            CED => '0',
            CEINMODE => '0',
            CEM => '0',
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0110101",
            P => m00_p,
            PCIN => (others => '0'),
            PCOUT => m00_pc,
            RSTA => '0',
            RSTALLCARRYIN => '0',
            RSTALUMODE => '0',
            RSTB => '0',
            RSTC => '0',
            RSTCTRL => '0',
            RSTD => '0',
            RSTINMODE => '0',
            RSTM => '0',
            RSTP => '0'
            );

    m01: DSP48E1
        generic map (
            ACASCREG => 0,
            ALUMODEREG => 0,
            AREG => 0,
            BCASCREG => 0,
            BREG => 0,
            CARRYINREG => 0,
            CARRYINSELREG => 0,
            CREG => 0,
            INMODEREG => 0,
            MREG => 0,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => "0000000" & data1(22 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => data2(34 downto 17),
            BCIN => (others => '0'),
            C => (others => '0'),
            CARRYCASCIN => '0',
            CARRYIN => '0',
            CARRYINSEL => "000",
            CEA1 => '0',
            CEA2 => '0',
            CEAD => '0',
            CEALUMODE => '0',
            CEB1 => '0',
            CEB2 => '0',
            CEC => '0',
            CECARRYIN => '0',
            CECTRL => '0',
            CED => '0',
            CEINMODE => '0',
            CEM => '0',
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m01_p,
            PCIN => m00_pc,
            RSTA => '0',
            RSTALLCARRYIN => '0',
            RSTALUMODE => '0',
            RSTB => '0',
            RSTC => '0',
            RSTCTRL => '0',
            RSTD => '0',
            RSTINMODE => '0',
            RSTM => '0',
            RSTP => '0'
            );

    m10: DSP48E1
        generic map (
            ACASCREG => 0,
            ALUMODEREG => 0,
            AREG => 0,
            BCASCREG => 0,
            BREG => 0,
            CARRYINREG => 0,
            CARRYINSELREG => 0,
            CREG => 1,
            INMODEREG => 0,
            MASK => x"fffffffe00ff",
            OPMODEREG => 0,
            PREG => 0,
            USE_PATTERN_DETECT => "PATDET"
            )
        port map (
            A => data1(52 downto 23),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & data2(16 downto 0),
            BCIN => (others => '0'),
            C => std_ulogic_vector(resize(signed(m01_p(38 downto 6)), 48)),
            CARRYCASCIN => '0',
            CARRYIN => '0',
            CARRYINSEL => "000",
            CEA1 => '0',
            CEA2 => '0',
            CEAD => '0',
            CEALUMODE => '0',
            CEB1 => '0',
            CEB2 => '0',
            CEC => clocken,
            CECARRYIN => '0',
            CECTRL => '0',
            CED => '0',
            CEINMODE => '0',
            CEM => clocken,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0110101",
            P => m10_p,
            PATTERNDETECT => p0_pat,
            PATTERNBDETECT => p0_patb,
            PCIN => (others => '0'),
            PCOUT => m10_pc,
            RSTA => '0',
            RSTALLCARRYIN => '0',
            RSTALUMODE => '0',
            RSTB => '0',
            RSTC => '0',
            RSTCTRL => '0',
            RSTD => '0',
            RSTINMODE => '0',
            RSTM => '0',
            RSTP => '0'
            );

    m11: DSP48E1
        generic map (
            ACASCREG => 0,
            ALUMODEREG => 0,
            AREG => 0,
            BCASCREG => 0,
            BREG => 0,
            CARRYINREG => 0,
            CARRYINSELREG => 0,
            CREG => 0,
            INMODEREG => 0,
            MASK => x"fffffc000000",
            OPMODEREG => 0,
            PREG => 0,
            USE_PATTERN_DETECT => "PATDET"
            )
        port map (
            A => data1(52 downto 23),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => data2(34 downto 17),
            BCIN => (others => '0'),
            C => (others => '0'),
            CARRYCASCIN => '0',
            CARRYIN => '0',
            CARRYINSEL => "000",
            CEA1 => '0',
            CEA2 => '0',
            CEAD => '0',
            CEALUMODE => '0',
            CEB1 => '0',
            CEB2 => '0',
            CEC => '0',
            CECARRYIN => '0',
            CECTRL => '0',
            CED => '0',
            CEINMODE => '0',
            CEM => clocken,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m11_p,
            PATTERNDETECT => p1_pat,
            PATTERNBDETECT => p1_patb,
            PCIN => m10_pc,
            RSTA => '0',
            RSTALLCARRYIN => '0',
            RSTALUMODE => '0',
            RSTB => '0',
            RSTC => '0',
            RSTCTRL => '0',
            RSTD => '0',
            RSTINMODE => '0',
            RSTM => '0',
            RSTP => '0'
            );

    m_out.result(127 downto 64) <= (others => '0');
    m_out.result(63 downto 40) <= m11_p(23 downto 0);
    m_out.result(39 downto 23) <= m10_p(16 downto 0);
    m_out.result(22 downto 0)  <= product_lo;

    m_out.overflow <= not ((p0_pat and p1_pat) or (p0_patb and p1_patb));

    process(clk)
    begin
        if rising_edge(clk) and stall = '0' then
            m_out.valid <= m_in.valid;
            product_lo <= m01_p(5 downto 0) & m00_p(16 downto 0);
        end if;
    end process;

end architecture behaviour;
