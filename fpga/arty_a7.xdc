set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { ext_clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { ext_clk }];

set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { ext_rst }];

set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart0_txd }];
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { uart0_rxd }];

# Buttons 0-3
set_property -dict { PACKAGE_PIN D9    IOSTANDARD LVCMOS33 } [get_ports { gpio0[0] }]; # BTN0
set_property -dict { PACKAGE_PIN C9    IOSTANDARD LVCMOS33 } [get_ports { gpio0[1] }]; # BTN1
set_property -dict { PACKAGE_PIN B9    IOSTANDARD LVCMOS33 } [get_ports { gpio0[2] }]; # BTN2
set_property -dict { PACKAGE_PIN B8    IOSTANDARD LVCMOS33 } [get_ports { gpio0[3] }]; # BTN3

# Slide switches 0-3
set_property -dict { PACKAGE_PIN A8    IOSTANDARD LVCMOS33 } [get_ports { gpio0[4] }]; # SW0
set_property -dict { PACKAGE_PIN C11   IOSTANDARD LVCMOS33 } [get_ports { gpio0[5] }]; # SW1
set_property -dict { PACKAGE_PIN C10   IOSTANDARD LVCMOS33 } [get_ports { gpio0[6] }]; # SW2
set_property -dict { PACKAGE_PIN A10   IOSTANDARD LVCMOS33 } [get_ports { gpio0[7] }]; # SW3

# RGB LEDs 0-3
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { gpio0[8]  }]; # LD0 Red
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { gpio0[9]  }]; # LD0 Green
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports { gpio0[10] }]; # LD0 Blue

set_property -dict { PACKAGE_PIN G3    IOSTANDARD LVCMOS33 } [get_ports { gpio0[11] }]; # LD1 Red
set_property -dict { PACKAGE_PIN J4    IOSTANDARD LVCMOS33 } [get_ports { gpio0[12] }]; # LD1 Green
set_property -dict { PACKAGE_PIN G4    IOSTANDARD LVCMOS33 } [get_ports { gpio0[13] }]; # LD1 Blue

set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[14] }]; # LD2 Red
set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { gpio0[15] }]; # LD2 Green
set_property -dict { PACKAGE_PIN H4    IOSTANDARD LVCMOS33 } [get_ports { gpio0[16] }]; # LD2 Blue

set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { gpio0[17] }]; # LD3 Red
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { gpio0[18] }]; # LD3 Green
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[19] }]; # LD3 Blue

# LEDs 4-7
set_property -dict { PACKAGE_PIN H5    IOSTANDARD LVCMOS33 } [get_ports { gpio0[20] }]; # LD4
set_property -dict { PACKAGE_PIN J5    IOSTANDARD LVCMOS33 } [get_ports { gpio0[21] }]; # LD5
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { gpio0[22] }]; # LD6
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { gpio0[23] }]; # LD7

# PMOD JA
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { gpio0[24] }]; # PMOD JA Pin 1
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { gpio0[25] }]; # PMOD JA Pin 2
set_property -dict { PACKAGE_PIN A11   IOSTANDARD LVCMOS33 } [get_ports { gpio0[26] }]; # PMOD JA Pin 3
set_property -dict { PACKAGE_PIN D12   IOSTANDARD LVCMOS33 } [get_ports { gpio0[27] }]; # PMOD JA Pin 4
set_property -dict { PACKAGE_PIN D13   IOSTANDARD LVCMOS33 } [get_ports { gpio0[28] }]; # PMOD JA Pin 7
set_property -dict { PACKAGE_PIN B18   IOSTANDARD LVCMOS33 } [get_ports { gpio0[29] }]; # PMOD JA Pin 8
set_property -dict { PACKAGE_PIN A18   IOSTANDARD LVCMOS33 } [get_ports { gpio0[30] }]; # PMOD JA Pin 9
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { gpio0[31] }]; # PMOD JA Pin 10

# PMOD JB
set_property -dict { PACKAGE_PIN E15   IOSTANDARD LVCMOS33 } [get_ports { gpio0[32] }]; # PMOD JB Pin 1
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { gpio0[33] }]; # PMOD JB Pin 2
set_property -dict { PACKAGE_PIN D15   IOSTANDARD LVCMOS33 } [get_ports { gpio0[34] }]; # PMOD JB Pin 3
set_property -dict { PACKAGE_PIN C15   IOSTANDARD LVCMOS33 } [get_ports { gpio0[35] }]; # PMOD JB Pin 4
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { gpio0[36] }]; # PMOD JB Pin 7
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { gpio0[37] }]; # PMOD JB Pin 8
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { gpio0[38] }]; # PMOD JB Pin 9
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { gpio0[39] }]; # PMOD JB Pin 10

