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

#define SRR0	26
#define SRR1	27
#define SPRG0	272
#define SPRG1	273

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
		print_string("FAIL ");
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

	return fail;
}
