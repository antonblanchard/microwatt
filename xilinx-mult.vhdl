library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.common.all;

library unisim;
use unisim.vcomponents.all;

entity multiply is
    port (
        clk   : in std_logic;

        m_in  : in MultiplyInputType;
        m_out : out MultiplyOutputType
        );
end entity multiply;

architecture behaviour of multiply is
    signal d1sign : std_ulogic_vector(13 downto 0);
    signal d2sign : std_ulogic_vector(4 downto 0);
    signal m00_p, m01_p, m02_p, m03_p : std_ulogic_vector(47 downto 0);
    signal m00_pc, m02_pc : std_ulogic_vector(47 downto 0);
    signal m10_p, m11_p, m12_p, m13_p : std_ulogic_vector(47 downto 0);
    signal m10_pc, m12_pc : std_ulogic_vector(47 downto 0);
    signal m20_p, m21_p, m22_p, m23_p : std_ulogic_vector(47 downto 0);
    signal m20_pc, m22_pc : std_ulogic_vector(47 downto 0);
    signal pp0, pp1 : std_ulogic_vector(127 downto 0);
    signal pp23 : std_ulogic_vector(127 downto 0);
    signal sumlo : std_ulogic_vector(8 downto 0);
    signal s0_pc, s1_pc : std_ulogic_vector(47 downto 0);
    signal s0_carry, p0_carry : std_ulogic_vector(3 downto 0);
    signal product : std_ulogic_vector(127 downto 0);
    signal addend : std_ulogic_vector(127 downto 0);
    signal p0_pat, p0_patb : std_ulogic;
    signal p1_pat, p1_patb : std_ulogic;

    signal rnot_1 : std_ulogic;
    signal valid_1 : std_ulogic;
    signal overflow : std_ulogic;

