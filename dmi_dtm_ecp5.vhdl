library ieee;
use ieee.std_logic_1164.all;
use ieee.math_real.all;

library work;
use work.wishbone_types.all;

entity dmi_dtm is
    generic(ABITS : INTEGER:=8;
            DBITS : INTEGER:=64);

    port(sys_clk   : in std_ulogic;
         sys_reset : in std_ulogic;
         dmi_addr  : out std_ulogic_vector(ABITS - 1 downto 0);
         dmi_din   : in std_ulogic_vector(DBITS - 1 downto 0);
         dmi_dout  : out std_ulogic_vector(DBITS - 1 downto 0);
         dmi_req   : out std_ulogic;
         dmi_wr    : out std_ulogic;
         dmi_ack   : in std_ulogic
--         dmi_err : in std_ulogic TODO: Add error response
         );
end entity dmi_dtm;

architecture behaviour of dmi_dtm is
    -- Signals coming out of the JTAGG block
    signal jtag_reset_n : std_ulogic;
    signal tdi        : std_ulogic;
    signal tdo        : std_ulogic;
    signal tck        : std_ulogic;
    signal jce1       : std_ulogic;
    signal jshift     : std_ulogic;
    signal update     : std_ulogic;

    -- signals to match dmi_dtb_xilinx
    signal jtag_reset : std_ulogic;
    signal capture    : std_ulogic;
    signal jtag_clk   : std_ulogic;
    signal sel        : std_ulogic;
    signal shift      : std_ulogic;

    -- delays
    signal jce1_d     : std_ulogic;
    constant TCK_DELAY : INTEGER := 8;
    signal tck_d : std_ulogic_vector(TCK_DELAY+1 downto 1);

    -- ** JTAG clock domain **

    -- Shift register
    signal shiftr : std_ulogic_vector(ABITS + DBITS + 1 downto 0);

    -- Latched request
    signal request : std_ulogic_vector(ABITS + DBITS + 1 downto 0);

    -- A request is present
    signal jtag_req : std_ulogic;

    -- Synchronizer for jtag_rsp (sys clk -> jtag_clk)
    signal dmi_ack_0 : std_ulogic;
    signal dmi_ack_1 : std_ulogic;

    -- ** sys clock domain **

    -- Synchronizer for jtag_req (jtag clk -> sys clk)
    signal jtag_req_0 : std_ulogic;
    signal jtag_req_1 : std_ulogic;

    -- ** combination signals
    signal jtag_bsy : std_ulogic;
    signal op_valid : std_ulogic;
    signal rsp_op   : std_ulogic_vector(1 downto 0);

    -- ** Constants **
    constant DMI_REQ_NOP : std_ulogic_vector(1 downto 0) := "00";
    constant DMI_REQ_RD  : std_ulogic_vector(1 downto 0) := "01";
    constant DMI_REQ_WR  : std_ulogic_vector(1 downto 0) := "10";
    constant DMI_RSP_OK  : std_ulogic_vector(1 downto 0) := "00";
    constant DMI_RSP_BSY : std_ulogic_vector(1 downto 0) := "11";

    attribute ASYNC_REG : string;
    attribute ASYNC_REG of jtag_req_0: signal is "TRUE";
    attribute ASYNC_REG of jtag_req_1: signal is "TRUE";
    attribute ASYNC_REG of dmi_ack_0: signal is "TRUE";
    attribute ASYNC_REG of dmi_ack_1: signal is "TRUE";

    -- ECP5 JTAGG
    component JTAGG is
        generic (
            ER1 : string := "ENABLED";
            ER2 : string := "ENABLED"
        );
        port(
            JTDO1 : in std_ulogic;
            JTDO2 : in std_ulogic;
            JTDI : out std_ulogic;
            JTCK : out std_ulogic;
            JRTI1 : out std_ulogic;
            JRTI2 : out std_ulogic;
            JSHIFT : out std_ulogic;
            JUPDATE : out std_ulogic;
            JRSTN : out std_ulogic;
            JCE1 : out std_ulogic;
            JCE2 : out std_ulogic
        );
    end component;

    component LUT4 is
        generic (
            INIT : std_logic_vector
        );
        port(
          A : in STD_ULOGIC;
          B : in STD_ULOGIC;
          C : in STD_ULOGIC;
          D : in STD_ULOGIC;
          Z : out STD_ULOGIC
        );
    end component;

