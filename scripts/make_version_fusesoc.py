#!/usr/bin/env python
#
# Simple wrapper around make_version.sh that fusesoc needs
# Just pulls out the files_root from yaml so we know where to run.
#

import yaml
import sys
import os

with open(sys.argv[1], 'r') as stream:
    data = yaml.safe_load(stream)

# Run make version in source dir so we can get the git version
os.system("cd %s; scripts/make_version.sh git.vhdl" % data["files_root"])
