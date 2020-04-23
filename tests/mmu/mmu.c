#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

extern int test_read(long *addr, long *ret, long init);
extern int test_write(long *addr, long val);

static inline void do_tlbie(unsigned long rb, unsigned long rs)
{
	__asm__ volatile("tlbie %0,%1" : : "r" (rb), "r" (rs) : "memory");
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

static inline void store_pte(unsigned long *p, unsigned long pte)
{
	__asm__ volatile("stdbrx %1,0,%0" : : "r" (p), "r" (pte) : "memory");
}

void print_string(const char *str)
{
	for (; *str; ++str)
		putchar(*str);
}

void print_hex(unsigned long val)
{
	int i, x;

	for (i = 60; i >= 0; i -= 4) {
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

#define DFLT_PERM	(PERM_WR | PERM_RD | REF | CHG)

/*
 * Set up an MMU translation tree using memory starting at the 64k point.
 * We use 2 levels, mapping 2GB (the minimum size possible), with a
 * 8kB PGD level pointing to 4kB PTE pages.
 */
unsigned long *pgdir = (unsigned long *) 0x10000;
unsigned long free_ptr = 0x12000;
void *eas_mapped[4];
int neas_mapped;

void init_mmu(void)
{
	zero_memory(pgdir, 1024 * sizeof(unsigned long));
	/* RTS = 0 (2GB address space), RPDS = 10 (1024-entry top level) */
	mtspr(720, (unsigned long) pgdir | 10);
	do_tlbie(0xc00, 0);	/* invalidate all TLB entries */
}

static unsigned long *read_pgd(unsigned long i)
{
	unsigned long ret;

	__asm__ volatile("ldbrx %0,%1,%2" : "=r" (ret) : "b" (pgdir),
			 "r" (i * sizeof(unsigned long)));
	return (unsigned long *) (ret & 0x00ffffffffffff00);
}

void map(void *ea, void *pa, unsigned long perm_attr)
{
	unsigned long epn = (unsigned long) ea >> 12;
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
	store_pte(&ptep[j], 0xc000000000000000 | ((unsigned long)pa & 0x00fffffffffff000) | perm_attr);
	eas_mapped[neas_mapped++] = ea;
}

void unmap(void *ea)
{
	unsigned long epn = (unsigned long) ea >> 12;
	unsigned long i, j;
	unsigned long *ptep;

	i = (epn >> 9) & 0x3ff;
	j = epn & 0x1ff;
	if (pgdir[i] == 0)
		return;
	ptep = read_pgd(i);
	ptep[j] = 0;
	do_tlbie(((unsigned long)ea & ~0xfff), 0);
}

void unmap_all(void)
{
	int i;

	for (i = 0; i < neas_mapped; ++i)
		unmap(eas_mapped[i]);
	neas_mapped = 0;
}

int mmu_test_1(void)
{
	long *ptr = (long *) 0x123000;
	long val;

	/* this should fail */
	if (test_read(ptr, &val, 0xdeadbeefd00d))
		return 1;
	/* dest reg of load should be unchanged */
	if (val != 0xdeadbeefd00d)
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long) ptr || mfspr(18) != 0x40000000)
		return 3;
	return 0;
}

int mmu_test_2(void)
{
	long *mem = (long *) 0x4000;
	long *ptr = (long *) 0x124000;
	long *ptr2 = (long *) 0x1124000;
	long val;

	/* create PTE */
	map(ptr, mem, DFLT_PERM);
	/* initialize the memory content */
	mem[33] = 0xbadc0ffee;
	/* this should succeed and be a cache miss */
	if (!test_read(&ptr[33], &val, 0xdeadbeefd00d))
		return 1;
	/* dest reg of load should have the value written */
	if (val != 0xbadc0ffee)
		return 2;
	/* load a second TLB entry in the same set as the first */
	map(ptr2, mem, DFLT_PERM);
	/* this should succeed and be a cache hit */
	if (!test_read(&ptr2[33], &val, 0xdeadbeefd00d))
		return 3;
	/* dest reg of load should have the value written */
	if (val != 0xbadc0ffee)
		return 4;
	/* check that the first entry still works */
	if (!test_read(&ptr[33], &val, 0xdeadbeefd00d))
		return 5;
	if (val != 0xbadc0ffee)
		return 6;
	return 0;
}

int mmu_test_3(void)
{
	long *mem = (long *) 0x5000;
	long *ptr = (long *) 0x149000;
	long val;

	/* create PTE */
	map(ptr, mem, DFLT_PERM);
	/* initialize the memory content */
	mem[45] = 0xfee1800d4ea;
	/* this should succeed and be a cache miss */
	if (!test_read(&ptr[45], &val, 0xdeadbeefd0d0))
		return 1;
	/* dest reg of load should have the value written */
	if (val != 0xfee1800d4ea)
		return 2;
	/* remove the PTE */
	unmap(ptr);
	/* this should fail */
	if (test_read(&ptr[45], &val, 0xdeadbeefd0d0))
		return 3;
	/* dest reg of load should be unchanged */
	if (val != 0xdeadbeefd0d0)
		return 4;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long) &ptr[45] || mfspr(18) != 0x40000000)
		return 5;
	return 0;
}

