#!/usr/bin/python3

import tempfile
import os
from shutil import copyfile
import subprocess
from pexpect import fdpexpect
import sys
import signal

tempdir = tempfile.TemporaryDirectory()
cwd = os.getcwd()
os.chdir(tempdir.name)

copyfile(os.path.join(cwd, 'micropython/firmware.bin'),
        os.path.join(tempdir.name, 'main_ram.bin'))

cmd = [ os.path.join(cwd, './core_tb') ]

devNull = open(os.devnull, 'w')
p = subprocess.Popen(cmd, stdout=devNull,
        stdin=subprocess.PIPE, stderr=subprocess.PIPE)

exp = fdpexpect.fdspawn(p.stderr)
exp.logfile = sys.stdout.buffer

exp.expect('Type "help\(\)" for more information.')
exp.expect('>>>')

p.stdin.write(b'n2=0\r\n')
p.stdin.write(b'n1=1\r\n')
p.stdin.write(b'for i in range(5):\r\n')
p.stdin.write(b'    n0 = n1 + n2\r\n')
p.stdin.write(b'    print(n0)\r\n')
p.stdin.write(b'    n2 = n1\r\n')
p.stdin.write(b'    n1 = n0\r\n')
p.stdin.write(b'\r\n')
p.stdin.flush()

exp.expect('n1 = n0', timeout=600)
exp.expect('1', timeout=600)
exp.expect('2', timeout=600)
exp.expect('3', timeout=600)
exp.expect('5', timeout=600)
exp.expect('8', timeout=600)
exp.expect('>>>', timeout=600)

os.kill(p.pid, signal.SIGKILL)
