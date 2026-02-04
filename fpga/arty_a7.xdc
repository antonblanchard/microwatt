################################################################################
# clkin, reset, uart pins...
################################################################################

set_property -dict { PACKAGE_PIN E3  IOSTANDARD LVCMOS33 } [get_ports { ext_clk }];

set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports { ext_rst_n }];

set_property -dict { PACKAGE_PIN D10 IOSTANDARD LVCMOS33 } [get_ports { uart_main_tx }];
set_property -dict { PACKAGE_PIN A9  IOSTANDARD LVCMOS33 } [get_ports { uart_main_rx }];

################################################################################
# RGB LEDs
################################################################################

set_property -dict { PACKAGE_PIN E1  IOSTANDARD LVCMOS33 } [get_ports { led_b[0] }];
set_property -dict { PACKAGE_PIN F6  IOSTANDARD LVCMOS33 } [get_ports { led_g[0] }];
set_property -dict { PACKAGE_PIN G6  IOSTANDARD LVCMOS33 } [get_ports { led_r[0] }];
set_property -dict { PACKAGE_PIN G4  IOSTANDARD LVCMOS33 } [get_ports { led_b[1] }];
set_property -dict { PACKAGE_PIN J4  IOSTANDARD LVCMOS33 } [get_ports { led_g[1] }];
set_property -dict { PACKAGE_PIN G3  IOSTANDARD LVCMOS33 } [get_ports { led_r[1] }];
set_property -dict { PACKAGE_PIN H4  IOSTANDARD LVCMOS33 } [get_ports { led_b[2] }];
set_property -dict { PACKAGE_PIN J2  IOSTANDARD LVCMOS33 } [get_ports { led_g[2] }];
set_property -dict { PACKAGE_PIN J3  IOSTANDARD LVCMOS33 } [get_ports { led_r[2] }];
set_property -dict { PACKAGE_PIN K2  IOSTANDARD LVCMOS33 } [get_ports { led_b[3] }];
set_property -dict { PACKAGE_PIN H6  IOSTANDARD LVCMOS33 } [get_ports { led_g[3] }];
set_property -dict { PACKAGE_PIN K1  IOSTANDARD LVCMOS33 } [get_ports { led_r[3] }];

################################################################################
# Normal LEDs
################################################################################

set_property -dict { PACKAGE_PIN H5  IOSTANDARD LVCMOS33 } [get_ports { led4 }];
set_property -dict { PACKAGE_PIN J5  IOSTANDARD LVCMOS33 } [get_ports { led5 }];
set_property -dict { PACKAGE_PIN T9  IOSTANDARD LVCMOS33 } [get_ports { led6 }];
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports { led7 }];

################################################################################
# Switches
################################################################################

set_property -dict { PACKAGE_PIN A8  IOSTANDARD LVCMOS33 } [get_ports { sw0 }];
set_property -dict { PACKAGE_PIN C11 IOSTANDARD LVCMOS33 } [get_ports { sw1 }];
set_property -dict { PACKAGE_PIN C10 IOSTANDARD LVCMOS33 } [get_ports { sw2 }];
set_property -dict { PACKAGE_PIN A10 IOSTANDARD LVCMOS33 } [get_ports { sw3 }];

################################################################################
# Buttons
################################################################################

set_property -dict { PACKAGE_PIN D9  IOSTANDARD LVCMOS33 } [get_ports { btn0 }];
set_property -dict { PACKAGE_PIN C9  IOSTANDARD LVCMOS33 } [get_ports { btn1 }];
set_property -dict { PACKAGE_PIN B9  IOSTANDARD LVCMOS33 } [get_ports { btn2 }];
set_property -dict { PACKAGE_PIN B8  IOSTANDARD LVCMOS33 } [get_ports { btn3 }];

################################################################################
# SPI Flash
################################################################################

set_property -dict { PACKAGE_PIN L13 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_cs_n }];
set_property -dict { PACKAGE_PIN L16 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_clk }];
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_mosi }];
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_miso }];
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_wp_n }];
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports { spi_flash_hold_n }];

# Put registers into IOBs to improve timing
set_property IOB true [get_cells -hierarchical -filter {NAME =~*/spi_rxtx/*sck_1_reg}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*/spi_rxtx/input_delay_1.dat_i_l*}]

