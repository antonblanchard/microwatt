#!/usr/bin/python3

import sys
import subprocess
import struct

with open(sys.argv[1], "rb") as f:
        while True:
            word = f.read(8)
            if len(word) == 8:
                print("%016x" % struct.unpack('Q', word));
            elif len(word) == 4:
                print("00000000%08x" % struct.unpack('I', word));
            elif len(word) == 0:
                exit(0);
            else:
                raise Exception("Bad length")
