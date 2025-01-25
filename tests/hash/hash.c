#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_LE	0x1
#define MSR_DR	0x10
#define MSR_IR	0x20
#define MSR_SF	0x8000000000000000ul

extern unsigned long hash1(unsigned long, unsigned long);
extern unsigned long hash1b(unsigned long, unsigned long);
extern unsigned long hash2(unsigned long, unsigned long);
extern unsigned long hash2b(unsigned long, unsigned long);
extern unsigned long hash3(unsigned long, unsigned long);
extern unsigned long hash3b(unsigned long, unsigned long);
extern unsigned long hash4(unsigned long, unsigned long);
extern unsigned long hash4b(unsigned long, unsigned long);

extern unsigned long callit(unsigned long arg1, unsigned long arg2,
			    unsigned long fn(unsigned long, unsigned long),
			    unsigned long msr);

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
#define HSRR0	314
#define HSRR1	315
#define PTCR	464
#define HASHKEY	468
#define HASHPKEY 469

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

static inline unsigned long mfmsr(void)
{
	unsigned long val;

	__asm__ volatile("mfmsr %0" : "=r" (val));
	return val;
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

static inline unsigned short rot_r_16(unsigned short x, int n)
{
	return (x >> n) | (x << (16 - n));
}

static inline unsigned short rot_l_16(unsigned short x, int n)
{
	return (x << n) | (x >> (16 - n));
}

unsigned int simon_like_32_64(unsigned int x, unsigned long long key,
			      unsigned int lane)
{
	unsigned short c = 0xfffc;
	unsigned long long z0 = 0xFA2561CDF44AC398ull;
	unsigned int result;
	unsigned short z, temp;
	unsigned short k[33], eff_k[33], xleft[33], xright[33], fxleft[33];
	int i;

	z = 0;
	k[0] = key >> 48;
	k[1] = key >> 32;
	k[2] = key >> 16;
	k[3] = key;
	xleft[0] = x;
	xright[0] = x >> 16;
	for (i = 0; i < 28; ++i) {
		z = (z0 >> (63 - i)) & 1;
		temp = rot_r_16(k[i+3], 3) ^ k[i+1];
		k[i+4] = c ^ z ^ k[i] ^ temp ^ rot_r_16(temp, 1);
	}
	for (i = 0; i < 8; ++i) {
		eff_k[4*i + 0] = k[4*i + ((0 + lane) % 4)];
		eff_k[4*i + 1] = k[4*i + ((1 + lane) % 4)];
		eff_k[4*i + 2] = k[4*i + ((2 + lane) % 4)];
		eff_k[4*i + 3] = k[4*i + ((3 + lane) % 4)];
	}
	for (i = 0; i < 32; ++i) {
		fxleft[i] = (rot_l_16(xleft[i], 1) & rot_l_16(xleft[i], 8)) ^
			rot_l_16(xleft[i], 2);
		xleft[i+1] = xright[i] ^ fxleft[i] ^ eff_k[i];
		xright[i+1] = xleft[i];
	}
	result = ((unsigned int)xright[32] << 16) | xleft[32];
	return result;
}

unsigned long long hash_digest(unsigned long long x, unsigned long long y,
			       unsigned long long key)
{
	unsigned int stage0[4];
	unsigned int stage1[4];
	unsigned long long result;
	unsigned int i;

	for (i = 0; i < 4; ++i)
		stage0[i] = 0;
	for (i = 0; i < 8; ++i)
		stage0[i/2] = (stage0[i/2] << 16) | (((y >> (i * 8)) & 0xff) << 8) |
			((x >> (56 - (i * 8))) & 0xff);
	for (i = 0; i < 4; ++i)
		stage1[i] = simon_like_32_64(stage0[i], key, i);
	result = (((unsigned long long)stage1[0] << 32) | stage1[1]) ^
		(((unsigned long long)stage1[2] << 32) | stage1[3]);
	return result;
}

unsigned long notstack[33];
unsigned long correct_hash;
unsigned long rb = 0x0f0e0d0c0b0a0908ul;
unsigned long key = 0x123456789abcdef0ul;

int hash_test_1(void)
{
	unsigned long ret;

	ret = callit((unsigned long) &notstack[32], rb, hash1, mfmsr());
	if (ret)
		return ret;
	if (notstack[31] != correct_hash) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return 1;
	}
	notstack[31] = 0;
	ret = callit((unsigned long) &notstack[32], rb, hash1b, mfmsr());
	if (ret)
		return ret;
	if (notstack[0] != correct_hash) {
		print_hex(notstack[0], 16);
		putchar(' ');
		return 2;
	}
	return 0;
}