################################################################################
# PMOD header JA (standard, 200 ohm protection resisters)
################################################################################

#set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_1 }];
#set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_2 }];
#set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_3 }];
#set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_4 }];
#set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_7 }];
#set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_8 }];
#set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_9 }];
#set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { pmod_ja_10 }];

# connection to Digilent PmodSD on JA
set_property -dict { PACKAGE_PIN G13 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ja_sdcard_data[3] }];
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ja_sdcard_cmd }];
set_property -dict { PACKAGE_PIN A11 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ja_sdcard_data[0] }];
set_property -dict { PACKAGE_PIN D12 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports { ja_sdcard_clk }];
set_property -dict { PACKAGE_PIN D13 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ja_sdcard_data[1] }];
set_property -dict { PACKAGE_PIN B18 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ja_sdcard_data[2] }];
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports { ja_sdcard_cd }];
#set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { ja_sdcard_wp }];

# Put registers into IOBs to improve timing
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard/sdpads_data_i_reg*}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard/xilinxsdrtristateimpl*_o_reg}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard/sdcard_clk_reg}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard/sdpads_cmd_i_reg}]

################################################################################
# PMOD header JB (high-speed, no protection resisters)
################################################################################

set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_1 }];
set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_2 }];
set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_3 }];
set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_4 }];
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_7 }];
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_8 }];
set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_9 }];
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { pmod_jb_10 }];

# connection to Digilent PmodSD on JB
#set_property -dict { PACKAGE_PIN E15 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard_data[3] }];
#set_property -dict { PACKAGE_PIN E16 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard_cmd }];
#set_property -dict { PACKAGE_PIN D15 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard_data[0] }];
#set_property -dict { PACKAGE_PIN C15 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports { sdcard_clk }];
#set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard_data[1] }];
#set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard_data[2] }];
#set_property -dict { PACKAGE_PIN K15 IOSTANDARD LVCMOS33 } [get_ports { sdcard_cd }];
#set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports { sdcard_wp }];

################################################################################
# PMOD header JC (high-speed, no protection resisters)
################################################################################

#set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_1 }];
#set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_2 }];
#set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_3 }];
#set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_4 }];
#set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_7 }];
#set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_8 }];
#set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_9 }];
#set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { pmod_jc_10 }];

# connection to second Digilent PmodSD on JC
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard2_data[3] }];
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard2_cmd }];
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard2_data[0] }];
set_property -dict { PACKAGE_PIN V11 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports { sdcard2_clk }];
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard2_data[1] }];
set_property -dict { PACKAGE_PIN V14 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { sdcard2_data[2] }];
set_property -dict { PACKAGE_PIN T13 IOSTANDARD LVCMOS33 } [get_ports { sdcard2_cd }];
#set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports { sdcard2_wp }];

# Put registers into IOBs to improve timing
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard2/sdpads_data_i_reg*}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard2/xilinxsdrtristateimpl*_o_reg}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard2/sdcard_clk_reg}]
set_property IOB true [get_cells -hierarchical -filter {NAME =~*.litesdcard2/sdpads_cmd_i_reg}]

################################################################################
# PMOD header JD (standard, 200 ohm protection resisters)
################################################################################

#set_property -dict { PACKAGE_PIN D4 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_1 }];
#set_property -dict { PACKAGE_PIN D3 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_2 }];
#set_property -dict { PACKAGE_PIN F4 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_3 }];
#set_property -dict { PACKAGE_PIN F3 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_4 }];
#set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_7 }];
#set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_8 }];
#set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_9 }];
#set_property -dict { PACKAGE_PIN G2 IOSTANDARD LVCMOS33 } [get_ports { pmod_jd_10 }];

# connection to i2c RTC chip (Dallas DS3231) on JD
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { i2c_rtc_d }];
set_property -dict { PACKAGE_PIN H2 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { i2c_rtc_c }];

################################################################################
# TFT LCD shield (arduino-compatible)
# hacked to swap the LCD_RST and LCD_D0 lines, and put LCD_D1 on A5
################################################################################

