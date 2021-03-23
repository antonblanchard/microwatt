module RAM32_1RW1R #(
    parameter BITS=5
) (
`ifdef USE_POWER_PINS
    inout VPWR,
    inout VGND,
`endif
    input CLK,

    input EN0,
    input [BITS-1:0] A0,
    input [7:0] WE0,
    input [63:0] Di0,
    output reg [63:0] Do0,

    input EN1,
    input [BITS-1:0] A1,
    output reg [63:0] Do1
);

    reg [63:0] RAM[2**BITS-1:0];

    always @(posedge CLK) begin
        if (EN1)
            Do1 <= RAM[A1];
    end

    generate
        genvar i;
        for (i=0; i<8; i=i+1) begin: BYTE
            always @(posedge CLK) begin
                if (EN0) begin
                    if (WE0[i])
                        RAM[A0][i*8+7:i*8] <= Di0[i*8+7:i*8];
                end
            end
        end
    endgenerate

endmodule
