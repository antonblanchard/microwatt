from pathlib import Path
from vunit import VUnit

ROOT = Path(__file__).parent

PRJ = VUnit.from_argv()
PRJ.add_osvvm()

PRJ.add_library("lib").add_source_files([
    ROOT / "litedram" / "extras" / "*.vhdl",
    ROOT / "litedram" / "generated" / "sim" / "*.vhdl"
] + [
    src_file
    for src_file in ROOT.glob("*.vhdl")
    # Use multiply.vhd and not xilinx-mult.vhd. Use VHDL-based random.
    if not any(exclude in str(src_file) for exclude in ["xilinx-mult", "foreign_random", "nonrandom"])
])

PRJ.add_library("unisim").add_source_files(ROOT / "sim-unisim" / "*.vhdl")

PRJ.set_sim_option("disable_ieee_warnings", True)

PRJ.main()
