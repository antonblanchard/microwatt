#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

extern unsigned long callit(unsigned long arg1, unsigned long arg2,
			    unsigned long (*fn)(unsigned long, unsigned long),
			    unsigned long msr, unsigned long *regs);
#define MSR_FP	0x2000
#define MSR_SE	0x400
#define MSR_BE	0x200

#define DSISR	18
#define DAR	19
#define SRR0	26
#define SRR1	27
#define SPRG0	272
#define SPRG1	273
#define CIABR	187
#define DAWR0	180
#define DAWR1	181
#define DAWRX0	188
#define DAWRX1	189
#define SIAR	780
#define SDAR	781

static inline unsigned long mfmsr(void)
{
	unsigned long msr;

	__asm__ volatile ("mfmsr %0" : "=r" (msr));
	return msr;
}

static inline unsigned long mfspr(int sprnum)
{
	long val;

	__asm__ volatile("mfspr %0,%1" : "=r" (val) : "i" (sprnum));
	return val;
}

static inline void mtspr(int sprnum, unsigned long val)
{
	__asm__ volatile("mtspr %0,%1" : : "i" (sprnum), "r" (val));
}

void print_string(const char *str)
{
	for (; *str; ++str)
		putchar(*str);
}

void print_hex(unsigned long val, int ndigits)
{
	int i, x;

	for (i = (ndigits - 1) * 4; i >= 0; i -= 4) {
		x = (val >> i) & 0xf;
		if (x >= 10)
			putchar(x + 'a' - 10);
		else
			putchar(x + '0');
	}
}

// i < 100
void print_test_number(int i)
{
	print_string("test ");
	putchar(48 + i/10);
	putchar(48 + i%10);
	putchar(':');
}

extern unsigned long test1(unsigned long, unsigned long);

int trace_test_1(void)
{
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(1, 2, test1, mfmsr() | MSR_SE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test1 + 4)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x40000000)
		return ret + 2;
	if (regs[0] != 3 || regs[1] != 2)
		return 3;
	if (mfspr(SIAR) != (unsigned long)&test1)
		return 4;
	return 0;
}

extern unsigned long test2(unsigned long, unsigned long);

int trace_test_2(void)
{
	unsigned long x = 3;
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(1, (unsigned long)&x, test2, mfmsr() | MSR_SE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test2 + 4)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x50000000)
		return ret + 2;
	if (regs[0] != 3 || x != 3)
		return 3;
	if (mfspr(SIAR) != (unsigned long)&test2 || mfspr(SDAR) != (unsigned long)&x)
		return 4;
	return 0;
}

extern unsigned long test3(unsigned long, unsigned long);

int trace_test_3(void)
{
	unsigned int x = 3;
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(11, (unsigned long)&x, test3, mfmsr() | MSR_SE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test3 + 4)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x48000000)
		return ret + 2;
	if (regs[0] != 11 || x != 11)
		return 3;
	if (mfspr(SIAR) != (unsigned long)&test3 || mfspr(SDAR) != (unsigned long)&x)
		return 4;
	return 0;
}

extern unsigned long test4(unsigned long, unsigned long);

int trace_test_4(void)
{
	unsigned long x = 3;
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(1, (unsigned long)&x, test4, mfmsr() | MSR_SE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test4 + 4)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x50000000)
		return ret + 2;
	if (regs[0] != 1 || x != 3)
		return 3;
	return 0;
}

extern unsigned long test5(unsigned long, unsigned long);

int trace_test_5(void)
{
	unsigned int x = 7;
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(11, (unsigned long)&x, test5, mfmsr() | MSR_SE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test5 + 4)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x48000000)
		return ret + 2;
	if (regs[0] != 11 || x != 7)
		return 3;
	return 0;
}

extern unsigned long test6(unsigned long, unsigned long);

int trace_test_6(void)
{
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(11, 55, test6, mfmsr() | MSR_BE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test6 + 20)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x40000000)
		return ret + 2;
	if (regs[0] != 11 || regs[1] != 55)
		return 3;
	if (mfspr(SIAR) != (unsigned long)&test6 + 8)
		return 4;
	return 0;
}

extern unsigned long test7(unsigned long, unsigned long);

int trace_test_7(void)
{
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(11, 55, test7, mfmsr() | MSR_BE, regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test7 + 16)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x40000000)
		return ret + 2;
	if (regs[0] != 11 || regs[1] != 1)
		return 3;
	if (mfspr(SIAR) != (unsigned long)&test7 + 8)
		return 4;
	return 0;
}

extern unsigned long test8(unsigned long, unsigned long);

int trace_test_8(void)
{
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(0, 0, test8, (mfmsr() & ~MSR_FP) | MSR_SE, regs);
	if (ret != 0x800)
		return ret + 1;
	ret = callit(0, 0, test8, mfmsr() | MSR_FP | MSR_SE, regs);
	if (ret != 0xd00)
		return ret + 2;
	return 0;
}

extern unsigned long test9(unsigned long, unsigned long);

int trace_test_9(void)
{
	unsigned long ret;
	unsigned long regs[2];

	ret = callit(0, 0, test9, mfmsr() | MSR_SE, regs);
	if (ret != 0xc00)
		return ret + 1;
	return 0;
}

