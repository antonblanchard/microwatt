GHDL ?= ghdl
GHDLFLAGS=--std=08 --work=unisim
CFLAGS=-O2 -Wall

GHDLSYNTH ?= ghdl.so
YOSYS     ?= yosys
NEXTPNR   ?= nextpnr-ecp5
ECPPACK   ?= ecppack
OPENOCD   ?= openocd

# We need a version of GHDL built with either the LLVM or gcc backend.
# Fedora provides this, but other distros may not. Another option is to use
# the Docker image.
DOCKER ?= 0
PODMAN ?= 0

ifeq ($(DOCKER), 1)
DOCKERBIN=docker
USE_DOCKER=1
endif

ifeq ($(PODMAN), 1)
DOCKERBIN=podman
USE_DOCKER=1
endif

ifeq ($(USE_DOCKER), 1)
PWD = $(shell pwd)
DOCKERARGS = run --rm -v $(PWD):/src:z -w /src
GHDL      = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 ghdl
CC        = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 gcc
GHDLSYNTH = ghdl
YOSYS     = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:beta yosys
NEXTPNR   = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:nextpnr-ecp5 nextpnr-ecp5
ECPPACK   = $(DOCKERBIN) $(DOCKERARGS) ghdl/synth:trellis ecppack
OPENOCD   = $(DOCKERBIN) $(DOCKERARGS) --device /dev/bus/usb ghdl/synth:prog openocd
endif

all = core_tb icache_tb dcache_tb multiply_tb dmi_dtm_tb divider_tb \
	rotator_tb countzero_tb wishbone_bram_tb soc_reset_tb

all: $(all)

CORE_FILES=decode_types.vhdl common.vhdl wishbone_types.vhdl fetch1.vhdl
CORE_FILES+=fetch2.vhdl utils.vhdl plru.vhdl cache_ram.vhdl icache.vhdl
CORE_FILES+=decode1.vhdl helpers.vhdl insn_helpers.vhdl gpr_hazard.vhdl
CORE_FILES+=cr_hazard.vhdl control.vhdl decode2.vhdl register_file.vhdl
CORE_FILES+=cr_file.vhdl crhelpers.vhdl ppc_fx_insns.vhdl rotator.vhdl
CORE_FILES+=logical.vhdl countzero.vhdl multiply.vhdl divider.vhdl
CORE_FILES+=execute1.vhdl loadstore1.vhdl mmu.vhdl dcache.vhdl
CORE_FILES+=writeback.vhdl core_debug.vhdl core.vhdl

SOC_FILES=wishbone_arbiter.vhdl wishbone_bram_wrapper.vhdl
SOC_FILES+=wishbone_debug_master.vhdl xics.vhdl syscon.vhdl soc.vhdl

SOC_SIM_FILES=sim_console.vhdl sim_uart.vhdl sim_bram_helpers.vhdl
SOC_SIM_FILES+=sim_bram.vhdl sim_jtag_socket.vhdl sim_jtag.vhdl
SOC_SIM_FILES+=sim-unisim/BUFG.vhdl sim-unisim/unisim_vcomponents.vhdl
SOC_SIM_FILES+=dmi_dtm_xilinx.vhdl

SOC_SIM_C_FILES=sim_vhpi_c.o sim_bram_helpers_c.o sim_console_c.o
SOC_SIM_C_FILES+=sim_jtag_socket_c.o
SOC_SIM_OBJ_FILES=$(SOC_SIM_C_FILES:.c=.o)
comma := ,
SOC_SIM_LINK=$(patsubst %,-Wl$(comma)%,$(SOC_SIM_OBJ_FILES))

CORE_TBS=multiply_tb divider_tb rotator_tb countzero_tb
SOC_TBS=core_tb icache_tb dcache_tb dmi_dtm_tb wishbone_bram_tb

$(SOC_TBS): %: $(CORE_FILES) $(SOC_FILES) $(SOC_SIM_FILES) $(SOC_SIM_OBJ_FILES) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(SOC_SIM_LINK) $(CORE_FILES) $(SOC_FILES) $(SOC_SIM_FILES) $@.vhdl -e $@

$(CORE_TBS): %: $(CORE_FILES) glibc_random.vhdl glibc_random_helpers.vhdl %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(CORE_FILES) glibc_random.vhdl glibc_random_helpers.vhdl $@.vhdl -e $@

soc_reset_tb: fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl
	$(GHDL) -c $(GHDLFLAGS) fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl -e $@

# Hello world
GHDL_IMAGE_GENERICS=-gMEMORY_SIZE=8192 -gRAM_INIT_FILE=hello_world/hello_world.hex

# Micropython
#GHDL_IMAGE_GENERICS=-gMEMORY_SIZE=393216 -gRAM_INIT_FILE=micropython/firmware.hex

