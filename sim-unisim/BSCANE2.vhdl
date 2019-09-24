library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.ALL;

library unisim;
use unisim.vcomponents.all;

entity BSCANE2 is
    generic(jtag_chain: INTEGER);
    port(capture : out std_logic;
	 drck	 : out std_logic;
	 reset	 : out std_logic;
	 runtest : out std_logic;
	 sel	 : out std_logic;
	 shift	 : out std_logic;
	 tck	 : out std_logic;
	 tdi	 : out std_logic;
	 tms	 : out std_logic;
	 update	 : out std_logic;
	 tdo	 : in std_logic
	 );
end BSCANE2;

architecture behaviour of BSCANE2 is
    alias j : glob_jtag_t is glob_jtag;
begin
    sel <= j.sel(jtag_chain);
    tck <= j.tck;
    drck <= tck and sel and (capture or shift);
    capture <= j.capture;
    reset <= j.reset;
    runtest <= j.runtest;
    shift <= j.shift;
    tdi <= j.tdi;
    tms <= j.tms;
    update <= j.update;
    j.tdo <= tdo;
end architecture behaviour;

