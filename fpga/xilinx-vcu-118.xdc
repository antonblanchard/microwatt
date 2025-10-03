# VCU118 Constraints for Debug Top-level

# ========================================
# SYSTEM CLOCK - 300MHz Differential
# ========================================
set_property -dict {PACKAGE_PIN AY24 IOSTANDARD LVDS} [get_ports ext_clk_p]
set_property -dict {PACKAGE_PIN AY23 IOSTANDARD LVDS} [get_ports ext_clk_n]


# Clock constraint - 125MHz input (8.000ns period)  
create_clock -period 8.000 -name ext_clk [get_ports ext_clk_p]

# ========================================
# RESET - CPU Reset Button (active-high)
# ========================================
set_property PACKAGE_PIN L19 [get_ports "ext_rst"]
set_property IOSTANDARD LVCMOS12 [get_ports "ext_rst"]

# ========================================  
# UART - USB-to-UART Bridge
# ========================================
set_property PACKAGE_PIN AW25 [get_ports "uart0_rxd"]
set_property IOSTANDARD LVCMOS18 [get_ports "uart0_rxd"]

set_property PACKAGE_PIN BB21 [get_ports "uart0_txd"]
set_property IOSTANDARD LVCMOS18 [get_ports "uart0_txd"]

# ========================================
# DEBUG LEDs - Use GPIO LEDs from VCU118
# From Table 3-29: GPIO_LED connections
# ========================================
set_property PACKAGE_PIN AT32 [get_ports "debug_led0"]
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led0"]

set_property PACKAGE_PIN AV34 [get_ports "debug_led1"] 
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led1"]

set_property PACKAGE_PIN AY30 [get_ports "debug_led2"]
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led2"]

set_property PACKAGE_PIN BB32 [get_ports "debug_led3"]
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led3"]

set_property PACKAGE_PIN BF32 [get_ports "debug_led4"]
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led4"]

set_property PACKAGE_PIN AU37 [get_ports "debug_led5"]
set_property IOSTANDARD LVCMOS12 [get_ports "debug_led5"]


# ========================================
# DDR4 C1 Interface - 40-bit (2.5 chips: U60, U61, U62, half of U63)
# ========================================

# DDR4 Address/Command Signals
set_property PACKAGE_PIN D14 [get_ports "ddram_a[0]"]
set_property PACKAGE_PIN B15 [get_ports "ddram_a[1]"]
set_property PACKAGE_PIN B16 [get_ports "ddram_a[2]"]
set_property PACKAGE_PIN C14 [get_ports "ddram_a[3]"]
set_property PACKAGE_PIN C15 [get_ports "ddram_a[4]"]
set_property PACKAGE_PIN A13 [get_ports "ddram_a[5]"]
set_property PACKAGE_PIN A14 [get_ports "ddram_a[6]"]
set_property PACKAGE_PIN A15 [get_ports "ddram_a[7]"]
set_property PACKAGE_PIN A16 [get_ports "ddram_a[8]"]
set_property PACKAGE_PIN B12 [get_ports "ddram_a[9]"]
set_property PACKAGE_PIN C12 [get_ports "ddram_a[10]"]
set_property PACKAGE_PIN B13 [get_ports "ddram_a[11]"]
set_property PACKAGE_PIN C13 [get_ports "ddram_a[12]"]
set_property PACKAGE_PIN D15 [get_ports "ddram_a[13]"]

set_property PACKAGE_PIN G15 [get_ports "ddram_ba[0]"]
set_property PACKAGE_PIN G13 [get_ports "ddram_ba[1]"]
set_property PACKAGE_PIN H13 [get_ports "ddram_bg"]

# DDR4 Command Signals - these are shared with address lines in DDR4
 # Shared with A16
set_property PACKAGE_PIN F15 [get_ports "ddram_ras_n"]
# Shared with A15    
set_property PACKAGE_PIN H15 [get_ports "ddram_cas_n"]   
# Shared with A14
set_property PACKAGE_PIN H14 [get_ports "ddram_we_n"]    
set_property PACKAGE_PIN F13 [get_ports "ddram_cs_n"]
set_property PACKAGE_PIN E13 [get_ports "ddram_act_n"]

# DDR4 Clock - Single-ended, not differential
set_property PACKAGE_PIN F14 [get_ports "ddram_clk_p"]
set_property PACKAGE_PIN E14 [get_ports "ddram_clk_n"]

# DDR4 Control
set_property PACKAGE_PIN A10 [get_ports "ddram_cke"]
set_property PACKAGE_PIN C8  [get_ports "ddram_odt"]
set_property PACKAGE_PIN N20 [get_ports "ddram_reset_n"]

