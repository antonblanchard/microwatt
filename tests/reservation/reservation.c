#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

extern unsigned long callit(unsigned long arg1, unsigned long arg2,
			    unsigned long (*fn)(unsigned long, unsigned long));

extern unsigned long do_lqarx(unsigned long src, unsigned long regs);
extern unsigned long do_lqarx_bad(unsigned long src, unsigned long regs);
extern unsigned long do_stqcx(unsigned long dst, unsigned long regs);

#define DSISR	18
#define DAR	19
#define SRR0	26
#define SRR1	27
#define PID	48
#define SPRG0	272
#define SPRG1	273

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

static inline void store_pte(unsigned long *p, unsigned long pte)
{
	__asm__ volatile("stdbrx %1,0,%0" : : "r" (p), "r" (pte) : "memory");
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

#define DO_LARX(instr, addr, val)	__asm__ volatile(instr " %0,0,%1" : "=r" (val) : "r" (addr))
#define DO_STCX(instr, addr, val, cc)	__asm__ volatile(instr " %2,0,%1; mfcr %0" : "=r" (cc) \
                                                         : "r" (addr), "r" (val) : "cr0", "memory");

int resv_test_1(void)
{
	unsigned long x, val, cc = 0;
	int count;

	x = 1234;
	for (count = 0; count < 1000; ++count) {
		DO_LARX("ldarx", &x, val);
		DO_STCX("stdcx.", &x, 5678, cc);
		if (cc & 0x20000000)
			break;
	}
	/* ldarx/stdcx. should succeed eventually */
	if (count == 1000)
		return 1;
	if (x != 5678)
		return 2;
	for (count = 0; count < 1000; ++count) {
		DO_LARX("lwarx", &x, val);
		DO_STCX("stwcx.", &x, 9876, cc);
		if (cc & 0x20000000)
			break;
	}
	/* lwarx/stwcx. should succeed eventually */
	if (count == 1000)
		return 3;
	if (x != 9876)
		return 4;
	for (count = 0; count < 1000; ++count) {
		DO_LARX("lharx", &x, val);
		DO_STCX("sthcx.", &x, 3210, cc);
		if (cc & 0x20000000)
			break;
	}
	/* lharx/sthcx. should succeed eventually */
	if (count == 1000)
		return 5;
	if (x != 3210)
		return 6;
	return 0;
}

unsigned long do_larx(unsigned long size, unsigned long addr)
{
	unsigned long val;

	switch (size) {
	case 1:
		DO_LARX("lbarx", addr, val);
		break;
	case 2:
		DO_LARX("lharx", addr, val);
		break;
	case 4:
		DO_LARX("lwarx", addr, val);
		break;
	case 8:
		DO_LARX("ldarx", addr, val);
		break;
	}
	return 0;
}

unsigned long do_stcx(unsigned long size, unsigned long addr)
{
	unsigned long val = 0, cc;

	switch (size) {
	case 1:
		DO_STCX("stbcx.", addr, val, cc);
		break;
	case 2:
		DO_STCX("sthcx.", addr, val, cc);
		break;
	case 4:
		DO_STCX("stwcx.", addr, val, cc);
		break;
	case 8:
		DO_STCX("stdcx.", addr, val, cc);
		break;
	}
	return 0;
}

int resv_test_2(void)
{
	unsigned long x[3];
	unsigned long offset, j, size, ret;

	x[0] = 1234;
	x[1] = x[2] = 0;
	for (j = 0; j <= 3; ++j) {
		size = 1 << j;
		for (offset = 0; offset < 16; ++offset) {
			ret = callit(size, (unsigned long)&x[0] + offset, do_larx);
			if (ret == 0 && (offset & (size - 1)) != 0)
				return j + 1;
			if (ret == 0x600) {
				if ((offset & (size - 1)) == 0)
					return j + 0x10;
			} else if (ret)
				return ret;
			ret = callit(size, (unsigned long)&x[0] + offset, do_stcx);
			if (ret == 0 && (offset & (size - 1)) != 0)
				return j + 0x20;
			if (ret == 0x600) {
				if ((offset & (size - 1)) == 0)
					return j + 0x30;
			} else if (ret)
				return ret;
		}
	}
	return 0;
}

/* test lqarx/stqcx */
int resv_test_3(void)
{
	unsigned long x[4] __attribute__((__aligned__(16)));
	unsigned long y[2], regs[2];
	unsigned long ret, offset;
	int count;

	x[0] = 0x7766554433221100ul;
	x[1] = 0xffeeddccbbaa9988ul;
	y[0] = 0x0badcafef00dd00dul;
	y[1] = 0xdeadbeef07070707ul;
	for (count = 0; count < 1000; ++count) {
		ret = callit((unsigned long)x, (unsigned long)regs, do_lqarx);
		if (ret)
			return ret | 1;
		ret = callit((unsigned long)x, (unsigned long)y, do_stqcx);
		if (ret < 0x10000)
			return ret | 2;
		if (ret & 0x20000000)
			break;
	}
	if (count == 1000)
		return 3;
	if (x[0] != y[1] || x[1] != y[0])
		return 4;
	if (regs[1] != 0x7766554433221100ul || regs[0] != 0xffeeddccbbaa9988ul)
		return 5;
	ret = callit((unsigned long)x, (unsigned long)regs, do_stqcx);
	if (ret < 0x10000 || (ret & 0x20000000))
		return ret | 12;
	/* test alignment interrupts */
	for (offset = 0; offset < 16; ++offset) {
		ret = callit((unsigned long)x + offset, (unsigned long)regs, do_lqarx);
		if (ret == 0 && (offset & 15) != 0)
			return 6;
		if (ret == 0x600) {
			if ((offset & 15) == 0)
				return ret + 7;
		} else if (ret)
			return ret;
		ret = callit((unsigned long)x + offset, (unsigned long)y, do_stqcx);
		if (ret >= 0x10000 && (offset & 15) != 0)
			return 8;
		if (ret == 0x600) {
			if ((offset & 15) == 0)
				return ret + 9;
		} else if (ret < 0x10000)
			return ret;
	}
	/* test illegal interrupt for bad lqarx case */
	ret = callit((unsigned long)x, (unsigned long)regs, do_lqarx_bad);
	if (ret != 0x700 || !(mfspr(SRR1) & 0x80000))
		return ret + 10;
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

	do_test(1, resv_test_1);
	do_test(2, resv_test_2);
	do_test(3, resv_test_3);

	return fail;
}
