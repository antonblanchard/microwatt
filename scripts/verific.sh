#!/bin/bash

D=$(dirname $0)

TCL=$(mktemp)

VERIFICDIR=$(dirname $(dirname $(which verific-linux)))

echo "setvhdllibrarypath -default $VERIFICDIR/vhdl_packages/vdbs_2008" >> $TCL

# FIXME: make this list dynamic
for i in decode_types.vhdl common.vhdl wishbone_types.vhdl insn_helpers.vhdl fetch1.vhdl fetch2.vhdl decode1.vhdl helpers.vhdl  decode2.vhdl register_file.vhdl  cr_file.vhdl crhelpers.vhdl ppc_fx_insns.vhdl sim_console.vhdl execute1.vhdl execute2.vhdl loadstore1.vhdl  loadstore2.vhdl multiply.vhdl writeback.vhdl wishbone_arbiter.vhdl core.vhdl simple_ram_behavioural_helpers.vhdl simple_ram_behavioural.vhdl core_tb.vhdl; do
    F=$(realpath $D/../$i)
    echo "analyze -format vhdl -vhdl_2008 $F" >> $TCL
done

echo "elaborate core" >> $TCL
echo "write core.v" >> $TCL
echo "area" >> $TCL
echo "optimize -hierarchy -constant -cse -operator -dangling -resource" >> $TCL
echo "area" >> $TCL
echo "write core-optimised.v" >> $TCL

verific-linux -script_file $TCL

rm -rf $TCL
