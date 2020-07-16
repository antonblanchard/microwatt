#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define asm	__asm__ volatile

#define MSR_FP	0x2000
#define MSR_FE0	0x800
#define MSR_FE1	0x100

extern int trapit(long arg, int (*func)(long));
extern void do_rfid(unsigned long msr);
extern void do_blr(void);

#define SRR0	26
#define SRR1	27

static inline unsigned long mfspr(int sprnum)
{
	long val;

	asm("mfspr %0,%1" : "=r" (val) : "i" (sprnum));
	return val;
}

static inline void mtspr(int sprnum, unsigned long val)
{
	asm("mtspr %0,%1" : : "i" (sprnum), "r" (val));
}

void disable_fp(void)
{
	unsigned long msr;

	asm("mfmsr %0" : "=r" (msr));
	msr &= ~(MSR_FP | MSR_FE0 | MSR_FE1);
	asm("mtmsrd %0" : : "r" (msr));
}

void enable_fp(void)
{
	unsigned long msr;

	asm("mfmsr %0" : "=r" (msr));
	msr |= MSR_FP;
	msr &= ~(MSR_FE0 | MSR_FE1);
	asm("mtmsrd %0" : : "r" (msr));
}

void enable_fp_interrupts(void)
{
	unsigned long msr;

	asm("mfmsr %0" : "=r" (msr));
	msr |= MSR_FE0 | MSR_FE1;
	asm("mtmsrd %0" : : "r" (msr));
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

unsigned long foo = 0x3ff8000000000000ul;
unsigned long foow;
int fooi = -76543;
int fooiw;

int do_fp_op(long arg)
{
	switch (arg) {
	case 0:
		asm("lfd 31,0(%0)" : : "b" (&foo));
		break;
	case 1:
		asm("stfd 31,0(%0)" : : "b" (&foow) : "memory");
		break;
	case 2:
		asm("lfd 30,0(%0); stfd 30,0(%1)"
		    : : "b" (&foo), "b" (&foow) : "memory");
		break;
	case 3:
		asm("lfiwax 29,0,%0; stfd 29,0(%1)"
		    : : "r" (&fooi), "b" (&foow) : "memory");
		break;
	case 4:
		asm("lfiwzx 28,0,%0; stfd 28,0(%1)"
		    : : "r" (&fooi), "b" (&foow) : "memory");
		break;
	case 5:
		asm("lfdx 27,0,%0; stfiwx 27,0,%1"
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

struct sp_dp_equiv {
	unsigned int sp;
	unsigned long dp;
} sp_dp_equiv[] = {
	{ 0, 0 },
	{ 0x80000000, 0x8000000000000000 },
	{ 0x7f800000, 0x7ff0000000000000 },
	{ 0xff800000, 0xfff0000000000000 },
	{ 0x7f812345, 0x7ff02468a0000000 },
	{ 0x456789ab, 0x40acf13560000000 },
	{ 0x12345678, 0x3a468acf00000000 },
	{ 0x00400000, 0x3800000000000000 },
	{ 0x00200000, 0x37f0000000000000 },
	{ 0x00000002, 0x36b0000000000000 },
	{ 0x00000001, 0x36a0000000000000 },
};

int sp_to_dp(long arg)
{
	unsigned long dp;

	asm("lfs 20,0(%0); stfd 20,0(%1)"
	    : : "b" (&sp_dp_equiv[arg].sp), "b" (&dp) : "memory");
	if (dp != sp_dp_equiv[arg].dp) {
		print_hex(sp_dp_equiv[arg].sp, 8, " ");
		print_hex(dp, 16, " ");
		print_hex(sp_dp_equiv[arg].dp, 16, " ");
	}
	return dp != sp_dp_equiv[arg].dp;
}

int dp_to_sp(long arg)
{
	unsigned int sp;

	asm("lfd 21,0(%0); stfs 21,0(%1)"
	    : : "b" (&sp_dp_equiv[arg].dp), "b" (&sp) : "memory");
	return sp != sp_dp_equiv[arg].sp;
}

int fpu_test_3(void)
{
	int i, n, ret;

	n = sizeof(sp_dp_equiv) / sizeof(sp_dp_equiv[0]);
	enable_fp();
	for (i = 0; i < n; ++i) {
		ret = trapit(i, sp_to_dp);
		if (ret != 0) {
			if (ret == 1)
				ret += i;
			return ret;
		}
		ret = trapit(i, dp_to_sp);
		if (ret != 0) {
			if (ret == 1)
				ret += i + 0x10000;
			return ret;
		}
	}
	return 0;
}

unsigned long get_fpscr(void)
{
	unsigned long ret;

	asm("mffs 10; stfd 10,0(%0)" : : "b" (&ret) : "memory");
	return ret;
}

void set_fpscr(unsigned long fpscr)
{
	asm("lfd%U0%X0 7,%0; mtfsf 0,7,1,0" : : "m" (fpscr));
}

unsigned long fpscr_eval(unsigned long val)
{
	val &= ~0x60000000;	/* clear FEX and VX */
	if (val & 0x1f80700)	/* test all VX* bits */
		val |= 0x20000000;
	if ((val >> 25) & (val >> 3) & 0x1f)
		val |= 0x40000000;
	return val;
}

unsigned int test4vals[] = {
	0xdeadbeef, 0x1324679a, 0, 0xffffffff, 0xabcd
};

int test4(long arg)
{
	unsigned long fsi, fso, fpscr;
	long i;
	unsigned long cr, mask;

	/* check we can do basic mtfsf and mffs */
	i = 1;
	for (fsi = 1; fsi < 0x100; fsi <<= 1) {
		asm("lfd 7,0(%0); mtfsf 0,7,1,0" : : "b" (&fsi));
		if (get_fpscr() != fsi)
			return i;
		++i;
		fpscr = fsi;
	}
	for (i = 0; i < sizeof(test4vals) / sizeof(test4vals[0]); ++i) {
		fsi = test4vals[i];
		asm("lfd 7,0(%0); mtfsf 0x55,7,0,0" : : "b" (&fsi));
		fpscr = fpscr_eval((fpscr & 0xf0f0f0f0) | (fsi & 0x0f0f0f0f));
		if (get_fpscr() != fpscr)
			return 16 * i + 16;
		asm("mtfsf 0xaa,7,0,0");
		fpscr = fpscr_eval((fpscr & 0x0f0f0f0f) | (fsi & 0xf0f0f0f0));
		if (get_fpscr() != fpscr)
			return 16 * i + 17;
		asm("mffs. 6; mfcr %0" : "=r" (cr) : : "cr1");
		if (((cr >> 24) & 0xf) != ((fpscr >> 28) & 0x1f))
			return 16 * i + 18;
		asm("mffsce 12; stfd 12,0(%0)" : : "b" (&fso) : "memory");
		if (fso != fpscr)
			return 16 * i + 19;
		fpscr = fpscr_eval(fpscr & ~0xf8);
		if (get_fpscr() != fpscr)
			return 16 * i + 20;
		asm("lfd 7,0(%0); mtfsf 0xff,7,0,0" : : "b" (&fsi));
		fpscr = fpscr_eval(fsi);
		fsi = ~fsi;
		asm("lfd 14,0(%0); mffscrn 15,14; stfd 15,0(%1)"
		    : : "b" (&fsi), "b" (&fso) : "memory");
		if (fso != (fpscr & 0xff))
			return 16 * i + 21;
		fpscr = (fpscr & ~3) | (fsi & 3);
		if (get_fpscr() != fpscr)
			return 16 * i + 22;
		fso = ~fso;
		asm("mffscrni 16,1; stfd 16,0(%0)" : : "b" (&fso) : "memory");
		if (fso != (fpscr & 0xff))
			return 16 * i + 23;
		fpscr = (fpscr & ~3) | 1;
		if (get_fpscr() != fpscr)
			return 16 * i + 24;
		asm("mffsl 17; stfd 17,0(%0)" : : "b" (&fso) : "memory");
		mask = ((1 << (63-45+1)) - (1 << (63-51))) | ((1 << (63-56+1)) - (1 << (63-63)));
		if (fso != (fpscr & mask))
			return 16 * i + 25;
		asm("mcrfs 0,3; mcrfs 7,0; mfcr %0" : "=r" (cr) : : "cr0", "cr7");
		fso = fpscr_eval(fpscr & ~0x80000);
		if (((cr >> 28) & 0xf) != ((fpscr >> 16) & 0xf) ||
		    ((cr >> 0) & 0xf) != ((fso >> 28) & 0xf))
			return 16 * i + 26;
		fpscr = fso & 0x6fffffff;
		asm("mtfsfi 0,7,0");
		fpscr = fpscr_eval((fpscr & 0x0fffffff) | 0x70000000);
		if (get_fpscr() != fpscr)
			return 16 * i + 27;
		asm("mtfsb0 21");
		fpscr = fpscr_eval(fpscr & ~(1 << (31-21)));
		if (get_fpscr() != fpscr)
			return 16 * i + 28;
		asm("mtfsb1 21");
		fpscr = fpscr_eval(fpscr | (1 << (31-21)));
		if (get_fpscr() != fpscr)
			return 16 * i + 29;
		asm("mtfsb0 24");
		fpscr = fpscr_eval(fpscr & ~(1 << (31-24)));
		if (get_fpscr() != fpscr)
			return 16 * i + 30;
		asm("mtfsb1. 24; mfcr %0" : "=r" (cr));
		fpscr = fpscr_eval(fpscr | (1 << (31-24)));
		if (get_fpscr() != fpscr || ((cr >> 24) & 0xf) != ((fpscr >> 28) & 0xf))
			return 16 * i + 31;
	}
	return 0;
}

int fpu_test_4(void)
{
	enable_fp();
	return trapit(0, test4);
}

int test5a(long arg)
{
	set_fpscr(0);
	enable_fp_interrupts();
	set_fpscr(0x80);	/* set VE */
	set_fpscr(0x480);	/* set VXSOFT */
	set_fpscr(0);
	return 1;		/* not supposed to get here */
}

int test5b(long arg)
{
	unsigned long msr;

	enable_fp();
	set_fpscr(0x80);	/* set VE */
	set_fpscr(0x480);	/* set VXSOFT */
	asm("mfmsr %0" : "=r" (msr));
	msr |= MSR_FE0 | MSR_FE1;
	asm("mtmsrd %0; xori 4,4,0" : : "r" (msr));
	set_fpscr(0);
	return 1;		/* not supposed to get here */
}

int test5c(long arg)
{
	unsigned long msr;

	enable_fp();
	set_fpscr(0x80);	/* set VE */
	set_fpscr(0x480);	/* set VXSOFT */
	asm("mfmsr %0" : "=r" (msr));
	msr |= MSR_FE0 | MSR_FE1;
	do_rfid(msr);
	set_fpscr(0);
	return 1;		/* not supposed to get here */
}

int fpu_test_5(void)
{
	int ret;
	unsigned int *ip;

	enable_fp();
	ret = trapit(0, test5a);
	if (ret != 0x700)
		return 1;
	ip = (unsigned int *)mfspr(SRR0);
	/* check it's a mtfsf 0,7,1,0 instruction */
	if (*ip != (63u << 26) + (1 << 25) + (7 << 11) + (711 << 1))
		return 2;
	if ((mfspr(SRR1) & 0x783f0000) != (1 << (63 - 43)))
		return 3;

	ret = trapit(0, test5b);
	if (ret != 0x700)
		return 4;
	ip = (unsigned int *)mfspr(SRR0);
	/* check it's an xori 4,4,0 instruction */
	if (*ip != 0x68840000)
		return 5;
	if ((mfspr(SRR1) & 0x783f0000) != (1 << (63 - 43)) + (1 << (63 - 47)))
		return 6;

	ret = trapit(0, test5c);
	if (ret != 0x700)
		return 7;
	ip = (unsigned int *)mfspr(SRR0);
	/* check it's the destination of the rfid */
	if (ip != (void *)&do_blr)
		return 8;
	if ((mfspr(SRR1) & 0x783f0000) != (1 << (63 - 43)) + (1 << (63 - 47)))
		return 9;

	return 0;
}

#define SIGN	0x8000000000000000ul

int test6(long arg)
{
	long i;
	unsigned long results[6];
	unsigned long v;

	for (i = 0; i < sizeof(sp_dp_equiv) / sizeof(sp_dp_equiv[0]); ++i) {
		v = sp_dp_equiv[i].dp;
		asm("lfd%U0%X0 3,%0; fmr 6,3; fneg 7,3; stfd 6,0(%1); stfd 7,8(%1)"
		    : : "m" (sp_dp_equiv[i].dp), "b" (results) : "memory");
		asm("fabs 9,6; fnabs 10,6; stfd 9,16(%0); stfd 10,24(%0)"
		    : : "b" (results) : "memory");
		asm("fcpsgn 4,9,3; stfd 4,32(%0); fcpsgn 5,10,3; stfd 5,40(%0)"
		    : : "b" (results) : "memory");
		if (results[0] != v ||
		    results[1] != (v ^ SIGN) ||
		    results[2] != (v & ~SIGN) ||
		    results[3] != (v | SIGN) ||
		    results[4] != (v & ~SIGN) ||
		    results[5] != (v | SIGN))
			return i + 1;
	}
	return 0;
}

struct int_fp_equiv {
	long		ival;
	unsigned long	fp;
	unsigned long	fp_u;
	unsigned long	fp_s;
	unsigned long	fp_us;
} intvals[] = {
	{ 0,  0, 0, 0, 0 },
	{ 1,  0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
	{ -1, 0xbff0000000000000, 0x43f0000000000000, 0xbff0000000000000, 0x43f0000000000000 },
	{ 2,  0x4000000000000000, 0x4000000000000000, 0x4000000000000000, 0x4000000000000000 },
	{ -2, 0xc000000000000000, 0x43f0000000000000, 0xc000000000000000, 0x43f0000000000000 },
	{ 0x12345678, 0x41b2345678000000, 0x41b2345678000000, 0x41b2345680000000, 0x41b2345680000000 },
	{ 0x0008000000000000, 0x4320000000000000, 0x4320000000000000, 0x4320000000000000, 0x4320000000000000 },
	{ 0x0010000000000000, 0x4330000000000000, 0x4330000000000000, 0x4330000000000000, 0x4330000000000000 },
	{ 0x0020000000000000, 0x4340000000000000, 0x4340000000000000, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000000000001, 0x4340000000000000, 0x4340000000000000, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000000000002, 0x4340000000000001, 0x4340000000000001, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000000000003, 0x4340000000000002, 0x4340000000000002, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000010000000, 0x4340000008000000, 0x4340000008000000, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000020000000, 0x4340000010000000, 0x4340000010000000, 0x4340000000000000, 0x4340000000000000 },
	{ 0x0020000030000000, 0x4340000018000000, 0x4340000018000000, 0x4340000020000000, 0x4340000020000000 },
	{ 0x0020000040000000, 0x4340000020000000, 0x4340000020000000, 0x4340000020000000, 0x4340000020000000 },
	{ 0x0020000080000000, 0x4340000040000000, 0x4340000040000000, 0x4340000040000000, 0x4340000040000000 },
	{ 0x0040000000000000, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000001, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000002, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000003, 0x4350000000000001, 0x4350000000000001, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000004, 0x4350000000000001, 0x4350000000000001, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000005, 0x4350000000000001, 0x4350000000000001, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000006, 0x4350000000000002, 0x4350000000000002, 0x4350000000000000, 0x4350000000000000 },
	{ 0x0040000000000007, 0x4350000000000002, 0x4350000000000002, 0x4350000000000000, 0x4350000000000000 },
};

int test7(long arg)
{
	long i;
	unsigned long results[4];

	for (i = 0; i < sizeof(intvals) / sizeof(intvals[0]); ++i) {
		asm("lfd%U0%X0 3,%0; fcfid 6,3; fcfidu 7,3; stfd 6,0(%1); stfd 7,8(%1)"
		    : : "m" (intvals[i].ival), "b" (results) : "memory");
		asm("fcfids 9,3; stfd 9,16(%0); fcfidus 10,3; stfd 10,24(%0)"
		    : : "b" (results) : "memory");
		if (results[0] != intvals[i].fp ||
		    results[1] != intvals[i].fp_u ||
		    results[2] != intvals[i].fp_s ||
		    results[3] != intvals[i].fp_us) {
			print_string("\r\n");
			print_hex(results[0], 16, " ");
			print_hex(results[1], 16, " ");
			print_hex(results[2], 16, " ");
			print_hex(results[3], 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_6(void)
{
	enable_fp();
	return trapit(0, test6);
}

int fpu_test_7(void)
{
	enable_fp();
	return trapit(0, test7);
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
		print_hex(ret, 5, " SRR0=");
		print_hex(mfspr(SRR0), 16, " SRR1=");
		print_hex(mfspr(SRR1), 16, "\r\n");
	}
}

int main(void)
{
	console_init();

	do_test(1, fpu_test_1);
	do_test(2, fpu_test_2);
	do_test(3, fpu_test_3);
	do_test(4, fpu_test_4);
	do_test(5, fpu_test_5);
	do_test(6, fpu_test_6);
	do_test(7, fpu_test_7);

	return fail;
}
