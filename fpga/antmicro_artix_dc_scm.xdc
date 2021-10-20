################################################################################
# clkin, reset, uart pins...
################################################################################

set_property -dict { PACKAGE_PIN C18  IOSTANDARD LVCMOS33 } [get_ports { ext_clk }];

set_property -dict { PACKAGE_PIN R19 IOSTANDARD LVCMOS33 } [get_ports { uart_main_tx }];
set_property -dict { PACKAGE_PIN P19  IOSTANDARD LVCMOS33 } [get_ports { uart_main_rx }];

set_property -dict { PACKAGE_PIN T20 IOSTANDARD LVCMOS33 } [get_ports { d11_led }];
set_property -dict { PACKAGE_PIN U20 IOSTANDARD LVCMOS33 } [get_ports { d12_led }];
set_property -dict { PACKAGE_PIN W20 IOSTANDARD LVCMOS33 } [get_ports { d13_led }];


################################################################################
# Design constraints and bitsteam attributes
################################################################################

#Internal VREF
set_property INTERNAL_VREF 0.675 [get_iobanks 34]

set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]

set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

################################################################################
# Clock constraints
################################################################################

create_clock -name sys_clk_pin -period 10.00 [get_ports { ext_clk }];
