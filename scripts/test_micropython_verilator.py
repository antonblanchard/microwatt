#!/usr/bin/python3

import os
import subprocess
from pexpect import fdpexpect
import sys
import signal

cmd = [ './microwatt-verilator' ]

devNull = open(os.devnull, 'w')
p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
        stdin=subprocess.PIPE, stderr=devNull)

exp = fdpexpect.fdspawn(p.stdout)
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
