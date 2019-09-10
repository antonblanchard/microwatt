library IEEE;
use IEEE.std_logic_1164.all;

entity BUFG is
    port(I	: in std_logic;
	 O	: out std_logic
	 );
end BUFG;
architecture behaviour of BUFG is
begin
    O <= I;
end architecture behaviour;
