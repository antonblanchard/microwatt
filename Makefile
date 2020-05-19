GHDL=ghdl
GHDLFLAGS=--std=08 -Psim-unisim
CFLAGS=-O2 -Wall

# We need a version of GHDL built with either the LLVM or gcc backend.
# Fedora provides this, but other distros may not. Another option, although
# rather slow, is to use the Docker image.
#
# Uncomment one of these to build with Docker or podman
#DOCKER=docker
#DOCKER=podman
#
# Uncomment these lines to build with Docker/podman
#PWD = $(shell pwd)
#DOCKERARGS = run --rm -v $(PWD):/src:z -w /src
#GHDL = $(DOCKER) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 ghdl
#CC = $(DOCKER) $(DOCKERARGS) ghdl/ghdl:buster-llvm-7 gcc

all = core_tb soc_reset_tb icache_tb dcache_tb multiply_tb dmi_dtm_tb divider_tb \
	rotator_tb countzero_tb wishbone_bram_tb

# XXX
# loadstore_tb fetch_tb

all: $(all)

%.o : %.vhdl
	$(GHDL) -a $(GHDLFLAGS) --workdir=$(shell dirname $@) $<

common.o: decode_types.o
control.o: gpr_hazard.o cr_hazard.o common.o
sim_jtag.o: sim_jtag_socket.o
core_tb.o: common.o wishbone_types.o core.o soc.o sim_jtag.o
core.o: common.o wishbone_types.o fetch1.o fetch2.o icache.o decode1.o decode2.o register_file.o cr_file.o execute1.o loadstore1.o mmu.o dcache.o writeback.o core_debug.o
core_debug.o: common.o
countzero.o:
countzero_tb.o: common.o glibc_random.o countzero.o
cr_file.o: common.o
crhelpers.o: common.o
decode1.o: common.o decode_types.o
decode2.o: decode_types.o common.o helpers.o insn_helpers.o control.o
decode_types.o:
execute1.o: decode_types.o common.o helpers.o crhelpers.o insn_helpers.o ppc_fx_insns.o rotator.o logical.o countzero.o multiply.o divider.o
fetch1.o: common.o
fetch2.o: common.o wishbone_types.o
glibc_random_helpers.o:
glibc_random.o: glibc_random_helpers.o
helpers.o:
cache_ram.o:
plru.o:
plru_tb.o: plru.o
utils.o:
sim_bram.o: sim_bram_helpers.o utils.o
wishbone_bram_wrapper.o: wishbone_types.o sim_bram.o utils.o
wishbone_bram_tb.o: wishbone_bram_wrapper.o
icache.o: utils.o common.o wishbone_types.o plru.o cache_ram.o utils.o
icache_tb.o: common.o wishbone_types.o icache.o wishbone_bram_wrapper.o
dcache.o: utils.o common.o wishbone_types.o plru.o cache_ram.o utils.o
dcache_tb.o: common.o wishbone_types.o dcache.o wishbone_bram_wrapper.o
insn_helpers.o:
loadstore1.o: common.o decode_types.o
logical.o: decode_types.o
multiply_tb.o: decode_types.o common.o glibc_random.o ppc_fx_insns.o multiply.o
multiply.o: common.o decode_types.o
mmu.o: common.o
divider_tb.o: decode_types.o common.o glibc_random.o ppc_fx_insns.o divider.o
divider.o: common.o decode_types.o
ppc_fx_insns.o: helpers.o
register_file.o: common.o
rotator.o: common.o
rotator_tb.o: common.o glibc_random.o ppc_fx_insns.o insn_helpers.o rotator.o
sim_console.o:
sim_uart.o: wishbone_types.o sim_console.o
xics.o: wishbone_types.o common.o
soc.o: common.o wishbone_types.o core.o wishbone_arbiter.o sim_uart.o wishbone_bram_wrapper.o dmi_dtm_xilinx.o wishbone_debug_master.o xics.o syscon.o
syscon.o: wishbone_types.o
wishbone_arbiter.o: wishbone_types.o
wishbone_types.o:
writeback.o: common.o crhelpers.o
dmi_dtm_tb.o: dmi_dtm_xilinx.o wishbone_debug_master.o
dmi_dtm_xilinx.o: wishbone_types.o sim-unisim/unisim_vcomponents.o
wishbone_debug_master.o: wishbone_types.o

UNISIM_BITS = sim-unisim/unisim_vcomponents.vhdl sim-unisim/BSCANE2.vhdl sim-unisim/BUFG.vhdl
sim-unisim/unisim_vcomponents.o: $(UNISIM_BITS)
	$(GHDL) -a $(GHDLFLAGS) --work=unisim --workdir=sim-unisim $^


fpga/soc_reset_tb.o: fpga/soc_reset.o

soc_reset_tb: fpga/soc_reset_tb.o fpga/soc_reset.o
	$(GHDL) -e $(GHDLFLAGS) --workdir=fpga soc_reset_tb

core_tb: core_tb.o sim_vhpi_c.o sim_bram_helpers_c.o sim_console_c.o sim_jtag_socket_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,sim_vhpi_c.o -Wl,sim_bram_helpers_c.o -Wl,sim_console_c.o -Wl,sim_jtag_socket_c.o $@

fetch_tb: fetch_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

icache_tb: icache_tb.o sim_vhpi_c.o sim_bram_helpers_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,sim_vhpi_c.o -Wl,sim_bram_helpers_c.o $@

dcache_tb: dcache_tb.o sim_vhpi_c.o sim_bram_helpers_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,sim_vhpi_c.o -Wl,sim_bram_helpers_c.o $@

plru_tb: plru_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

loadstore_tb: loadstore_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

multiply_tb: multiply_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

divider_tb: divider_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

rotator_tb: rotator_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

countzero_tb: countzero_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

simple_ram_tb: simple_ram_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

wishbone_bram_tb: sim_vhpi_c.o sim_bram_helpers_c.o wishbone_bram_tb.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,sim_vhpi_c.o -Wl,sim_bram_helpers_c.o $@

dmi_dtm_tb: dmi_dtm_tb.o sim_vhpi_c.o sim_bram_helpers_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,sim_vhpi_c.o -Wl,sim_bram_helpers_c.o $@

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
