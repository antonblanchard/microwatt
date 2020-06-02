#!/usr/bin/python3
from fusesoc.capi2.generator import Generator
import os
import sys
import pathlib

class LiteDRAMGenerator(Generator):
    def run(self):
        board    = self.config.get('board')

        # Collect a bunch of directory path
        script_dir = os.path.dirname(sys.argv[0])
        base_dir = os.path.join(script_dir, os.pardir)
        gen_dir = os.path.join(base_dir, "generated", board)
        extras_dir = os.path.join(base_dir, "extras")

        print("Adding LiteDRAM for board... ", board)

        # Grab init-cpu.txt if it exists
        cpu_file = os.path.join(gen_dir, "init-cpu.txt")
        if os.path.exists(cpu_file):
            cpu = pathlib.Path(cpu_file).read_text()
        else:
            cpu = None

        # Add files to fusesoc
        files = []
        f = os.path.join(gen_dir, "litedram_core.v")
        files.append({f : {'file_type' : 'verilogSource'}})
        f = os.path.join(gen_dir, "litedram-wrapper.vhdl")
        files.append({f : {'file_type' : 'vhdlSource-2008'}})
        f = os.path.join(gen_dir, "litedram-initmem.vhdl")
        files.append({f : {'file_type' : 'vhdlSource-2008'}})
        f = os.path.join(gen_dir, "litedram_core.init")
        files.append({f : {'file_type' : 'user'}})

        # Look for init CPU types and add corresponding files
        if cpu == "vexriscv":
            f = os.path.join(base_dir, "extras", "VexRiscv.v")
            files.append({f : {'file_type' : 'verilogSource'}})

        self.add_files(files)

g = LiteDRAMGenerator()
g.run()
g.write()

