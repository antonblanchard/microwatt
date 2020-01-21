#!/usr/bin/python3

# Create makefile dependencies for VHDL files, looking for "use work" and
# "entity work" declarations

import sys
import re
import os
from collections import defaultdict

if len(sys.argv) == 1 and sys.argv[1] == '--help':
    print("Usage: dependencies.py [--synth]")
    sys.exit(1)

synth = False
args = sys.argv[1:]
if sys.argv[1] == '--synth':
    synth = True
    args = sys.argv[2:]

# Look at what a file provides
entity = re.compile('entity (.*) is')
package = re.compile('package (.*) is')

# Look at what a file depends on
work = re.compile('use work\.([^.]+)\.')
entity_work = re.compile('entity work\.([^;]+)')

# Synthesis targets
synth_provides = {
    "dmi_dtm" : "dmi_dtm_dummy.vhdl",
    "clock_generator" : "fpga/clk_gen_bypass.vhd",
    "main_bram" : "fpga/main_bram.vhdl",
    "pp_soc_uart" : "fpga/pp_soc_uart.vhd"
}

# Simulation targets
sim_provides = {
    "dmi_dtm" : "dmi_dtm_xilinx.vhdl",
    "clock_generator" : "fpga/clk_gen_bypass.vhd",
    "main_bram" : "sim_bram.vhdl",
    "pp_soc_uart" : "sim_uart.vhdl"
}

if synth:
    provides = synth_provides
else:
    provides = sim_provides

dependencies = defaultdict(set)

for filename in args:
    with open(filename, 'r') as f:
        for line in f:
            l = line.rstrip(os.linesep)
            m = entity.search(l)
            if m:
                p = m.group(1)
                if p not in provides:
                    provides[p] = filename

            m = package.search(l)
            if m:
                p = m.group(1)
                if p not in provides:
                    provides[p] = filename

            m = work.search(l)
            if m:
                dependency = m.group(1)
                dependencies[filename].add(dependency)

            m = entity_work.search(l)
            if m:
                dependency = m.group(1)
                dependencies[filename].add(dependency)


emitted = set()
def chase_dependencies(filename):
    if filename not in dependencies:
        if filename not in emitted:
            print("%s " % (filename), end="")
            emitted.add(filename)
    else:
        for dep in dependencies[filename]:
            f = provides[dep]
            chase_dependencies(f)
            if f not in emitted:
                print("%s " % (f), end="")
                emitted.add(f)


if synth:
    chase_dependencies("fpga/toplevel.vhdl")
    print("fpga/toplevel.vhdl")
else:
    for filename in dependencies:
        (basename, suffix) = filename.split('.')
        print("%s.o:" % (basename), end="")
        for dependency in dependencies[filename]:
            p = provides[dependency]
            (basename2, suffix2) = p.split('.')
            print(" %s.o" % (basename2), end="")
        print("")
