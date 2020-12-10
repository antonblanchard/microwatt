-- Wishbone slave to packet bus

-- add way to reset (or do externally)
-- not obeying sel on local writes yet!
-- theoretically, this should work with slave-initiated packets like ints, even
--  if they intervene within a pending master command (unpreventable because of
--  concurrent xmits).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;
use work.mc_pkg.all;

entity mc is

   generic(
      WB_AW          : integer := 32;        -- wishbone_addr_bits
      WB_DW          : integer := 64;        -- wishbone_data_bits
      OIB_DW         : integer := 8;
      OIB_RATIO      : integer := 0;         -- encode
      --WB_MAX_WR 	   : integer := 1;      -- could allow posted writes (no wait for ack)
--      BAR_BITS       : integer := 16;        -- in mc_pkg
      BAR_INIT       : std_ulogic_vector(BAR_BITS-1 downto 0) := x"FFFF" -- FFFFxxxx is local
	 );
    port(
      clk	         : in  std_ulogic;
      rst   	      : in  std_ulogic;

      wb_cyc         : in  std_ulogic;
      wb_stb         : in  std_ulogic;
      wb_we          : in  std_ulogic;
      wb_addr        : in  std_ulogic_vector(WB_AW-1 downto 0);
      wb_wr_data     : in  std_ulogic_vector(WB_DW-1 downto 0);
      wb_sel         : in  std_ulogic_vector((WB_DW/8)-1 downto 0);
      wb_ack         : out std_ulogic;
      wb_err         : out std_ulogic;
      wb_stall       : out std_ulogic;
      wb_rd_data     : out std_ulogic_vector(WB_DW-1 downto 0);
      
      oib_clk        : out std_ulogic;
      ob_data        : out std_ulogic_vector(OIB_DW-1 downto 0);
      ob_pty         : out std_ulogic;
      
      ib_data        : in  std_ulogic_vector(OIB_DW-1 downto 0);
      ib_pty         : in  std_ulogic;
      
      err            : out std_ulogic;      
      int            : out std_ulogic
    );
end mc;


architecture mc of mc is

-- ff
signal config_d, config_q, config_rst: T_Config;
signal config_data : std_ulogic_vector(WB_DW-1 downto 0);

signal wbseq_d, wbseq_q : std_ulogic_vector(3 downto 0);
signal wb_in_d, wb_in_q : wishbone_master_out;
signal wb_out_d, wb_out_q : wishbone_slave_out;

signal oclk_d, oclk_q : std_ulogic;
signal oclk_last_d, oclk_last_q : std_ulogic;
signal odata_d, odata_q : std_ulogic_vector(OIB_DW-1 downto 0);
signal opty_d, opty_q : std_ulogic;
signal oseq_d, oseq_q : std_ulogic_vector(3 downto 0);
signal oclk_cnt_d, oclk_cnt_q : std_ulogic_vector(15 downto 0);
signal odata_cnt_d, odata_cnt_q : std_ulogic_vector(2 downto 0);

signal idata_d, idata_q : std_ulogic_vector(OIB_DW-1 downto 0);
signal ipty_d, ipty_q : std_ulogic;
signal iseq_d, iseq_q : std_ulogic_vector(3 downto 0);
signal icapture_d, icapture_q : std_ulogic;
signal idata_cnt_d, idata_cnt_q : std_ulogic_vector(2 downto 0);

-- misc
signal wbseq_err : std_ulogic;
signal wb_req, wb_req_err, wb_local, wb_local_rd, wb_local_wr, wb_remote_rd, wb_remote_wr, wb_req_stall, wb_sync : std_ulogic;
signal rd_data_load : std_ulogic_vector(WB_DW-1 downto 0);
signal ob_busy, ob_stall : std_ulogic;
signal local_rd_data : std_ulogic_vector(WB_DW-1 downto 0);
signal ob_header : std_ulogic_vector(OIB_DW-1 downto 0);

signal oclk_advance, ob_complete, oseq_err, oseq_hold, iseq_err, rd_err, wr_err : std_ulogic;
signal odata_clear, odata_advance, oaddr_last, odata_last, odata_ld_header, odata_ld_addr, odata_ld_sel, odata_ld_data : std_ulogic;
signal oaddr_mux : std_ulogic_vector(7 downto 0);
signal odata_mux : std_ulogic_vector(7 downto 0);
signal ib_complete : std_ulogic;
signal oclk_match : std_ulogic;
signal oclk_toggle : std_ulogic_vector(15 downto 0);  
signal config_write : std_ulogic;
signal wb_rd_resp, idata_clear : std_ulogic;
signal link_req_o, link_rsp_o, link_req_i, link_rsp_i : std_ulogic;
signal rd8_rsp, wr8_rsp, cache_inv, sync_ack, int_req : std_ulogic;
signal bad_header, good_header, pty_err, ld_rd_data : std_ulogic;
signal iseq_idle, idle_header, rd_rsp_data_done, rd_rsp_complete, wr_rsp_complete, int_req_complete, save_header : std_ulogic;