# PMOD JC
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { gpio0[40] }]; # PMOD JC Pin 1
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { gpio0[41] }]; # PMOD JC Pin 2
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { gpio0[42] }]; # PMOD JC Pin 3
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { gpio0[43] }]; # PMOD JC Pin 4
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { gpio0[44] }]; # PMOD JC Pin 7
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { gpio0[45] }]; # PMOD JC Pin 8
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { gpio0[46] }]; # PMOD JC Pin 9
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { gpio0[47] }]; # PMOD JC Pin 10

# PMOD JD
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { gpio0[48] }]; # PMOD JD Pin 1
set_property -dict { PACKAGE_PIN D3    IOSTANDARD LVCMOS33 } [get_ports { gpio0[49] }]; # PMOD JD Pin 2
set_property -dict { PACKAGE_PIN F4    IOSTANDARD LVCMOS33 } [get_ports { gpio0[50] }]; # PMOD JD Pin 3
set_property -dict { PACKAGE_PIN F3    IOSTANDARD LVCMOS33 } [get_ports { gpio0[51] }]; # PMOD JD Pin 4
set_property -dict { PACKAGE_PIN E2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[52] }]; # PMOD JD Pin 7
set_property -dict { PACKAGE_PIN D2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[53] }]; # PMOD JD Pin 8
set_property -dict { PACKAGE_PIN H2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[54] }]; # PMOD JD Pin 9
set_property -dict { PACKAGE_PIN G2    IOSTANDARD LVCMOS33 } [get_ports { gpio0[55] }]; # PMOD JD Pin 10

# Chipkit
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { gpio1[0]  }]; # Chipkit IO0
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[1]  }]; # Chipkit IO1
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { gpio1[2]  }]; # Chipkit IO2
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { gpio1[3]  }]; # Chipkit IO3
set_property -dict { PACKAGE_PIN R12   IOSTANDARD LVCMOS33 } [get_ports { gpio1[4]  }]; # Chipkit IO4
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { gpio1[5]  }]; # Chipkit IO5
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { gpio1[6]  }]; # Chipkit IO6
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[7]  }]; # Chipkit IO7
set_property -dict { PACKAGE_PIN N15   IOSTANDARD LVCMOS33 } [get_ports { gpio1[8]  }]; # Chipkit IO8
set_property -dict { PACKAGE_PIN M16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[9]  }]; # Chipkit IO9
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[10] }]; # Chipkit IO10
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[11] }]; # Chipkit IO11
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[12] }]; # Chipkit IO12
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[13] }]; # Chipkit IO13

set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { gpio1[14] }]; # Chipkit IO26
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[15] }]; # Chipkit IO27
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { gpio1[16] }]; # Chipkit IO28
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { gpio1[17] }]; # Chipkit IO29
set_property -dict { PACKAGE_PIN R11   IOSTANDARD LVCMOS33 } [get_ports { gpio1[18] }]; # Chipkit IO30
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { gpio1[19] }]; # Chipkit IO31
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { gpio1[20] }]; # Chipkit IO32
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { gpio1[21] }]; # Chipkit IO33
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[22] }]; # Chipkit IO34
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports { gpio1[23] }]; # Chipkit IO35
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { gpio1[24] }]; # Chipkit IO36
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[25] }]; # Chipkit IO37
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[26] }]; # Chipkit IO38
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[27] }]; # Chipkit IO39
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[28] }]; # Chipkit IO40
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[29] }]; # Chipkit IO41
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { gpio1[30] }]; # Chipkit IO42

set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[31] }]; # Chipkit I2C SCL
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { gpio1[32] }]; # Chipkit I2C SDA
set_property -dict { PACKAGE_PIN C1    IOSTANDARD LVCMOS33 } [get_ports { gpio1[33] }]; # Chipkit SPI SS
set_property -dict { PACKAGE_PIN F1    IOSTANDARD LVCMOS33 } [get_ports { gpio1[34] }]; # Chipkit SPI CLK
set_property -dict { PACKAGE_PIN H1    IOSTANDARD LVCMOS33 } [get_ports { gpio1[35] }]; # Chipkit SPI MOSI
set_property -dict { PACKAGE_PIN G1    IOSTANDARD LVCMOS33 } [get_ports { gpio1[36] }]; # Chipkit SPI MISO

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
