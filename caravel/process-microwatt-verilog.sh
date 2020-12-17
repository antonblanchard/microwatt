#!/bin/bash -e

# process microwatt verilog

FILE=microwatt.v

# Remove these modules that are implemented as hard macros
for module in register_file_0_1489f923c4dca729178b3e3233458550d8dddf29 dcache_64_2_2_2_2_12_0 icache_64_8_2_2_4_12_56_0_5ba93c9db0cff93f52b521d7420e43f6eda2784f cache_ram_4_64_1489f923c4dca729178b3e3233458550d8dddf29 cache_ram_4_64_3f29546453678b855931c174a97d6c0894b8f546 plru_1 multiply_4
do
        sed -i "/^module $module/,/^endmodule/d" $FILE
done

# Remove the debug bus in the places we call our macros
for module in dcache_64_2_2_2_2_12_0 icache_64_8_2_2_4_12_56_0_5ba93c9db0cff93f52b521d7420e43f6eda2784f register_file_0_1489f923c4dca729178b3e3233458550d8dddf29; do
	for port in dbg_gpr log_out sim_dump; do
		sed -i "/  $module /,/);/{ /$port/d }" $FILE
	done
done

# Rename these modules to match the hard macro names
sed -i 's/register_file_0_1489f923c4dca729178b3e3233458550d8dddf29/register_file/' $FILE
sed -i 's/dcache_64_2_2_2_2_12_0/dcache/' $FILE
sed -i 's/icache_64_8_2_2_4_12_56_0_5ba93c9db0cff93f52b521d7420e43f6eda2784f/icache/' $FILE
sed -i 's/toplevel/microwatt/' $FILE

# Add power to all macros, and route power in microwatt down to them
caravel/insert_power.py $FILE dcache icache register_file multiply_4 RAM_512x64 main_bram_64_10_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 soc_4096_50000000_0_0_4_0_4_0_c832069ef22b63469d396707bc38511cc2410ddb wishbone_bram_wrapper_4096_a75adb9e07879fb6c63b494abe06e3f9a6bb2ed9 microwatt core_0_602f7ae323a872754ff5ac989c2e00f60e206d8e execute1_0_0e356ba505631fbf715758bed27d503f8b260e3a > $FILE.tmp && mv $FILE.tmp $FILE

# Add defines
sed -i '1 a\
\
/* Hard macros */\
`ifdef SIM\
`include "RAM_512x64.v"\
`include "register_file.v"\
`include "icache.v"\
`include "dcache.v"\
`include "multiply_4.v"\
`endif\
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
`include "uart_top.v"' $FILE