begin
    addend <= m_in.addend when m_in.subtract = '0' else not m_in.addend;
    d1sign <= (others => m_in.data1(63) and m_in.is_signed);
    d2sign <= (others => m_in.data2(63) and m_in.is_signed);

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
            PREG => 1
            )
        port map (
            A => 6x"0" & m_in.data1(23 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(16 downto 0),
            BCIN => (others => '0'),
            C => 14x"0" & addend(33 downto 0),
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
            CEP => m_in.valid,
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => 6x"0" & m_in.data1(23 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(33 downto 17),
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
            CEM => m_in.valid,
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

    m02: DSP48E1
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
            PREG => 1
            )
        port map (
            A => 6x"0" & m_in.data1(23 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(50 downto 34),
            BCIN => (others => '0'),
            C => 24x"0" & addend(57 downto 34),
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
            CEP => m_in.valid,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0110101",
            P => m02_p,
            PCIN => (others => '0'),
            PCOUT => m02_pc,
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

    m03: DSP48E1
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => 6x"0" & m_in.data1(23 downto 0),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => d2sign & m_in.data2(63 downto 51),
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
            CEM => m_in.valid,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m03_p,
            PCIN => m02_pc,
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
            CREG => 0,
            INMODEREG => 0,
            MREG => 0,
            OPMODEREG => 0,
            PREG => 1
            )
        port map (
            A => 6x"0" & m_in.data1(47 downto 24),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(16 downto 0),
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
            CEP => m_in.valid,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0000101",
            P => m10_p,
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => 6x"0" & m_in.data1(47 downto 24),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(33 downto 17),
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
            CEM => m_in.valid,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m11_p,
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

    m12: DSP48E1
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
            PREG => 1
            )
        port map (
            A => 6x"0" & m_in.data1(47 downto 24),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(50 downto 34),
            BCIN => (others => '0'),
            C => 24x"0" & addend(81 downto 58),
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
            CEP => m_in.valid,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0110101",
            P => m12_p,
            PCIN => (others => '0'),
            PCOUT => m12_pc,
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

    m13: DSP48E1
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => 6x"0" & m_in.data1(47 downto 24),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => d2sign & m_in.data2(63 downto 51),
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
            CEM => m_in.valid,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m13_p,
            PCIN => m12_pc,
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

    m20: DSP48E1
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
            PREG => 1
            )
        port map (
            A => d1sign & m_in.data1(63 downto 48),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(16 downto 0),
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
            CEP => m_in.valid,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0000101",
            P => m20_p,
            PCIN => (others => '0'),
            PCOUT => m20_pc,
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

    m21: DSP48E1
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => d1sign & m_in.data1(63 downto 48),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(33 downto 17),
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
            CEM => m_in.valid,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m21_p,
            PCIN => m20_pc,
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

    m22: DSP48E1
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
            PREG => 1
            )
        port map (
            A => d1sign & m_in.data1(63 downto 48),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => '0' & m_in.data2(50 downto 34),
            BCIN => (others => '0'),
            C => "00" & addend(127 downto 82),
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
            CEP => m_in.valid,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0110101",
            P => m22_p,
            PCIN => (others => '0'),
            PCOUT => m22_pc,
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

    m23: DSP48E1
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
            MREG => 1,
            OPMODEREG => 0,
            PREG => 0
            )
        port map (
            A => d1sign & m_in.data1(63 downto 48),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => d2sign & m_in.data2(63 downto 51),
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
            CEM => m_in.valid,
            CEP => '0',
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "1010101",
            P => m23_p,
            PCIN => m22_pc,
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

    pp0 <= std_ulogic_vector(resize(signed(m13_p(37 downto 0) & m12_p(16 downto 0) &
                                           m01_p(40 downto 0) & m00_p(16 downto 0)), 128));
    pp1 <= m23_p(28 downto 0) & m22_p(16 downto 0) & m11_p(40 downto 0) & m10_p(16 downto 0) & 24x"0";
    -- pp2 <= std_ulogic_vector(resize(signed(m03_p(37 downto 0) & m02_p(16 downto 0) & 34x"0"), 128));
    -- pp3 <= std_ulogic_vector(resize(signed(m21_p(34 downto 0) & m20_p(16 downto 0) & 48x"0"), 128));

    pp23 <= std_ulogic_vector(resize(resize(signed(m03_p(37 downto 0) & m02_p(16 downto 0) & 34x"0"), 100) +
                                     signed(m21_p(34 downto 0) & m20_p(16 downto 0) & 48x"0"), 128));

    sumlo <= std_ulogic_vector(unsigned('0' & pp0(31 downto 24)) + unsigned('0' & pp1(31 downto 24)));

    s0: DSP48E1
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
            PREG => 0,
            USE_MULT => "none"
            )
        port map (
            A => pp0(79 downto 50),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => pp0(49 downto 32),
            BCIN => (others => '0'),
            C => pp1(79 downto 32),
            CARRYCASCIN => '0',
            CARRYIN => '0',
            CARRYINSEL => "000",
            CARRYOUT => s0_carry,
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
            OPMODE => "0001111",
            PCIN => (others => '0'),
            PCOUT => s0_pc,
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

    s1: DSP48E1
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
            PREG => 1,
            USE_MULT => "none"
            )
        port map (
            A => pp0(127 downto 98),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => pp0(97 downto 80),
            BCIN => (others => '0'),
            C => pp1(127 downto 80),
            CARRYCASCIN => '0',
            CARRYIN => s0_carry(3),
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
            CEP => valid_1,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0001111",
            PCIN => (others => '0'),
            PCOUT => s1_pc,
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

    p0: DSP48E1
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
            MASK => x"00007fffffff",
            MREG => 0,
            OPMODEREG => 0,
            PREG => 1,
            USE_MULT => "none",
            USE_PATTERN_DETECT => "PATDET"
            )
        port map (
            A => pp23(79 downto 50),
            ACIN => (others => '0'),
            ALUMODE => "00" & rnot_1 & '0',
            B => pp23(49 downto 32),
            BCIN => (others => '0'),
            C => (others => '0'),
            CARRYCASCIN => '0',
            CARRYIN => sumlo(8),
            CARRYINSEL => "000",
            CARRYOUT => p0_carry,
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
            CEP => valid_1,
            CLK => clk,
            D => (others => '0'),
            INMODE => "00000",
            MULTSIGNIN => '0',
            OPMODE => "0010011",
            P => product(79 downto 32),
            PATTERNDETECT => p0_pat,
            PATTERNBDETECT => p0_patb,
            PCIN => s0_pc,
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

    p1: DSP48E1
        generic map (
            ACASCREG => 1,
            ALUMODEREG => 1,
            AREG => 1,
            BCASCREG => 1,
            BREG => 1,
            CARRYINREG => 0,
            CARRYINSELREG => 0,
            CREG => 0,
            INMODEREG => 0,
            MASK => x"000000000000",
            MREG => 0,
            OPMODEREG => 0,
            PREG => 0,
            USE_MULT => "none",
            USE_PATTERN_DETECT => "PATDET"
            )
        port map (
            A => pp23(127 downto 98),
            ACIN => (others => '0'),
            ALUMODE => "00" & rnot_1 & '0',
            B => pp23(97 downto 80),
            BCIN => (others => '0'),
            C => (others => '0'),
            CARRYCASCIN => '0',
            CARRYIN => p0_carry(3),
            CARRYINSEL => "000",
            CEA1 => '0',
            CEA2 => valid_1,
            CEAD => '0',
            CEALUMODE => valid_1,
            CEB1 => '0',
            CEB2 => valid_1,
            CEC => valid_1,
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
            OPMODE => "0010011",
            P => product(127 downto 80),
            PATTERNDETECT => p1_pat,
            PATTERNBDETECT => p1_patb,
            PCIN => s1_pc,
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

    process(clk)
    begin
        if rising_edge(clk) then
            if valid_1 = '1' then
                if rnot_1 = '0' then
                    product(31 downto 0) <= sumlo(7 downto 0) & pp0(23 downto 0);
                else
                    product(31 downto 0) <= not (sumlo(7 downto 0) & pp0(23 downto 0));
                end if;
            end if;
            m_out.valid <= valid_1;
            valid_1 <= m_in.valid;
            rnot_1 <= m_in.subtract;
            overflow <= not ((p1_pat and p0_pat) or (p1_patb and p0_patb));
        end if;
    end process;

    m_out.result <= product;
    m_out.overflow <= overflow;

end architecture behaviour;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity short_multiply is
    port (
        clk   : in std_logic;

        a_in  : in std_ulogic_vector(15 downto 0);
        b_in  : in std_ulogic_vector(15 downto 0);
        m_out : out std_ulogic_vector(31 downto 0)
        );
end entity short_multiply;

architecture behaviour of short_multiply is
    signal mshort_p : std_ulogic_vector(47 downto 0);
begin
    mshort: DSP48E1
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
            A => std_ulogic_vector(resize(signed(a_in(15 downto 0)), 30)),
            ACIN => (others => '0'),
            ALUMODE => "0000",
            B => std_ulogic_vector(resize(signed(b_in(15 downto 0)), 18)),
            BCIN => (others => '0'),
            C => 48x"0",
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
            P => mshort_p,
            PCIN => (others => '0'),
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

    m_out <= mshort_p(31 downto 0);

end architecture behaviour;
