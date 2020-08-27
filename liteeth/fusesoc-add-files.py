#!/usr/bin/python3
from fusesoc.capi2.generator import Generator
import os
import sys
import pathlib

class LiteEthGenerator(Generator):
    def run(self):
        board = self.config.get('board')

        # Collect a bunch of directory path
        script_dir = os.path.dirname(sys.argv[0])
        gen_dir = os.path.join(script_dir, "generated", board)

        print("Adding LiteEth for board... ", board)

        # Add files to fusesoc
        files = []
        f = os.path.join(gen_dir, "liteeth_core.v")
        files.append({f : {'file_type' : 'verilogSource'}})

        self.add_files(files)

g = LiteEthGenerator()
g.run()
g.write()

