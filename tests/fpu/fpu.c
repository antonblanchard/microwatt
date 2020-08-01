#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define asm	__asm__ volatile

#define MSR_FP	0x2000
#define MSR_FE0	0x800
#define MSR_FE1	0x100

#define FPS_RN_NEAR	0
#define FPS_RN_ZERO	1
#define FPS_RN_CEIL	2
#define FPS_RN_FLOOR	3
#define FPS_XE		0x8
#define FPS_ZE		0x10
#define FPS_UE		0x20
#define FPS_OE		0x40
#define FPS_VE		0x80
#define FPS_VXCVI	0x100
#define FPS_VXSOFT	0x400

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
	{ 0x7f7fffff, 0x47efffffe0000000 },
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
	set_fpscr(FPS_VE);		/* set VE */
	set_fpscr(FPS_VXSOFT | FPS_VE);	/* set VXSOFT */
	set_fpscr(0);
	return 1;		/* not supposed to get here */
}

int test5b(long arg)
{
	unsigned long msr;

	enable_fp();
	set_fpscr(FPS_VE);		/* set VE */
	set_fpscr(FPS_VXSOFT | FPS_VE);	/* set VXSOFT */
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
	set_fpscr(FPS_VE);		/* set VE */
	set_fpscr(FPS_VXSOFT | FPS_VE);	/* set VXSOFT */
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

int fpu_test_6(void)
{
	enable_fp();
	return trapit(0, test6);
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

int fpu_test_7(void)
{
	enable_fp();
	return trapit(0, test7);
}

struct roundvals {
	unsigned long fpscr;
	unsigned long dpval;
	unsigned long spval;
} roundvals[] = {
	{ FPS_RN_NEAR,  0, 0 },
	{ FPS_RN_CEIL,  0x8000000000000000, 0x8000000000000000 },
	{ FPS_RN_NEAR,  0x402123456789abcd, 0x4021234560000000 },
	{ FPS_RN_ZERO,  0x402123456789abcd, 0x4021234560000000 },
	{ FPS_RN_CEIL,  0x402123456789abcd, 0x4021234580000000 },
	{ FPS_RN_FLOOR, 0x402123456789abcd, 0x4021234560000000 },
	{ FPS_RN_NEAR,  0x402123457689abcd, 0x4021234580000000 },
	{ FPS_RN_ZERO,  0x402123457689abcd, 0x4021234560000000 },
	{ FPS_RN_CEIL,  0x402123457689abcd, 0x4021234580000000 },
	{ FPS_RN_FLOOR, 0x402123457689abcd, 0x4021234560000000 },
	{ FPS_RN_NEAR,  0x4021234570000000, 0x4021234580000000 },
	{ FPS_RN_NEAR,  0x4021234550000000, 0x4021234540000000 },
	{ FPS_RN_NEAR,  0x7ff123456789abcd, 0x7ff9234560000000 },
	{ FPS_RN_ZERO,  0x7ffa3456789abcde, 0x7ffa345660000000 },
	{ FPS_RN_FLOOR, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ FPS_RN_NEAR,  0x47e1234550000000, 0x47e1234540000000 },
	{ FPS_RN_NEAR,  0x47f1234550000000, 0x7ff0000000000000 },
	{ FPS_RN_ZERO,  0x47f1234550000000, 0x47efffffe0000000 },
	{ FPS_RN_CEIL,  0x47f1234550000000, 0x7ff0000000000000 },
	{ FPS_RN_FLOOR, 0x47f1234550000000, 0x47efffffe0000000 },
	{ FPS_RN_NEAR,  0x38012345b0000000, 0x38012345c0000000 },
	{ FPS_RN_NEAR,  0x37c12345b0000000, 0x37c1234400000000 },
};

int test8(long arg)
{
	long i;
	unsigned long result;

	for (i = 0; i < sizeof(roundvals) / sizeof(roundvals[0]); ++i) {
		asm("lfd 3,0(%0); lfd 4,8(%0); mtfsf 0,3,1,0; frsp 6,4; stfd 6,0(%1)"
		    : : "b" (&roundvals[i]), "b" (&result) : "memory");
		if (result != roundvals[i].spval) {
			print_string("\r\n");
			print_hex(i, 4, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_8(void)
{
	enable_fp();
	return trapit(0, test8);
}

struct cvtivals {
	unsigned long dval;
	long lval;
	unsigned long ulval;
	int ival;
	unsigned int uival;
	unsigned char invalids[4];
} cvtivals[] = {
	{ 0x0000000000000000, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x8000000000000000, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x3fdfffffffffffff, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x3ff0000000000000, 1, 1, 1, 1, {0, 0, 0, 0} },
	{ 0xbff0000000000000, -1, 0, -1, 0, {0, 1, 0, 1} },
	{ 0x402123456789abcd, 9, 9, 9, 9, {0, 0, 0, 0} },
	{ 0x406123456789abcd, 137, 137, 137, 137, {0, 0, 0, 0} },
	{ 0x409123456789abcd, 1097, 1097, 1097, 1097, {0, 0, 0, 0} },
	{ 0x41c123456789abcd, 0x22468acf, 0x22468acf, 0x22468acf, 0x22468acf, {0, 0, 0, 0} },
	{ 0x41d123456789abcd, 0x448d159e, 0x448d159e, 0x448d159e, 0x448d159e, {0, 0, 0, 0} },
	{ 0x41e123456789abcd, 0x891a2b3c, 0x891a2b3c, 0x7fffffff, 0x891a2b3c, {0, 0, 1, 0} },
	{ 0x41f123456789abcd, 0x112345679, 0x112345679, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0xc1f123456789abcd, -0x112345679, 0, 0x80000000, 0, {0, 1, 1, 1} },
	{ 0x432123456789abcd, 0x891a2b3c4d5e6, 0x891a2b3c4d5e6, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x433123456789abcd, 0x1123456789abcd, 0x1123456789abcd, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x434123456789abcd, 0x22468acf13579a, 0x22468acf13579a, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43c123456789abcd, 0x22468acf13579a00, 0x22468acf13579a00, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43d123456789abcd, 0x448d159e26af3400, 0x448d159e26af3400, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43e123456789abcd, 0x7fffffffffffffff, 0x891a2b3c4d5e6800, 0x7fffffff, 0xffffffff, {1, 0, 1, 1} },
	{ 0x43f123456789abcd, 0x7fffffffffffffff, 0xffffffffffffffff, 0x7fffffff, 0xffffffff, {1, 1, 1, 1} },
	{ 0xc3f123456789abcd, 0x8000000000000000, 0, 0x80000000, 0, {1, 1, 1, 1} },
	{ 0x7ff0000000000000, 0x7fffffffffffffff, 0xffffffffffffffff, 0x7fffffff, 0xffffffff, {1, 1, 1, 1} },
	{ 0xfff0000000000000, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
	{ 0x7ff923456789abcd, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
	{ 0xfff923456789abcd, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
	{ 0xbfd123456789abcd, 0, 0, 0, 0, {0, 0, 0, 0} },
};

#define GET_VXCVI()	((get_fpscr() >> 8) & 1)

int test9(long arg)
{
	long i;
	int ires;
	unsigned int ures;
	long lres;
	unsigned long ulres;
	unsigned char inv[4];
	struct cvtivals *vp = cvtivals;

	for (i = 0; i < sizeof(cvtivals) / sizeof(cvtivals[0]); ++i, ++vp) {
		set_fpscr(FPS_RN_NEAR);
		asm("lfd 3,0(%0); fctid 4,3; stfd 4,0(%1)"
		    : : "b" (&vp->dval), "b" (&lres) : "memory");
		inv[0] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctidu 5,3; stfd 5,0(%0)" : : "b" (&ulres) : "memory");
		inv[1] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctiw 6,3; stfiwx 6,0,%0" : : "b" (&ires) : "memory");
		inv[2] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctiwu 7,3; stfiwx 7,0,%0" : : "b" (&ures) : "memory");
		inv[3] = GET_VXCVI();

		if (lres != vp->lval || ulres != vp->ulval || ires != vp->ival || ures != vp->uival ||
		    inv[0] != vp->invalids[0] || inv[1] != vp->invalids[1] ||
		    inv[2] != vp->invalids[2] || inv[3] != vp->invalids[3]) {
			print_hex(lres, 16, inv[0]? "V ": "  ");
			print_hex(ulres, 16, inv[1]? "V ": "  ");
			print_hex(ires, 8, inv[2]? "V ": "  ");
			print_hex(ures, 8, inv[3]? "V ": "  ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_9(void)
{
	enable_fp();
	return trapit(0, test9);
}

struct cvtivals cvtizvals[] = {
	{ 0x0000000000000000, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x8000000000000000, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x3fdfffffffffffff, 0, 0, 0, 0, {0, 0, 0, 0} },
	{ 0x3ff0000000000000, 1, 1, 1, 1, {0, 0, 0, 0} },
	{ 0xbff0000000000000, -1, 0, -1, 0, {0, 1, 0, 1} },
	{ 0x402123456789abcd, 8, 8, 8, 8, {0, 0, 0, 0} },
	{ 0x406123456789abcd, 137, 137, 137, 137, {0, 0, 0, 0} },
	{ 0x409123456789abcd, 1096, 1096, 1096, 1096, {0, 0, 0, 0} },
	{ 0x41c123456789abcd, 0x22468acf, 0x22468acf, 0x22468acf, 0x22468acf, {0, 0, 0, 0} },
	{ 0x41d123456789abcd, 0x448d159e, 0x448d159e, 0x448d159e, 0x448d159e, {0, 0, 0, 0} },
	{ 0x41e123456789abcd, 0x891a2b3c, 0x891a2b3c, 0x7fffffff, 0x891a2b3c, {0, 0, 1, 0} },
	{ 0x41f123456789abcd, 0x112345678, 0x112345678, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0xc1f123456789abcd, -0x112345678, 0, 0x80000000, 0, {0, 1, 1, 1} },
	{ 0x432123456789abcd, 0x891a2b3c4d5e6, 0x891a2b3c4d5e6, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x433123456789abcd, 0x1123456789abcd, 0x1123456789abcd, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x434123456789abcd, 0x22468acf13579a, 0x22468acf13579a, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43c123456789abcd, 0x22468acf13579a00, 0x22468acf13579a00, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43d123456789abcd, 0x448d159e26af3400, 0x448d159e26af3400, 0x7fffffff, 0xffffffff, {0, 0, 1, 1} },
	{ 0x43e123456789abcd, 0x7fffffffffffffff, 0x891a2b3c4d5e6800, 0x7fffffff, 0xffffffff, {1, 0, 1, 1} },
	{ 0x43f123456789abcd, 0x7fffffffffffffff, 0xffffffffffffffff, 0x7fffffff, 0xffffffff, {1, 1, 1, 1} },
	{ 0xc3f123456789abcd, 0x8000000000000000, 0, 0x80000000, 0, {1, 1, 1, 1} },
	{ 0x7ff0000000000000, 0x7fffffffffffffff, 0xffffffffffffffff, 0x7fffffff, 0xffffffff, {1, 1, 1, 1} },
	{ 0xfff0000000000000, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
	{ 0x7ff923456789abcd, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
	{ 0xfff923456789abcd, 0x8000000000000000, 0, 0x80000000, 0, { 1, 1, 1, 1 } },
};

int test10(long arg)
{
	long i;
	int ires;
	unsigned int ures;
	long lres;
	unsigned long ulres;
	unsigned char inv[4];
	struct cvtivals *vp = cvtizvals;

	for (i = 0; i < sizeof(cvtizvals) / sizeof(cvtizvals[0]); ++i, ++vp) {
		set_fpscr(FPS_RN_NEAR);
		asm("lfd 3,0(%0); fctidz 4,3; stfd 4,0(%1)"
		    : : "b" (&vp->dval), "b" (&lres) : "memory");
		inv[0] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctiduz 5,3; stfd 5,0(%0)" : : "b" (&ulres) : "memory");
		inv[1] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctiwz 6,3; stfiwx 6,0,%0" : : "b" (&ires) : "memory");
		inv[2] = GET_VXCVI();
		set_fpscr(FPS_RN_NEAR);
		asm("fctiwuz 7,3; stfiwx 7,0,%0" : : "b" (&ures) : "memory");
		inv[3] = GET_VXCVI();

		if (lres != vp->lval || ulres != vp->ulval || ires != vp->ival || ures != vp->uival ||
		    inv[0] != vp->invalids[0] || inv[1] != vp->invalids[1] ||
		    inv[2] != vp->invalids[2] || inv[3] != vp->invalids[3]) {
			print_hex(lres, 16, inv[0]? "V ": "  ");
			print_hex(ulres, 16, inv[1]? "V ": "  ");
			print_hex(ires, 8, inv[2]? "V ": "  ");
			print_hex(ures, 8, inv[3]? "V ": "  ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_10(void)
{
	enable_fp();
	return trapit(0, test10);
}

struct frivals {
	unsigned long val;
	unsigned long nval;
	unsigned long zval;
	unsigned long pval;
	unsigned long mval;
} frivals[] = {
	{ 0x0000000000000000, 0, 0, 0, 0 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x8000000000000000 },
	{ 0x3fdfffffffffffff, 0, 0, 0x3ff0000000000000, 0 },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
	{ 0xbff0000000000000, 0xbff0000000000000, 0xbff0000000000000, 0xbff0000000000000, 0xbff0000000000000 },
	{ 0x402123456789abcd, 0x4022000000000000, 0x4020000000000000, 0x4022000000000000, 0x4020000000000000 },
	{ 0x406123456789abcd, 0x4061200000000000, 0x4061200000000000, 0x4061400000000000, 0x4061200000000000 },
	{ 0x409123456789abcd, 0x4091240000000000, 0x4091200000000000, 0x4091240000000000, 0x4091200000000000 },
	{ 0x41c123456789abcd, 0x41c1234567800000, 0x41c1234567800000, 0x41c1234568000000, 0x41c1234567800000 },
	{ 0x41d123456789abcd, 0x41d1234567800000, 0x41d1234567800000, 0x41d1234567c00000, 0x41d1234567800000 },
	{ 0x41e123456789abcd, 0x41e1234567800000, 0x41e1234567800000, 0x41e1234567a00000, 0x41e1234567800000 },
	{ 0x41f123456789abcd, 0x41f1234567900000, 0x41f1234567800000, 0x41f1234567900000, 0x41f1234567800000 },
	{ 0xc1f123456789abcd, 0xc1f1234567900000, 0xc1f1234567800000, 0xc1f1234567800000, 0xc1f1234567900000 },
	{ 0xc1f1234567880000, 0xc1f1234567900000, 0xc1f1234567800000, 0xc1f1234567800000, 0xc1f1234567900000 },
	{ 0x432123456789abcd, 0x432123456789abce, 0x432123456789abcc, 0x432123456789abce, 0x432123456789abcc },
	{ 0x433123456789abcd, 0x433123456789abcd, 0x433123456789abcd, 0x433123456789abcd, 0x433123456789abcd },
	{ 0x434123456789abcd, 0x434123456789abcd, 0x434123456789abcd, 0x434123456789abcd, 0x434123456789abcd },
	{ 0x43c123456789abcd, 0x43c123456789abcd, 0x43c123456789abcd, 0x43c123456789abcd, 0x43c123456789abcd },
	{ 0x43d123456789abcd, 0x43d123456789abcd, 0x43d123456789abcd, 0x43d123456789abcd, 0x43d123456789abcd },
	{ 0x43e123456789abcd, 0x43e123456789abcd, 0x43e123456789abcd, 0x43e123456789abcd, 0x43e123456789abcd },
	{ 0x43f123456789abcd, 0x43f123456789abcd, 0x43f123456789abcd, 0x43f123456789abcd, 0x43f123456789abcd },
	{ 0xc3f123456789abcd, 0xc3f123456789abcd, 0xc3f123456789abcd, 0xc3f123456789abcd, 0xc3f123456789abcd },
	{ 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0xfff0000000000000, 0xfff0000000000000, 0xfff0000000000000, 0xfff0000000000000, 0xfff0000000000000 },
	{ 0x7ff123456789abcd, 0x7ff923456789abcd, 0x7ff923456789abcd, 0x7ff923456789abcd, 0x7ff923456789abcd },
	{ 0xfff923456789abcd, 0xfff923456789abcd, 0xfff923456789abcd, 0xfff923456789abcd, 0xfff923456789abcd },
};

int test11(long arg)
{
	long i;
	unsigned long results[4];
	struct frivals *vp = frivals;

	for (i = 0; i < sizeof(frivals) / sizeof(frivals[0]); ++i, ++vp) {
		set_fpscr(FPS_RN_FLOOR);
		asm("lfd 3,0(%0); frin 4,3; stfd 4,0(%1)"
		    : : "b" (&vp->val), "b" (results) : "memory");
		set_fpscr(FPS_RN_NEAR);
		asm("friz 5,3; stfd 5,8(%0)" : : "b" (results) : "memory");
		set_fpscr(FPS_RN_ZERO);
		asm("frip 5,3; stfd 5,16(%0)" : : "b" (results) : "memory");
		set_fpscr(FPS_RN_CEIL);
		asm("frim 5,3; stfd 5,24(%0)" : : "b" (results) : "memory");
		if (results[0] != vp->nval || results[1] != vp->zval ||
		    results[2] != vp->pval || results[3] != vp->mval) {
			print_hex(i, 2, "\r\n");
			print_hex(results[0], 16, " ");
			print_hex(results[1], 16, " ");
			print_hex(results[2], 16, " ");
			print_hex(results[3], 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_11(void)
{
	enable_fp();
	return trapit(0, test11);
}

int test12(long arg)
{
	unsigned long vals[2];
	unsigned long results[2];

	vals[0] = 0xf0f0f0f05a5a5a5aul;
	vals[1] = 0x0123456789abcdeful;
	asm("lfd 5,0(%0); lfd 6,8(%0); fmrgew 7,5,6; fmrgow 8,5,6; stfd 7,0(%1); stfd 8,8(%1)"
	    : : "b" (vals), "b" (results) : "memory");
	if (results[0] != 0xf0f0f0f001234567ul || results[1] != 0x5a5a5a5a89abcdeful)
		return 1;
	return 0;
}

int fpu_test_12(void)
{
	enable_fp();
	return trapit(0, test12);
}

struct addvals {
	unsigned long val_a;
	unsigned long val_b;
	unsigned long sum;
	unsigned long diff;
} addvals[] = {
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x3fdfffffffffffff, 0x0000000000000000, 0x3fdfffffffffffff, 0x3fdfffffffffffff },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x4000000000000000, 0x0000000000000000 },
	{ 0xbff0000000000000, 0xbff0000000000000, 0xc000000000000000, 0x0000000000000000 },
	{ 0x402123456789abcd, 0x4021000000000000, 0x403111a2b3c4d5e6, 0x3fb1a2b3c4d5e680 },
	{ 0x4061200000000000, 0x406123456789abcd, 0x407121a2b3c4d5e6, 0xbfba2b3c4d5e6800 },
	{ 0x4061230000000000, 0x3fa4560000000000, 0x4061244560000000, 0x406121baa0000000 },
	{ 0xc061230000000000, 0x3fa4560000000000, 0xc06121baa0000000, 0xc061244560000000 },
	{ 0x4061230000000000, 0xbfa4560000000000, 0x406121baa0000000, 0x4061244560000000 },
	{ 0xc061230000000000, 0xbfa4560000000000, 0xc061244560000000, 0xc06121baa0000000 },
	{ 0x3fa1230000000000, 0x4064560000000000, 0x4064571230000000, 0xc06454edd0000000 },
	{ 0xbfa1230000000000, 0x4064560000000000, 0x406454edd0000000, 0xc064571230000000 },
	{ 0x3fa1230000000000, 0xc064560000000000, 0xc06454edd0000000, 0x4064571230000000 },
	{ 0xbfa1230000000000, 0xc064560000000000, 0xc064571230000000, 0x406454edd0000000 },
	{ 0x6780000000000001, 0x6470000000000000, 0x6780000000000009, 0x677ffffffffffff2 },
	{ 0x6780000000000001, 0x6460000000000000, 0x6780000000000005, 0x677ffffffffffffa },
	{ 0x6780000000000001, 0x6450000000000000, 0x6780000000000003, 0x677ffffffffffffe },
	{ 0x6780000000000001, 0x6440000000000000, 0x6780000000000002, 0x6780000000000000 },
	{ 0x7ff8888888888888, 0x7ff9999999999999, 0x7ff8888888888888, 0x7ff8888888888888 },
	{ 0xfff8888888888888, 0x7ff9999999999999, 0xfff8888888888888, 0xfff8888888888888 },
	{ 0x7ff8888888888888, 0x7ff0000000000000, 0x7ff8888888888888, 0x7ff8888888888888 },
	{ 0x7ff8888888888888, 0x0000000000000000, 0x7ff8888888888888, 0x7ff8888888888888 },
	{ 0x7ff8888888888888, 0x0001111111111111, 0x7ff8888888888888, 0x7ff8888888888888 },
	{ 0x7ff8888888888888, 0x3ff0000000000000, 0x7ff8888888888888, 0x7ff8888888888888 },
	{ 0x7ff0000000000000, 0x7ff9999999999999, 0x7ff9999999999999, 0x7ff9999999999999 },
	{ 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x0000000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x8000000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x8002222222222222, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0xc002222222222222, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x0000000000000000, 0x7ff9999999999999, 0x7ff9999999999999, 0x7ff9999999999999 },
	{ 0x0000000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000 },
	{ 0x8000000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000 },
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x8002222222222222, 0x0001111111111111, 0x8001111111111111, 0x8003333333333333 },
	{ 0x0000022222222222, 0x0000111111111111, 0x0000133333333333, 0x80000eeeeeeeeeef },
	{ 0x401ffffffbfffefe, 0x406b8265196bd89e, 0x406c8265194bd896, 0xc06a8265198bd8a6 },
	{ 0x4030020000000004, 0xbf110001ffffffff, 0x403001fbbfff8004, 0x4030020440008004 },
	{ 0x3fdfffffffffffff, 0x3fe0000000000000, 0x3ff0000000000000, 0xbc90000000000000 },
};

int test13(long arg)
{
	long i;
	unsigned long results[2];
	struct addvals *vp = addvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(addvals) / sizeof(addvals[0]); ++i, ++vp) {
		asm("lfd 5,0(%0); lfd 6,8(%0); fadd 7,5,6; fsub 8,5,6; stfd 7,0(%1); stfd 8,8(%1)"
		    : : "b" (&vp->val_a), "b" (results) : "memory");
		if (results[0] != vp->sum || results[1] != vp->diff) {
			print_hex(i, 2, " ");
			print_hex(results[0], 16, " ");
			print_hex(results[1], 16, "\r\n");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_13(void)
{
	enable_fp();
	return trapit(0, test13);
}

struct addvals sp_addvals[] = {
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x3fdfffffffffffff, 0x0000000000000000, 0x3fe0000000000000, 0x3fe0000000000000 },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x4000000000000000, 0x0000000000000000 },
	{ 0xbff0000000000000, 0xbff0000000000000, 0xc000000000000000, 0x0000000000000000 },
	{ 0x402123456789abcd, 0x4021000000000000, 0x403111a2c0000000, 0x3fb1a2b000000000 },
	{ 0x4061200000000000, 0x406123456789abcd, 0x407121a2c0000000, 0xbfba2b0000000000 },
	{ 0x4061230000000000, 0x3fa4560000000000, 0x4061244560000000, 0x406121baa0000000 },
	{ 0xc061230000000000, 0x3fa4560000000000, 0xc06121baa0000000, 0xc061244560000000 },
	{ 0x4061230000000000, 0xbfa4560000000000, 0x406121baa0000000, 0x4061244560000000 },
	{ 0xc061230000000000, 0xbfa4560000000000, 0xc061244560000000, 0xc06121baa0000000 },
	{ 0x3fa1230000000000, 0x4064560000000000, 0x4064571240000000, 0xc06454edc0000000 },
	{ 0xbfa1230000000000, 0x4064560000000000, 0x406454edc0000000, 0xc064571240000000 },
	{ 0x3fa1230000000000, 0xc064560000000000, 0xc06454edc0000000, 0x4064571240000000 },
	{ 0xbfa1230000000000, 0xc064560000000000, 0xc064571240000000, 0x406454edc0000000 },
	{ 0x6780000000000001, 0x6470000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x6780000000000001, 0x6460000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x6780000000000001, 0x6450000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x6780000000000001, 0x6440000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x7ff8888888888888, 0x7ff9999999999999, 0x7ff8888880000000, 0x7ff8888880000000 },
	{ 0xfff8888888888888, 0x7ff9999999999999, 0xfff8888880000000, 0xfff8888880000000 },
	{ 0x7ff8888888888888, 0x7ff0000000000000, 0x7ff8888880000000, 0x7ff8888880000000 },
	{ 0x7ff8888888888888, 0x0000000000000000, 0x7ff8888880000000, 0x7ff8888880000000 },
	{ 0x7ff8888888888888, 0x0001111111111111, 0x7ff8888880000000, 0x7ff8888880000000 },
	{ 0x7ff8888888888888, 0x3ff0000000000000, 0x7ff8888880000000, 0x7ff8888880000000 },
	{ 0x7ff0000000000000, 0x7ff9999999999999, 0x7ff9999980000000, 0x7ff9999980000000 },
	{ 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0x7ff8000000000000 },
	{ 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x0000000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x8000000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x8002222222222222, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0xc002222222222222, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x0000000000000000, 0x7ff9999999999999, 0x7ff9999980000000, 0x7ff9999980000000 },
	{ 0x0000000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000 },
	{ 0x8000000000000000, 0x7ff0000000000000, 0x7ff0000000000000, 0xfff0000000000000 },
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x8002222222222222, 0x0001111111111111, 0x0000000000000000, 0x8000000000000000 },
	{ 0x0000022222222222, 0x0000111111111111, 0x0000000000000000, 0x0000000000000000 },
	{ 0x47dc000020000000, 0x47ec03ffe0000000, 0x7ff0000000000000, 0xc7dc07ffa0000000 },
	{ 0x47dbffffe0000000, 0x47eff7ffe0000000, 0x7ff0000000000000, 0xc7e1f80000000000 },
	{ 0x47efffffc0000000, 0xc7efffffc0000000, 0x0000000000000000, 0x7ff0000000000000 },
};

int test14(long arg)
{
	long i;
	unsigned long results[2];
	struct addvals *vp = sp_addvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(sp_addvals) / sizeof(sp_addvals[0]); ++i, ++vp) {
		asm("lfd 5,0(%0); frsp 5,5; lfd 6,8(%0); frsp 6,6; "
		    "fadds 7,5,6; fsubs 8,5,6; stfd 7,0(%1); stfd 8,8(%1)"
		    : : "b" (&vp->val_a), "b" (results) : "memory");
		if (results[0] != vp->sum || results[1] != vp->diff) {
			print_hex(i, 2, " ");
			print_hex(results[0], 16, " ");
			print_hex(results[1], 16, "\r\n");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_14(void)
{
	enable_fp();
	return trapit(0, test14);
}

struct mulvals {
	unsigned long val_a;
	unsigned long val_b;
	unsigned long prod;
} mulvals[] = {
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000, 0x0000000000000000 },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
	{ 0xbff0000000000000, 0x3ff0000000000000, 0xbff0000000000000 },
	{ 0xbf4fff801fffffff, 0x6d7fffff8000007f, 0xecdfff7fa001fffe },
	{ 0x3fbd50275a65ed80, 0x0010000000000000, 0x0001d50275a65ed8 },
	{ 0x3fe95d8937acf1ce, 0x0000000000000001, 0x0000000000000001 },
};

int test15(long arg)
{
	long i;
	unsigned long result;
	struct mulvals *vp = mulvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(mulvals) / sizeof(mulvals[0]); ++i, ++vp) {
		asm("lfd 5,0(%0); lfd 6,8(%0); fmul 7,5,6; stfd 7,0(%1)"
		    : : "b" (&vp->val_a), "b" (&result) : "memory");
		if (result != vp->prod) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_15(void)
{
	enable_fp();
	return trapit(0, test15);
}

struct mulvals_sp {
	unsigned int val_a;
	unsigned int val_b;
	unsigned int prod;
} mulvals_sp[] = {
	{ 0x00000000, 0x00000000, 0x00000000 },
	{ 0x80000000, 0x80000000, 0x00000000 },
	{ 0x3f800000, 0x3f800000, 0x3f800000 },
	{ 0xbf800000, 0x3f800000, 0xbf800000 },
	{ 0xbe7ff801, 0x6d7fffff, 0xec7ff800 },
	{ 0xc100003d, 0xfe803ff8, 0x7f800000 },
	{ 0x4f780080, 0x389003ff, 0x488b8427 },
};

int test16(long arg)
{
	long i;
	unsigned int result;
	struct mulvals_sp *vp = mulvals_sp;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(mulvals_sp) / sizeof(mulvals_sp[0]); ++i, ++vp) {
		asm("lfs 5,0(%0); lfs 6,4(%0); fmuls 7,5,6; stfs 7,0(%1)"
		    : : "b" (&vp->val_a), "b" (&result) : "memory");
		if (result != vp->prod) {
			print_hex(i, 2, " ");
			print_hex(result, 8, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_16(void)
{
	enable_fp();
	return trapit(0, test16);
}

struct divvals {
	unsigned long val_a;
	unsigned long val_b;
	unsigned long prod;
} divvals[] = {
	{ 0x3ff0000000000000, 0x0000000000000000, 0x7ff0000000000000 },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000000000000 },
	{ 0xbff0000000000000, 0x3ff0000000000000, 0xbff0000000000000 },
	{ 0x4000000000000000, 0x4008000000000000, 0x3fe5555555555555 },
	{ 0xc01fff0007ffffff, 0xc03ffffffdffffbf, 0x3fcfff0009fff041 },
};

int test17(long arg)
{
	long i;
	unsigned long result;
	struct divvals *vp = divvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(divvals) / sizeof(divvals[0]); ++i, ++vp) {
		asm("lfd 5,0(%0); lfd 6,8(%0); fdiv 7,5,6; stfd 7,0(%1)"
		    : : "b" (&vp->val_a), "b" (&result) : "memory");
		if (result != vp->prod) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_17(void)
{
	enable_fp();
	return trapit(0, test17);
}

struct recipvals {
	unsigned long val;
	unsigned long inv;
} recipvals[] = {
	{ 0x0000000000000000, 0x7ff0000000000000 },
	{ 0xfff0000000000000, 0x8000000000000000 },
	{ 0x3ff0000000000000, 0x3feff00400000000 },
	{ 0xbff0000000000000, 0xbfeff00400000000 },
	{ 0x4008000000000000, 0x3fd54e3800000000 },
	{ 0xc03ffffffdffffbf, 0xbfa0040000000000 },
};

int test18(long arg)
{
	long i;
	unsigned long result;
	struct recipvals *vp = recipvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(recipvals) / sizeof(recipvals[0]); ++i, ++vp) {
		asm("lfd 6,0(%0); fre 7,6; stfd 7,0(%1)"
		    : : "b" (&vp->val), "b" (&result) : "memory");
		if (result != vp->inv) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_18(void)
{
	enable_fp();
	return trapit(0, test18);
}

#define RES_B	0x7ffaaaaaaaaaaaaa
#define RES_C	0x000bbbbbbbbbbbbb

struct selvals {
	unsigned long val;
	unsigned long result;
} selvals[] = {
	{ 0x0000000000000000, RES_C },
	{ 0x8000000000000000, RES_C },
	{ 0x3ff0000000000000, RES_C },
	{ 0xbff0000000000000, RES_B },
	{ 0x7ff0000000000000, RES_C },
	{ 0xfff0000000000000, RES_B },
	{ 0x7ff8000000000000, RES_B },
	{ 0xfff8000000000000, RES_B },
	{ 0x0000000000000001, RES_C },
	{ 0x8000000000000001, RES_B },
	{ 0xffffffffffffffff, RES_B },
};

int test19(long arg)
{
	long i;
	unsigned long result;
	unsigned long frb = RES_B;
	unsigned long frc = RES_C;
	struct selvals *vp = selvals;

	for (i = 0; i < sizeof(selvals) / sizeof(selvals[0]); ++i, ++vp) {
		asm("lfd 6,0(%0); lfd 10,0(%1); lfd 22,0(%2); fsel 0,6,22,10; stfd 0,0(%3)"
		    : : "b" (&vp->val), "b" (&frb), "b" (&frc), "b" (&result) : "memory");
		if (result != vp->result) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_19(void)
{
	enable_fp();
	return trapit(0, test19);
}

#define LT	8
#define GT	4
#define EQ	2
#define UN	1

struct cmpvals {
	unsigned long vala, valb;
	unsigned long result;
} cmpvals[] = {
	{ 0x0000000000000000, 0x0000000000000000, EQ },
	{ 0x8000000000000000, 0x0000000000000000, EQ },
	{ 0x3ff0000000000000, 0x3ff0000000000000, EQ },
	{ 0x3ff0000000000001, 0x3ff0000000000000, GT },
	{ 0x3ff0000000000000, 0x3ff0000000000001, LT },
	{ 0xbff0000000000000, 0x3ff0000000000000, LT },
	{ 0x7ff0000000000000, 0x7ff0000000000000, EQ },
	{ 0xfff0000000000000, 0x7ff0000000000000, LT },
	{ 0x7ff8000000000000, 0x7ff0000000000000, UN },
	{ 0xfff8000000000000, 0x7ff0000000000000, UN },
	{ 0x0000000000000001, 0x0000000000000001, EQ },
	{ 0x8000000000000001, 0x7ff0000000000000, LT },
	{ 0xffffffffffffffff, 0x7ff0000000000000, UN },
	{ 0xffffffffffffffff, 0xffffffffffffffff, UN },
};

int test20(long arg)
{
	long i;
	unsigned long cr;
	struct cmpvals *vp = cmpvals;

	for (i = 0; i < sizeof(cmpvals) / sizeof(cmpvals[0]); ++i, ++vp) {
		asm("lfd 6,0(%1); lfd 10,8(%1); fcmpu 7,6,10; mfcr %0"
		    : "=r" (cr) : "b" (&vp->vala) : "memory");
		cr &= 0xf;
		if (cr != vp->result) {
			print_hex(i, 2, " ");
			print_hex(cr, 1, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_20(void)
{
	enable_fp();
	return trapit(0, test20);
}

struct isqrtvals {
	unsigned long val;
	unsigned long inv;
} isqrtvals[] = {
	{ 0x0000000000000000, 0x7ff0000000000000 },
	{ 0x8000000000000000, 0xfff0000000000000 },
	{ 0xfff0000000000000, 0x7ff8000000000000 },
	{ 0x7ff0000000000000, 0x0000000000000000 },
	{ 0xfff123456789abcd, 0xfff923456789abcd },
	{ 0x3ff0000000000000, 0x3feff80000000000 },
	{ 0x4000000000000000, 0x3fe69dc800000000 },
	{ 0x4010000000000000, 0x3fdff80000000000 },
	{ 0xbff0000000000000, 0x7ff8000000000000 },
	{ 0x4008000000000000, 0x3fe2781800000000 },
	{ 0x7fd0000000000000, 0x1ffff80000000000 },
	{ 0x0008000000000000, 0x5fe69dc800000000 },
	{ 0x0004000000000000, 0x5feff80000000000 },
	{ 0x0002000000000000, 0x5ff69dc800000000 },
	{ 0x0000000000000002, 0x61769dc800000000 },
	{ 0x0000000000000001, 0x617ff80000000000 },
};

int test21(long arg)
{
	long i;
	unsigned long result;
	struct isqrtvals *vp = isqrtvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(isqrtvals) / sizeof(isqrtvals[0]); ++i, ++vp) {
		asm("lfd 6,0(%0); frsqrte 7,6; stfd 7,0(%1)"
		    : : "b" (&vp->val), "b" (&result) : "memory");
		if (result != vp->inv) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_21(void)
{
	enable_fp();
	return trapit(0, test21);
}

struct sqrtvals {
	unsigned long val;
	unsigned long inv;
} sqrtvals[] = {
	{ 0x0000000000000000, 0x0000000000000000 },
	{ 0x8000000000000000, 0x8000000000000000 },
	{ 0xfff0000000000000, 0x7ff8000000000000 },
	{ 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0xfff123456789abcd, 0xfff923456789abcd },
	{ 0x3ff0000000000000, 0x3ff0000000000000 },
	{ 0x4000000000000000, 0x3ff6a09e667f3bcd },
	{ 0x4010000000000000, 0x4000000000000000 },
	{ 0xbff0000000000000, 0x7ff8000000000000 },
	{ 0x4008000000000000, 0x3ffbb67ae8584caa },
	{ 0x7fd0000000000000, 0x5fe0000000000000 },
	{ 0x0008000000000000, 0x1ff6a09e667f3bcd },
	{ 0x0004000000000000, 0x1ff0000000000000 },
	{ 0x0002000000000000, 0x1fe6a09e667f3bcd },
	{ 0x0000000000000002, 0x1e66a09e667f3bcd },
	{ 0x0000000000000001, 0x1e60000000000000 },
};

int test22(long arg)
{
	long i;
	unsigned long result;
	struct sqrtvals *vp = sqrtvals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(sqrtvals) / sizeof(sqrtvals[0]); ++i, ++vp) {
		asm("lfd 6,0(%0); fsqrt 7,6; stfd 7,0(%1)"
		    : : "b" (&vp->val), "b" (&result) : "memory");
		if (result != vp->inv) {
			print_hex(i, 2, " ");
			print_hex(result, 16, " ");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_22(void)
{
	enable_fp();
	return trapit(0, test22);
}

struct fmavals {
	unsigned long ra;
	unsigned long rc;
	unsigned long rb;
	unsigned long fma;
	unsigned long fms;
	unsigned long nfma;
	unsigned long nfms;
} fmavals[] = {
	{ 0x0000000000000000, 0x0000000000000000, 0x0000000000000000,
	  0x0000000000000000, 0x0000000000000000, 0x8000000000000000, 0x8000000000000000 },
	{ 0x0000000000000000, 0x7ffc000000000000, 0x0000000000000000,
	  0x7ffc000000000000, 0x7ffc000000000000, 0x7ffc000000000000, 0x7ffc000000000000 },
	{ 0x0000000000000000, 0x7ffc000000000000, 0x7ffb000000000000,
	  0x7ffb000000000000, 0x7ffb000000000000, 0x7ffb000000000000, 0x7ffb000000000000 },
	{ 0x7ffa000000000000, 0x7ffc000000000000, 0x7ffb000000000000,
	  0x7ffa000000000000, 0x7ffa000000000000, 0x7ffa000000000000, 0x7ffa000000000000 },
	{ 0x3ff0000000000000, 0x8000000000000000, 0x678123456789abcd, 
	  0x678123456789abcd, 0xe78123456789abcd, 0xe78123456789abcd, 0x678123456789abcd },
	{ 0x3ff0000000000000, 0xbff0000000000000, 0x678123456789abcd, 
	  0x678123456789abcd, 0xe78123456789abcd, 0xe78123456789abcd, 0x678123456789abcd },
	{ 0x7ff0000000000000, 0xbff0000000000000, 0x678123456789abcd, 
	  0xfff0000000000000, 0xfff0000000000000, 0x7ff0000000000000, 0x7ff0000000000000 },
	{ 0x7ff0000000000000, 0x0000000000000000, 0x678123456789abcd, 
	  0x7ff8000000000000, 0x7ff8000000000000, 0x7ff8000000000000, 0x7ff8000000000000 },
	{ 0x3ff0000000000000, 0x3ff0000000000000, 0x3ff0000020000000, 
	  0x4000000010000000, 0xbe80000000000000, 0xc000000010000000, 0x3e80000000000000 },
	{ 0x3ff0000000000001, 0x3ff0000000000001, 0x3ff0000000000000,
	  0x4000000000000001, 0x3cc0000000000000, 0xc000000000000001, 0xbcc0000000000000 },
	{ 0x3ff0000000000003, 0x3ff0000000000002, 0x3ff0000000000000,
	  0x4000000000000002, 0x3cd4000000000002, 0xc000000000000002, 0xbcd4000000000002 },
	{ 0x3006a09e667f3bcc, 0x4006a09e667f3bcd, 0xb020000000000000,
	  0xaca765753908cd20, 0x3030000000000000, 0x2ca765753908cd20, 0xb030000000000000 },
	{ 0x3006a09e667f3bcd, 0x4006a09e667f3bcd, 0xb020000000000000,
	  0x2cd3b3efbf5e2229, 0x3030000000000000, 0xacd3b3efbf5e2229, 0xb030000000000000 },
	{ 0x3006a09e667f3bcc, 0x4006a09e667f3bcd, 0xb060003450000000,
	  0xb05e0068a0000000, 0x3061003450000000, 0x305e0068a0000000, 0xb061003450000000 },
};

int test23(long arg)
{
	long i;
	unsigned long results[4];
	struct fmavals *vp = fmavals;

	set_fpscr(FPS_RN_NEAR);
	for (i = 0; i < sizeof(fmavals) / sizeof(fmavals[0]); ++i, ++vp) {
		asm("lfd 6,0(%0); lfd 7,8(%0); lfd 8,16(%0); fmadd 0,6,7,8; stfd 0,0(%1)"
		    : : "b" (&vp->ra), "b" (results) : "memory");
		asm("fmsub 1,6,7,8; fnmadd 2,6,7,8; fnmsub 3,6,7,8; stfd 1,8(%0); stfd 2,16(%0); stfd 3,24(%0)"
		    : : "b" (results) : "memory");
		if (results[0] != vp->fma || results[1] != vp->fms ||
		    results[2] != vp->nfma || results[3] != vp->nfms) {
			print_hex(i, 2, " ");
			print_hex(results[0], 16, " ");
			print_hex(results[1], 16, " ");
			print_hex(results[2], 16, " ");
			print_hex(results[3], 16, "\r\n");
			return i + 1;
		}
	}
	return 0;
}

int fpu_test_23(void)
{
	enable_fp();
	return trapit(0, test23);
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
		print_hex(mfspr(SRR1), 16, " FPSCR=");
		enable_fp();
		print_hex(get_fpscr(), 8, "\r\n");
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
	do_test(8, fpu_test_8);
	do_test(9, fpu_test_9);
	do_test(10, fpu_test_10);
	do_test(11, fpu_test_11);
	do_test(12, fpu_test_12);
	do_test(13, fpu_test_13);
	do_test(14, fpu_test_14);
	do_test(15, fpu_test_15);
	do_test(16, fpu_test_16);
	do_test(17, fpu_test_17);
	do_test(18, fpu_test_18);
	do_test(19, fpu_test_19);
	do_test(20, fpu_test_20);
	do_test(21, fpu_test_21);
	do_test(22, fpu_test_22);
	do_test(23, fpu_test_23);

	return fail;
}
