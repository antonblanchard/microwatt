#!/usr/bin/python3
from fusesoc.capi2.generator import Generator
import os
import sys
import pathlib

class LiteDRAMGenerator(Generator):
    def run(self):
        board = self.config.get('board')
        payload = self.config.get('payload')

        # Collect a bunch of directory path
        script_dir = os.path.dirname(sys.argv[0])
        base_dir = os.path.join(script_dir, os.pardir)
        gen_dir = os.path.join(base_dir, "generated", board)
        extras_dir = os.path.join(base_dir, "extras")

        print("Adding LiteDRAM for board... ", board)

        # Add files to fusesoc
        files = []
        f = os.path.join(gen_dir, "litedram_core.v")
        files.append({f : {'file_type' : 'verilogSource'}})
        f = os.path.join(gen_dir, "litedram-initmem.vhdl")
        files.append({f : {'file_type' : 'vhdlSource-2008'}})
        f = os.path.join(gen_dir, "litedram_core.init")
        files.append({f : {'file_type' : 'user'}})
        f = os.path.join(extras_dir, "litedram-wrapper-l2.vhdl")
        files.append({f : {'file_type' : 'vhdlSource-2008'}})

        self.add_files(files)

g = LiteDRAMGenerator()
g.run()
g.write()