# DDR4 Data - DQ[39:0] (First 2.5 chips: U60, U61, U62, half of U63)
# Device U60 - DQ[15:0]
set_property PACKAGE_PIN F11 [get_ports "ddram_dq[0]"]
set_property PACKAGE_PIN E11 [get_ports "ddram_dq[1]"]
set_property PACKAGE_PIN F10 [get_ports "ddram_dq[2]"]
set_property PACKAGE_PIN F9  [get_ports "ddram_dq[3]"]
set_property PACKAGE_PIN H12 [get_ports "ddram_dq[4]"]
set_property PACKAGE_PIN G12 [get_ports "ddram_dq[5]"]
set_property PACKAGE_PIN E9  [get_ports "ddram_dq[6]"]
set_property PACKAGE_PIN D9  [get_ports "ddram_dq[7]"]
set_property PACKAGE_PIN R19 [get_ports "ddram_dq[8]"]
set_property PACKAGE_PIN P19 [get_ports "ddram_dq[9]"]
set_property PACKAGE_PIN M18 [get_ports "ddram_dq[10]"]
set_property PACKAGE_PIN M17 [get_ports "ddram_dq[11]"]
set_property PACKAGE_PIN N19 [get_ports "ddram_dq[12]"]
set_property PACKAGE_PIN N18 [get_ports "ddram_dq[13]"]
set_property PACKAGE_PIN N17 [get_ports "ddram_dq[14]"]
set_property PACKAGE_PIN M16 [get_ports "ddram_dq[15]"]

# Device U61 - DQ[31:16]
set_property PACKAGE_PIN L16 [get_ports "ddram_dq[16]"]
set_property PACKAGE_PIN K16 [get_ports "ddram_dq[17]"]
set_property PACKAGE_PIN L18 [get_ports "ddram_dq[18]"]
set_property PACKAGE_PIN K18 [get_ports "ddram_dq[19]"]
set_property PACKAGE_PIN J17 [get_ports "ddram_dq[20]"]
set_property PACKAGE_PIN H17 [get_ports "ddram_dq[21]"]
set_property PACKAGE_PIN H19 [get_ports "ddram_dq[22]"]
set_property PACKAGE_PIN H18 [get_ports "ddram_dq[23]"]
set_property PACKAGE_PIN F19 [get_ports "ddram_dq[24]"]
set_property PACKAGE_PIN F18 [get_ports "ddram_dq[25]"]
set_property PACKAGE_PIN E19 [get_ports "ddram_dq[26]"]
set_property PACKAGE_PIN E18 [get_ports "ddram_dq[27]"]
set_property PACKAGE_PIN G20 [get_ports "ddram_dq[28]"]
set_property PACKAGE_PIN F20 [get_ports "ddram_dq[29]"]
set_property PACKAGE_PIN E17 [get_ports "ddram_dq[30]"]
set_property PACKAGE_PIN D16 [get_ports "ddram_dq[31]"]

# Device U62 - DQ[39:32] (first 8 bits only)
set_property PACKAGE_PIN D17 [get_ports "ddram_dq[32]"]
set_property PACKAGE_PIN C17 [get_ports "ddram_dq[33]"]
set_property PACKAGE_PIN C19 [get_ports "ddram_dq[34]"]
set_property PACKAGE_PIN C18 [get_ports "ddram_dq[35]"]
set_property PACKAGE_PIN D20 [get_ports "ddram_dq[36]"]
set_property PACKAGE_PIN D19 [get_ports "ddram_dq[37]"]
set_property PACKAGE_PIN C20 [get_ports "ddram_dq[38]"]
set_property PACKAGE_PIN B20 [get_ports "ddram_dq[39]"]

# DDR4 Data Strobes - DQS[4:0] (5 pairs for 2.5 chips)
set_property PACKAGE_PIN D11 [get_ports "ddram_dqs_p[0]"]
set_property PACKAGE_PIN D10 [get_ports "ddram_dqs_n[0]"]
set_property PACKAGE_PIN P17 [get_ports "ddram_dqs_p[1]"]
set_property PACKAGE_PIN P16 [get_ports "ddram_dqs_n[1]"]
set_property PACKAGE_PIN K19 [get_ports "ddram_dqs_p[2]"]
set_property PACKAGE_PIN J19 [get_ports "ddram_dqs_n[2]"]
set_property PACKAGE_PIN F16 [get_ports "ddram_dqs_p[3]"]
set_property PACKAGE_PIN E16 [get_ports "ddram_dqs_n[3]"]
set_property PACKAGE_PIN A19 [get_ports "ddram_dqs_p[4]"]
set_property PACKAGE_PIN A18 [get_ports "ddram_dqs_n[4]"]

# DDR4 Data Mask - DM[4:0] (5 signals for 2.5 chips)
set_property PACKAGE_PIN G11 [get_ports "ddram_dm[0]"]
set_property PACKAGE_PIN R18 [get_ports "ddram_dm[1]"]
set_property PACKAGE_PIN K17 [get_ports "ddram_dm[2]"]
set_property PACKAGE_PIN G18 [get_ports "ddram_dm[3]"]
set_property PACKAGE_PIN B18 [get_ports "ddram_dm[4]"]

# IO Standards for DDR4
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_a[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_ba[*]"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_bg"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_ras_n"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_cas_n"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_we_n"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_cs_n"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_act_n"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_cke"]
set_property IOSTANDARD SSTL12_DCI [get_ports "ddram_odt"]
set_property IOSTANDARD LVCMOS12   [get_ports "ddram_reset_n"]

# Clock signals use single-ended SSTL12_DCI (not differential)
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "ddram_clk_p"]
set_property IOSTANDARD DIFF_SSTL12_DCI [get_ports "ddram_clk_n"]

set_property IOSTANDARD POD12_DCI [get_ports "ddram_dq[*]"]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports "ddram_dqs_p[*]"]
set_property IOSTANDARD DIFF_POD12_DCI [get_ports "ddram_dqs_n[*]"]
set_property IOSTANDARD POD12_DCI [get_ports "ddram_dm[*]"]