begin

    jtag: JTAGG
        generic map(
            ER2 => "DISABLED"
        )
        port map (
            JTDO1 => tdo,
            JTDO2 => '0',
            JTDI => tdi,
            JTCK => tck,
            JRTI1 => open,
            JRTI2 => open,
            JSHIFT => jshift,
            JUPDATE => update,
            JRSTN => jtag_reset_n,
            JCE1 => jce1,
            JCE2 => open
        );

    -- JRTI1 looks like it could be connected to SEL, but
    -- in practise JRTI1 is only high briefly, not for the duration
    -- of the transmission. possibly mw_debug could be modified.
    -- The ecp5 is probably the only jtag device anyway.
    sel <= '1';

    -- TDI needs to align with TCK, we use LUT delays here.
    -- From https://github.com/enjoy-digital/litex/pull/1087
    tck_d(1) <= tck;
    del: for i in 1 to TCK_DELAY generate
        attribute keep : boolean;
        attribute keep of l: label is true;
    begin
        l: LUT4
            generic map(
                INIT => b"0000_0000_0000_0010"
            )
            port map (
                A => tck_d(i),
                B => '0', C => '0', D => '0',
                Z => tck_d(i+1)
            );
    end generate;
    jtag_clk <= tck_d(TCK_DELAY+1);

    -- capture signal
    jce1_sync : process(jtag_clk)
    begin
        if rising_edge(jtag_clk) then
            jce1_d <= jce1;
            capture <= jce1 and not jce1_d;
        end if;
    end process;

    -- latch the shift signal, otherwise
    -- we miss the last shift in
    -- (maybe because we are delaying tck?)
    shift_sync : process(jtag_clk)
    begin
        if (sys_reset = '1') then
            shift <= '0';
        elsif rising_edge(jtag_clk) then
            shift <= jshift;
        end if;
    end process;

    jtag_reset <= not jtag_reset_n;

    -- dmi_req synchronization
    dmi_req_sync : process(sys_clk)
    begin
        -- sys_reset is synchronous
        if rising_edge(sys_clk) then
            if (sys_reset = '1') then
                jtag_req_0 <= '0';
                jtag_req_1 <= '0';
            else
                jtag_req_0 <= jtag_req;
                jtag_req_1 <= jtag_req_0;
            end if;
        end if;
    end process;
    dmi_req <= jtag_req_1;

    -- dmi_ack synchronization
    dmi_ack_sync: process(jtag_clk, jtag_reset)
    begin
        -- jtag_reset is async (see comments)
        if jtag_reset = '1' then
            dmi_ack_0 <= '0';
            dmi_ack_1 <= '0';
        elsif rising_edge(jtag_clk) then
            dmi_ack_0 <= dmi_ack;
            dmi_ack_1 <= dmi_ack_0;
        end if;
    end process;
   
    -- jtag_bsy indicates whether we can start a new request, we can when
    -- we aren't already processing one (jtag_req) and the synchronized ack
    -- of the previous one is 0.
    --
    jtag_bsy <= jtag_req or dmi_ack_1;

    -- decode request type in shift register
    with shiftr(1 downto 0) select op_valid <=
        '1' when DMI_REQ_RD,
        '1' when DMI_REQ_WR,
        '0' when others;

    -- encode response op
    rsp_op <= DMI_RSP_BSY when jtag_bsy = '1' else DMI_RSP_OK;

    -- Some DMI out signals are directly driven from the request register
    dmi_addr <= request(ABITS + DBITS + 1 downto DBITS + 2);
    dmi_dout <= request(DBITS + 1 downto 2);
    dmi_wr   <= '1' when request(1 downto 0) = DMI_REQ_WR else '0';

    -- TDO is wired to shift register bit 0
    tdo <= shiftr(0);

    -- Main state machine. Handles shift registers, request latch and
    -- jtag_req latch. Could be split into 3 processes but it's probably
    -- not worthwhile.
    --
    shifter: process(jtag_clk, jtag_reset, sys_reset)
    begin
        if jtag_reset = '1' or sys_reset = '1' then
            shiftr <= (others => '0');
            jtag_req <= '0';
            request <= (others => '0');
        elsif rising_edge(jtag_clk) then

            -- Handle jtag "commands" when sel is 1
            if sel = '1' then
                -- Shift state, rotate the register
                if shift = '1' then
                    shiftr <= tdi & shiftr(ABITS + DBITS + 1 downto 1);
                end if;

                -- Update state (trigger)
                --
                -- Latch the request if we aren't already processing one and
                -- it has a valid command opcode.
                --
                    if update = '1' and op_valid = '1' then
                    if jtag_bsy = '0' then
                        request <= shiftr;
                        jtag_req <= '1';
                    end if;
                    -- Set the shift register "op" to "busy". This will prevent
                    -- us from re-starting the command on the next update if
                    -- the command completes before that.
                    shiftr(1 downto 0) <= DMI_RSP_BSY;
                end if;

                -- Request completion.
                --
                -- Capture the response data for reads and clear request flag.
                --
                -- Note: We clear req (and thus dmi_req) here which relies on tck
                -- ticking and sel set. This means we are stuck with dmi_req up if
                -- the jtag interface stops. Slaves must be resilient to this.
                --
                if jtag_req = '1' and dmi_ack_1 = '1' then
                    jtag_req <= '0';
                    if request(1 downto 0) = DMI_REQ_RD then
                        request(DBITS + 1 downto 2) <= dmi_din;
                    end if;
                end if;

                -- Capture state, grab latch content with updated status
                if capture = '1' then
                    shiftr <= request(ABITS + DBITS + 1 downto 2) & rsp_op;
                end if;

            end if;
        end if;
    end process;
end architecture behaviour;