# OrangeCrab with ECP85
GHDL_TARGET_GENERICS=-gRESET_LOW=true -gCLK_INPUT=50000000 -gCLK_FREQUENCY=50000000
LPF=constraints/orange-crab.lpf
PACKAGE=CSFBGA285
NEXTPNR_FLAGS=--um5g-85k --freq 50
OPENOCD_JTAG_CONFIG=openocd/olimex-arm-usb-tiny-h.cfg
OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg

# ECP5-EVN
#GHDL_TARGET_GENERICS=-gRESET_LOW=true -gCLK_INPUT=12000000 -gCLK_FREQUENCY=12000000
#LPF=constraints/ecp5-evn.lpf
#PACKAGE=CABGA381
#NEXTPNR_FLAGS=--um5g-85k --freq 12
#OPENOCD_JTAG_CONFIG=openocd/ecp5-evn.cfg
#OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg

CLKGEN=fpga/clk_gen_bypass.vhd
TOPLEVEL=fpga/top-generic.vhdl
DMI_DTM=dmi_dtm_dummy.vhdl

FPGA_FILES  = $(CORE_FILES) $(SOC_FILES)
FPGA_FILES += fpga/soc_reset.vhdl fpga/pp_fifo.vhd fpga/pp_soc_uart.vhd
FPGA_FILES += fpga/main_bram.vhdl

SYNTH_FILES = $(CORE_FILES) $(SOC_FILES) $(FPGA_FILES) $(CLKGEN) $(TOPLEVEL) $(DMI_DTM)

microwatt.json: $(SYNTH_FILES)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(SYNTH_FILES) -e toplevel; synth_ecp5 -json $@"

microwatt.v: $(SYNTH_FILES)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(SYNTH_FILES) -e toplevel; write_verilog $@"

# Need to investigate why yosys is hitting verilator warnings, and eventually turn on -Wall
microwatt-verilator: microwatt.v verilator/microwatt-verilator.cpp verilator/uart-verilator.c
	verilator -O3 --assert --cc microwatt.v --exe verilator/microwatt-verilator.cpp verilator/uart-verilator.c -o $@ -Wno-CASEOVERLAP -Wno-UNOPTFLAT #--trace
	make -C obj_dir -f Vmicrowatt.mk
	@cp -f obj_dir/microwatt-verilator microwatt-verilator

microwatt_out.config: microwatt.json $(LPF)
	$(NEXTPNR) --json $< --lpf $(LPF) --textcfg $@ $(NEXTPNR_FLAGS) --package $(PACKAGE)

microwatt.bit: microwatt_out.config
	$(ECPPACK) --svf microwatt.svf $< $@

microwatt.svf: microwatt.bit

prog: microwatt.svf
	$(OPENOCD) -f $(OPENOCD_JTAG_CONFIG) -f $(OPENOCD_DEVICE_CONFIG) -c "transport select jtag; init; svf $<; exit"

tests = $(sort $(patsubst tests/%.out,%,$(wildcard tests/*.out)))
tests_console = $(sort $(patsubst tests/%.console_out,%,$(wildcard tests/*.console_out)))

check: $(tests) $(tests_console) test_micropython test_micropython_long

check_light: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 test_micropython test_micropython_long $(tests_console)

$(tests): core_tb
	@./scripts/run_test.sh $@

$(tests_console): core_tb
	@./scripts/run_test_console.sh $@

test_micropython: core_tb
	@./scripts/test_micropython.py

test_micropython_long: core_tb
	@./scripts/test_micropython_long.py

TAGS:
	find . -name '*.vhdl' | xargs ./scripts/vhdltags

.PHONY: TAGS

_clean:
	rm -f *.o work-*cf unisim-*cf $(all)
	rm -f fpga/*.o fpga/work-*cf
	rm -f sim-unisim/*.o sim-unisim/unisim-*cf
	rm -f TAGS
	rm -f scripts/mw_debug/*.o
	rm -f scripts/mw_debug/mw_debug
	rm -f microwatt.bin microwatt.json microwatt.svf microwatt_out.config
	rm -f microwatt.v microwatt-verilator
	rm -rf obj_dir/

clean: _clean
	make -f scripts/mw_debug/Makefile clean
	make -f hello_world/Makefile clean

distclean: _clean
	rm -f *~ fpga/*~ lib/*~ console/*~ include/*~
	rm -rf litedram/build
	rm -f litedram/extras/*~
	rm -f litedram/gen-src/*~
	rm -f litedram/gen-src/sdram_init/*~
	make -f scripts/mw_debug/Makefile distclean
	make -f hello_world/Makefile distclean

.PHONY: all prog check check_light clean distclean
.PRECIOUS: microwatt.json microwatt_out.config microwatt.bit
