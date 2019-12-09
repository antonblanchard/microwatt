set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { ext_clk }];
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { ext_clk }];

set_property -dict { PACKAGE_PIN C2    IOSTANDARD LVCMOS33 } [get_ports { ext_rst }];

set_property -dict { PACKAGE_PIN D10   IOSTANDARD LVCMOS33 } [get_ports { uart0_txd }];
set_property -dict { PACKAGE_PIN A9    IOSTANDARD LVCMOS33 } [get_ports { uart0_rxd }];

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