begin

-- these could sample the input bus for several of the bits on reset, but you need to know how wide the bus is
-- maybe use another pin to determine if config_pins or hardcoded default are used
--config_pins <= 

config_rst <= (oib_en => '1', oib_width => bus_width_enc(OIB_DW), oib_ratio => bus_ratio_enc(OIB_RATIO), cpol => '0', cpha => '0',
               ib_en_pck => '1', rsvd0 => (others => '0'), int_req => '1', bar_en => '1',
               bar => BAR_INIT, 
               rsvd1 => (others => '0'),
               idle_flit => (others => '0'), rcv_header => (others => '0'), 
               err => (others => '0')
               );

config_data <= config_q.oib_en & config_q.oib_width & config_q.oib_ratio &                                                 -- 63:56
               config_q.cpol & config_q.cpha & config_q.ib_en_pck & config_q.rsvd0 & config_q.int_req & config_q.bar_en &  -- 55:48
               config_q.bar &                                                                                              -- 47:32
               config_q.rsvd1 &                                                                                            -- 31:24
               config_q.idle_flit & config_q.rcv_header &                                                                  -- 23:08
               config_q.err;                                                                                               -- 07:00

int <= config_q.int_req;
--err <= or_reduce(config_q.err);
err <= config_q.err(7) or config_q.err(6) or config_q.err(5) or config_q.err(4) or config_q.err(3) or config_q.err(2) or config_q.err(1) or config_q.err(0);

-- normal FF
FF: process(clk) begin
	
if rising_edge(clk) then
	
   if rst = '1' then 
	   
      config_q <= config_rst; 
      wb_in_q <= wishbone_master_out_init;
      wb_out_q <= wishbone_slave_out_init;
      oclk_q  <= '0';
      oclk_last_q <= '0';
      odata_q <= (others => '0');
      opty_q  <= '1';
      wbseq_q <= (others => '1');      
      oseq_q <= (others => '1');
      iseq_q <= (others => '1');  
      oclk_cnt_q <= (others => '0');
      odata_cnt_q <= (others => '0');
      idata_cnt_q <= (others => '0');      
      icapture_q <= '0';     
      idata_q <= (others => '0');
      ipty_q  <= '1';
                  	                	              
	else
	    
	   config_q <= config_d;
	   wb_in_q <= wb_in_d;
	   wb_out_q <= wb_out_d;
	   oclk_q <= oclk_d;
	   oclk_last_q <= oclk_last_d;
	   odata_q <= odata_d;
	   opty_q <= opty_d;
	   wbseq_q <= wbseq_d;
      oseq_q <= oseq_d;
      iseq_q <= iseq_d;
      oclk_cnt_q <= oclk_cnt_d;
      odata_cnt_q <= odata_cnt_d;
      idata_cnt_q <= idata_cnt_d;
      icapture_q <= icapture_d;
      idata_q <= idata_d;
      ipty_q  <= ipty_d;
         
   end if;
	
end if;
	
end process FF;

-- do something

-- latch master - cyc/stb should be a single valid 

wb_req <= wb_cyc and wb_stb and not wb_out_q.stall;
wb_in_d.cyc <= '1' when wb_req = '1' else (wb_in_q.cyc and not wb_out_q.ack);
wb_in_d.stb <= '1' when wb_req = '1' else (wb_in_q.stb and not wb_out_q.ack);
wb_in_d.we  <= wb_we  when wb_req = '1' else wb_in_q.we;
wb_in_d.adr <= wb_addr when wb_req = '1' else wb_in_q.adr;
wb_in_d.dat <= wb_wr_data when wb_req = '1' else wb_in_q.dat;
wb_in_d.sel <= wb_sel when wb_req = '1' else wb_in_q.sel;

-- process req

-- move to unlatched
--wb_local <= config_q.bar_en and eq(wb_in_q.adr(WB_AW-1 downto WB_AW-BAR_BITS), config_q.bar);
wb_local <= config_q.bar_en and eq(wb_addr(WB_AW-1 downto WB_AW-BAR_BITS), config_q.bar);

-- should be able to ack immediately rather than send latched (skip ack cycle in seq, send _d)

