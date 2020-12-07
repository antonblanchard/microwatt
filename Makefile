GHDL ?= ghdl
GHDLFLAGS=--std=08 -frelaxed
CFLAGS=-O3 -Wall

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
YOSYS     = $(DOCKERBIN) $(DOCKERARGS) hdlc/ghdl:yosys yosys
NEXTPNR   = $(DOCKERBIN) $(DOCKERARGS) hdlc/nextpnr:ecp5 nextpnr-ecp5
ECPPACK   = $(DOCKERBIN) $(DOCKERARGS) hdlc/prjtrellis ecppack
OPENOCD   = $(DOCKERBIN) $(DOCKERARGS) --device /dev/bus/usb hdlc/prog openocd
endif

all = core_tb icache_tb dcache_tb multiply_tb dmi_dtm_tb divider_tb \
	rotator_tb countzero_tb wishbone_bram_tb soc_reset_tb

all: $(all)

core_files = decode_types.vhdl common.vhdl wishbone_types.vhdl fetch1.vhdl \
	utils.vhdl plru.vhdl cache_ram.vhdl icache.vhdl \
	decode1.vhdl helpers.vhdl insn_helpers.vhdl gpr_hazard.vhdl \
	cr_hazard.vhdl control.vhdl decode2.vhdl register_file.vhdl \
	cr_file.vhdl crhelpers.vhdl ppc_fx_insns.vhdl rotator.vhdl \
	logical.vhdl countzero.vhdl multiply.vhdl divider.vhdl execute1.vhdl \
	loadstore1.vhdl mmu.vhdl dcache.vhdl writeback.vhdl core_debug.vhdl \
	core.vhdl fpu.vhdl

soc_files = $(core_files) wishbone_arbiter.vhdl wishbone_bram_wrapper.vhdl sync_fifo.vhdl \
	wishbone_debug_master.vhdl xics.vhdl syscon.vhdl soc.vhdl \
	spi_rxtx.vhdl spi_flash_ctrl.vhdl

