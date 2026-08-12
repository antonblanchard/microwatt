library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cordic is
    generic (
        DATA_WIDTH  : integer := 16;
        ANGLE_WIDTH : integer := 32;
        ITER        : integer := 16
    );
    port (
        clk   : in  std_logic;
        angle : in  signed(ANGLE_WIDTH-1 downto 0);
        Xin   : in  signed(DATA_WIDTH-1 downto 0);
        Yin   : in  signed(DATA_WIDTH-1 downto 0);
        Xout  : out signed(DATA_WIDTH downto 0);
        Yout  : out signed(DATA_WIDTH downto 0)
    );
end entity;

architecture rtl of cordic is

    type vec_data is array (0 to ITER-1) of signed(DATA_WIDTH downto 0);
    type vec_angle is array (0 to ITER-1) of signed(ANGLE_WIDTH-1 downto 0);

    signal X : vec_data := (others => (others => '0'));
    signal Y : vec_data := (others => (others => '0'));
    signal Z : vec_angle := (others => (others => '0'));


    -- π/2 = 2^(ANGLE_WIDTH-2)
    constant PI_OVER_2 : signed(ANGLE_WIDTH-1 downto 0)
        := to_signed(1, ANGLE_WIDTH) sll (ANGLE_WIDTH-2);

    -- Arctan LUT
    type lut_t is array (0 to 15) of signed(ANGLE_WIDTH-1 downto 0);
    constant atan_lut : lut_t := (
        to_signed(16#20000000#, ANGLE_WIDTH),
        to_signed(16#12B4040D#, ANGLE_WIDTH),
        to_signed(16#09FB180B#, ANGLE_WIDTH),
        to_signed(16#05110875#, ANGLE_WIDTH),
        to_signed(16#028B0D43#, ANGLE_WIDTH),
        to_signed(16#0142BBF1#, ANGLE_WIDTH),
        to_signed(16#00A159CE#, ANGLE_WIDTH),
        to_signed(16#0050AC15#, ANGLE_WIDTH),
        to_signed(16#00285653#, ANGLE_WIDTH),
        to_signed(16#00142F8E#, ANGLE_WIDTH),
        to_signed(16#000A17C8#, ANGLE_WIDTH),
        to_signed(16#00050BE4#, ANGLE_WIDTH),
        to_signed(16#000285F3#, ANGLE_WIDTH),
        to_signed(16#000142FB#, ANGLE_WIDTH),
        to_signed(16#0000A17D#, ANGLE_WIDTH),
        to_signed(16#000050BE#, ANGLE_WIDTH)
    );

begin

        -- Stage 0 (safe assignments using explicit resize)
    stage0: process(clk)
        -- temporaries with the target widths so we never assign unknown sized vectors
        variable Xin_ext  : signed(DATA_WIDTH downto 0);
        variable Yin_ext  : signed(DATA_WIDTH downto 0);
        variable angle_ext: signed(ANGLE_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            -- make explicit widths
            Xin_ext   := resize(Xin,  DATA_WIDTH + 1);
            Yin_ext   := resize(Yin,  DATA_WIDTH + 1);
            angle_ext := resize(angle, ANGLE_WIDTH);

            -- quadrant handling (same semantics as before)
            if angle_ext > PI_OVER_2 then
                X(0) <= -Xin_ext;        -- note: rotate by +90 (X <- -Y)
                Y(0) <=  Xin_ext;        -- rotate inputs intentionally preserved style
                Z(0) <= angle_ext - PI_OVER_2;
            elsif angle_ext < -PI_OVER_2 then
                X(0) <=  Yin_ext;
                Y(0) <= -Xin_ext;
                Z(0) <= angle_ext + PI_OVER_2;
            else
                X(0) <= Xin_ext;
                Y(0) <= Yin_ext;
                Z(0) <= angle_ext;
            end if;
        end if;
    end process stage0;
    -- Iterative pipeline
    gen: for i in 0 to ITER-2 generate
        process(clk)
            variable X_shr, Y_shr : signed(DATA_WIDTH downto 0);
        begin
            if rising_edge(clk) then
                X_shr := X(i) sra i;
                Y_shr := Y(i) sra i;

                if Z(i)(ANGLE_WIDTH-1) = '1' then
                    X(i+1) <= X(i) + Y_shr;
                    Y(i+1) <= Y(i) - X_shr;
                    Z(i+1) <= Z(i) + atan_lut(i);
                else
                    X(i+1) <= X(i) - Y_shr;
                    Y(i+1) <= Y(i) + X_shr;
                    Z(i+1) <= Z(i) - atan_lut(i);
                end if;
            end if;
        end process;
    end generate;

    Xout <= X(ITER-1);
    Yout <= Y(ITER-1);

end architecture;