--tbl WBSlaveSeq
--n wbseq_q                             wbseq_d                
--n |     wb_req                        |             
--n |     |                             |     wb_local_rd                         
--n |     | wb_we                       |     |wb_local_wr   
--n |     | |                           |     ||wb_remote_rd   
--n |     | |                           |     |||wb_remote_wr                                                          
--n |     | |                           |     |||| wb_out_d.stall
--n |     | |  wb_local                 |     |||| |wb_out_d.ack            
--n |     | |  | ob_complete            |     |||| || oseq_hold             
--n |     | |  | |rd_rsp_complete       |     |||| || |    
--n |     | |  | ||wr_rsp_complete      |     |||| || |                    
--n |     | |  | |||                    |     |||| || |   wbseq_err
--b 3210  | |  | |||                    3210  |||| || |   |
--t iiii  i i  i iii                    oooo  oooo oo o   o
--*--------------------------------------------------------------------------------------------------------------------
--*-- Idle ------------------------------------------------------------------------------------------------------------
--s 1111  0 -  - ---                    1111  0000 00 0   0              * zzz..zzz....     
--s 1111  1 0  1 ---                    0001  1000 10 0   0              * read local
--s 1111  1 1  1 ---                    0010  0100 10 0   0              * write local
--s 1111  1 0  0 ---                    0100  0010 10 0   0              * read remote
--s 1111  1 1  0 ---                    1000  0001 10 0   0              * write remote
--*-- Read Local ------------------------------------------------------------------------------------------------------
--s 0001  - -  - ---                    1110  0000 11 0   0              * read ack
--*-- Write Local -----------------------------------------------------------------------------------------------------
--s 0010  - -  - ---                    1110  0000 11 0   0              * write ack
--*-- Read Remote -----------------------------------------------------------------------------------------------------
--s 0100  - -  - ---                    ----  0010 10 0   0              *
--s 0100  - -  - 0--                    0100  ---- -- -   -              * read send
--s 0100  - -  - 1--                    0101  ---- -- -   -              * read sent
--*-- Read Remote Wait ------------------------------------------------------------------------------------------------
--s 0101  - -  - ---                    ----  0010 10 1   0              *
--s 0101  - -  - -0-                    0101  ---- -- -   -              * wait for response
--s 0101  - -  - -1-                    0110  ---- -- -   -              * response received
--*-- Read Remote Done-------------------------------------------------------------------------------------------------
--s 0110  - -  - -0-                    1110  0010 11 1   0              * read ack
--*-- Write Remote ----------------------------------------------------------------------------------------------------
--s 1000  - -  - ---                    ----  0001 10 0   0              *
--s 1000  - -  - 0--                    1000  ---- -- -   -              * write send
--s 1000  - -  - 1--                    1001  ---- -- -   -              * write sent
--*-- Write Remote Wait -----------------------------------------------------------------------------------------------
--s 1001  - -  - ---                    ----  0001 10 1   0              *
--s 1001  - -  - --0                    1001  ---- -- -   -              * wait for response
--s 1001  - -  - --1                    1010  ---- -- -   -              * response received
--*-- Write Remote Done -----------------------------------------------------------------------------------------------
--s 1010  - -  - ---                    1110  0000 11 1   0              * write ack
--*-- Ack Cycle -------------------------------------------------------------------------------------------------------
--s 1110  - -  - ---                    1111  0000 00 1   0              * last cycle of stall; ack=1
--*-- ERROR -----------------------------------------------------------------------------------------------------------
--s 0000  - -  - ---                    0000  0000 00 0   1     
--s 0011  - -  - ---                    0011  0000 00 0   1         
--s 0111  - -  - ---                    0111  0000 00 0   1  
--s 1011  - -  - ---                    1011  0000 00 0   1      
--s 1100  - -  - ---                    1100  0000 00 0   1                                                          
--s 1101  - -  - ---                    1101  0000 00 0   1                                                                                                              
--*--------------------------------------------------------------------------------------------------------------------

--tbl WBSlaveSeq

-- local

-- move to unlatched
--config_write <= wb_local_wr and eq(wb_in_q.adr(31-BAR_BITS downto 0), 0);
config_write <= wb_local_wr and eq(wb_addr(31-BAR_BITS downto 0), 0);

config_d.oib_en    <= wb_in_d.dat(63)           when config_write = '1' else config_q.oib_en;
config_d.oib_ratio <= wb_in_d.dat(62 downto 59) when config_write = '1' else config_q.oib_ratio;
config_d.oib_width <= wb_in_d.dat(58 downto 56) when config_write = '1' else config_q.oib_width;
config_d.cpol      <= wb_in_d.dat(55)           when config_write = '1' else config_q.cpol;
config_d.cpha      <= wb_in_d.dat(54)           when config_write = '1' else config_q.cpha;
config_d.ib_en_pck <= wb_in_d.dat(50)           when config_write = '1' else config_q.ib_en_pck;
config_d.rsvd0     <= wb_in_d.dat(53 downto 51) when config_write = '1' else config_q.rsvd0;
config_d.int_req   <= wb_in_d.dat(49)           when config_write = '1' else (config_q.int_req or int_req_complete);
config_d.bar_en    <= wb_in_d.dat(48)           when config_write = '1' else config_q.bar_en;
config_d.bar       <= wb_in_d.dat(47 downto 32) when config_write = '1' else config_q.bar;
config_d.rsvd1     <= wb_in_d.dat(31 downto 24) when config_write = '1' else config_q.rsvd1;
config_d.idle_flit <= wb_in_d.dat(23 downto 16) when config_write = '1' else config_q.idle_flit;
-- or write once until cleared?
config_d.rcv_header <= wb_in_d.dat(15 downto 8) when config_write = '1' else
  gate_and(save_header, idata_q) or gate_and(not save_header, config_q.rcv_header);

