GHDL=ghdl
GHDLFLAGS=--std=08 -Psim-unisim
CFLAGS=-O2 -Wall

all = core_tb simple_ram_behavioural_tb soc_reset_tb icache_tb multiply_tb dmi_dtm_tb divider_tb

# XXX
# loadstore_tb fetch_tb

all: $(all)

%.o : %.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

common.o: decode_types.o
sim_jtag.o: sim_jtag_socket.o
core_tb.o: common.o wishbone_types.o core.o soc.o sim_jtag.o
core.o: common.o wishbone_types.o fetch1.o fetch2.o icache.o decode1.o decode2.o register_file.o cr_file.o execute1.o execute2.o loadstore1.o loadstore2.o multiply.o writeback.o core_debug.o divider.o
core_debug.o: common.o
cr_file.o: common.o
crhelpers.o: common.o
decode1.o: common.o decode_types.o
decode2.o: decode_types.o common.o helpers.o insn_helpers.o
decode_types.o:
execute1.o: decode_types.o common.o helpers.o crhelpers.o ppc_fx_insns.o
execute2.o: common.o crhelpers.o ppc_fx_insns.o
fetch1.o: common.o
fetch2.o: common.o wishbone_types.o
glibc_random_helpers.o:
glibc_random.o: glibc_random_helpers.o
helpers.o:
icache.o: common.o wishbone_types.o
icache_tb.o: common.o wishbone_types.o icache.o simple_ram_behavioural.o
insn_helpers.o:
loadstore1.o: common.o helpers.o
loadstore2.o: common.o helpers.o wishbone_types.o
multiply_tb.o: decode_types.o common.o glibc_random.o ppc_fx_insns.o multiply.o
multiply.o: common.o decode_types.o ppc_fx_insns.o crhelpers.o
divider_tb.o: decode_types.o common.o glibc_random.o ppc_fx_insns.o divider.o
divider.o: common.o decode_types.o crhelpers.o
ppc_fx_insns.o: helpers.o
register_file.o: common.o
sim_console.o:
simple_ram_behavioural_helpers.o:
simple_ram_behavioural_tb.o: wishbone_types.o simple_ram_behavioural.o
simple_ram_behavioural.o: wishbone_types.o simple_ram_behavioural_helpers.o
sim_uart.o: wishbone_types.o sim_console.o
soc.o: common.o wishbone_types.o core.o wishbone_arbiter.o sim_uart.o simple_ram_behavioural.o dmi_dtm_xilinx.o wishbone_debug_master.o
wishbone_arbiter.o: wishbone_types.o
wishbone_types.o:
writeback.o: common.o
dmi_dtm_tb.o: dmi_dtm_xilinx.o wishbone_debug_master.o
dmi_dtm_xilinx.o: wishbone_types.o sim-unisim/unisim_vcomponents.o
wishbone_debug_master.o: wishbone_types.o

UNISIM_BITS = sim-unisim/unisim_vcomponents.vhdl sim-unisim/BSCANE2.vhdl sim-unisim/BUFG.vhdl
sim-unisim/unisim_vcomponents.o: $(UNISIM_BITS)
	$(GHDL) -a $(GHDLFLAGS) --work=unisim --workdir=sim-unisim $^


fpga/soc_reset_tb.o: fpga/soc_reset.o

soc_reset_tb: fpga/soc_reset_tb.o fpga/soc_reset.o
	$(GHDL) -e $(GHDLFLAGS) soc_reset_tb

core_tb: core_tb.o simple_ram_behavioural_helpers_c.o sim_console_c.o sim_jtag_socket_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o -Wl,sim_console_c.o -Wl,sim_jtag_socket_c.o $@

fetch_tb: fetch_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

icache_tb: icache_tb.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o $@

loadstore_tb: loadstore_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

multiply_tb: multiply_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

divider_tb: divider_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

simple_ram_tb: simple_ram_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

simple_ram_behavioural_tb: simple_ram_behavioural_helpers_c.o simple_ram_behavioural_tb.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o $@

dmi_dtm_tb: dmi_dtm_tb.o simple_ram_behavioural_helpers_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o $@

tests = $(sort $(patsubst tests/%.out,%,$(wildcard tests/*.out)))

check: $(tests) test_micropython test_micropython_long

check_light: 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 test_micropython test_micropython_long 

$(tests): core_tb
	@./scripts/run_test.sh $@

test_micropython: core_tb
	@./scripts/test_micropython.py

test_micropython_long: core_tb
	@./scripts/test_micropython_long.py

clean:
	rm -f *.o work-*cf unisim-*cf $(all)
	rm -f sim-unisim/*.o sim-unisim/unisim-*cf

distclean: clean
	rm -f *~ fpga/~
