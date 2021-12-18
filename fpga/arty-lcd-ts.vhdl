library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

library work;
use work.wishbone_types.all;

-- Interface for LCD/touchscreen connected to Arduino-compatible socket on Arty A7
entity lcd_touchscreen is
    port (
        clk    : in  std_ulogic;
        rst    : in  std_ulogic;
        wb_in  : in  wb_io_master_out;
        wb_out : out wb_io_slave_out;
        wb_sel : in  std_ulogic;
        tp     : out std_ulogic;

        lcd_din  : in  std_ulogic_vector(7 downto 0);
        lcd_dout : out std_ulogic_vector(7 downto 0);
        lcd_doe  : out std_ulogic;
        lcd_doe0 : out std_ulogic;
        lcd_doe1 : out std_ulogic;
        lcd_rd   : out std_ulogic;      -- note active low
        lcd_wr   : out std_ulogic;      -- note active low
        lcd_rs   : out std_ulogic;
        lcd_rsoe : out std_ulogic;
        lcd_cs   : out std_ulogic;      -- note active low
        lcd_csoe : out std_ulogic;
        lcd_rst  : out std_ulogic;      -- note active low

        -- Differential analog inputs from touchscreen
        a2_p : in std_ulogic;
        a2_n : in std_ulogic;
        a3_p : in std_ulogic;
        a3_n : in std_ulogic;
        a4_p : in std_ulogic;
        a4_n : in std_ulogic;
        a5_p : in std_ulogic;
        a5_n : in std_ulogic
        );
end entity lcd_touchscreen;

architecture rtl of lcd_touchscreen is

    type state_t is (idle, prep1, prep2, writing, wr_pause, reading, rd_recovery,
                     drp_lo, drp_hi);

    signal state : state_t;
    signal delay : unsigned(5 downto 0);
    signal ack   : std_ulogic;
    signal idle1 : std_ulogic;
    signal idle2 : std_ulogic;

    signal rs     : std_ulogic;
    signal rsoe   : std_ulogic;
    signal cs     : std_ulogic;
    signal csoe   : std_ulogic;
    signal d0     : std_ulogic;
    signal doe0   : std_ulogic;
    signal doe1   : std_ulogic;
    signal d1     : std_ulogic;
    signal tsctrl : std_ulogic;

    signal wr_data : std_ulogic_vector(31 downto 0);
    signal rd_data : std_ulogic_vector(31 downto 0);
    signal wr_sel  : std_ulogic_vector(3 downto 0);
    signal req_wr  : std_ulogic;

    signal xadc_di   : std_ulogic_vector(15 downto 0);
    signal xadc_do   : std_ulogic_vector(15 downto 0);
    signal xadc_addr : std_ulogic_vector(6 downto 0);
    signal xadc_en   : std_ulogic;
    signal xadc_we   : std_ulogic;
    signal xadc_rdy  : std_ulogic;
    signal xadc_eoc  : std_ulogic;
    signal xadc_eos  : std_ulogic;
    signal xadc_busy : std_ulogic;
    signal eoc_stat  : std_ulogic;
    signal eos_stat  : std_ulogic;

    -- Assume touchscreen is connected to the A2 - A5 analog inputs