config_d.err <= wb_in_d.dat(7 downto 0) when config_write = '1' else 
  (config_q.err(7) or wbseq_err) & (config_q.err(6) or oseq_err) & (config_q.err(5) or iseq_err) & (config_q.err(4) or rd_err) &
  (config_q.err(3) or wr_err) & (config_q.err(2) or pty_err) & (config_q.err(1) or bad_header) & config_q.err(0);

-- outputs
wb_stall   <= wb_out_q.stall;  
wb_ack     <= wb_out_q.ack;    
wb_rd_data <= wb_out_q.dat;
wb_err     <= '0';

-- send 

wb_sync <= '0';
link_req_o <= '0';
link_rsp_o <= '0';

--tbl HeaderEncode
--n wb_remote_rd                        ob_header
--n |wb_remote_wr                       |       
--n ||wb_sync                           |                            
--n |||     link_req_o                  |       
--n |||     |link_rsp_o                 |       
--n |||     ||                          |                                                                         
--n |||     ||                          |    
--b |||     ||                          76543210 
--t iii     ii                          oooooooo             
--*-------------------------------------------------
--s 1--     --                          00000010    * read 8B
--s -1-     --                          00000011    * write 8B
--s --1     --                          01000000    * sync and code
--s ---     1-                          11110000    * link req and code
--s ---     -1                          11111000    * link rsp and code
--*-------------------------------------------------

--tbl HeaderEncode

-- bus clock

with config_q.oib_ratio select
   oclk_toggle <= x"0000" when "0000",  -- toggle every clk    2:1 * fails right now *
                  x"0001" when "0001",  -- toggle every 2      4:1
                  x"0002" when "0010",  -- toggle every 3      6:1
                  x"0004" when "0011",  -- toggle every 5     10:1
                  x"0008" when "0100",  -- toggle every 9     18:1
                  x"0010" when "0101",  -- toggle every 17    34:1
                  x"0020" when "0110",  -- toggle every 33    66:1
                  x"0040" when "0111",  -- toggle every 65   130:1
                  x"0080" when "1000",  -- toggle every 129  258:1                  
                  x"0100" when "1001",  -- toggle every 257  514:1                                                     
                  x"0200" when others;  -- toggle every 513 1026:1                  

oclk_match <= eq(oclk_cnt_q, oclk_toggle);

oclk_cnt_d <= gate_and(not config_q.oib_en or config_write, x"0000") or
              gate_and(config_q.oib_en and not config_write and oclk_match, x"0000") or
              gate_and(config_q.oib_en and not config_write and not oclk_match, inc(oclk_cnt_q));
   
oclk_advance <= oclk_match and oclk_q;

oib_clk <= oclk_q;

oclk_d      <= (oclk_q xor oclk_match) and config_q.oib_en;
oclk_last_d <= oclk_q and config_q.oib_en;

-- cpol not used; clock always running  

with config_q.cpha select 
   icapture_d <= not oclk_last_q and oclk_q and config_q.oib_en when '0',     -- rising 
                 oclk_last_q and not oclk_q and config_q.oib_en when others;  -- falling

-- output