set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { lcd_rst }];
#set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 } [get_ports { lcd_tp }];
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[2] }];
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[3] }];
set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[4] }];
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[5] }];
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[6] }];
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports { lcd_d[7] }];
set_property -dict { PACKAGE_PIN F5  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { lcd_rd }]; # A0
set_property -dict { PACKAGE_PIN D8  IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { lcd_wr }]; # A1
set_property -dict { PACKAGE_PIN C7  IOSTANDARD LVCMOS33 } [get_ports { lcd_rs }]; # A2
set_property -dict { PACKAGE_PIN E7  IOSTANDARD LVCMOS33 } [get_ports { lcd_cs }]; # A3
set_property -dict { PACKAGE_PIN D7  IOSTANDARD LVCMOS33 } [get_ports { lcd_d[0] }]; # A4
set_property -dict { PACKAGE_PIN D5  IOSTANDARD LVCMOS33 } [get_ports { lcd_d[1] }]; # A5

################################################################################
# Analog inputs (connected to touchscreen)
################################################################################
set_property -dict { PACKAGE_PIN C4 IOSTANDARD LVCMOS33 } [get_ports { a2_p }];
set_property -dict { PACKAGE_PIN B4 IOSTANDARD LVCMOS33 } [get_ports { a2_n }];
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports { a3_p }];
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports { a3_n }];
set_property -dict { PACKAGE_PIN B3 IOSTANDARD LVCMOS33 } [get_ports { a4_p }];
set_property -dict { PACKAGE_PIN B2 IOSTANDARD LVCMOS33 } [get_ports { a4_n }];
set_property -dict { PACKAGE_PIN D14 IOSTANDARD LVCMOS33 } [get_ports { a5_p }];
set_property -dict { PACKAGE_PIN C14 IOSTANDARD LVCMOS33 } [get_ports { a5_n }];

################################################################################
# connection to micro SD card socket on touchscreen board
################################################################################
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ts_sdcard_data[3] }];
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ts_sdcard_cmd }];
set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ts_sdcard_data[0] }];
set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 SLEW FAST } [get_ports { ts_sdcard_clk }];
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ts_sdcard_data[1] }];
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 SLEW FAST PULLUP TRUE } [get_ports { ts_sdcard_data[2] }];
set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 PULLUP TRUE } [get_ports { ts_sdcard_cd }];
#set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports { ts_sdcard_wp }];

################################################################################
# Arduino/chipKIT shield connector
################################################################################

#set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io0 }];
#set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io1 }];
#set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io2 }];
#set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io3 }];
#set_property -dict { PACKAGE_PIN R12 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io4 }];
#set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io5 }];
#set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io6 }];
#set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io7 }];
#set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io8 }];
set_property -dict { PACKAGE_PIN M16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io9 }];
#set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io10 }];
#set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io11 }];
#set_property -dict { PACKAGE_PIN R17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io12 }];
#set_property -dict { PACKAGE_PIN P17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io13 }];
#set_property -dict { PACKAGE_PIN U11 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io26 }];
#set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io27 }];
#set_property -dict { PACKAGE_PIN M13 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io28 }];
#set_property -dict { PACKAGE_PIN R10 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io29 }];
set_property -dict { PACKAGE_PIN R11 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io30 }];
set_property -dict { PACKAGE_PIN R13 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io31 }];
set_property -dict { PACKAGE_PIN R15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io32 }];
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io33 }];
#set_property -dict { PACKAGE_PIN R16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io34 }];
#set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io35 }];
#set_property -dict { PACKAGE_PIN N14 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io36 }];
#set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io37 }];
#set_property -dict { PACKAGE_PIN T18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io38 }];
#set_property -dict { PACKAGE_PIN R18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io39 }];
#set_property -dict { PACKAGE_PIN P18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io40 }];
#set_property -dict { PACKAGE_PIN N17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io41 }];
#set_property -dict { PACKAGE_PIN M17 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io42 }]; # A
#set_property -dict { PACKAGE_PIN L18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io43 }]; # SCL
#set_property -dict { PACKAGE_PIN M18 IOSTANDARD LVCMOS33 PULLDOWN TRUE } [get_ports { shield_io44 }]; # SDA
#set_property -dict { PACKAGE_PIN C2  IOSTANDARD LVCMOS33 } [get_ports { shield_rst }];

