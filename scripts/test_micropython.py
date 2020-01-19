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

p.stdin.write(b'print("foo")\r\n')
p.stdin.flush()

# Catch the command echoed back to the console
exp.expect('foo', timeout=600)

# Now catch the output
exp.expect('foo', timeout=600)
exp.expect('>>>')

os.kill(p.pid, signal.SIGKILL)
