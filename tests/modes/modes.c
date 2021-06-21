#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_LE	0x1
#define MSR_DR	0x10
#define MSR_IR	0x20
#define MSR_SF	0x8000000000000000ul

extern unsigned long callit(unsigned long arg1, unsigned long arg2,
			    unsigned long fn, unsigned long msr);

extern void do_lq(void *src, unsigned long *regs);
extern void do_lq_np(void *src, unsigned long *regs);
extern void do_lq_bad(void *src, unsigned long *regs);
extern void do_stq(void *dst, unsigned long *regs);
extern void do_lq_be(void *src, unsigned long *regs);
extern void do_lq_np_be(void *src, unsigned long *regs);
extern void do_stq_be(void *dst, unsigned long *regs);

static inline void do_tlbie(unsigned long rb, unsigned long rs)
{
	__asm__ volatile("tlbie %0,%1" : : "r" (rb), "r" (rs) : "memory");
}

#define DSISR	18
#define DAR	19
#define SRR0	26
#define SRR1	27
#define PID	48
#define SPRG0	272
#define SPRG1	273
#define SPRG3	275
#define PTCR	464

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

void print_hex(unsigned long val, int ndigit)
{
	int i, x;

	for (i = (ndigit - 1) * 4; i >= 0; i -= 4) {
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

#define DFLT_PERM	(PERM_EX | PERM_WR | PERM_RD | REF | CHG)

/*
 * Set up an MMU translation tree using memory starting at the 64k point.
 * We use 3 levels, mapping 512GB, with 4kB PGD/PMD/PTE pages.
 */
unsigned long *part_tbl = (unsigned long *) 0x10000;
unsigned long *proc_tbl = (unsigned long *) 0x11000;
unsigned long *pgdir = (unsigned long *) 0x12000;
unsigned long free_ptr = 0x13000;

void init_mmu(void)
{
	/* set up partition table */
	store_pte(&part_tbl[1], (unsigned long)proc_tbl);
	/* set up process table */
	zero_memory(proc_tbl, 512 * sizeof(unsigned long));
	mtspr(PTCR, (unsigned long)part_tbl);
	mtspr(PID, 1);
	zero_memory(pgdir, 512 * sizeof(unsigned long));
	/* RTS = 8 (512GB address space), RPDS = 9 (512-entry top level) */
	store_pte(&proc_tbl[2 * 1], (unsigned long) pgdir | 0x2000000000000009);
	do_tlbie(0xc00, 0);	/* invalidate all TLB entries */
}

static unsigned long *read_pd(unsigned long *pdp, unsigned long i)
{
	unsigned long ret;

	__asm__ volatile("ldbrx %0,%1,%2" : "=r" (ret) : "b" (pdp),
			 "r" (i * sizeof(unsigned long)));
	return (unsigned long *) (ret & 0x00ffffffffffff00);
}

void map(unsigned long ea, unsigned long pa, unsigned long perm_attr)
{
	unsigned long epn = ea >> 12;
	unsigned long h, i, j;
	unsigned long *ptep;
	unsigned long *pmdp;

	h = (epn >> 18) & 0x1ff;
	i = (epn >> 9) & 0x1ff;
	j = epn & 0x1ff;
	if (pgdir[h] == 0) {
		zero_memory((void *)free_ptr, 512 * sizeof(unsigned long));
		store_pte(&pgdir[h], 0x8000000000000000 | free_ptr | 9);
		free_ptr += 512 * sizeof(unsigned long);
	}
	pmdp = read_pd(pgdir, h);
	if (pmdp[i] == 0) {
		zero_memory((void *)free_ptr, 512 * sizeof(unsigned long));
		store_pte(&pmdp[i], 0x8000000000000000 | free_ptr | 9);
		free_ptr += 512 * sizeof(unsigned long);
	}
	ptep = read_pd(pmdp, i);
	if (ptep[j]) {
		ptep[j] = 0;
		do_tlbie(ea & ~0xfff, 0);
	}
	store_pte(&ptep[j], 0xc000000000000000 | (pa & 0x00fffffffffff000) |
		  perm_attr);
}

void unmap(void *ea)
{
	unsigned long epn = (unsigned long) ea >> 12;
	unsigned long h, i, j;
	unsigned long *ptep, *pmdp;

	h = (epn >> 18) & 0x1ff;
	i = (epn >> 9) & 0x1ff;
	j = epn & 0x1ff;
	if (pgdir[h] == 0)
		return;
	pmdp = read_pd(pgdir, h);
	if (pmdp[i] == 0)
		return;
	ptep = read_pd(pmdp, i);
	ptep[j] = 0;
	do_tlbie(((unsigned long)ea & ~0xfff), 0);
}

extern unsigned long test_code(unsigned long sel, unsigned long addr);

static unsigned long bits = 0x0102030405060708ul;

int mode_test_1(void)
{
	unsigned long ret, msr;

	msr = MSR_SF | MSR_IR | MSR_DR | MSR_LE;
	ret = callit(1, (unsigned long)&bits, (unsigned long)&test_code, msr);
	if (ret != bits)
		return ret? ret: 1;
	return 0;
}

unsigned long be_test_code;

int mode_test_2(void)
{
	unsigned long i;
	unsigned int *src, *dst;
	unsigned long ret, msr;

	/* copy and byte-swap the page containing test_code */
	be_test_code = free_ptr;
	free_ptr += 0x1000;
	src = (unsigned int *) &test_code;
	dst = (unsigned int *) be_test_code;
	for (i = 0; i < 0x1000 / sizeof(unsigned int); ++i)
		dst[i] = __builtin_bswap32(src[i]);
	__asm__ volatile("isync; icbi 0,%0" : : "r" (be_test_code));
	map(be_test_code, be_test_code, DFLT_PERM);

	msr = MSR_SF | MSR_IR | MSR_DR;
	ret = callit(1, (unsigned long)&bits, be_test_code, msr);
	if (ret != __builtin_bswap64(bits))
		return ret? ret: 1;
	return 0;
}

int mode_test_3(void)
{
	unsigned long ret, msr;
	unsigned long addr = (unsigned long) &bits;
	unsigned long code = (unsigned long) &test_code;

	msr = MSR_IR | MSR_DR | MSR_LE;
	ret = callit(1, addr, code, msr);
	if (ret != bits)
		return ret? ret: 1;
	ret = callit(1, addr + 0x5555555500000000ul,
		     code + 0x9999999900000000ul, msr);
	if (ret != bits)
		return ret? ret: 2;
	return 0;
}

int mode_test_4(void)
{
	unsigned long ret, msr;
	unsigned long addr = (unsigned long) &bits;

	msr = MSR_IR | MSR_DR;
	ret = callit(1, addr, be_test_code, msr);
	if (ret != __builtin_bswap64(bits))
		return ret? ret: 1;
	ret = callit(1, addr + 0x5555555500000000ul,
		     be_test_code + 0x9999999900000000ul, msr);
	if (ret != __builtin_bswap64(bits))
		return ret? ret: 2;
	return 0;
}

int mode_test_5(void)
{
	unsigned long ret, msr;

	/*
	 * Try branching from the page at fffff000
	 * to the page at 0 in 32-bit mode.
	 */
	map(0xfffff000, (unsigned long) &test_code, DFLT_PERM);
	map(0, (unsigned long) &test_code, DFLT_PERM);
	msr = MSR_IR | MSR_DR | MSR_LE;
	ret = callit(2, 0, 0xfffff000, msr);
	return ret;
}

int mode_test_6(void)
{
	unsigned long ret, msr;

	/*
	 * Try a bl from address fffffffc in 32-bit mode.
	 * We expect LR to be set to 100000000, though the
	 * arch says the value is undefined.
	 */
	msr = MSR_IR | MSR_DR | MSR_LE;
	ret = callit(3, 0, 0xfffff000, msr);
	if (ret != 0x100000000ul)
		return 1;
	return 0;
}

int mode_test_7(void)
{
	unsigned long quad[4] __attribute__((__aligned__(16)));
	unsigned long regs[2];
	unsigned long ret, msr;

	/*
	 * Test lq/stq in LE mode
	 */
	msr = MSR_SF | MSR_LE;
	quad[0] = 0x123456789abcdef0ul;
	quad[1] = 0xfafa5959bcbc3434ul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_lq, msr);
	if (ret)
		return ret | 1;
	if (regs[0] != quad[1] || regs[1] != quad[0])
		return 2;
	/* unaligned may give alignment interrupt */
	quad[2] = 0x0011223344556677ul;
	ret = callit((unsigned long)&quad[1], (unsigned long)regs,
		     (unsigned long)&do_lq, msr);
	if (ret == 0) {
		if (regs[0] != quad[2] || regs[1] != quad[1])
			return 3;
	} else if (ret == 0x600) {
		if (mfspr(SPRG0) != (unsigned long) &do_lq ||
		    mfspr(DAR) != (unsigned long) &quad[1])
			return ret | 4;
	} else
		return ret | 5;

	/* try stq */
	regs[0] = 0x5238523852385238ul;
	regs[1] = 0x5239523952395239ul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_stq, msr);
	if (ret)
		return ret | 5;
	if (quad[0] != regs[1] || quad[1] != regs[0])
		return 6;
	regs[0] = 0x0172686966746564ul;
	regs[1] = 0xfe8d0badd00dabcdul;
	ret = callit((unsigned long)quad + 1, (unsigned long)regs,
		     (unsigned long)&do_stq, msr);
	if (ret)
		return ret | 7;
	if (((quad[0] >> 8) | (quad[1] << 56)) != regs[1] ||
	    ((quad[1] >> 8) | (quad[2] << 56)) != regs[0])
		return 8;

	/* try lq non-preferred form */
	quad[0] = 0x56789abcdef01234ul;
	quad[1] = 0x5959bcbc3434fafaul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_lq_np, msr);
	if (ret)
		return ret | 9;
	if (regs[0] != quad[1] || regs[1] != quad[0])
		return 10;
	/* unaligned should give alignment interrupt in uW implementation */
	quad[2] = 0x6677001122334455ul;
	ret = callit((unsigned long)&quad[1], (unsigned long)regs,
		     (unsigned long)&do_lq_np, msr);
	if (ret == 0x600) {
		if (mfspr(SPRG0) != (unsigned long) &do_lq_np + 4 ||
		    mfspr(DAR) != (unsigned long) &quad[1])
			return ret | 11;
	} else
		return 12;

	/* make sure lq with rt = ra causes an illegal instruction interrupt */
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_lq_bad, msr);
	if (ret != 0x700)
		return 13;
	if (mfspr(SPRG0) != (unsigned long)&do_lq_bad + 4 ||
	    !(mfspr(SPRG3) & 0x80000))
		return 14;
	return 0;
}

