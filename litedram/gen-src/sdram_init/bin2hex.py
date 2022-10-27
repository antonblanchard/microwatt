#!/usr/bin/python3

import sys
import subprocess
import struct

with open(sys.argv[1], "rb") as f:
        while True:
            word = f.read(8)
            if len(word) == 0:
                exit(0);
            if len(word) != 8:
                word = word + bytes(8 - len(word))
            print("%016x" % struct.unpack('Q', word));