begin

    -- The connection of the analog A0 - A5 pins on the Arty
    -- to FPGA pins is as follows:
    -- A0 connects to AD4P/AD4N
    -- A1 connects to AD5P/AD5N
    -- A2 connects to AD6P/AD6N
    -- A3 connects to AD7P/AD7N
    -- A4 connects to AD15P/AD15N
    -- A5 connects to AD0P/AD0N
    xadc_0 : XADC
        generic map (
            init_42 => x"0400"  -- adcclk = dclk / 4, i.e. 25MHz
            )
        port map (
            di => xadc_di,
            do => xadc_do,
            daddr => xadc_addr,
            den => xadc_en,
            dwe => xadc_we,
            dclk => clk,
            drdy => xadc_rdy,
            reset => rst,
            convst => '0',
            convstclk => '0',
            vp => '0',
            vn => '0',
            vauxp => a4_p & "0000000" & a3_p & a2_p & "00000" & a5_p,
            vauxn => a4_n & "0000000" & a3_n & a2_n & "00000" & a5_n,
            eoc => xadc_eoc,
            eos => xadc_eos,
            busy => xadc_busy
            );

    -- for now; should make sure it is at least 10us wide
    lcd_rst <= not rst;

    wb_out.dat <= rd_data;
    wb_out.ack <= ack;
    wb_out.stall <= '0' when state = idle else '1';

    lcd_doe0 <= doe0;
    lcd_doe1 <= doe1;
    lcd_rs <= rs;
    lcd_rsoe <= rsoe;
    lcd_cs <= cs;
    lcd_csoe <= csoe;

    tp <= tsctrl;

    process (clk)
        variable rdat : std_ulogic_vector(7 downto 0);
    begin
        if rising_edge(clk) then
            ack <= '0';
            xadc_en <= '0';
            idle2 <= idle1;
            if xadc_eoc = '1' then
                eoc_stat <= '1';
            end if;
            if xadc_eos = '1' then
                eos_stat <= '1';
            end if;
            if rst = '1' then
                state <= idle;
                delay <= to_unsigned(0, 6);
                rd_data <= (others => '0');
                lcd_rd <= '1';
                lcd_wr <= '1';
                cs <= '1';
                csoe <= '1';
                rs <= '0';
                rsoe <= '1';
                lcd_doe <= '0';
                doe0 <= '0';
                doe1 <= '0';
                d0 <= '0';
                d1 <= '0';
                idle1 <= '0';
                idle2 <= '0';
                tsctrl <= '0';
                xadc_en <= '0';
                eoc_stat <= '0';
                eos_stat <= '0';
            elsif delay /= "000000" then
                delay <= delay - 1;
            else
                case state is
                    when idle =>
                        req_wr <= wb_in.we;
                        wr_data <= wb_in.dat;
                        wr_sel <= wb_in.sel;
                        if idle2 = '1' then
                            -- delay this one cycle after entering idle
                            lcd_doe <= '0';
                            doe0 <= '0';
                            doe1 <= '0';
                        end if;
                        idle1 <= '0';
                        if wb_in.cyc = '1' and wb_in.stb = '1' and wb_sel = '1' then
                            if wb_in.sel = "0000" then
                                ack <= '1';
                            elsif wb_in.adr(6) = '0' then
                                if wb_in.we = '1' or wb_in.adr(2) = '1' then
                                    ack <= '1';
                                end if;
                                if wb_in.adr(2) = '0' then
                                    -- c8050000 or 8, access LCD controller chip
                                    tsctrl <= '0';
                                    csoe <= '1';
                                    cs <= '0';  -- active low
                                    rsoe <= '1';
                                    rs <= wb_in.adr(1);
                                    doe0 <= '0';
                                    doe1 <= '0';
                                    state <= prep1;
                                elsif wb_in.adr(1) = '0' then
                                    -- c8050010, touchscreen drive register
                                    tsctrl <= '1';
                                    idle2 <= '0';
                                    rdat := rsoe & rs & doe0 & d0 & doe1 & d1 & csoe & cs;
                                    rd_data <= rdat & rdat & rdat & rdat;
                                    if wb_in.we = '1' and wb_in.sel(0) = '1' then
                                        rsoe <= wb_in.dat(7);
                                        rs <= wb_in.dat(6);
                                        doe0 <= wb_in.dat(5);
                                        d0 <= wb_in.dat(4);
                                        lcd_dout(0) <= wb_in.dat(4);
                                        doe1 <= wb_in.dat(3);
                                        d1 <= wb_in.dat(2);
                                        lcd_dout(1) <= wb_in.dat(2);
                                        csoe <= wb_in.dat(1);
                                        cs <= wb_in.dat(0);
                                    end if;
                                else
                                    -- c8050018, touchscreen status register
                                    rdat := 4x"0" & xadc_busy & eoc_stat & eos_stat & tsctrl;
                                    rd_data <= rdat & rdat & rdat & rdat;
                                    if wb_in.we = '1' and wb_in.sel(0) = '1' then
                                        -- for eoc_stat and eos_state, write 0 to clear
                                        if wb_in.dat(2) = '0' then
                                            eoc_stat <= '0';
                                        end if;
                                        if wb_in.dat(1) = '0' then
                                            eos_stat <= '0';
                                        end if;
                                    end if;
                                end if;
                            else
                                -- c80501xx, access to the XADC DRP port
                                xadc_en <= '1';
                                xadc_we <= wb_in.we;
                                xadc_addr(6 downto 1) <= wb_in.adr(5 downto 0);
                                if wb_in.sel(1 downto 0) = "00" then
                                    xadc_di <= wb_in.dat(31 downto 16);
                                    xadc_addr(0) <= '1';
                                    state <= drp_hi;
                                else
                                    xadc_di <= wb_in.dat(15 downto 0);
                                    xadc_addr(0) <= '0';
                                    state <= drp_lo;
                                end if;
                            end if;
                        else
                            if tsctrl = '0' then
                                cs <= '1';
                            end if;
                        end if;
                    when prep1 =>
                        lcd_doe <= req_wr;
                        doe0 <= req_wr;
                        doe1 <= req_wr;
                        if req_wr = '1' then
                            if wr_sel(1 downto 0) /= "00" then
                                if wr_sel(1) = '1' then
                                    lcd_dout <= wr_data(15 downto 8);
                                    wr_sel(1) <= '0';
                                else
                                    lcd_dout <= wr_data(7 downto 0);
                                    wr_sel(0) <= '0';
                                end if;
                            else
                                if wr_sel(3) = '1' then
                                    lcd_dout <= wr_data(31 downto 24);
                                    wr_sel(3) <= '0';
                                else
                                    lcd_dout <= wr_data(23 downto 16);
                                    wr_sel(2) <= '0';
                                end if;
                            end if;
                        end if;
                        state <= prep2;
                    when prep2 =>
                        if req_wr = '1' then
                            lcd_wr <= '0';  -- active low
                            state <= writing;
                            delay <= to_unsigned(1, 6);
                        else
                            lcd_rd <= '0';
                            state <= reading;
                            delay <= to_unsigned(35, 6);
                        end if;
                    when writing =>
                        -- last cycle of writing state
                        lcd_wr <= '1';
                        if wr_sel = "0000" then
                            state <= idle;
                            idle1 <= '1';
                        else
                            state <= wr_pause;
                        end if;
                    when wr_pause =>
                        state <= prep1;
                    when reading =>
                        -- last cycle of reading state
                        lcd_rd <= '1';
                        rd_data <= lcd_din & lcd_din & lcd_din & lcd_din;
                        ack <= '1';
                        state <= rd_recovery;
                        delay <= to_unsigned(6, 6);
                    when rd_recovery =>
                        state <= idle;
                    when drp_lo =>
                        if xadc_rdy = '1' then
                            rd_data(15 downto 0) <= xadc_do;
                            if wr_sel(3 downto 2) = "00" then
                                ack <= '1';
                                state <= idle;
                            else
                                xadc_di <= wr_data(31 downto 16);
                                xadc_addr(0) <= '1';
                                state <= drp_hi;
                            end if;
                        end if;
                    when drp_hi =>
                        if xadc_rdy = '1' then
                            rd_data(31 downto 16) <= xadc_do;
                            ack <= '1';
                            state <= idle;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;
