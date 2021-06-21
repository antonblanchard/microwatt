#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

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

int main(void)
{
	unsigned long tmp;

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

	puts(PASS);

	return 0;
}