--tbl SendSeq
--
--n oseq_q                              oseq_d
--n |    oseq_hold                      |                       
--n |    |wb_remote_rd                  |     odata_ld_header    
--n |    ||wb_remote_wr                 |     |odata_ld_addr         
--n |    |||                            |     ||odata_ld_sel
--n |    |||   oclk_advance             |     |||odata_clear          
--n |    |||   |oaddr_last              |     ||||odata_ld_data
--n |    |||   ||odata_last             |     ||||| ob_complete
--n |    |||   |||                      |     ||||| |        
--n |    |||   |||                      |     ||||| |   oseq_err
--b 3210 |||   |||                      3210  ||||| |   |
--t iiii iii   iii                      oooo  ooooo o   o
--*-------------------------------------------------------------------------------------------------------------------
--*-- Idle -----------------------------------------------------------------------------------------------------------
--s 1111 1--   ---                      1111  00010 0   0               * zzz..zzz...  
--s 1111 -00   ---                      1111  00010 0   0               * zzz..zzz...              
--s 1111 0--   0--                      1111  00010 0   0               * ...slow...
--s 1111 01-   1--                      0001  10000 0   0               * start read
--s 1111 0-1   1--                      0001  10000 0   0               * start write
--*-- Remote Header --------------------------------------------------------------------------------------------------
--s 0001 ---   0--                      0001  00000 0   0               * ...slow...
--s 0001 -1-   1--                      0010  01000 0   0               * begin address
--s 0001 --1   1--                      0010  01000 0   0               * begin address
--*-- Remote Address -------------------------------------------------------------------------------------------------
--s 0010 ---   0--                      0010  01000 0   0               * ...slow...
--s 0010 ---   10-                      0010  01000 0   0               * sending addr
--s 0010 --0   11-                      1111  00010 1   0               * finish read request
--s 0010 --1   11-                      0011  00110 0   0               * begin write sel
--*-- Remote Write (Sel) ---------------------------------------------------------------------------------------------
--s 0011 ---   0--                      0011  00000 0   0               * ...slow...
--s 0011 ---   1--                      0100  00001 0   0               * begin write data
--*-- Remote Write (Data) --------------------------------------------------------------------------------------------
--s 0100 ---   0--                      0100  00001 0   0               * ...slow...
--s 0100 ---   1-0                      0100  00001 0   0               * sending data
--s 0100 ---   1-1                      1111  00001 1   0               * finish write request
--*-- ERROR ----------------------------------------------------------------------------------------------------------
--s 0000 ---   ---                      0000  00000 0   1    
--s 0101 ---   ---                      0101  00000 0   1             
--s 0110 ---   ---                      0110  00000 0   1             
--s 0111 ---   ---                      0111  00000 0   1             
--s 1000 ---   ---                      1000  00000 0   1             
--s 1001 ---   ---                      1001  00000 0   1        
--s 1010 ---   ---                      1010  00000 0   1                      
--s 1011 ---   ---                      1011  00000 0   1                      
--s 1100 ---   ---                      1100  00000 0   1                      
--s 1101 ---   ---                      1101  00000 0   1                      
--s 1110 ---   ---                      1110  00000 0   1                                    
--*-------------------------------------------------------------------------------------------------------------------
--tbl SendSeq


-- 4 xfer for addr, 8 xfer for data
odata_cnt_d <= gate_and(odata_clear, "000") or
               gate_and(odata_advance and odata_ld_addr, inc(odata_cnt_q)) or  -- no clear?
               gate_and(odata_advance and odata_ld_data, inc(odata_cnt_q)) or  -- no clear?
               gate_and(not odata_clear and not(odata_advance and (odata_ld_addr or odata_ld_data)), odata_cnt_q);  

oaddr_last <= eq(odata_cnt_q, 4);
odata_last <= eq(odata_cnt_q, 7);

with odata_cnt_q select 
   oaddr_mux <= wb_in_q.adr(7 downto 0)   when "000",
                wb_in_q.adr(15 downto 8)  when "001",
                wb_in_q.adr(23 downto 16) when "010", 
                wb_in_q.adr(31 downto 24) when others;

with odata_cnt_q select
   odata_mux <= wb_in_q.dat(7 downto 0)   when "000",
                wb_in_q.dat(15 downto 8)  when "001",  
                wb_in_q.dat(23 downto 16) when "010",  
                wb_in_q.dat(31 downto 24) when "011",  
                wb_in_q.dat(39 downto 32) when "100",  
                wb_in_q.dat(47 downto 40) when "101",                  
                wb_in_q.dat(55 downto 48) when "110",  
                wb_in_q.dat(63 downto 56) when others;     
                
--wtf fix this to look normal                
odata_d <= gate_and(odata_clear and odata_advance, config_q.idle_flit) or
           gate_and(odata_ld_header, ob_header) or
           gate_and(odata_ld_addr and odata_advance, oaddr_mux) or
           gate_and(odata_ld_sel, wb_in_q.sel) or
           gate_and(odata_ld_data and odata_advance, odata_mux) or
           gate_and(not odata_ld_header and not odata_ld_sel and 
                    not(odata_ld_addr and odata_advance) and
                    not odata_ld_sel and 
                    not(odata_ld_data and odata_advance) and
                    not(odata_clear and odata_advance), odata_q);

opty_d <= not(odata_d(7) xor odata_d(6) xor odata_d(5) xor odata_d(4) xor odata_d(3) xor odata_d(2) xor odata_d(1) xor odata_d(0));                                                                                                          

odata_advance <= oclk_advance; -- oclk_match and not oclk_q and odata_ld_data;

ob_data <= odata_q;
ob_pty  <= opty_q;

-- input

with icapture_d select
   idata_d <= ib_data when '1',
              idata_q when others;
              
with icapture_d select
   ipty_d <= ib_pty when '1',
             ipty_q when others;
             

