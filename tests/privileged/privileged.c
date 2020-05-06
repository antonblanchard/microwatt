#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_EE	0x8000
#define MSR_PR	0x4000
#define MSR_IR	0x0020
#define MSR_DR	0x0010

extern int call_with_msr(unsigned long arg, int (*fn)(unsigned long), unsigned long msr);

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

int priv_fn_1(unsigned long x)
{
	__asm__ volatile("attn");
	__asm__ volatile("li 3,0; sc");
	return 0;
}

int priv_fn_2(unsigned long x)
{
	__asm__ volatile("mfmsr 3");
	__asm__ volatile("sc");
	return 0;
}

int priv_fn_3(unsigned long x)
{
	__asm__ volatile("mtmsrd 3");
	__asm__ volatile("li 3,0; sc");
	return 0;
}

int priv_fn_4(unsigned long x)
{
	__asm__ volatile("rfid");
	__asm__ volatile("li 3,0; sc");
	return 0;
}

int priv_fn_5(unsigned long x)
{
	__asm__ volatile("mfsrr0 3");
	__asm__ volatile("sc");
	return 0;
}

int priv_fn_6(unsigned long x)
{
	__asm__ volatile("mtsrr0 3");
	__asm__ volatile("sc");
	return 0;
}

int priv_test(int (*fn)(unsigned long))
{
	unsigned long msr;
	int vec;

	__asm__ volatile ("mtdec %0" : : "r" (0x7fffffff));
	__asm__ volatile ("mfmsr %0" : "=r" (msr));
	/* this should fail */
	vec = call_with_msr(0, fn, msr | MSR_PR);
	if (vec != 0x700)
		return vec | 1;
	/* SRR1 should be set correctly */
	msr |= MSR_PR | MSR_EE | MSR_IR | MSR_DR;
	if (mfspr(SRR1) != (msr | 0x40000))
		return 2;
	return 0;
}

int fail = 0;

void do_test(int num, int (*fn)(unsigned long))
{
	int ret;

	print_test_number(num);
	ret = priv_test(fn);
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
	potato_uart_init();

	do_test(1, priv_fn_1);
	do_test(2, priv_fn_2);
	do_test(3, priv_fn_3);
	do_test(4, priv_fn_4);
	do_test(5, priv_fn_5);
	do_test(6, priv_fn_6);

	return fail;
}
