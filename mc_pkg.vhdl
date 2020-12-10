library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mc_pkg is

constant BAR_BITS : integer := 16;

--types 
type T_Config is record
   oib_en    : std_ulogic;
   oib_ratio : std_ulogic_vector(3 downto 0);      
   oib_width : std_ulogic_vector(2 downto 0);
   cpol      : std_ulogic;
   cpha      : std_ulogic;
   ib_en_pck : std_ulogic;
   rsvd0     : std_ulogic_vector(2 downto 0);
   bar_en    : std_ulogic;
   int_req   : std_ulogic;
   bar       : std_ulogic_vector(BAR_BITS-1 downto 0);
   --bar mask
   rsvd1     : std_ulogic_vector(7 downto 0);
   idle_flit : std_ulogic_vector(7 downto 0);
   rcv_header : std_ulogic_vector(7 downto 0);
   err       : std_ulogic_vector(7 downto 0);       
end record;

-- functions
function inc(a: in std_ulogic_vector) return std_ulogic_vector;
function inc(a: in std_ulogic_vector; b: in integer) return std_ulogic_vector;use ieee.numeric_std.all;
function dec(a: in std_ulogic_vector) return std_ulogic_vector;
function eq(a: in std_ulogic_vector; b: in integer) return boolean;
function eq(a: in std_ulogic_vector; b: in integer) return std_ulogic;
function eq(a: in std_ulogic_vector; b: in std_ulogic_vector) return boolean;
function eq(a: in std_ulogic_vector; b: in std_ulogic_vector) return std_ulogic;

function gate_and(a: in std_ulogic; b: in std_ulogic_vector) return std_ulogic_vector;
function or_reduce(slv: in std_ulogic_vector) return std_ulogic;
function and_reduce(slv: in std_ulogic_vector) return std_ulogic;

function clog2(n : in integer) return integer;

function bus_ratio_enc(n : in integer) return std_ulogic_vector;
function bus_width_enc(n : in integer) return std_ulogic_vector;

end package mc_pkg;


package body mc_pkg is

function inc(a: in std_ulogic_vector) return std_ulogic_vector is
  variable res: std_ulogic_vector(0 to a'length-1);
begin
  res := std_ulogic_vector(unsigned(a) + 1);
  return res;
end function;

function inc(a: in std_ulogic_vector; b: in integer) return std_ulogic_vector is
  variable res: std_ulogic_vector(0 to a'length-1);
begin
  res := std_ulogic_vector(unsigned(a) + b);
  return res;
end function;

function dec(a: in std_ulogic_vector) return std_ulogic_vector is
  variable res: std_ulogic_vector(0 to a'length-1);
begin
  res := std_ulogic_vector(unsigned(a) - 1);
  return res;
end function;

function eq(a: in std_ulogic_vector; b: in integer) return boolean is
  variable res: boolean;
begin
  res := unsigned(a) = b;
  return res;
end function;

function eq(a: in std_ulogic_vector; b: in integer) return std_ulogic is
  variable res: std_ulogic;
begin
  if unsigned(a) = b then
   res := '1';
  else
   res := '0';
  end if;
  return res;
end function;

function eq(a: in std_ulogic_vector; b: in std_ulogic_vector) return boolean is
  variable res: boolean;
begin
  res := unsigned(a) = unsigned(b);
  return res;
end function;

function eq(a: in std_ulogic_vector; b: in std_ulogic_vector) return std_ulogic is
  variable res: std_ulogic;
begin
  if unsigned(a) = unsigned(b) then
    res := '1';
  else
    res := '0';
  end if;
  return res;
end function;

function gate_and(a: in std_ulogic; b: in std_ulogic_vector) return std_ulogic_vector is
  variable res: std_ulogic_vector(0 to b'length-1);
begin
  if a = '1' then
     res := b;
  else   
     res := (others => '0');  
  end if;
  return res;
end function;		

function or_reduce(slv: in std_ulogic_vector) return std_ulogic is
  variable res: std_logic := '0';
begin
  for i in 0 to slv'length-1 loop
    res := res or slv(i);
  end loop;
  return res;
end function;

function and_reduce(slv: in std_ulogic_vector) return std_ulogic is
  variable res: std_logic := '1';
begin
  for i in 0 to slv'length-1 loop
    res := res and slv(i);
  end loop;
  return res;
end function;

function clog2(n : in integer) return integer is            
   variable i : integer;
   variable j : integer := n - 1;
	variable res : integer := 1;                                       
begin                                                                   
   for i in 0 to 31 loop
      if (j > 1) then
         j := j / 2;
         res := res + 1;
      else
         exit;
      end if;
   end loop;
   return res;        	                                              
end;

function bus_ratio_enc(n : in integer) return std_ulogic_vector is
   variable res : std_ulogic_vector(3 downto 0);
begin
   case n is
      when    1    => res := "0000";	
      when    2    => res := "0001";	
      when    4    => res := "0010";	
      when    8    => res := "0011";	
      when   16    => res := "0100";	
      when   32    => res := "0101";	   
      when   64    => res := "0110";	               
      when  128    => res := "0111";	               
      when  256    => res := "1000";	
      when  512    => res := "1001";	                                 
      when others  => res := "1111";
   end case;
   return res;
end;

function bus_width_enc(n : in integer) return std_ulogic_vector is
   variable res : std_ulogic_vector(2 downto 0);
begin
   case n is
      when   1    => res := "000";	
      when   2    => res := "001";	
      when   4    => res := "010";	
      when   8    => res := "011";	
      when  16    => res := "100";	                                   
      when others => res := "111";
   end case;
   return res;
end;

end package body mc_pkg;