--tbl HeaderDecode
--n idata_q  wb_remote_rd               rd8_rsp
--n |        |wb_remote_wr              |wr8_rsp
--n |        ||                         ||int_req               
--n |        ||                         |||sync_ack     
--n |        ||                         ||||cache_inv    
--n |        ||                         |||||link_req_i                                                     
--n |        ||                         ||||||link_rsp_i
--n |        ||                         |||||||
--n |        ||                         ||||||| good_header 
--n |        ||                         ||||||| | 
--b 76543210 ||                         ||||||| | 
--t iiiiiiii ii                         ooooooo o               
--*-------------------------------------------------
--s 1000--10 1-                         1000000 1    * read 8B resp and code
--s 1000--11 -1                         0100000 1    * write 8B ack and code
--s 11000--- --                         0001000 1    * sync_ack and code (thread, type, etc.)
--s 11001--- --                         0000100 1    * cache inv
--s 11010--- --                         0010000 1    * int_req and code (ext, crit, stop, fry)
--s 11110--- --                         0000010 1    * link req and code
--s 11111--- --                         0000001 1    * link rsp and code
--*-------------------------------------------------
--tbl HeaderDecode

idle_header <= eq(idata_q, config_q.idle_flit);
bad_header <= iseq_idle and icapture_q and not idle_header and not good_header;
pty_err <= icapture_q and not(idata_q(0) xor idata_q(1) xor idata_q(2) xor idata_q(3) xor idata_q(4) xor idata_q(5) xor idata_q(6) xor idata_q(7) xor ipty_q);


--tbl RecvSeq
--
--n iseq_q                              iseq_d
--n |    icapture_q                     |   
--n |    |idle_header                   |    ld_rd_data             
--n |    ||rd8_rsp                      |    |rd_rsp_complete                   
--n |    |||wr8_rsp                     |    ||wr_rsp_complete                       
--n |    ||||int_req                    |    |||int_req_complete 
--n |    |||||sync_ack                  |    ||||                       
--n |    ||||||cache_inv                |    ||||                
--n |    |||||||link_req_i              |    ||||                     
--n |    ||||||||link_rsp_i             |    ||||  idata_clear            
--n |    |||||||||  bad_header          |    ||||  |save_header
--n |    |||||||||  |                   |    ||||  ||                                 
--n |    |||||||||  |  rd_rsp_data_done |    ||||  ||     iseq_idle                    
--n |    |||||||||  |  |                |    ||||  ||     |iseq_err                           
--b 3210 |||||||||  |  |                3210 ||||  ||     ||
--t iiii iiiiiiiii  i  i                oooo oooo  oo     oo   
--*-------------------------------------------------------------------------------------------------------------------
--*-- Idle -----------------------------------------------------------------------------------------------------------
--s 1111 ---------  -  -                ---- ----  --     10
--s 1111 0--------  -  -                1111 0000  10     --            * zzz..zzz...  
--s 1111 11-------  -  -                1111 0000  10     --            * idle
--s 1111 1--------  1  -                0110 0000  00     --            * bad header   
--s 1111 1-1------  -  -                1000 0000  00     --            * rd8 response
--s 1111 1--1-----  -  -                0001 0000  00     --            * wr8 ack
--s 1111 1---1----  -  -                0010 0000  00     --            * int req
--s 1111 1----1---  -  -                0110 0000  00     --            * other response
--s 1111 1-----1--  -  -                0110 0000  00     --            * other response
--s 1111 1------1-  -  -                0110 0000  00     --            * other response
--s 1111 1-------1  -  -                0110 0000  00     --            * other response
--*-- Rd Resp --------------------------------------------------------------------------------------------------------
--s 1000 0 -------  -  -                1000 0000  00     00            * ...slow...
--s 1000 1 -------  -  0                1000 1000  00     00            * Dx
--s 1000 1 -------  -  1                1111 1100  00     00            * Dlast
--*-- Wr Ack ---------------------------------------------------------------------------------------------------------
--s 0001 - -------  -  -                1111 0010  00     00            * ack + code
--*-- Int Req --------------------------------------------------------------------------------------------------------
--s 0010 - -------  -  -                1111 0001  01     00            * int + code
--*-- Unknown Header -------------------------------------------------------------------------------------------------
--s 0110 - -------  -  -                0111 0000  01     00            * save header and wait for idle bus
--*-- Wait for Idle --------------------------------------------------------------------------------------------------
--s 0111 0 -------  -  -                0110 0000  00     00            * ...slow...
--s 0111 11-------  -  -                1111 0000  00     00            * idle
--s 0111 10-------  -  -                0110 0000  00     00            * non-idle
--*-- ERROR ----------------------------------------------------------------------------------------------------------
--s 0000 ---------  -  -                0000 0000  00     01   
--s 0011 ---------  -  -                0011 0000  00     01           
--s 0100 ---------  -  -                0100 0000  00     01           
--s 0101 ---------  -  -                0101 0000  00     01           
--s 1001 ---------  -  -                1001 0000  00     01           
--s 1010 ---------  -  -                1010 0000  00     01           
--s 1011 ---------  -  -                1011 0000  00     01           
--s 1100 ---------  -  -                1100 0000  00     01           
--s 1101 ---------  -  -                1101 0000  00     01           
--s 1110 ---------  -  -                1110 0000  00     01           
--*-------------------------------------------------------------------------------------------------------------------
--tbl RecvSeq