uart_files = $(wildcard uart16550/*.v)

soc_sim_files = $(soc_files) sim_console.vhdl sim_pp_uart.vhdl sim_bram_helpers.vhdl \
	sim_bram.vhdl sim_jtag_socket.vhdl sim_jtag.vhdl dmi_dtm_xilinx.vhdl \
	sim_16550_uart.vhdl \
	random.vhdl glibc_random.vhdl glibc_random_helpers.vhdl

soc_sim_c_files = sim_vhpi_c.c sim_bram_helpers_c.c sim_console_c.c \
	sim_jtag_socket_c.c

soc_sim_obj_files=$(soc_sim_c_files:.c=.o)
comma := ,
soc_sim_link=$(patsubst %,-Wl$(comma)%,$(soc_sim_obj_files))

unisim_dir = sim-unisim
unisim_lib = $(unisim_dir)/unisim-obj08.cf
unisim_lib_files = $(unisim_dir)/BSCANE2.vhdl $(unisim_dir)/BUFG.vhdl \
	$(unisim_dir)/unisim_vcomponents.vhdl
$(unisim_lib): $(unisim_lib_files)
	$(GHDL) -i --std=08 --work=unisim --workdir=$(unisim_dir) $^
GHDLFLAGS += -P$(unisim_dir)

core_tbs = multiply_tb divider_tb rotator_tb countzero_tb
soc_tbs = core_tb icache_tb dcache_tb dmi_dtm_tb wishbone_bram_tb
soc_flash_tbs = core_flash_tb
soc_dram_tbs = dram_tb core_dram_tb

ifneq ($(FLASH_MODEL_PATH),)
fmf_dir = $(FLASH_MODEL_PATH)/fmf
fmf_lib = $(fmf_dir)/fmf-obj08.cf
fmf_lib_files = $(wildcard $(fmf_dir)/*.vhd)
GHDLFLAGS += -P$(fmf_dir)
$(fmf_lib): $(fmf_lib_files)
	$(GHDL) -i --std=08 --work=fmf --workdir=$(fmf_dir) $^

flash_model_files=$(FLASH_MODEL_PATH)/s25fl128s.vhd
flash_model_files: $(fmf_lib)
else
flash_model_files=sim_no_flash.vhdl
fmf_lib=
endif

$(soc_flash_tbs): %: $(soc_sim_files) $(soc_sim_obj_files) $(unisim_lib) $(fmf_lib) $(flash_model_files) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(soc_sim_link) $(soc_sim_files) $(flash_model_files) $@.vhdl $(unisim_files) -e $@

$(soc_tbs): %: $(soc_sim_files) $(soc_sim_obj_files) $(unisim_lib) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(soc_sim_link) $(soc_sim_files) $@.vhdl -e $@

$(core_tbs): %: $(core_files) glibc_random.vhdl glibc_random_helpers.vhdl %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(core_files) glibc_random.vhdl glibc_random_helpers.vhdl $@.vhdl -e $@

soc_reset_tb: fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl
	$(GHDL) -c $(GHDLFLAGS) fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl -e $@

# LiteDRAM sim
VERILATOR_ROOT=$(shell verilator -getenv VERILATOR_ROOT 2>/dev/null)
ifeq (, $(VERILATOR_ROOT))
$(soc_dram_tbs):
	$(error "Verilator is required to make this target !")
else

VERILATOR_CFLAGS=-O3
VERILATOR_FLAGS=-O3
verilated_dram: litedram/generated/sim/litedram_core.v
	verilator $(VERILATOR_FLAGS) -CFLAGS $(VERILATOR_CFLAGS) -Wno-fatal --cc $< --trace
	make -C obj_dir -f ../litedram/extras/sim_dram_verilate.mk VERILATOR_ROOT=$(VERILATOR_ROOT)

SIM_DRAM_CFLAGS  = -I. -Iobj_dir -Ilitedram/generated/sim -I$(VERILATOR_ROOT)/include -I$(VERILATOR_ROOT)/include/vltstd
SIM_DRAM_CFLAGS += -DVM_COVERAGE=0 -DVM_SC=0 -DVM_TRACE=1 -DVL_PRINTF=printf -faligned-new
sim_litedram_c.o: litedram/extras/sim_litedram_c.cpp verilated_dram
	$(CC)  $(CPPFLAGS) $(SIM_DRAM_CFLAGS) $(CFLAGS) -c $< -o $@

soc_dram_files = $(soc_files) litedram/extras/litedram-wrapper-l2.vhdl litedram/generated/sim/litedram-initmem.vhdl
soc_dram_sim_files = $(soc_sim_files) litedram/extras/sim_litedram.vhdl
soc_dram_sim_obj_files = $(soc_sim_obj_files) sim_litedram_c.o
dram_link_files=-Wl,obj_dir/Vlitedram_core__ALL.a -Wl,obj_dir/verilated.o -Wl,obj_dir/verilated_vcd_c.o -Wl,-lstdc++
soc_dram_sim_link=$(patsubst %,-Wl$(comma)%,$(soc_dram_sim_obj_files)) $(dram_link_files)

$(soc_dram_tbs): %: $(soc_dram_files) $(soc_dram_sim_files) $(soc_dram_sim_obj_files) $(flash_model_files) $(unisim_lib) $(fmf_lib) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(soc_dram_sim_link) $(soc_dram_files) $(soc_dram_sim_files) $(flash_model_files) $@.vhdl -e $@
endif

# Hello world
MEMORY_SIZE=8192
RAM_INIT_FILE=hello_world/hello_world.hex

# Micropython
#MEMORY_SIZE=393216
#RAM_INIT_FILE=micropython/firmware.hex

FPGA_TARGET ?= ORANGE-CRAB

# OrangeCrab with ECP85
ifeq ($(FPGA_TARGET), ORANGE-CRAB)
RESET_LOW=true
CLK_INPUT=50000000
CLK_FREQUENCY=40000000
LPF=constraints/orange-crab.lpf
PACKAGE=CSFBGA285
NEXTPNR_FLAGS=--um5g-85k --freq 40
OPENOCD_JTAG_CONFIG=openocd/olimex-arm-usb-tiny-h.cfg
OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg
endif

# ECP5-EVN
ifeq ($(FPGA_TARGET), ECP5-EVN)
RESET_LOW=true
CLK_INPUT=12000000
CLK_FREQUENCY=40000000
LPF=constraints/ecp5-evn.lpf
PACKAGE=CABGA381
NEXTPNR_FLAGS=--um5g-85k --freq 40
OPENOCD_JTAG_CONFIG=openocd/ecp5-evn.cfg
OPENOCD_DEVICE_CONFIG=openocd/LFE5UM5G-85F.cfg
endif

GHDL_IMAGE_GENERICS=-gMEMORY_SIZE=$(MEMORY_SIZE) -gRAM_INIT_FILE=$(RAM_INIT_FILE) \
	-gRESET_LOW=$(RESET_LOW) -gCLK_INPUT=$(CLK_INPUT) -gCLK_FREQUENCY=$(CLK_FREQUENCY)

clkgen=fpga/clk_gen_ecp5.vhd
toplevel=fpga/top-generic.vhdl
dmi_dtm=dmi_dtm_dummy.vhdl

ifeq ($(FPGA_TARGET), verilator)
RESET_LOW=true
CLK_INPUT=50000000
CLK_FREQUENCY=50000000
clkgen=fpga/clk_gen_bypass.vhd
endif

fpga_files = $(core_files) $(soc_files) fpga/soc_reset.vhdl \
	fpga/pp_fifo.vhd fpga/pp_soc_uart.vhd fpga/main_bram.vhdl \
	nonrandom.vhdl

synth_files = $(core_files) $(soc_files) $(fpga_files) $(clkgen) $(toplevel) $(dmi_dtm)

microwatt.json: $(synth_files) $(RAM_INIT_FILE)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 --no-formal $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(synth_files) -e toplevel; synth_ecp5 -json $@  $(SYNTH_ECP5_FLAGS)" $(uart_files)

microwatt.v: $(synth_files) $(RAM_INIT_FILE)
	$(YOSYS) -m $(GHDLSYNTH) -p "ghdl --std=08 --no-formal $(GHDL_IMAGE_GENERICS) $(GHDL_TARGET_GENERICS) $(synth_files) -e toplevel; write_verilog $@"

# Need to investigate why yosys is hitting verilator warnings, and eventually turn on -Wall
microwatt-verilator: microwatt.v verilator/microwatt-verilator.cpp verilator/uart-verilator.c
	verilator -O3 -CFLAGS "-DCLK_FREQUENCY=$(CLK_FREQUENCY)" --assert --cc microwatt.v --exe verilator/microwatt-verilator.cpp verilator/uart-verilator.c -o $@ -Iuart16550 -Wno-fatal -Wno-CASEOVERLAP -Wno-UNOPTFLAT #--trace
	make -C obj_dir -f Vmicrowatt.mk
	@cp -f obj_dir/microwatt-verilator microwatt-verilator

microwatt_out.config: microwatt.json $(LPF)
	$(NEXTPNR) --json $< --lpf $(LPF) --textcfg $@.tmp $(NEXTPNR_FLAGS) --package $(PACKAGE)
	mv -f $@.tmp $@

microwatt.bit: microwatt_out.config
	$(ECPPACK) --svf microwatt.svf $< $@

microwatt.svf: microwatt.bit

prog: microwatt.svf
	$(OPENOCD) -f $(OPENOCD_JTAG_CONFIG) -f $(OPENOCD_DEVICE_CONFIG) -c "transport select jtag; init; svf $<; exit"

tests = $(sort $(patsubst tests/%.out,%,$(wildcard tests/*.out)))
tests_console = $(sort $(patsubst tests/%.console_out,%,$(wildcard tests/*.console_out)))

tests_console: $(tests_console)

check: $(tests) tests_console test_micropython test_micropython_long tests_unit

check_light: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 test_micropython test_micropython_long tests_console tests_unit

$(tests): core_tb
	@./scripts/run_test.sh $@

$(tests_console): core_tb
	@./scripts/run_test_console.sh $@

test_micropython: core_tb
	@./scripts/test_micropython.py

test_micropython_long: core_tb
	@./scripts/test_micropython_long.py

tests_core_tb = $(patsubst %_tb,%_tb_test,$(core_tbs))
tests_soc_tb = $(patsubst %_tb,%_tb_test,$(soc_tbs))

%_test: %
	./$< --assert-level=error > /dev/null

tests_core: $(tests_core_tb)

tests_soc: $(tests_soc_tb)

# FIXME SOC tests have bit rotted, so disable for now
#tests_unit: tests_core tests_soc
tests_unit: tests_core

TAGS:
	find . -name '*.vhdl' | xargs ./scripts/vhdltags

.PHONY: TAGS

_clean:
	rm -f *.o *.cf $(all)
	rm -f fpga/*.o fpga/*.cf
	rm -f sim-unisim/*.o sim-unisim/*.cf
	rm -f litedram/extras/*.o
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
