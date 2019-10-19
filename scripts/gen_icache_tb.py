#!/usr/bin/python3

b = bytearray()
for i in range(0x100):
    b = b + i.to_bytes(4, 'little')
f = open('icache_test.bin', 'w+b')
f.write(b)
f.close()

