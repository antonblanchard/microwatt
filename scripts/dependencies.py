#!/usr/bin/python3

# Create makefile dependencies for VHDL files, looking for "use work" and
# "entity work" declarations

import sys
import re

work = re.compile('use work\.([^.]+)\.')
entity = re.compile('entity work\.(.*)')

for filename in sys.argv[1:]:
    with open(filename, 'r') as f:
        (basename, suffix) = filename.split('.')
        print('%s.o:' % basename, end='')

        for line in f:
            m = work.search(line)
            if m:
                print(' %s.o' % m.group(1), end='')

            m = entity.search(line)
            if m:
                print(' %s.o' % m.group(1), end='')
    print()
