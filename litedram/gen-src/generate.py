#!/usr/bin/python3

from litex.build.tools import write_to_file
from litex.build.tools import replace_in_file
from litedram.gen import *
import subprocess
import os
import shutil

def make_new_dir(base, added):
    r = os.path.join(base, added)
    if os.path.exists(r):
        shutil.rmtree(r)
    os.mkdir(r)
    return r
    
gen_src_dir = os.path.dirname(os.path.realpath(__file__))
base_dir = os.path.normpath(os.path.join(gen_src_dir, os.pardir))
build_top_dir = make_new_dir(base_dir, "build")
gen_src_dir = os.path.join(base_dir, "gen-src")
gen_dir = make_new_dir(base_dir, "generated")

# Build the init code for microwatt-initialized DRAM
def build_init_code(build_dir, is_sim):

    # More path fudging
    sw_dir = os.path.join(build_dir, "software");
    sw_inc_dir = os.path.join(sw_dir, "include")
    gen_inc_dir = os.path.join(sw_inc_dir, "generated")
    src_dir = os.path.join(gen_src_dir, "sdram_init")
    lxbios_src_dir = os.path.join(soc_directory, "software")
    print("     sw dir:", sw_dir)
    print("gen_inc_dir:", gen_inc_dir)
    print("    src dir:", src_dir)
    print(" lx src dir:", lxbios_src_dir)

    # Generate mem.h (hard wire size, it's not important)
    mem_h = "#define MAIN_RAM_BASE 0x40000000UL\n#define MAIN_RAM_SIZE 0x10000000UL\n"
    write_to_file(os.path.join(gen_inc_dir, "mem.h"), mem_h)

    # Environment
    env_vars = []
    def _makefile_escape(s):  # From LiteX
        return s.replace("\\", "\\\\")
    def add_var(k, v):
        env_vars.append("{}={}\n".format(k, _makefile_escape(v)))

    makefile = os.path.join(src_dir, "Makefile")
    cmd = ["make", "-C", build_dir, "-f", makefile]
    cmd.append("BUILD_DIR=%s" % sw_dir)
    cmd.append("SRC_DIR=%s" % src_dir)
    cmd.append("GENINC_DIR=%s" % sw_inc_dir)
    cmd.append("LXSRC_DIR=%s" % lxbios_src_dir)

    if is_sim:
        cmd.append("EXTRA_CFLAGS=%s" % "-D__SIM__")

    # Build init code
    print(" Generating init software...")
    r = subprocess.check_call(cmd)
    print("Make result:", r)

    return os.path.join(sw_dir, "obj", "sdram_init.hex")

def generate_one(t):

    print("Generating target:", t)

    # Is it a simulation ?
    is_sim = "sim" in t

    # Muck with directory path
    build_dir = make_new_dir(build_top_dir, t)
    t_dir = make_new_dir(gen_dir, t)

    cmd = ["litedram_gen", "--output-dir=%s" % build_dir]
    if is_sim:
        cmd.append("--sim")
    cmd.append("%s.yml" % t)
    subprocess.check_call(cmd)

    # Grab generated gatewar dir
    gw_dir = os.path.join(build_dir, "gateware")

    # Generate init code
    src_init_file = build_init_code(build_dir, is_sim)
    src_initram_file = os.path.join(gen_src_dir, "dram-init-mem.vhdl")

    # Copy generated files to target dir, amend them if necessary
    initfile_name = "litedram_core.init"
    core_file = os.path.join(gw_dir, "litedram_core.v")
    dst_init_file = os.path.join(t_dir, initfile_name)
    dst_initram_file = os.path.join(t_dir, "litedram-initmem.vhdl")
    shutil.copyfile(src_init_file, dst_init_file)    
    shutil.copyfile(src_initram_file, dst_initram_file)
    if is_sim:
        initfile_path = os.path.join("litedram", "generated", "sim", initfile_name)
        replace_in_file(dst_initram_file, initfile_name, initfile_path)
    shutil.copy(core_file, t_dir)

def main():

    targets = ['arty','nexys-video', 'genesys2', 'acorn-cle-215', 'wukong-v2', 'orangecrab-85-0.2', 'sim']
    for t in targets:
        generate_one(t)
    
if __name__ == "__main__":
    main()
