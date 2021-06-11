from pathlib import Path
from vunit import VUnit
from glob import glob

prj = VUnit.from_argv()
prj.add_osvvm()
root = Path(__file__).parent

lib = prj.add_library("lib")
lib.add_source_files(root / "litedram" / "extras" / "*.vhdl")
lib.add_source_files(root / "litedram" / "generated" / "sim" / "*.vhdl")

# Use multiply.vhd and not xilinx-mult.vhd. Use VHDL-based random.
vhdl_files = glob(str(root / "*.vhdl"))
vhdl_files = [
    src_file
    for src_file in vhdl_files
    if ("xilinx-mult" not in src_file)
    and ("foreign_random" not in src_file)
    and ("nonrandom" not in src_file)
]
lib.add_source_files(vhdl_files)

unisim = prj.add_library("unisim")
unisim.add_source_files(root / "sim-unisim" / "*.vhdl")

multiply_tb = lib.test_bench("multiply_tb")
for pipeline_depth in [1, 4]:
    multiply_tb.add_config(
        name=f"pipeline_depth={pipeline_depth}",
        generics=dict(pipeline_depth=pipeline_depth),
    )

prj.set_sim_option("disable_ieee_warnings", True)

prj.main()
