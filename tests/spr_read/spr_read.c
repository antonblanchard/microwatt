#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

extern long read_sprn(long, long);
extern long write_sprn(long);

// i < 100
void print_test(char *str)
{
	puts(TEST);
	puts(str);
	putchar(':');
}

#define SPR_XER		1
#define SPR_LR		8
#define SPR_CTR		9
#define SPR_TAR		815
#define SPR_DSISR	18
#define SPR_DAR		19
#define SPR_TB		268
#define SPR_TBU		269
#define SPR_DEC		22
#define SPR_SRR0	26
#define SPR_SRR1	27
#define SPR_CFAR	28
#define SPR_HSRR0	314
#define SPR_HSRR1	315
#define SPR_SPRG0	272
#define SPR_SPRG1	273
#define SPR_SPRG2	274
#define SPR_SPRG3	275
#define SPR_SPRG3U	259
#define SPR_HSPRG0	304
#define SPR_HSPRG1	305
#define SPR_PID		48
#define SPR_PTCR	464
#define SPR_PVR		287

#define __stringify_1(x...)	#x
#define __stringify(x...)	__stringify_1(x)

void print_hex(unsigned long val, int ndigits, const char *str)
{
	int i, x;

	for (i = (ndigits - 1) * 4; i >= 0; i -= 4) {
		x = (val >> i) & 0xf;
		if (x >= 10)
			putchar(x + 'a' - 10);
		else
			putchar(x + '0');
	}
	puts(str);
}

int main(void)
{
	unsigned long tmp, r;
	int fail = 0;

	console_init();

	/*
	 * Read all SPRs. Rely on the register file raising an assertion if we
	 * write X state to a GPR.
	 */

#define DO_ONE(SPR) { \
		print_test(#SPR); \
		__asm__ __volatile__("mfspr %0," __stringify(SPR) : "=r" (tmp)); \
		puts(PASS); \
	}

	DO_ONE(SPR_XER);
	DO_ONE(SPR_LR);
	DO_ONE(SPR_CTR);
	DO_ONE(SPR_TAR);
	DO_ONE(SPR_DSISR);
	DO_ONE(SPR_DAR);
	DO_ONE(SPR_TB);
	DO_ONE(SPR_TBU);
	DO_ONE(SPR_DEC);
	DO_ONE(SPR_SRR0);
	DO_ONE(SPR_SRR1);
	DO_ONE(SPR_CFAR);
	DO_ONE(SPR_HSRR0);
	DO_ONE(SPR_HSRR1);
	DO_ONE(SPR_SPRG0);
	DO_ONE(SPR_SPRG1);
	DO_ONE(SPR_SPRG2);
	DO_ONE(SPR_SPRG3);
	DO_ONE(SPR_SPRG3U);
	DO_ONE(SPR_HSPRG0);
	DO_ONE(SPR_HSPRG1);
	DO_ONE(SPR_PID);
	DO_ONE(SPR_PTCR);
	DO_ONE(SPR_PVR);

	/*
	 * Test no-op behaviour of reserved no-op SPRs,
	 * and of accesses to undefined SPRs in privileged mode.
	 */
	print_test("reserved no-op");
	__asm__ __volatile__("mtspr 811,%0" : : "r" (7838));
	__asm__ __volatile__("li %0,%1; mfspr %0,811" : "=r" (tmp) : "i" (2398));
	if (tmp == 2398) {
		puts(PASS);
	} else {
		puts(FAIL);
		fail = 1;
	}

	print_test("undefined SPR");
	r = write_sprn(179);
	tmp = read_sprn(179, 2498);
	if (r == 0 && tmp == 2498) {
		puts(PASS);
	} else {
		puts(FAIL);
		fail = 1;
	}

	print_test("read SPR 0/4/5/6");
	if (read_sprn(0, 1234) == 0xe40 && read_sprn(2, 1234) == 1234 &&
	    read_sprn(4, 1234) == 0xe40 && read_sprn(5, 1234) == 0xe40 &&
	    read_sprn(6, 1234) == 0xe40 &&
	    write_sprn(0) == 0xe40 && write_sprn(2) == 0 &&
	    write_sprn(4) == 0xe40 && write_sprn(5) == 0xe40 &&
	    write_sprn(6) == 0xe40) {
		puts(PASS);
	} else {
		puts(FAIL);
		fail = 1;
	}

	if (!fail)
		puts(PASS);
	else
		puts(FAIL);

	return fail;
}