#set_property -dict { PACKAGE_PIN C1  IOSTANDARD LVCMOS33 } [get_ports { spi_hdr_ss }];
#set_property -dict { PACKAGE_PIN F1  IOSTANDARD LVCMOS33 } [get_ports { spi_hdr_clk }];
#set_property -dict { PACKAGE_PIN H1  IOSTANDARD LVCMOS33 } [get_ports { spi_hdr_mosi }];
#set_property -dict { PACKAGE_PIN G1  IOSTANDARD LVCMOS33 } [get_ports { spi_hdr_miso }];

################################################################################
# Ethernet (generated by LiteX)
################################################################################

# eth_ref_clk:0
set_property LOC G18 [get_ports {eth_ref_clk}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_ref_clk}]

# eth_clocks:0.tx
set_property LOC H16 [get_ports {eth_clocks_tx}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_clocks_tx}]

# eth_clocks:0.rx
set_property LOC F15 [get_ports {eth_clocks_rx}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_clocks_rx}]

# eth:0.rst_n
set_property LOC C16 [get_ports {eth_rst_n}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rst_n}]

# eth:0.mdio
set_property LOC K13 [get_ports {eth_mdio}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_mdio}]

# eth:0.mdc
set_property LOC F16 [get_ports {eth_mdc}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_mdc}]

# eth:0.rx_dv
set_property LOC G16 [get_ports {eth_rx_dv}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_dv}]

# eth:0.rx_er
set_property LOC C17 [get_ports {eth_rx_er}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_er}]

# eth:0.rx_data
set_property LOC D18 [get_ports {eth_rx_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_data[0]}]

# eth:0.rx_data
set_property LOC E17 [get_ports {eth_rx_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_data[1]}]

# eth:0.rx_data
set_property LOC E18 [get_ports {eth_rx_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_data[2]}]

# eth:0.rx_data
set_property LOC G17 [get_ports {eth_rx_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_rx_data[3]}]

# eth:0.tx_en
set_property LOC H15 [get_ports {eth_tx_en}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_en}]

# eth:0.tx_data
set_property LOC H14 [get_ports {eth_tx_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_data[0]}]

