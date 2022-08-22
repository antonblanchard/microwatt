#!/usr/bin/python

import argparse
import re

module_regex = r'[a-zA-Z0-9_:\.\\]+'

module_re = re.compile(r'module\s+(' + module_regex + r')')

# match:
# dcache_64_2_2_2_2_12_0 dcache_0 (
hookup_re = re.compile(r'\s+(' + module_regex + r') ' + module_regex + r'\s+\(')

header = """\
`ifdef USE_POWER_PINS
   inout {power},
   inout {ground},
`endif\
"""

header3 = """\
`ifdef USE_POWER_PINS
    .{power}({parent_power}),
    .{ground}({parent_ground}),
`endif\
"""

parser = argparse.ArgumentParser(description='Insert power and ground into verilog modules')
parser.add_argument('--power', default='VPWR', help='POWER net name (default VPWR)')
parser.add_argument('--ground', default='VGND', help='POWER net name (default VGND)')
parser.add_argument('--parent-power', default='VPWR', help='POWER net name of parent module (default VPWR)')
parser.add_argument('--parent-ground', default='VGND', help='POWER net name of parent module (default VGND)')
parser.add_argument('--verilog', required=True, help='Verilog file to modify')
parser.add_argument('--module', required=True, action='append', help='Module to replace (can be specified multiple times')

args = parser.parse_args()

with open(args.verilog, 'r') as f:
    strip_lpar = False
    for line in f:
        line = line.rstrip()

        m = module_re.match(line)
        m2 = hookup_re.match(line)
        if m and m.group(1) in args.module:
            strip_lpar = True
            print(line)
            print('(')
            print(header.format(power=args.power, ground=args.ground))
        elif m2 and m2.group(1) in args.module:
            print(line)
            print(header3.format(parent_power=args.parent_power, parent_ground=args.parent_ground, power=args.power, ground=args.ground))
        elif strip_lpar:
            print(line.replace('(', ' '))
            strip_lpar = False
        else:
            print(line)

