#!/usr/bin/python3

import sys
import subprocess
import struct

even = open('even.hex', 'w')
odd = open('odd.hex', 'w')

with open(sys.argv[1], "rb") as f:
        while True:
            even_word = f.read(4)
            if len(even_word) == 0:
                exit(0)
            if len(even_word) != 4:
                raise Exception("Bad length")
            even.write("%08x\n" % struct.unpack('<I', even_word));

            odd_word = f.read(4)
            if len(odd_word) == 0:
                exit(0)
            if len(odd_word) != 4:
                raise Exception("Bad length")
            odd.write("%08x\n" % struct.unpack('<I', odd_word));
