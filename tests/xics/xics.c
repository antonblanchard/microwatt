#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "xics.h"

#undef DEBUG
//#define DEBUG 1

void delay(void)
{
	static volatile int i;

	for (i = 0; i < 16; ++i)
		__asm__ volatile("" : : : "memory");
}

void print_number(unsigned int i) // only for i = 0-999
{
	unsigned int j, k, m;
	bool zeros = false;

	k = 1000000000;

	for (m = 0; m < 10 ; m++) {
		j = i/k;
		if (m == 9) zeros = true;
		if (zeros || (j != 0)) {
		    putchar(48 + j);
		    zeros = true;
		}
		i = i % k;
		k = k / 10;
	}
}

#ifdef DEBUG
#define DEBUG_STR "\nDEBUG: "
void debug_print(int i)
{
	puts(DEBUG_STR);
	print_number(i);
	puts("\n");
}

#define debug_puts(a) puts(a)
#else
#define debug_puts(a)
#define debug_print(i)
#endif

#define ASSERT_FAIL "() ASSERT_FAILURE!\n "
#define assert(cond)	\
	if (!(cond))  { \
		puts(__FILE__); \
		putchar(':');	    \
		print_number(__LINE__);	\
		putchar(':');	    \
		puts(__FUNCTION__);\
		puts(ASSERT_FAIL); \
		__asm__ ("attn"); \
	}


volatile uint64_t isrs_run;

#define ISR_IPI      0x0000000000000001
#define ISR_UART     0x0000000000000002
#define ISR_SPURIOUS 0x0000000000000004

#define IPI "IPI\n"
void ipi_isr(void) {
	debug_puts(IPI);

	isrs_run |= ISR_IPI;

	icp_write8(XICS_MFRR, 0xff);
}


#define UART "UART\n"
void uart_isr(void) {
	debug_puts(UART);

	console_set_irq_en(false, false);

	isrs_run |= ISR_UART;
}

// The hardware doesn't support this but it's part of XICS so add it.
#define SPURIOUS "SPURIOUS\n"
void spurious_isr(void) {
	debug_puts(SPURIOUS);

	isrs_run |= ISR_SPURIOUS;
}

struct isr_op {
	void (*func)(void);
	int source_id;
};

struct isr_op isr_table[] = {
	{ .func = ipi_isr,  .source_id = 2 },
	{ .func = uart_isr, .source_id = 16 },
	{ .func = spurious_isr,  .source_id = 0 },
	{ .func = NULL, .source_id = 0 }
};

bool ipi_running;

#define ISR "ISR XISR="
#define PRIO " PRIO="
#define CPPR " CPPR="
void isr(void)
{
	struct isr_op *op;
	uint32_t xirr;

	assert(!ipi_running); // check we aren't reentrant
	ipi_running = true;

	xirr = icp_read32(XICS_XIRR); // read hardware irq source

#ifdef DEBUG
	puts(ISR);
	print_number(xirr & 0xff);
	puts(PRIO);
	print_number(xirr >> 24);
	puts(CPPR);
	print_number(icp_read8(XICS_XIRR_POLL));
	puts("\n");
#endif

	op = isr_table;
	while (1) {
		assert(op->func); // didn't find isr
		if (op->source_id == (xirr & 0x00ffffff)) {
		    op->func();
		    break;
		}
		op++;
	}

	icp_write32(XICS_XIRR, xirr); // EOI

	ipi_running = false;
}

/*****************************************/

int xics_test_0(void)
{
	uint32_t v0, v1;

	v0 = ics_read_xive(0);
	v1 = ics_read_xive(1);
#ifdef DEBUG
	puts("\n");
	puts("xive(0) bfr: ");
	print_number(v0);
	puts("\n");
	puts("xive(1) bfr: ");
	print_number(v1);
	puts("\n");
#endif
	assert(v0 = 0xff);
	assert(v1 = 0xff);

	ics_write_xive(0xa, 0);
	ics_write_xive(0x5, 1);
	v0 = ics_read_xive(0);
	v1 = ics_read_xive(1);
#ifdef DEBUG
	puts("\n");
	puts("xive(0) aft: ");
	print_number(v0);
	puts("\n");
	puts("xive(1) aft: ");
	print_number(v1);
	puts("\n");
#endif
	assert(v0 = 0xa);
	assert(v1 = 0x5);

	ics_write_xive(0xff, 0);
	ics_write_xive(0xff, 1);
	v0 = ics_read_xive(0);
	v1 = ics_read_xive(1);
	assert(v0 = 0xff);
	assert(v1 = 0xff);
	return 0;
}

int xics_test_1(void)
{
	// setup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	icp_write8(XICS_XIRR, 0x00); // mask all interrupts

	// trigger two interrupts
	console_set_irq_en(true,true);// cause serial interrupt
	ics_write_xive(0x6, 0);      // set source to prio 6
	icp_write8(XICS_MFRR, 0x04); // cause ipi interrupt at prio 5

	// still masked, so shouldn't happen yet
	delay();
	assert(isrs_run == 0);

	// unmask IPI only
	icp_write8(XICS_XIRR, 0x6);
	delay();
	assert(isrs_run == ISR_IPI);

	// unmask UART
	icp_write8(XICS_XIRR, 0x7);
	delay();
	assert(isrs_run == (ISR_IPI | ISR_UART));

	// cleanup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	console_set_irq_en(false, false);
	ics_write_xive(0, 0xff);
	isrs_run = 0;

	return 0;
}

int xics_test_2(void)
{
	// setup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	icp_write8(XICS_XIRR, 0xff); // allow all interrupts

	// should be none pending
	delay();
	assert(isrs_run == 0);

	// trigger both
	console_set_irq_en(true, true);
	icp_write8(XICS_MFRR, 0x05); // cause 0x500 interrupt

	delay();
	assert(isrs_run == (ISR_IPI | ISR_UART));

	// cleanup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	console_set_irq_en(false, false);
	isrs_run = 0;

	return 0;
}

void mtmsrd(uint64_t val)
{
	__asm__ volatile("mtmsrd %0" : : "r" (val));
}

int xics_test_3(void)
{
	// setup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	// trigger interrupts with MSR[EE]=0 and show they are not run
	mtmsrd(0x9000000000000003); // EE off

	icp_write8(XICS_XIRR, 0xff); // allow all interrupts

	// trigger an IPI
	icp_write8(XICS_MFRR, 0x05); // cause 0x500 interrupt

	delay();
	assert(isrs_run == 0);

	mtmsrd(0x9000000000008003); // EE on
	delay();
	assert(isrs_run == ISR_IPI);

	// cleanup
	icp_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	return 0;
}

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

int (*tests[])(void) = {
	xics_test_0,
	xics_test_1,
	xics_test_2,
	xics_test_3,
	NULL
};

int main(void)
{
	int fail = 0;
	int i = 0;
	int (*t)(void);

	console_init();
	ipi_running = false;

	/* run the tests */
	while (1) {
		t = tests[i];
		if (!t)
			break;

		puts(TEST);
		print_number(i);
		putchar(':');
		if (t() != 0) {
			fail = 1;
			puts(FAIL);
		} else
			puts(PASS);

		i++;
	}

	return fail;
}