extern unsigned long test10(unsigned long, unsigned long);

/* test CIABR */
int trace_test_10(void)
{
	unsigned long ret;
	unsigned long regs[2];

	mtspr(CIABR, (unsigned long)&test10 + 4 + 3);
	ret = callit(1, 1, test10, mfmsr(), regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test10 + 8)
		return ret + 1;
	if ((mfspr(SRR1) & 0x781f0000) != 0x40100000)
		return ret + 2;
	if (regs[0] != 2 || regs[1] != 3)
		return 3;

	/* test CIABR on a taken branch */
	mtspr(CIABR, (unsigned long)&test10 + 20 + 3);
	ret = callit(1, 1, test10, mfmsr(), regs);
	if (ret != 0xd00 || mfspr(SRR0) != (unsigned long)&test10 + 32)
		return ret + 4;
	if ((mfspr(SRR1) & 0x781f0000) != 0x40100000)
		return ret + 5;
	if (regs[0] != 6 || regs[1] != 11)
		return 6;

	/* test CIABR with PRIV = problem state */
	mtspr(CIABR, (unsigned long)&test10 + 1);
	ret = callit(1, 1, test10, mfmsr(), regs);
	if (ret != 0)
		return ret + 7;
	/* don't have page tables so can't actually run in problem state */
	return 0;
}

/* test DAWR[X]{0,1} */
#define MRD_SHIFT	10
#define HRAMMC		0x80
#define DW		0x40
#define DR		0x20
#define WT		0x10
#define WTI		0x08
#define PRIVM_HYP	0x04
#define PRIVM_PNH	0x02
#define PRIVM_PRO	0x01

extern unsigned long test11(unsigned long, unsigned long);

int trace_test_11(void)
{
	unsigned long ret;
	unsigned long regs[2];
	unsigned long x[4];

	mtspr(DAWR0, (unsigned long)&x[0]);
	mtspr(DAWRX0, (0 << MRD_SHIFT) + DW + PRIVM_HYP);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 1;
	if (mfspr(SRR0) != (unsigned long) &test11 || mfspr(DSISR) != 0x02400000 ||
	    mfspr(DAR) != (unsigned long)&x[0])
		return 2;

	mtspr(DAWR0, (unsigned long)&x[1]);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 3;
	if (mfspr(SRR0) != (unsigned long) &test11 + 4 || mfspr(DSISR) != 0x02400000 ||
	    mfspr(DAR) != (unsigned long)&x[1])
		return 4;

	mtspr(DAWR0, (unsigned long)&x[0]);
	mtspr(DAWRX0, (0 << MRD_SHIFT) + DR + PRIVM_HYP);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 5;
	if (mfspr(SRR0) != (unsigned long) &test11 + 24 || mfspr(DSISR) != 0x00400000)
		return 6;

	mtspr(DAWR0, (unsigned long)&x[1]);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 7;
	if (mfspr(SRR0) != (unsigned long) &test11 + 28 || mfspr(DSISR) != 0x00400000)
		return 8;

	mtspr(DAWR0, (unsigned long)&x[3]);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 9;
	if (mfspr(SRR0) != (unsigned long) &test11 + 32 || mfspr(DSISR) != 0x00400000)
		return 10;

	mtspr(DAWR0, (unsigned long)&x[2]);
	mtspr(DAWRX0, (1 << MRD_SHIFT) + DW + PRIVM_HYP);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 11;
	if (mfspr(SRR0) != (unsigned long) &test11 + 36 || mfspr(DSISR) != 0x02400000)
		return 12;

	mtspr(DAWR0, (unsigned long)&x[0]);
	mtspr(DAWRX0, (3 << MRD_SHIFT) + DR + DW + WT + PRIVM_HYP);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0)
		return ret + 13;

	mtspr(DAWR0, (unsigned long)&x[0]);
	mtspr(DAWRX0, (3 << MRD_SHIFT) + DR + DW + WT + WTI + PRIVM_HYP);
	ret = callit(0, (unsigned long) &x, test11, mfmsr(), regs);
	if (ret != 0x300)
		return ret + 14;
	if (mfspr(SRR0) != (unsigned long) &test11 || mfspr(DSISR) != 0x02400000)
		return 15;

	return 0;
}

int fail = 0;

void do_test(int num, int (*test)(void))
{
	int ret;

	print_test_number(num);
	ret = test();
	if (ret == 0) {
		print_string("PASS\r\n");
	} else {
		fail = 1;
		print_string(" FAIL ");
		print_hex(ret, 4);
		print_string("\r\n");
	}
}

int main(void)
{
	console_init();

	do_test(1, trace_test_1);
	do_test(2, trace_test_2);
	do_test(3, trace_test_3);
	do_test(4, trace_test_4);
	do_test(5, trace_test_5);
	do_test(6, trace_test_6);
	do_test(7, trace_test_7);
	do_test(8, trace_test_8);
	do_test(9, trace_test_9);
	do_test(10, trace_test_10);
	do_test(11, trace_test_11);

	return fail;
}
