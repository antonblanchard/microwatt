#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>

#include "console.h"
#include "xics.h"

#undef DEBUG
//#define DEBUG 1

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
#define DEBUG_STR "\r\nDEBUG: "
void debug_print(int i)
{
	putstr(DEBUG_STR, strlen(DEBUG_STR));
	print_number(i);
	putstr("\r\n", 2);
}

#define debug_putstr(a, b) putstr(a,b)
#else
#define debug_putstr(a, b)
#define debug_print(i)
#endif

#define ASSERT_FAIL "() ASSERT_FAILURE!\r\n "
#define assert(cond)	\
	if (!(cond))  { \
		putstr(__FILE__, strlen(__FILE__)); \
		putstr(":", 1);	    \
		print_number(__LINE__);	\
		putstr(":", 1);	    \
		putstr(__FUNCTION__, strlen(__FUNCTION__));\
		putstr(ASSERT_FAIL, strlen(ASSERT_FAIL)); \
		__asm__ ("attn"); \
	}


volatile uint64_t isrs_run;

#define ISR_IPI      0x0000000000000001
#define ISR_UART     0x0000000000000002
#define ISR_SPURIOUS 0x0000000000000004

#define IPI "IPI\r\n"
void ipi_isr(void) {
	debug_putstr(IPI, strlen(IPI));

	isrs_run |= ISR_IPI;
}


#define UART "UART\r\n"
void uart_isr(void) {
	debug_putstr(UART, strlen(UART));

	potato_uart_irq_dis(); // disable interrupt to ack it

	isrs_run |= ISR_UART;
}

// The hardware doesn't support this but it's part of XICS so add it.
#define SPURIOUS "SPURIOUS\r\n"
void spurious_isr(void) {
	debug_putstr(SPURIOUS, strlen(SPURIOUS));

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
void isr(void)
{
	struct isr_op *op;
	uint32_t xirr;

	assert(!ipi_running); // check we aren't reentrant
	ipi_running = true;

	xirr = xics_read32(XICS_XIRR); // read hardware irq source

#ifdef DEBUG
	putstr(ISR, strlen(ISR));
	print_number(xirr & 0xff);
	putstr("\r\n", 2);
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

	xics_write32(XICS_XIRR, xirr); // EOI

	ipi_running = false;
}

/*****************************************/

int xics_test_0(void)
{
	// setup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	xics_write8(XICS_XIRR, 0x00); // mask all interrupts

	// trigger two interrupts
	potato_uart_irq_en(); // cause 0x500 interrupt
	xics_write8(XICS_MFRR, 0x05); // cause 0x500 interrupt

	// still masked, so shouldn't happen yet
	assert(isrs_run == 0);

	// unmask IPI only
	xics_write8(XICS_XIRR, 0x40);
	assert(isrs_run == ISR_IPI);

	// unmask UART
	xics_write8(XICS_XIRR, 0xc0);
	assert(isrs_run == (ISR_IPI | ISR_UART));

	// cleanup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	return 0;
}

int xics_test_1(void)
{
	// setup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	xics_write8(XICS_XIRR, 0xff); // allow all interrupts

	// should be none pending
	assert(isrs_run == 0);

	// trigger both
	potato_uart_irq_en(); // cause 0x500 interrupt
	xics_write8(XICS_MFRR, 0x05); // cause 0x500 interrupt

	assert(isrs_run == (ISR_IPI | ISR_UART));

	// cleanup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	return 0;
}

void mtmsrd(uint64_t val)
{
	__asm__ volatile("mtmsrd %0" : : "r" (val));
}

int xics_test_2(void)
{
	// setup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	// trigger interrupts with MSR[EE]=0 and show they are not run
	mtmsrd(0x9000000000000003); // EE off

	xics_write8(XICS_XIRR, 0xff); // allow all interrupts

	// trigger an IPI
	xics_write8(XICS_MFRR, 0x05); // cause 0x500 interrupt

	assert(isrs_run == 0);

	mtmsrd(0x9000000000008003); // EE on
	assert(isrs_run == ISR_IPI);

	// cleanup
	xics_write8(XICS_XIRR, 0x00); // mask all interrupts
	isrs_run = 0;

	return 0;
}

#define TEST "Test "
#define PASS "PASS\r\n"
#define FAIL "FAIL\r\n"

int (*tests[])(void) = {
	xics_test_0,
	xics_test_1,
	xics_test_2,
	NULL
};

int main(void)
{
	int fail = 0;
	int i = 0;
	int (*t)(void);

	potato_uart_init();
	ipi_running = false;

	/* run the tests */
	while (1) {
		t = tests[i];
		if (!t)
			break;

		putstr(TEST, strlen(TEST));
		print_number(i);
		putstr(": ", 1);
		if (t() != 0) {
			fail = 1;
			putstr(FAIL, strlen(FAIL));
		} else
			putstr(PASS, strlen(PASS));

		i++;
	}

	return fail;
}
