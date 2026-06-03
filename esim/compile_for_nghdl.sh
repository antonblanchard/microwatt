#!/bin/bash
# ==========================================================
# Compile Microwatt + NGHDL wrapper
# Full simulation-safe flow with all C helper linking
# ==========================================================

set -e

ESIM_DIR="esim"
WORK_DIR="esim/ghdl_work"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "=============================================="
echo " Step 0: Build required C helper objects"
echo "=============================================="

cc -O3 -Wall -c -o sim_vhpi_c.o sim_vhpi_c.c
cc -O3 -Wall -c -o sim_console_c.o sim_console_c.c
cc -O3 -Wall -c -o sim_bram_helpers_c.o sim_bram_helpers_c.c

echo "=============================================="
echo " Step 1: Compile Microwatt + wrapper"
echo "=============================================="

ghdl -c --std=08 --workdir="$WORK_DIR" \
    -Wl,sim_vhpi_c.o \
    -Wl,sim_console_c.o \
    -Wl,sim_bram_helpers_c.o \
    decode_types.vhdl \
    common.vhdl \
    wishbone_types.vhdl \
    fetch1.vhdl \
    utils.vhdl \
    plrufn.vhdl \
    cache_ram.vhdl \
    icache.vhdl \
    predecode.vhdl \
    decode1.vhdl \
    helpers.vhdl \
    insn_helpers.vhdl \
    control.vhdl \
    decode2.vhdl \
    register_file.vhdl \
    cr_file.vhdl \
    crhelpers.vhdl \
    ppc_fx_insns.vhdl \
    rotator.vhdl \
    logical.vhdl \
    countbits.vhdl \
    multiply.vhdl \
    multiply-32s.vhdl \
    divider.vhdl \
    execute1.vhdl \
    loadstore1.vhdl \
    mmu.vhdl \
    dcache.vhdl \
    writeback.vhdl \
    core_debug.vhdl \
    core.vhdl \
    fpu.vhdl \
    pmu.vhdl \
    bitsort.vhdl \
    wishbone_arbiter.vhdl \
    wishbone_bram_wrapper.vhdl \
    sync_fifo.vhdl \
    wishbone_debug_master.vhdl \
    xics.vhdl \
    git.vhdl \
    syscon.vhdl \
    gpio.vhdl \
    dmi_dtm_dummy.vhdl \
    soc.vhdl \
    spi_rxtx.vhdl \
    spi_flash_ctrl.vhdl \
    sim_console.vhdl \
    sim_pp_uart.vhdl \
    sim_bram_helpers.vhdl \
    sim_bram.vhdl \
    sim_16550_uart.vhdl \
    foreign_random.vhdl \
    glibc_random.vhdl \
    glibc_random_helpers.vhdl \
    "$ESIM_DIR/microwatt_cosim.vhdl" \
    -e microwatt_cosim

echo "=============================================="
echo " SUCCESS"
echo "=============================================="
echo "Microwatt NGHDL wrapper compiled successfully"
echo "GHDL work directory: $WORK_DIR"
