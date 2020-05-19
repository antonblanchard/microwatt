#include <stdlib.h>
#include "Vmicrowatt.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

/*
 * Current simulation time
 * This is a 64-bit integer to reduce wrap over issues and
 * allow modulus.  You can also use a double, if you wish.
 */
vluint64_t main_time = 0;

/*
 * Called by $time in Verilog
 * converts to double, to match
 * what SystemC does
 */
double sc_time_stamp(void)
{
	return main_time;
}

#if VM_TRACE
VerilatedVcdC *tfp;
#endif

void tick(Vmicrowatt *top)
{
	top->ext_clk = 1;
	top->eval();
#if VM_TRACE
	if (tfp)
		tfp->dump((double) main_time);
#endif
	main_time++;

	top->ext_clk = 0;
	top->eval();
#if VM_TRACE
	if (tfp)
		tfp->dump((double) main_time);
#endif
	main_time++;
}

void uart_tx(unsigned char tx);
unsigned char uart_rx(void);

int main(int argc, char **argv)
{
	Verilated::commandArgs(argc, argv);

	// init top verilog instance
	Vmicrowatt* top = new Vmicrowatt;

#if VM_TRACE
	// init trace dump
	Verilated::traceEverOn(true);
	tfp = new VerilatedVcdC;
	top->trace(tfp, 99);
	tfp->open("microwatt-verilator.vcd");
#endif

	// Reset
	top->ext_rst = 0;
	for (unsigned long i = 0; i < 5; i++)
		tick(top);
	top->ext_rst = 1;

	while(!Verilated::gotFinish()) {
		tick(top);

		uart_tx(top->uart0_txd);
		top->uart0_rxd = uart_rx();
	}

#if VM_TRACE
	tfp->close();
	delete tfp;
#endif

	delete top;
}
