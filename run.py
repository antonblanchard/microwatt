#!/usr/bin/env python3

import json
from pathlib import Path
from vunit import VUnit

ROOT = Path(__file__).parent

PRJ = VUnit.from_argv()
PRJ.add_vhdl_builtins()
PRJ.add_osvvm()

PRJ.add_library("lib").add_source_files([
    ROOT / "litedram" / "extras" / "*.vhdl",
    ROOT / "litedram" / "generated" / "sim" / "*.vhdl"
] + [
    src_file
    for src_file in ROOT.glob("*.vhdl")
    # Use multiply.vhd and not xilinx-mult.vhd. Use VHDL-based random.
    if not any(exclude in str(src_file) for exclude in ["xilinx-mult", "foreign_random", "nonrandom", "dmi_dtm_ecp5", "dmi_dtm_xilinx"])
])

PRJ.add_library("unisim").add_source_files(ROOT / "sim-unisim" / "*.vhdl")

PRJ.set_sim_option("disable_ieee_warnings", True)

def _gen_vhdl_ls(vu):
    """
    Generate the vhdl_ls.toml file required by VHDL-LS language server.
    """
    # Repo root
    parent = Path(__file__).parent

    proj = vu._project
    libs = proj.get_libraries()

    with open(parent / 'vhdl_ls.toml', "w") as f:
        for lib in libs:
            f.write(f"[libraries.{lib.name}]\n")
            files = [str(file).replace('\\', '/') for file in lib._source_files]
            f.write(f"files = {json.dumps(files, indent=4)}\n")

_gen_vhdl_ls(PRJ)
PRJ.main()
