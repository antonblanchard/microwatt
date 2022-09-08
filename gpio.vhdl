-- GPIO module for microwatt
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.wishbone_types.all;

entity gpio is
    generic (
        NGPIO : integer := 32
        );
    port (
        clk : in std_ulogic;
        rst : in std_ulogic;

        -- Wishbone
        wb_in  : in wb_io_master_out;
        wb_out : out wb_io_slave_out;

        -- GPIO lines
        gpio_in  : in std_ulogic_vector(NGPIO - 1 downto 0);
        gpio_out : out std_ulogic_vector(NGPIO - 1 downto 0);
        -- 1 = output, 0 = input
        gpio_dir : out std_ulogic_vector(NGPIO - 1 downto 0);

        -- Interrupt
        intr : out std_ulogic
        );
end entity gpio;

architecture behaviour of gpio is
    constant GPIO_REG_BITS  : positive := 5;

    -- Register addresses, matching addr downto 2, so 4 bytes per reg
    constant GPIO_REG_DATA_OUT : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "00000";
    constant GPIO_REG_DATA_IN  : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "00001";
    constant GPIO_REG_DIR      : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "00010";
    constant GPIO_REG_DATA_SET : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "00100";
    constant GPIO_REG_DATA_CLR : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "00101";

    constant GPIO_REG_INT_EN   : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01000";
    constant GPIO_REG_INT_STAT : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01001";
    -- write 1 to clear
    constant GPIO_REG_INT_CLR : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01100";
    -- edge 0, level 1
    constant GPIO_REG_INT_TYPE : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01101";
    -- for edge: trigger on either edge = 1
    constant GPIO_REG_INT_BOTH_EDGE : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01110";
    -- for edge: rising 0, falling 1
    -- for level: high 0, low 1
    constant GPIO_REG_INT_LEVEL : std_ulogic_vector(GPIO_REG_BITS-1 downto 0) := "01111";

    -- Current output value and direction
    signal reg_data : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_dirn : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_in0  : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_in1  : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_in2  : std_ulogic_vector(NGPIO - 1 downto 0);

    signal reg_intr_en    : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_intr_hit   : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_intr_type : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_intr_level : std_ulogic_vector(NGPIO - 1 downto 0);
    signal reg_intr_both : std_ulogic_vector(NGPIO - 1 downto 0);

    signal wb_rsp   : wb_io_slave_out;
    signal reg_out  : std_ulogic_vector(NGPIO - 1 downto 0);

    constant ZEROS : std_ulogic_vector(NGPIO-1 downto 0) := (others => '0');
begin
    intr <= '0' when reg_intr_hit = ZEROS else '1';
    gpio_out <= reg_data;
    gpio_dir <= reg_dirn;

    -- Wishbone response
    wb_rsp.ack <= wb_in.cyc and wb_in.stb;
    with wb_in.adr(GPIO_REG_BITS - 1 downto 0) select reg_out <=
        reg_data when GPIO_REG_DATA_OUT,
        reg_in1  when GPIO_REG_DATA_IN,
        reg_dirn when GPIO_REG_DIR,
        reg_intr_en when GPIO_REG_INT_EN,
        reg_intr_hit when GPIO_REG_INT_STAT,
        reg_intr_type when GPIO_REG_INT_TYPE,
        reg_intr_both when GPIO_REG_INT_BOTH_EDGE,
        reg_intr_level when GPIO_REG_INT_LEVEL,
        (others => '0') when others;
    wb_rsp.dat(wb_rsp.dat'left downto NGPIO) <= (others => '0');
    wb_rsp.dat(NGPIO - 1 downto 0) <= reg_out;
    wb_rsp.stall <= '0';

    regs_rw: process(clk)
       variable trig : std_logic_vector(0 to 2);
       variable change : std_logic;
       variable intr_hit : boolean;
    begin
        if rising_edge(clk) then
            wb_out <= wb_rsp;
            for i in NGPIO - 1 downto 0 loop
                -- interrupt triggers. reg_in1 is current value
                if reg_intr_type(i) = '0' then
                    -- edge
                    change := '0' when (reg_in1(i) = reg_in2(i)) else '1';
                    trig := change & reg_intr_both(i) & reg_intr_level(i);
                    case trig is
                        -- both
                        when "110" | "111" => intr_hit := true;
                        -- rising
                        when "100" => intr_hit := reg_in1(i) = '1';
                        -- falling
                        when "101" => intr_hit := reg_in1(i) = '0';
                        when others => intr_hit := false;
                    end case;
                else
                    -- level
                    intr_hit := reg_in1(i) = not reg_intr_level(i);
                end if;
                reg_intr_hit(i) <= '1' when intr_hit and reg_intr_en(i) = '1';

            end loop;

            -- previous value for interrupt edge detection
            reg_in2 <= reg_in1;
            -- 2 flip flops to cross from async input to sys clock domain
            reg_in1 <= reg_in0;
            reg_in0 <= gpio_in;

            if rst = '1' then
                reg_data <= (others => '0');
                reg_dirn <= (others => '0');
                reg_intr_en <= (others => '0');
                reg_intr_hit <= (others => '0');
                reg_intr_type <= (others => '0');
                reg_intr_both <= (others => '0');
                reg_intr_level <= (others => '0');
                wb_out.ack <= '0';
            else
                if wb_in.cyc = '1' and wb_in.stb = '1' and wb_in.we = '1' then
                    case wb_in.adr(GPIO_REG_BITS - 1 downto 0) is
                        when GPIO_REG_DATA_OUT =>
                            reg_data <= wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_DIR =>
                            reg_dirn <= wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_DATA_SET =>
                            reg_data <= reg_data or wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_DATA_CLR =>
                            reg_data <= reg_data and not wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_INT_EN =>
                            reg_intr_en <= wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_INT_CLR =>
                            reg_intr_hit <= reg_intr_hit and not wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_INT_TYPE =>
                            reg_intr_type <= wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_INT_BOTH_EDGE =>
                            reg_intr_both <= wb_in.dat(NGPIO - 1 downto 0);
                        when GPIO_REG_INT_LEVEL =>
                            reg_intr_level <= wb_in.dat(NGPIO - 1 downto 0);
                        when others =>
                    end case;
                end if;
            end if;
        end if;
    end process;

end architecture behaviour;