# eth:0.tx_data
set_property LOC J14 [get_ports {eth_tx_data[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_data[1]}]

# eth:0.tx_data
set_property LOC J13 [get_ports {eth_tx_data[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_data[2]}]

# eth:0.tx_data
set_property LOC H17 [get_ports {eth_tx_data[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_tx_data[3]}]

# eth:0.col
set_property LOC D17 [get_ports {eth_col}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_col}]

# eth:0.crs
set_property LOC G14 [get_ports {eth_crs}]
set_property IOSTANDARD LVCMOS33 [get_ports {eth_crs}]

################################################################################
# DRAM (generated by LiteX)
################################################################################

# ddram:0.a
set_property LOC R2 [get_ports {ddram_a[0]}]
set_property SLEW FAST [get_ports {ddram_a[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[0]}]

# ddram:0.a
set_property LOC M6 [get_ports {ddram_a[1]}]
set_property SLEW FAST [get_ports {ddram_a[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[1]}]

# ddram:0.a
set_property LOC N4 [get_ports {ddram_a[2]}]
set_property SLEW FAST [get_ports {ddram_a[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[2]}]

# ddram:0.a
set_property LOC T1 [get_ports {ddram_a[3]}]
set_property SLEW FAST [get_ports {ddram_a[3]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[3]}]

# ddram:0.a
set_property LOC N6 [get_ports {ddram_a[4]}]
set_property SLEW FAST [get_ports {ddram_a[4]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[4]}]

# ddram:0.a
set_property LOC R7 [get_ports {ddram_a[5]}]
set_property SLEW FAST [get_ports {ddram_a[5]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[5]}]

# ddram:0.a
set_property LOC V6 [get_ports {ddram_a[6]}]
set_property SLEW FAST [get_ports {ddram_a[6]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[6]}]

# ddram:0.a
set_property LOC U7 [get_ports {ddram_a[7]}]
set_property SLEW FAST [get_ports {ddram_a[7]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[7]}]

# ddram:0.a
set_property LOC R8 [get_ports {ddram_a[8]}]
set_property SLEW FAST [get_ports {ddram_a[8]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[8]}]

# ddram:0.a
set_property LOC V7 [get_ports {ddram_a[9]}]
set_property SLEW FAST [get_ports {ddram_a[9]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[9]}]

# ddram:0.a
set_property LOC R6 [get_ports {ddram_a[10]}]
set_property SLEW FAST [get_ports {ddram_a[10]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[10]}]

# ddram:0.a
set_property LOC U6 [get_ports {ddram_a[11]}]
set_property SLEW FAST [get_ports {ddram_a[11]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[11]}]

# ddram:0.a
set_property LOC T6 [get_ports {ddram_a[12]}]
set_property SLEW FAST [get_ports {ddram_a[12]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[12]}]

# ddram:0.a
set_property LOC T8 [get_ports {ddram_a[13]}]
set_property SLEW FAST [get_ports {ddram_a[13]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_a[13]}]

# ddram:0.ba
set_property LOC R1 [get_ports {ddram_ba[0]}]
set_property SLEW FAST [get_ports {ddram_ba[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_ba[0]}]

# ddram:0.ba
set_property LOC P4 [get_ports {ddram_ba[1]}]
set_property SLEW FAST [get_ports {ddram_ba[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_ba[1]}]

# ddram:0.ba
set_property LOC P2 [get_ports {ddram_ba[2]}]
set_property SLEW FAST [get_ports {ddram_ba[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_ba[2]}]

# ddram:0.ras_n
set_property LOC P3 [get_ports {ddram_ras_n}]
set_property SLEW FAST [get_ports {ddram_ras_n}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_ras_n}]

# ddram:0.cas_n
set_property LOC M4 [get_ports {ddram_cas_n}]
set_property SLEW FAST [get_ports {ddram_cas_n}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_cas_n}]

# ddram:0.we_n
set_property LOC P5 [get_ports {ddram_we_n}]
set_property SLEW FAST [get_ports {ddram_we_n}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_we_n}]

# ddram:0.cs_n
set_property LOC U8 [get_ports {ddram_cs_n}]
set_property SLEW FAST [get_ports {ddram_cs_n}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_cs_n}]

# ddram:0.dm
set_property LOC L1 [get_ports {ddram_dm[0]}]
set_property SLEW FAST [get_ports {ddram_dm[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dm[0]}]

# ddram:0.dm
set_property LOC U1 [get_ports {ddram_dm[1]}]
set_property SLEW FAST [get_ports {ddram_dm[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dm[1]}]

# ddram:0.dq
set_property LOC K5 [get_ports {ddram_dq[0]}]
set_property SLEW FAST [get_ports {ddram_dq[0]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[0]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[0]}]

# ddram:0.dq
set_property LOC L3 [get_ports {ddram_dq[1]}]
set_property SLEW FAST [get_ports {ddram_dq[1]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[1]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[1]}]

# ddram:0.dq
set_property LOC K3 [get_ports {ddram_dq[2]}]
set_property SLEW FAST [get_ports {ddram_dq[2]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[2]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[2]}]

# ddram:0.dq
set_property LOC L6 [get_ports {ddram_dq[3]}]
set_property SLEW FAST [get_ports {ddram_dq[3]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[3]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[3]}]

# ddram:0.dq
set_property LOC M3 [get_ports {ddram_dq[4]}]
set_property SLEW FAST [get_ports {ddram_dq[4]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[4]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[4]}]

# ddram:0.dq
set_property LOC M1 [get_ports {ddram_dq[5]}]
set_property SLEW FAST [get_ports {ddram_dq[5]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[5]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[5]}]

# ddram:0.dq
set_property LOC L4 [get_ports {ddram_dq[6]}]
set_property SLEW FAST [get_ports {ddram_dq[6]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[6]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[6]}]

# ddram:0.dq
set_property LOC M2 [get_ports {ddram_dq[7]}]
set_property SLEW FAST [get_ports {ddram_dq[7]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[7]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[7]}]

# ddram:0.dq
set_property LOC V4 [get_ports {ddram_dq[8]}]
set_property SLEW FAST [get_ports {ddram_dq[8]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[8]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[8]}]

# ddram:0.dq
set_property LOC T5 [get_ports {ddram_dq[9]}]
set_property SLEW FAST [get_ports {ddram_dq[9]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[9]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[9]}]

# ddram:0.dq
set_property LOC U4 [get_ports {ddram_dq[10]}]
set_property SLEW FAST [get_ports {ddram_dq[10]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[10]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[10]}]

# ddram:0.dq
set_property LOC V5 [get_ports {ddram_dq[11]}]
set_property SLEW FAST [get_ports {ddram_dq[11]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[11]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[11]}]

# ddram:0.dq
set_property LOC V1 [get_ports {ddram_dq[12]}]
set_property SLEW FAST [get_ports {ddram_dq[12]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[12]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[12]}]

# ddram:0.dq
set_property LOC T3 [get_ports {ddram_dq[13]}]
set_property SLEW FAST [get_ports {ddram_dq[13]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[13]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[13]}]

# ddram:0.dq
set_property LOC U3 [get_ports {ddram_dq[14]}]
set_property SLEW FAST [get_ports {ddram_dq[14]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[14]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[14]}]

# ddram:0.dq
set_property LOC R3 [get_ports {ddram_dq[15]}]
set_property SLEW FAST [get_ports {ddram_dq[15]}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_dq[15]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dq[15]}]

# ddram:0.dqs_p
set_property LOC N2 [get_ports {ddram_dqs_p[0]}]
set_property SLEW FAST [get_ports {ddram_dqs_p[0]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_dqs_p[0]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dqs_p[0]}]

# ddram:0.dqs_p
set_property LOC U2 [get_ports {ddram_dqs_p[1]}]
set_property SLEW FAST [get_ports {ddram_dqs_p[1]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_dqs_p[1]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dqs_p[1]}]

# ddram:0.dqs_n
set_property LOC N1 [get_ports {ddram_dqs_n[0]}]
set_property SLEW FAST [get_ports {ddram_dqs_n[0]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_dqs_n[0]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dqs_n[0]}]

# ddram:0.dqs_n
set_property LOC V2 [get_ports {ddram_dqs_n[1]}]
set_property SLEW FAST [get_ports {ddram_dqs_n[1]}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_dqs_n[1]}]
set_property IN_TERM UNTUNED_SPLIT_40 [get_ports {ddram_dqs_n[1]}]

# ddram:0.clk_p
set_property LOC U9 [get_ports {ddram_clk_p}]
set_property SLEW FAST [get_ports {ddram_clk_p}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_clk_p}]

# ddram:0.clk_n
set_property LOC V9 [get_ports {ddram_clk_n}]
set_property SLEW FAST [get_ports {ddram_clk_n}]
set_property IOSTANDARD DIFF_SSTL135 [get_ports {ddram_clk_n}]

# ddram:0.cke
set_property LOC N5 [get_ports {ddram_cke}]
set_property SLEW FAST [get_ports {ddram_cke}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_cke}]

# ddram:0.odt
set_property LOC R5 [get_ports {ddram_odt}]
set_property SLEW FAST [get_ports {ddram_odt}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_odt}]

# ddram:0.reset_n
set_property LOC K6 [get_ports {ddram_reset_n}]
set_property SLEW FAST [get_ports {ddram_reset_n}]
set_property IOSTANDARD SSTL135 [get_ports {ddram_reset_n}]

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

create_clock -name eth_rx_clk -period 40.0 [get_ports { eth_clocks_rx }]

create_clock -name eth_tx_clk -period 40.0 [get_ports { eth_clocks_tx }]

set_clock_groups -group [get_clocks -include_generated_clocks -of [get_nets system_clk]] -group [get_clocks -include_generated_clocks -of [get_nets eth_clocks_rx]] -asynchronous

set_clock_groups -group [get_clocks -include_generated_clocks -of [get_nets system_clk]] -group [get_clocks -include_generated_clocks -of [get_nets eth_clocks_tx]] -asynchronous

set_clock_groups -group [get_clocks -include_generated_clocks -of [get_nets eth_clocks_rx]] -group [get_clocks -include_generated_clocks -of [get_nets eth_clocks_tx]] -asynchronous

################################################################################
# False path constraints (from LiteX as they relate to LiteDRAM and LiteEth)
################################################################################

set_false_path -quiet -through [get_nets -hierarchical -filter {mr_ff == TRUE}]

set_false_path -quiet -to [get_pins -filter {REF_PIN_NAME == PRE} -of_objects [get_cells -hierarchical -filter {ars_ff1 == TRUE || ars_ff2 == TRUE}]]

set_max_delay 2 -quiet -from [get_pins -filter {REF_PIN_NAME == C} -of_objects [get_cells -hierarchical -filter {ars_ff1 == TRUE}]] -to [get_pins -filter {REF_PIN_NAME == D} -of_objects [get_cells -hierarchical -filter {ars_ff2 == TRUE}]]