int hash_test_2(void)
{
	unsigned long ret;

	notstack[31] = correct_hash;
	ret = callit((unsigned long) &notstack[32], rb, hash2, mfmsr());
	if (ret)
		return ret;
	notstack[31] ^= 0x1000;
	ret = callit((unsigned long) &notstack[32], rb, hash2, mfmsr());
	if (ret != 0x700) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return ret | 1;
	}
	if (mfspr(SPRG0) != (unsigned long) &hash2) {
		print_hex(mfspr(SPRG0), 16);
		putchar(' ');
		return 2;
	}
	if ((mfspr(SPRG3) & 0xffff0000ul) != 0x00020000) {
		print_hex(mfspr(SPRG3), 8);
		putchar(' ');
		return 3;
	}
	notstack[0] = correct_hash;
	ret = callit((unsigned long) &notstack[32], rb, hash2b, mfmsr());
	if (ret)
		return ret | 4;
	notstack[0] ^= 0x1000;
	ret = callit((unsigned long) &notstack[32], rb, hash2b, mfmsr());
	if (ret != 0x700) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return ret | 5;
	}
	return 0;
}

int hash_test_3(void)
{
	unsigned long ret;

	ret = callit((unsigned long) &notstack[32], rb, hash3, mfmsr());
	if (ret)
		return ret;
	if (notstack[31] != correct_hash) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return 1;
	}
	notstack[31] = 0;
	ret = callit((unsigned long) &notstack[32], rb, hash3b, mfmsr());
	if (ret)
		return ret;
	if (notstack[0] != correct_hash) {
		print_hex(notstack[0], 16);
		putchar(' ');
		return 2;
	}
	return 0;
}

int hash_test_4(void)
{
	unsigned long ret;

	notstack[31] = correct_hash;
	ret = callit((unsigned long) &notstack[32], rb, hash4, mfmsr());
	if (ret)
		return ret;
	notstack[31] ^= 0x1000;
	ret = callit((unsigned long) &notstack[32], rb, hash4, mfmsr());
	if (ret != 0x700) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return ret | 1;
	}
	if (mfspr(SPRG0) != (unsigned long) &hash4) {
		print_hex(mfspr(SPRG0), 16);
		putchar(' ');
		return 2;
	}
	if ((mfspr(SPRG3) & 0xffff0000ul) != 0x00020000) {
		print_hex(mfspr(SPRG3), 8);
		putchar(' ');
		return 3;
	}
	notstack[0] = correct_hash;
	ret = callit((unsigned long) &notstack[32], rb, hash4b, mfmsr());
	if (ret)
		return ret | 4;
	notstack[0] ^= 0x1000;
	ret = callit((unsigned long) &notstack[32], rb, hash4b, mfmsr());
	if (ret != 0x700) {
		print_hex(notstack[31], 16);
		putchar(' ');
		return ret | 5;
	}
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
		print_hex(ret, 8);
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
	unsigned long ra;

	console_init();

	ra = (unsigned long)&notstack[32];
	/* cache the usual value */
	if (ra == 0x4190) {
		correct_hash = 0xcd57657a24afdd14ul;
	} else {
		correct_hash = hash_digest(ra, rb, key);
		print_hex(ra, 16);
		putchar(' ');
		print_hex(correct_hash, 16);
		print_string("\r\n");
	}

	mtspr(HASHKEY, key);
	do_test(1, hash_test_1);
	do_test(2, hash_test_2);
	mtspr(HASHKEY, ~0ul);
	mtspr(HASHPKEY, key);
	do_test(3, hash_test_3);
	do_test(4, hash_test_4);

	return fail;
}
