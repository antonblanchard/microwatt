#!/bin/bash -e

# process microwatt verilog

FILE_IN=microwatt_asic.v
FILE_OUT=microwatt_asic_processed.v

# Rename top level
sed 's/toplevel/microwatt/' < $FILE_IN > $FILE_OUT

# Add power to all macros, and route power in microwatt down to them
caravel/insert_power.py --verilog=$FILE_OUT --parent-power=vccd1 --parent-ground=vssd1 --power=vccd1 --ground=vssd1 --module=microwatt --module=core_0_4_1_4_4_1_2_2_452bf2882a9b5f1c06340d5059c72dbd8af3bf8b --module=execute1_0_276e8824c88e117571aa19e570895b56ecbd3507 --module=multiply_2 --module=soc_4096_100000000_0_0_4_0_4_0_4_1_4_4_1_2_2_32_529beb193518cdd5546a21170d32ebafc9f9cb89 --module=icache_64_8_4_1_4_12_0_5ba93c9db0cff93f52b521d7420e43f6eda2784f --module=dcache_64_4_1_2_2_12_0 --module=cache_ram_5_64_1489f923c4dca729178b3e3233458550d8dddf29 --module=main_bram_64_9_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 --module=register_file_0_3f29546453678b855931c174a97d6c0894b8f546 --module=wishbone_bram_wrapper_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 --module=fpu > ${FILE_OUT}.tmp1

# Hard macros use VPWR/VGND
caravel/insert_power.py --verilog=${FILE_OUT}.tmp1 --parent-power=vccd1 --parent-ground=vssd1 --power=VPWR --ground=VGND --module=Microwatt_FP_DFFRFile --module=multiply_add_64x64 --module=RAM32_1RW1R --module=RAM512 > ${FILE_OUT}.tmp2

mv ${FILE_OUT}.tmp2 ${FILE_OUT}
rm ${FILE_OUT}.tmp1

# Add defines
sed -i '1 i\
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
`include "uart_top.v"\
`include "simplebus_host.v"' $FILE_OUT