int mmu_test_4(void)
{
	long *mem = (long *) 0x6000;
	long *ptr = (long *) 0x10a000;
	long *ptr2 = (long *) 0x110a000;
	long val;

	/* create PTE */
	map(ptr, mem, DFLT_PERM);
	/* initialize the memory content */
	mem[27] = 0xf00f00f00f00;
	/* this should succeed and be a cache miss */
	if (!test_write(&ptr[27], 0xe44badc0ffee))
		return 1;
	/* memory should now have the value written */
	if (mem[27] != 0xe44badc0ffee)
		return 2;
	/* load a second TLB entry in the same set as the first */
	map(ptr2, mem, DFLT_PERM);
	/* this should succeed and be a cache hit */
	if (!test_write(&ptr2[27], 0x6e11ae))
		return 3;
	/* memory should have the value written */
	if (mem[27] != 0x6e11ae)
		return 4;
	/* check that the first entry still exists */
	/* (assumes TLB is 2-way associative or more) */
	if (!test_read(&ptr[27], &val, 0xdeadbeefd00d))
		return 5;
	if (val != 0x6e11ae)
		return 6;
	return 0;
}

int mmu_test_5(void)
{
	long *mem = (long *) 0x7ffd;
	long *ptr = (long *) 0x39fffd;
	long val;

	/* create PTE */
	map(ptr, mem, DFLT_PERM);
	/* this should fail */
	if (test_read(ptr, &val, 0xdeadbeef0dd0))
		return 1;
	/* dest reg of load should be unchanged */
	if (val != 0xdeadbeef0dd0)
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != ((long)ptr & ~0xfff) + 0x1000 || mfspr(18) != 0x40000000)
		return 3;
	return 0;
}

int mmu_test_6(void)
{
	long *mem = (long *) 0x7ffd;
	long *ptr = (long *) 0x39fffd;

	/* create PTE */
	map(ptr, mem, DFLT_PERM);
	/* initialize memory */
	*mem = 0x123456789abcdef0;
	/* this should fail */
	if (test_write(ptr, 0xdeadbeef0dd0))
		return 1;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != ((long)ptr & ~0xfff) + 0x1000 || mfspr(18) != 0x42000000)
		return 2;
	return 0;
}

int mmu_test_7(void)
{
	long *mem = (long *) 0x4000;
	long *ptr = (long *) 0x124000;
	long val;

	*mem = 0x123456789abcdef0;
	/* create PTE without R or C */
	map(ptr, mem, PERM_RD | PERM_WR);
	/* this should fail */
	if (test_read(ptr, &val, 0xdeadd00dbeef))
		return 1;
	/* dest reg of load should be unchanged */
	if (val != 0xdeadd00dbeef)
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long) ptr || mfspr(18) != 0x00040000)
		return 3;
	/* this should fail */
	if (test_write(ptr, 0xdeadbeef0dd0))
		return 4;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long)ptr || mfspr(18) != 0x02040000)
		return 5;
	/* memory should be unchanged */
	if (*mem != 0x123456789abcdef0)
		return 6;
	return 0;
}

int mmu_test_8(void)
{
	long *mem = (long *) 0x4000;
	long *ptr = (long *) 0x124000;
	long val;

	*mem = 0x123456789abcdef0;
	/* create PTE with R but not C */
	map(ptr, mem, REF | PERM_RD | PERM_WR);
	/* this should succeed */
	if (!test_read(ptr, &val, 0xdeadd00dbeef))
		return 1;
	/* this should fail */
	if (test_write(ptr, 0xdeadbeef0dd1))
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long)ptr || mfspr(18) != 0x02040000)
		return 3;
	/* memory should be unchanged */
	if (*mem != 0x123456789abcdef0)
		return 4;
	return 0;
}

int mmu_test_9(void)
{
	long *mem = (long *) 0x4000;
	long *ptr = (long *) 0x124000;
	long val;

	*mem = 0x123456789abcdef0;
	/* create PTE without read or write permission */
	map(ptr, mem, REF);
	/* this should fail */
	if (test_read(ptr, &val, 0xdeadd00dbeef))
		return 1;
	/* dest reg of load should be unchanged */
	if (val != 0xdeadd00dbeef)
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long) ptr || mfspr(18) != 0x08000000)
		return 3;
	/* this should fail */
	if (test_write(ptr, 0xdeadbeef0dd1))
		return 4;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long)ptr || mfspr(18) != 0x0a000000)
		return 5;
	/* memory should be unchanged */
	if (*mem != 0x123456789abcdef0)
		return 6;
	return 0;
}

int mmu_test_10(void)
{
	long *mem = (long *) 0x4000;
	long *ptr = (long *) 0x124000;
	long val;

	*mem = 0x123456789abcdef0;
	/* create PTE with read but not write permission */
	map(ptr, mem, REF | PERM_RD);
	/* this should succeed */
	if (!test_read(ptr, &val, 0xdeadd00dbeef))
		return 1;
	/* this should fail */
	if (test_write(ptr, 0xdeadbeef0dd1))
		return 2;
	/* DAR and DSISR should be set correctly */
	if (mfspr(19) != (long)ptr || mfspr(18) != 0x0a000000)
		return 3;
	/* memory should be unchanged */
	if (*mem != 0x123456789abcdef0)
		return 4;
	return 0;
}

int fail = 0;

void do_test(int num, int (*test)(void))
{
	int ret;

	mtspr(18, 0);
	mtspr(19, 0);
	unmap_all();
	print_test_number(num);
	ret = test();
	if (ret == 0) {
		print_string("PASS\r\n");
	} else {
		fail = 1;
		print_string("FAIL ");
		putchar(ret + '0');
		print_string(" DAR=");
		print_hex(mfspr(19));
		print_string(" DSISR=");
		print_hex(mfspr(18));
		print_string("\r\n");
	}
}

int main(void)
{
	potato_uart_init();
	init_mmu();

	do_test(1, mmu_test_1);
	do_test(2, mmu_test_2);
	do_test(3, mmu_test_3);
	do_test(4, mmu_test_4);
	do_test(5, mmu_test_5);
	do_test(6, mmu_test_6);
	do_test(7, mmu_test_7);
	do_test(8, mmu_test_8);
	do_test(9, mmu_test_9);
	do_test(10, mmu_test_10);

	return fail;
}
