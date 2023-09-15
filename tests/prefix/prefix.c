#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_LE	0x1
#define MSR_DR	0x10
#define MSR_IR	0x20
#define MSR_SF	0x8000000000000000ul

#define DSISR	18
#define DAR	19
#define SRR0	26
#define SRR1	27
#define PID	48
#define PTCR	464

extern long trapit(long arg, long (*func)(long));
extern long test_paddi(long arg);
extern long test_paddi_r(long arg);
extern long test_paddi_neg(long arg);
extern long test_paddi_mis(long arg);
extern long test_plbz(long arg);
extern long test_pld(long arg);
extern long test_plha(long arg);
extern long test_plhz(long arg);
extern long test_plwa(long arg);
extern long test_plwz(long arg);
extern long test_pstb(long arg);
extern long test_pstd(long arg);
extern long test_psth(long arg);
extern long test_pstw(long arg);
extern long test_plfd(long arg);

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
	print_string(str);
}

// i < 100
void print_test_number(int i)
{
	print_string("test ");
	putchar(48 + i/10);
	putchar(48 + i%10);
	putchar(':');
}

long int prefix_test_1(void)
{
	long int ret;

	ret = trapit(0x321, test_paddi);
	if (ret != 0x123456789 + 0x321)
		return ret;
	ret = trapit(0x322, test_paddi_r);
	if (ret != 0x123456789)
		return ret;
	ret = trapit(0x323, test_paddi_neg);
	if (ret != 0x323 - 0x123456789)
		return ret;
	return 0;
}

double fpvar = 123.456;

long int prefix_test_2(void)
{
	long int ret;
	double x;

	ret = trapit(0x123, test_paddi_mis);
	if (ret != 0x600)
		return 1;
	if (mfspr(SRR0) != (unsigned long)&test_paddi_mis + 8)
		return 2;
	if (mfspr(SRR1) != (MSR_SF | MSR_LE | (1ul << (63 - 35)) | (1ul << (63 - 34))))
		return 3;

	ret = trapit((long)&x, test_plfd);
	if (ret != 0x800)
		return ret;
	if (mfspr(SRR0) != (unsigned long)&test_plfd + 8)
		return 6;
	if (mfspr(SRR1) != (MSR_SF | MSR_LE | (1ul << (63 - 34))))
		return 7;
	return 0;
}

unsigned char bvar = 0x63;
long lvar = 0xfedcba987654;
unsigned short hvar = 0xffee;
unsigned int wvar = 0x80457788;

long int prefix_test_3(void)
{
	long int ret;
	long int x;

	ret = trapit((long)&x, test_pld);
	if (ret)
		return ret | 1;
	if (x != lvar)
		return 2;
	ret = trapit(1234, test_pstd);
	if (ret)
		return ret | 2;
	if (lvar != 1234)
		return 3;

	ret = trapit((long)&x, test_plbz);
	if (ret)
		return ret | 0x10;
	if (x != bvar)
		return 0x11;
	ret = trapit(0xaa, test_pstb);
	if (ret)
		return ret | 0x12;
	if (bvar != 0xaa)
		return 0x13;

	ret = trapit((long)&x, test_plhz);
	if (ret)
		return ret | 0x20;
	if (x != hvar)
		return 0x21;
	ret = trapit((long)&x, test_plha);
	if (ret)
		return ret | 0x22;
	if (x != (signed short)hvar)
		return 0x23;
	ret = trapit(0x23aa, test_psth);
	if (ret)
		return ret | 0x24;
	if (hvar != 0x23aa)
		return 0x25;

	ret = trapit((long)&x, test_plwz);
	if (ret)
		return ret | 0x30;
	if (x != wvar)
		return 0x31;
	ret = trapit((long)&x, test_plwa);
	if (ret)
		return ret | 0x32;
	if (x != (signed int)wvar)
		return 0x33;
	ret = trapit(0x23aaf44f, test_pstw);
	if (ret)
		return ret | 0x34;
	if (wvar != 0x23aaf44f)
		return 0x35;
	return 0;
}

int fail = 0;

void do_test(int num, long int (*test)(void))
{
	long int ret;

	print_test_number(num);
	ret = test();
	if (ret == 0) {
		print_string("PASS\r\n");
	} else {
		fail = 1;
		print_string("FAIL ");
		print_hex(ret, 16, " SRR0=");
		print_hex(mfspr(SRR0), 16, " SRR1=");
		print_hex(mfspr(SRR1), 16, "\r\n");
	}
}

int main(void)
{
	console_init();
	//init_mmu();

	do_test(1, prefix_test_1);
	do_test(2, prefix_test_2);
	do_test(3, prefix_test_3);

	return fail;
}
