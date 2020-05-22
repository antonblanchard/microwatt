#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <poll.h>

#include "sim_vhpi_c.h"
#include "Vlitedram_core.h"
#include "verilated_vcd_c.h"

static Vlitedram_core *v;
vluint64_t main_time = 0;

#if VM_TRACE
VerilatedVcdC *tfp;
#endif

static void cleanup(void)
{
#if VM_TRACE
	if (tfp) {
		tfp->flush();
		tfp->close();
		delete tfp;
	}
#endif
}

static inline void check_init(bool traces)
{
	if (v)
		return;
	// XX Catch exceptions ?
	v = new Vlitedram_core;
	if (!v) {
		fprintf(stderr, "Failure allocating litedram core\n");
		exit(1);
	}
#if VM_TRACE
	if (traces) {
		// init trace dump
		Verilated::traceEverOn(true);
		tfp = new VerilatedVcdC;
		v->trace(tfp, 99);
		tfp->open("litedram.vcd");
	}
#endif
	atexit(cleanup);
}

unsigned char get_bit(unsigned char **p)
{
	unsigned char b = **p;

	*p = *p + 1;

	return b  == vhpi1 ? 1  : 0;
}

uint64_t get_bits(unsigned char **p, int len)
{
	uint64_t r = 0;

	while(len--)
		r = (r << 1) | get_bit(p);
	
	return r;
}

void set_bit(unsigned char **p, int bit)
{
	**p = bit ? vhpi1 : vhpi0;
	*p = *p + 1;
}

void set_bits(unsigned char **p, uint64_t val, int len)
{
	while(len--)
		set_bit(p, (val >> len) & 1);
}

double sc_time_stamp(void)
{
	return main_time;
}

#define check_size(s, exp)						\
	do {								\
		int __s = (s);						\
		int __e = (exp);					\
		if (__s != __e)						\
			fprintf(stderr, "WARNING: %s exp %d got %d\n", __func__, __e, __s); \
	} while(0)

static void do_eval(void)
{
	v->eval();
#if VM_TRACE
	if (tfp)
		tfp->dump((double) main_time);
#endif
}

extern "C" void litedram_set_wb(unsigned char *req)
{
	unsigned char *orig = req;

	check_init(false);
	
	v->wb_ctrl_cti   = get_bits(&req, 3);
	v->wb_ctrl_bte   = get_bits(&req, 2);
	v->wb_ctrl_sel   = get_bits(&req, 4);
	v->wb_ctrl_we    = get_bit(&req);
	v->wb_ctrl_stb   = get_bit(&req);
	v->wb_ctrl_cyc   = get_bit(&req);
	v->wb_ctrl_adr   = get_bits(&req, 30);
	v->wb_ctrl_dat_w = get_bits(&req, 32);

	check_size(req - orig, 74);

	do_eval();
}

extern "C" void litedram_get_wb(unsigned char *req)
{
	unsigned char *orig = req;

	check_init(false);

	set_bit(&req, v->init_error);
	set_bit(&req, v->init_done);
	set_bit(&req, v->wb_ctrl_err);
	set_bit(&req, v->wb_ctrl_ack);
	set_bits(&req, v->wb_ctrl_dat_r, 32);

	check_size(req - orig, 36);
}

extern "C" void litedram_set_user(unsigned char *req)
{
	unsigned char *orig = req;

	check_init(false);

	v->user_port_native_0_cmd_valid     = get_bit(&req);
	v->user_port_native_0_cmd_we        = get_bit(&req);
	v->user_port_native_0_wdata_valid   = get_bit(&req);
	v->user_port_native_0_rdata_ready   = get_bit(&req);
	v->user_port_native_0_cmd_addr      = get_bits(&req, 24);
	v->user_port_native_0_wdata_we      = get_bits(&req, 16);
	v->user_port_native_0_wdata_data[3] = get_bits(&req, 32);
	v->user_port_native_0_wdata_data[2] = get_bits(&req, 32);
	v->user_port_native_0_wdata_data[1] = get_bits(&req, 32);
	v->user_port_native_0_wdata_data[0] = get_bits(&req, 32);

	check_size(req - orig, 172);

	do_eval();
}

extern "C" void litedram_get_user(unsigned char *req)
{
	unsigned char *orig = req;

	check_init(false);

	set_bit(&req, v->user_port_native_0_cmd_ready);
	set_bit(&req, v->user_port_native_0_wdata_ready);
	set_bit(&req, v->user_port_native_0_rdata_valid);
	set_bits(&req, v->user_port_native_0_rdata_data[3], 32);
	set_bits(&req, v->user_port_native_0_rdata_data[2], 32);
	set_bits(&req, v->user_port_native_0_rdata_data[1], 32);
	set_bits(&req, v->user_port_native_0_rdata_data[0], 32);

	check_size(req - orig, 131);
}

extern "C" void litedram_clock(void)
{
	check_init(false);

	v->clk = 1;
	do_eval();
	main_time++;
	v->clk = 0;
	do_eval();
	main_time++;
}

extern "C" void litedram_init(int trace_on)
{
	check_init(!!trace_on);
}

	
