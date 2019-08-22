#!/usr/bin/python3

import re
import fileinput

r = re.compile("REG ([0-9A-F]+)");

regs = list()

for line in fileinput.input():
    m = r.search(line)
    if m:
        regs.append(int(m.group(1), 16))
        #print("%016X"% int(m.group(1), 16))

print("%x" % hash(tuple(regs)))
