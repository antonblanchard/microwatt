#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_FP	0x2000
#define MSR_FE0	0x800
#define MSR_FE1	0x100

extern int trapit(long arg, int (*func)(long));

#define SRR0	26
#define SRR1	27

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

void disable_fp(void)
{
	unsigned long msr;

	__asm__("mfmsr %0" : "=r" (msr));
	msr &= ~(MSR_FP | MSR_FE0 | MSR_FE1);
	__asm__("mtmsrd %0" : : "r" (msr));
}

void enable_fp(void)
{
	unsigned long msr;

	__asm__("mfmsr %0" : "=r" (msr));
	msr |= MSR_FP;
	__asm__("mtmsrd %0" : : "r" (msr));
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

unsigned long foo = 0x3ff8000000000000ul;
unsigned long foow;
int fooi = -76543;
int fooiw;

int do_fp_op(long arg)
{
	switch (arg) {
	case 0:
		__asm__("lfd 31,0(%0)" : : "b" (&foo));
		break;
	case 1:
		__asm__("stfd 31,0(%0)" : : "b" (&foow) : "memory");
		break;
	case 2:
		__asm__("lfd 30,0(%0); stfd 30,0(%1)"
			: : "b" (&foo), "b" (&foow) : "memory");
		break;
	case 3:
		__asm__("lfiwax 29,0,%0; stfd 29,0(%1)"
			: : "r" (&fooi), "b" (&foow) : "memory");
		break;
	case 4:
		__asm__("lfiwzx 28,0,%0; stfd 28,0(%1)"
			: : "r" (&fooi), "b" (&foow) : "memory");
		break;
	case 5:
		__asm__("lfdx 27,0,%0; stfiwx 27,0,%1"
			: : "r" (&foow), "r" (&fooiw) : "memory");
		break;
	}
	return 0;
}


int fpu_test_1(void)
{
	int ret;

	disable_fp();
	/* these should give a FP unavailable exception */
	ret = trapit(0, do_fp_op);
	if (ret != 0x800)
		return 1;
	ret = trapit(1, do_fp_op);
	if (ret != 0x800)
		return 2;
	enable_fp();
	/* these should succeed */
	ret = trapit(0, do_fp_op);
	if (ret)
		return ret | 3;
	ret = trapit(1, do_fp_op);
	if (ret)
		return ret | 4;
	if (foow != foo)
		return 5;
	return 0;
}

int fpu_test_2(void)
{
	int ret;

	enable_fp();
	foow = ~0;
	ret = trapit(2, do_fp_op);
	if (ret)
		return ret | 1;
	if (foow != foo)
		return 2;
	foow = ~0;
	ret = trapit(3, do_fp_op);
	if (ret)
		return ret | 3;
	if (foow != fooi)
		return 4;
	foow = ~0;
	ret = trapit(4, do_fp_op);
	if (ret)
		return ret | 5;
	if (foow != (unsigned int)fooi)
		return 6;
	ret = trapit(5, do_fp_op);
	if (ret)
		return ret | 7;
	if (fooiw != fooi)
		return 8;
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
		print_string(" SRR0=");
		print_hex(mfspr(SRR0), 16);
		print_string(" SRR1=");
		print_hex(mfspr(SRR1), 16);
		print_string("\r\n");
	}
}

int main(void)
{
	console_init();

	do_test(1, fpu_test_1);
	do_test(2, fpu_test_2);

	return fail;
}
