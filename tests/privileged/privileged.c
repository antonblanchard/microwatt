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
#define PID	48
#define PRTBL	720
#define PVR	287

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

static inline void store_pte(unsigned long *p, unsigned long pte)
{
	__asm__ volatile("stdbrx %1,0,%0" : : "r" (p), "r" (pte) : "memory");
}

#define CACHE_LINE_SIZE	64

void zero_memory(void *ptr, unsigned long nbytes)
{
	unsigned long nb, i, nl;
	void *p;

	for (; nbytes != 0; nbytes -= nb, ptr += nb) {
		nb = -((unsigned long)ptr) & (CACHE_LINE_SIZE - 1);
		if (nb == 0 && nbytes >= CACHE_LINE_SIZE) {
			nl = nbytes / CACHE_LINE_SIZE;
			p = ptr;
			for (i = 0; i < nl; ++i) {
				__asm__ volatile("dcbz 0,%0" : : "r" (p) : "memory");
				p += CACHE_LINE_SIZE;
			}
			nb = nl * CACHE_LINE_SIZE;
		} else {
			if (nb > nbytes)
				nb = nbytes;
			for (i = 0; i < nb; ++i)
				((unsigned char *)ptr)[i] = 0;
		}
	}
}

#define PERM_EX		0x001
#define PERM_WR		0x002
#define PERM_RD		0x004
#define PERM_PRIV	0x008
#define ATTR_NC		0x020
#define CHG		0x080
#define REF		0x100

#define DFLT_PERM	(PERM_WR | PERM_RD | REF | CHG)

/*
 * Set up an MMU translation tree using memory starting at the 64k point.
 * We use 2 levels, mapping 2GB (the minimum size possible), with a
 * 8kB PGD level pointing to 4kB PTE pages.
 */
unsigned long *pgdir = (unsigned long *) 0x10000;
unsigned long *proc_tbl = (unsigned long *) 0x12000;
unsigned long free_ptr = 0x13000;

void init_mmu(void)
{
	/* set up process table */
	zero_memory(proc_tbl, 512 * sizeof(unsigned long));
	/* RTS = 0 (2GB address space), RPDS = 10 (1024-entry top level) */
	store_pte(&proc_tbl[2 * 1], (unsigned long) pgdir | 10);
	mtspr(PRTBL, (unsigned long)proc_tbl);
	mtspr(PID, 1);
	zero_memory(pgdir, 1024 * sizeof(unsigned long));
}

static unsigned long *read_pgd(unsigned long i)
{
	unsigned long ret;

	__asm__ volatile("ldbrx %0,%1,%2" : "=r" (ret) : "b" (pgdir),
			 "r" (i * sizeof(unsigned long)));
	return (unsigned long *) (ret & 0x00ffffffffffff00);
}

void map(unsigned long ea, unsigned long pa, unsigned long perm_attr)
{
	unsigned long epn = ea >> 12;
	unsigned long i, j;
	unsigned long *ptep;

	i = (epn >> 9) & 0x3ff;
	j = epn & 0x1ff;
	if (pgdir[i] == 0) {
		zero_memory((void *)free_ptr, 512 * sizeof(unsigned long));
		store_pte(&pgdir[i], 0x8000000000000000 | free_ptr | 9);
		free_ptr += 512 * sizeof(unsigned long);
	}
	ptep = read_pgd(i);
	store_pte(&ptep[j], 0xc000000000000000 | (pa & 0x00fffffffffff000) | perm_attr);
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

int priv_fn_7(unsigned long x)
{
	mfspr(PVR);
	__asm__ volatile("sc");
	return 0;
}

int priv_fn_8(unsigned long x)
{
	mtspr(PVR, x);
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
	console_init();
	init_mmu();
	map(0x2000, 0x2000, REF | CHG | PERM_RD | PERM_EX);	/* map code page */
	map(0x7000, 0x7000, REF | CHG | PERM_RD | PERM_WR);	/* map stack page */

	do_test(1, priv_fn_1);
	do_test(2, priv_fn_2);
	do_test(3, priv_fn_3);
	do_test(4, priv_fn_4);
	do_test(5, priv_fn_5);
	do_test(6, priv_fn_6);
	do_test(7, priv_fn_7);
	do_test(8, priv_fn_8);

	return fail;
}
