#!/bin/bash -e

# process microwatt verilog

FILE_IN=microwatt_asic.v
FILE_OUT=microwatt_asic_processed.v

# Rename top level
sed 's/toplevel/microwatt/' < $FILE_IN > $FILE_OUT

# Add power to all macros, and route power in microwatt down to them
caravel/insert_power.py --verilog=$FILE_OUT --parent-power=vccd1 --parent-ground=vssd1 --power=vccd1 --ground=vssd1 --module=microwatt --module=core_0_4_1_4_4_1_2_2_92a0c5f888148ab9da14068b971849437301064b --module=execute1_0_9508e90548b0440a4a61e5743b76c1e309b23b7f --module=multiply_4 --module=soc_4096_100000000_0_0_4_0_4_0_4_1_4_4_1_2_2_32_ed0b68172790179612c5bea419d574732b13cc2a --module=icache_64_8_4_1_4_12_0_5ba93c9db0cff93f52b521d7420e43f6eda2784f --module=dcache_64_4_1_2_2_12_0 --module=cache_ram_5_64_1489f923c4dca729178b3e3233458550d8dddf29 --module=main_bram_64_10_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 --module=register_file_0_1489f923c4dca729178b3e3233458550d8dddf29 --module=wishbone_bram_wrapper_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 > ${FILE_OUT}.tmp1

# Hard macros use VPWR/VGND
caravel/insert_power.py --verilog=${FILE_OUT}.tmp1 --parent-power=vccd1 --parent-ground=vssd1 --power=VPWR --ground=VGND --module=Microwatt_FP_DFFRFile --module=multiply_add_64x64 --module=RAM32_1RW1R --module=RAM512 > ${FILE_OUT}.tmp2

mv ${FILE_OUT}.tmp2 ${FILE_OUT}
rm ${FILE_OUT}.tmp1

# Add defines
sed -i '1 a\
\
/* JTAG */\
`include "tap_top.v"\
\
/* UART */\
`include "raminfr.v"\
`include "uart_receiver.v"\
`include "uart_rfifo.v"\
`include "uart_tfifo.v"\
`include "uart_transmitter.v"\
`include "uart_defines.v"\
`include "uart_regs.v"\
`include "uart_sync_flops.v"\
`include "uart_wb.v"\
`include "uart_top.v"' $FILE_OUT