-- read data
-- load immediately with local data
-- load 0:n for ib data
idata_cnt_d <= gate_and(icapture_q and ld_rd_data, inc(idata_cnt_q)) or
               gate_and(not idata_clear and not(icapture_q and ld_rd_data), idata_cnt_q);  

rd_rsp_data_done <= eq(idata_cnt_q, 7);

with wb_in_q.adr(7 downto 4) select
   local_rd_data <= config_data     when "0000",
                    (others => '1') when others;

with idata_cnt_q select 
   rd_data_load <= wb_out_q.dat(63 downto 8) & idata_q                              when "000",
                   wb_out_q.dat(63 downto 16) & idata_q & wb_out_q.dat(7 downto 0)  when "001",
                   wb_out_q.dat(63 downto 24) & idata_q & wb_out_q.dat(15 downto 0) when "010", 
                   wb_out_q.dat(63 downto 32) & idata_q & wb_out_q.dat(23 downto 0) when "011",                   
                   wb_out_q.dat(63 downto 40) & idata_q & wb_out_q.dat(31 downto 0) when "100",                   
                   wb_out_q.dat(63 downto 48) & idata_q & wb_out_q.dat(39 downto 0) when "101",                   
                   wb_out_q.dat(63 downto 56) & idata_q & wb_out_q.dat(47 downto 0) when "110",                   
                   idata_q & wb_out_q.dat(55 downto 0)                              when others;                                                                                                                

wb_out_d.dat   <= gate_and(wb_local_rd,                                           local_rd_data) or
                  gate_and(wb_remote_rd and ld_rd_data,                           rd_data_load) or
                  gate_and(not wb_local_rd and not (wb_remote_rd and ld_rd_data), wb_out_q.dat);

rd_err <= rd8_rsp and iseq_idle and icapture_q and not(eq(idata_q(4 downto 3), 0));
wr_err <= wr8_rsp and iseq_idle and icapture_q and not(eq(idata_q(4 downto 3), 0));

---------------- Generated --------------------------

--vtable HeaderEncode
ob_header(7) <= 
  (link_req_o) or
  (link_rsp_o);
ob_header(6) <= 
  (wb_sync) or
  (link_req_o) or
  (link_rsp_o);
ob_header(5) <= 
  (link_req_o) or
  (link_rsp_o);
ob_header(4) <= 
  (link_req_o) or
  (link_rsp_o);
ob_header(3) <= 
  (link_rsp_o);
ob_header(2) <= '0';
ob_header(1) <= 
  (wb_remote_rd) or
  (wb_remote_wr);
ob_header(0) <= 
  (wb_remote_wr);
--vtable HeaderEncode

--vtable HeaderDecode
rd8_rsp <= 
  (idata_q(7) and not idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(1) and not idata_q(0) and wb_remote_rd);
wr8_rsp <= 
  (idata_q(7) and not idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(1) and idata_q(0) and wb_remote_wr);
int_req <= 
  (idata_q(7) and idata_q(6) and not idata_q(5) and idata_q(4) and not idata_q(3));
sync_ack <= 
  (idata_q(7) and idata_q(6) and not idata_q(5) and not idata_q(4) and not idata_q(3));
cache_inv <= 
  (idata_q(7) and idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(3));
link_req_i <= 
  (idata_q(7) and idata_q(6) and idata_q(5) and idata_q(4) and not idata_q(3));
link_rsp_i <= 
  (idata_q(7) and idata_q(6) and idata_q(5) and idata_q(4) and idata_q(3));
good_header <= 
  (idata_q(7) and not idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(1) and not idata_q(0) and wb_remote_rd) or
  (idata_q(7) and not idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(1) and idata_q(0) and wb_remote_wr) or
  (idata_q(7) and idata_q(6) and not idata_q(5) and not idata_q(4) and not idata_q(3)) or
  (idata_q(7) and idata_q(6) and not idata_q(5) and not idata_q(4) and idata_q(3)) or
  (idata_q(7) and idata_q(6) and not idata_q(5) and idata_q(4) and not idata_q(3)) or
  (idata_q(7) and idata_q(6) and idata_q(5) and idata_q(4) and not idata_q(3)) or
  (idata_q(7) and idata_q(6) and idata_q(5) and idata_q(4) and idata_q(3));