int mode_test_8(void)
{
	unsigned long quad[4] __attribute__((__aligned__(16)));
	unsigned long regs[2];
	unsigned long ret, msr;

	/*
	 * Test lq/stq in BE mode
	 */
	msr = MSR_SF;
	quad[0] = 0x123456789abcdef0ul;
	quad[1] = 0xfafa5959bcbc3434ul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_lq_be, msr);
	if (ret)
		return ret | 1;
	if (regs[0] != quad[0] || regs[1] != quad[1]) {
		print_hex(regs[0], 16);
		print_string(" ");
		print_hex(regs[1], 16);
		print_string(" ");
		return 2;
	}
	/* don't expect alignment interrupt */
	quad[2] = 0x0011223344556677ul;
	ret = callit((unsigned long)&quad[1], (unsigned long)regs,
		     (unsigned long)&do_lq_be, msr);
	if (ret == 0) {
		if (regs[0] != quad[1] || regs[1] != quad[2])
			return 3;
	} else
		return ret | 5;

	/* try stq */
	regs[0] = 0x5238523852385238ul;
	regs[1] = 0x5239523952395239ul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_stq_be, msr);
	if (ret)
		return ret | 5;
	if (quad[0] != regs[0] || quad[1] != regs[1])
		return 6;
	regs[0] = 0x0172686966746564ul;
	regs[1] = 0xfe8d0badd00dabcdul;
	ret = callit((unsigned long)quad + 1, (unsigned long)regs,
		     (unsigned long)&do_stq_be, msr);
	if (ret)
		return ret | 7;
	if (((quad[0] >> 8) | (quad[1] << 56)) != regs[0] ||
	    ((quad[1] >> 8) | (quad[2] << 56)) != regs[1]) {
			print_hex(quad[0], 16);
			print_string(" ");
			print_hex(quad[1], 16);
			print_string(" ");
			print_hex(quad[2], 16);
			print_string(" ");
		return 8;
	}

	/* try lq non-preferred form */
	quad[0] = 0x56789abcdef01234ul;
	quad[1] = 0x5959bcbc3434fafaul;
	ret = callit((unsigned long)quad, (unsigned long)regs,
		     (unsigned long)&do_lq_np_be, msr);
	if (ret)
		return ret | 9;
	if (regs[0] != quad[0] || regs[1] != quad[1])
		return 10;
	/* unaligned should not give alignment interrupt in uW implementation */
	quad[2] = 0x6677001122334455ul;
	ret = callit((unsigned long)&quad[1], (unsigned long)regs,
		     (unsigned long)&do_lq_np_be, msr);
	if (ret)
		return ret | 11;
	if (regs[0] != quad[1] || regs[1] != quad[2])
		return 12;
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
		print_hex(ret, 16);
		if (ret != 0 && (ret & ~0xfe0ul) == 0) {
			print_string(" SRR0=");
			print_hex(mfspr(SPRG0), 16);
			print_string(" SRR1=");
			print_hex(mfspr(SPRG1), 16);
		}
		print_string("\r\n");
	}
}

int main(void)
{
	unsigned long addr;
	extern unsigned char __stack_top[];

	console_init();
	init_mmu();

	/*
	 * Map test code and stack 1-1
	 */
	for (addr = 0; addr < (unsigned long)&__stack_top; addr += 0x1000)
		map(addr, addr, DFLT_PERM);

	do_test(1, mode_test_1);
	do_test(2, mode_test_2);
	do_test(3, mode_test_3);
	do_test(4, mode_test_4);
	do_test(5, mode_test_5);
	do_test(6, mode_test_6);
	do_test(7, mode_test_7);
	do_test(8, mode_test_8);

	return fail;
}
