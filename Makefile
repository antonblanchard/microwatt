GHDL=ghdl
GHDLFLAGS=--std=08
CFLAGS=-O2

all = core_tb simple_ram_behavioural_tb
# XXX
# loadstore_tb fetch_tb

all: $(all)

%.o : %.vhdl
	$(GHDL) -a $(GHDLFLAGS) $<

common.o: decode_types.o
core_tb.o: common.o wishbone_types.o core.o simple_ram_behavioural.o
core.o: common.o wishbone_types.o fetch1.o fetch2.o decode1.o decode2.o register_file.o cr_file.o execute1.o execute2.o loadstore1.o loadstore2.o multiply.o writeback.o wishbone_arbiter.o
cr_file.o: common.o
crhelpers.o: common.o
decode1.o: common.o decode_types.o
decode2.o: decode_types.o common.o helpers.o
decode_types.o:
execute1.o: decode_types.o common.o helpers.o crhelpers.o ppc_fx_insns.o sim_console.o
execute2.o: common.o crhelpers.o ppc_fx_insns.o
fetch1.o: common.o
fetch2.o: common.o wishbone_types.o
fetch_tb.o: common.o wishbone_types.o fetch.o
glibc_random_helpers.o:
glibc_random.o: glibc_random_helpers.o
helpers.o:
loadstore1.o: common.o
loadstore2.o: common.o helpers.o wishbone_types.o
loadstore_tb.o: common.o simple_ram_types.o simple_ram.o loadstore1.o loadstore2.o
multiply_tb.o: common.o glibc_random.o ppc_fx_insns.o multiply.o
multiply.o: common.o decode_types.o ppc_fx_insns.o crhelpers.o
ppc_fx_insns.o: helpers.o
register_file.o: common.o
sim_console.o:
simple_ram_behavioural_helpers.o:
simple_ram_behavioural_tb.o: wishbone_types.o simple_ram_behavioural.o
simple_ram_behavioural.o: wishbone_types.o simple_ram_behavioural_helpers.o
wishbone_arbiter.o: wishbone_types.o
wishbone_types.o:
writeback.o: common.o

core_tb: core_tb.o simple_ram_behavioural_helpers_c.o sim_console_c.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o -Wl,sim_console_c.o $@

fetch_tb: fetch_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

loadstore_tb: loadstore_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

simple_ram_tb: simple_ram_tb.o
	$(GHDL) -e $(GHDLFLAGS) $@

simple_ram_behavioural_tb: simple_ram_behavioural_helpers_c.o simple_ram_behavioural_tb.o
	$(GHDL) -e $(GHDLFLAGS) -Wl,simple_ram_behavioural_helpers_c.o $@

tests = $(sort $(patsubst tests/%.out,%,$(wildcard tests/*.out)))

check: $(tests) test_micropython test_micropython_long

$(tests): core_tb
	@./scripts/run_test.sh $@

test_micropython:
	@./scripts/test_micropython.py

test_micropython_long:
	@./scripts/test_micropython_long.py

clean:
	rm -f *.o work-*cf $(all)
