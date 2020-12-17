#!/usr/bin/python

import sys
import re

module_regex = r'[a-zA-Z0-9_\.\\]+'

# match:
# module dcache(clk, rst, d_in, m_in, wishbone_in, d_out, m_out, stall_out, wishbone_out);
module_re = re.compile(r'module\s+(' + module_regex + r')\((.*)\);')

# match:
# dcache_64_2_2_2_2_12_0 dcache_0 (
hookup_re = re.compile(r'\s+(' + module_regex + r') ' + module_regex + r'\s+\(')

header1 = """\
`ifdef USE_POWER_PINS
        vdda1, vdda2, vssa1, vssa2, vccd1, vccd2, vssd1, vssd2,
`endif\
"""

header2 = """\
`ifdef USE_POWER_PINS
  inout vdda1;        // User area 1 3.3V supply
  inout vdda2;        // User area 2 3.3V supply
  inout vssa1;        // User area 1 analog ground
  inout vssa2;        // User area 2 analog ground
  inout vccd1;        // User area 1 1.8V supply
  inout vccd2;        // User area 2 1.8v supply
  inout vssd1;        // User area 1 digital ground
  inout vssd2;        // User area 2 digital ground
`endif\
"""

header3 = """\
`ifdef USE_POWER_PINS
    .vdda1(vdda1),  // User area 1 3.3V power
    .vdda2(vdda2),  // User area 2 3.3V power
    .vssa1(vssa1),  // User area 1 analog ground
    .vssa2(vssa2),  // User area 2 analog ground
    .vccd1(vccd1),  // User area 1 1.8V power
    .vccd2(vccd2),  // User area 2 1.8V power
    .vssd1(vssd1),  // User area 1 digital ground
    .vssd2(vssd2),  // User area 2 digital ground
`endif\
"""

if len(sys.argv) < 3:
    print("Usage: insert_power.py verilog.v module1 module2..")
    sys.exit(1);

verilog_file = sys.argv[1]
modules = sys.argv[2:]

with open(sys.argv[1]) as f:
    for line in f:
        m = module_re.match(line)
        m2 = hookup_re.match(line)
        if m and m.group(1) in modules:
            module_name = m.group(1)
            module_args = m.group(2)
            print('module %s(' % module_name)
            print(header1)
            print(' %s);' % module_args)
            print(header2)
        elif m2 and m2.group(1) in modules:
            print(line, end='')
            print(header3)
        else:
            print(line, end='')