--vtable HeaderDecode

--vtable WBSlaveSeq
wbseq_d(3) <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and not wb_req) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and not wb_local) or
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and not ob_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and ob_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and not wr_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and wr_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0));
wbseq_d(2) <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and not wb_req) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and not wb_local) or
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and not ob_complete) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and ob_complete) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and not rd_rsp_complete) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and rd_rsp_complete) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0));
wbseq_d(1) <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and not wb_req) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and wb_local) or
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and rd_rsp_complete) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and wr_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0));
wbseq_d(0) <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and not wb_req) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and wb_local) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and ob_complete) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0) and ob_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0) and not wr_rsp_complete) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0));
wb_local_rd <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and wb_local);
wb_local_wr <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and wb_local);
wb_remote_rd <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and not wb_local) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete);
wb_remote_wr <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and not wb_local) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0));
wb_out_d.stall <= 
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and wb_local) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and wb_local) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and not wb_we and not wb_local) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0) and wb_req and wb_we and not wb_local) or
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0));
wb_out_d.ack <= 
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0));
oseq_hold <= 
  (not wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0) and not rd_rsp_complete) or
  (wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and not wbseq_q(0));
wbseq_err <= 
  (not wbseq_q(3) and not wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (not wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (not wbseq_q(3) and wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and not wbseq_q(2) and wbseq_q(1) and wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and not wbseq_q(0)) or
  (wbseq_q(3) and wbseq_q(2) and not wbseq_q(1) and wbseq_q(0));
--vtable WBSlaveSeq

--vtable SendSeq
oseq_d(3) <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and oseq_hold) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not wb_remote_rd and not wb_remote_wr) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last) or
  (oseq_q(3) and not oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0));
oseq_d(2) <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and oseq_hold) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not wb_remote_rd and not wb_remote_wr) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0) and oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and not odata_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0));
oseq_d(1) <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and oseq_hold) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not wb_remote_rd and not wb_remote_wr) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0) and wb_remote_rd and oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0) and wb_remote_wr and oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and oclk_advance and not oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0));
oseq_d(0) <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and oseq_hold) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not wb_remote_rd and not wb_remote_wr) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and not oclk_advance) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and wb_remote_rd and oclk_advance) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and wb_remote_wr and oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0));
odata_ld_header <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and wb_remote_rd and oclk_advance) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and wb_remote_wr and oclk_advance);
odata_ld_addr <= 
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0) and wb_remote_rd and oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0) and wb_remote_wr and oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and oclk_advance and not oaddr_last);
odata_ld_sel <= 
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and wb_remote_wr and oclk_advance and oaddr_last);
odata_clear <= 
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and oseq_hold) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not wb_remote_rd and not wb_remote_wr) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0) and not oseq_hold and not oclk_advance) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and wb_remote_wr and oclk_advance and oaddr_last);
odata_ld_data <= 
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0) and oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and not oclk_advance) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and not odata_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last);
ob_complete <= 
  (not oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0) and not wb_remote_wr and oclk_advance and oaddr_last) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0) and oclk_advance and odata_last);
oseq_err <= 
  (not oseq_q(3) and not oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (not oseq_q(3) and oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and not oseq_q(2) and oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and not oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and not oseq_q(1) and oseq_q(0)) or
  (oseq_q(3) and oseq_q(2) and oseq_q(1) and not oseq_q(0));
--vtable SendSeq

--vtable RecvSeq
iseq_d(3) <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and rd8_rsp) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and not icapture_q) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and not rd_rsp_data_done) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done) or
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0));
iseq_d(2) <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and bad_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and sync_ack) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and cache_inv) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and link_req_i) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and link_rsp_i) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done) or
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and not idle_header) or
  (not iseq_q(3) and iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0));
iseq_d(1) <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and bad_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and int_req) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and sync_ack) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and cache_inv) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and link_req_i) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and link_rsp_i) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done) or
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and not idle_header) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0));
iseq_d(0) <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and wr8_rsp) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done) or
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0));
ld_rd_data <= 
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and not rd_rsp_data_done) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done);
rd_rsp_complete <= 
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0) and icapture_q and rd_rsp_data_done);
wr_rsp_complete <= 
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0));
int_req_complete <= 
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0));
idata_clear <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and not icapture_q) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0) and icapture_q and idle_header);
save_header <= 
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0));
iseq_idle <= 
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and iseq_q(0));
iseq_err <= 
  (not iseq_q(3) and not iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (not iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and not iseq_q(2) and iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and not iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and not iseq_q(1) and iseq_q(0)) or
  (iseq_q(3) and iseq_q(2) and iseq_q(1) and not iseq_q(0));
--vtable RecvSeq

end architecture mc;
