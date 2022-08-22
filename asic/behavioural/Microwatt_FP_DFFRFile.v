module Microwatt_FP_DFFRFile (
`ifdef USE_POWER_PINS
    inout VPWR,
    inout VGND,
`endif
    input [5:0]   R1, R2, R3, RW,
    input [63:0]  DW,
    output reg [63:0] D1, D2, D3,
    input CLK,
    input WE
);

    reg [63:0] registers[0:63];

    always @(posedge CLK) begin
        if (WE)
            registers[RW] <= DW;
        D1 <= registers[R1];
        D2 <= registers[R2];
        D3 <= registers[R3];
    end

endmodule
