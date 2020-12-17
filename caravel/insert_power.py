#!/usr/bin/python

import argparse
import re

module_regex = r'[a-zA-Z0-9_:\.\\]+'

# match:
# module dcache(clk, rst, d_in, m_in, wishbone_in, d_out, m_out, stall_out, wishbone_out);
# A bit of a hack - ignore anything contining a '`', and assume that means we've already
# processed this module in a previous run. This helps when having to run this script
# multiple times for different power names.
multiline_module_re = re.compile(r'module\s+(' + module_regex + r')\(([^`]*?)\);', re.DOTALL)
module_re = re.compile(r'module\s+(' + module_regex + r')\((.*?)\);')

# match:
# dcache_64_2_2_2_2_12_0 dcache_0 (
hookup_re = re.compile(r'\s+(' + module_regex + r') ' + module_regex + r'\s+\(')

header1 = """\
`ifdef USE_POWER_PINS
  {power}, {ground}, `endif\
"""

header2 = """\
`ifdef USE_POWER_PINS
  inout {power};
  inout {ground};
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
    d = f.read()
    # Remove newlines from module definitions, yosys started doing this as of
    # commit ff8e999a7112 ("Split module ports, 20 per line")
    fixed = multiline_module_re.sub(lambda m: m.group(0).replace("\n", ""), d)

    for line in fixed.splitlines():
        m = module_re.match(line)
        m2 = hookup_re.match(line)
        if m and m.group(1) in args.module:
            module_name = m.group(1)
            module_args = m.group(2)
            print('module %s(' % (module_name))
            print("")
            print(header1.format(power=args.power, ground=args.ground))
            print('  %s);' % module_args)
            print(header2.format(power=args.power, ground=args.ground))
        elif m2 and m2.group(1) in args.module:
            print(line)
            print(header3.format(parent_power=args.parent_power, parent_ground=args.parent_ground, power=args.power, ground=args.ground))
        else:
            print(line)

