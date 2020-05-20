GHDL ?= ghdl
GHDLFLAGS=--std=08 --work=unisim
CFLAGS=-O2 -Wall

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
GHDL = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 ghdl
CC = $(DOCKERBIN) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 gcc
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

$(processes): %_processes: tests/%.o main.c

$(SOC_TBS): %: $(CORE_FILES) $(SOC_FILES) $(SOC_SIM_FILES) $(SOC_SIM_OBJ_FILES) %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(SOC_SIM_LINK) $(CORE_FILES) $(SOC_FILES) $(SOC_SIM_FILES) $@.vhdl -e $@

$(CORE_TBS): %: $(CORE_FILES) glibc_random.vhdl glibc_random_helpers.vhdl %.vhdl
	$(GHDL) -c $(GHDLFLAGS) $(CORE_FILES) glibc_random.vhdl glibc_random_helpers.vhdl $@.vhdl -e $@

soc_reset_tb: fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl
	$(GHDL) -c $(GHDLFLAGS) fpga/soc_reset_tb.vhdl fpga/soc_reset.vhdl -e $@

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
