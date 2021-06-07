from pathlib import Path
from vunit import VUnit
from glob import glob

prj = VUnit.from_argv()
root = Path(__file__).parent

lib = prj.add_library("lib")
lib.add_source_files(root / "litedram/extras/*.vhdl")
lib.add_source_files(root / "litedram/generated/sim/*.vhdl")

# Use multiply.vhd and not xilinx-mult.vhd
vhdl_files_in_root = glob(str(root / "*.vhdl"))
vhdl_files_to_use = [src_file for src_file in vhdl_files_in_root if "xilinx-mult" not in src_file]
lib.add_source_files(vhdl_to_use)

unisim = prj.add_library("unisim")
unisim.add_source_files(root / "sim-unisim/*.vhdl")

prj.main()
