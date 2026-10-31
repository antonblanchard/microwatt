/*
 * Test for the MMU page-walk trace array.
 *
 * The trace array lives in mmu.vhdl and is sized by the MMU_TRACE_LENGTH
 * generic, which core_tb.vhdl sets to 2048 for simulation.  It is accessed
 * through two privileged SPRs:
 *
 *   MTRC (730)	control on write, status on read
 *   MTRD (731)	read the doubleword at the read address, then advance it
 *
 * Each record is four doublewords: EA, PTCR, descriptor, misc.
 *
 * Sub-tests:
 *   01  MTRC write/read: enable, re-arm and read address
 *   02  streaming read of a captured record and read address auto-advance
 *   03  a real page walk is captured as WALK_START with the right EA
 *   04  clearing the enable bit freezes capture
 *   05  exact record sequence of a cold page walk
 *   06  a translation fault is recorded as ERROR with the invalid flag
 *   07  mtspr MTRD is a no-op
 *   08  MTRC/MTRD are privileged
 *   09  back-to-back MTRD reads right after a dcache-missing load
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_EE	0x8000
#define MSR_PR	0x4000
#define MSR_IR	0x0020
#define MSR_DR	0x0010

extern int test_read(long *addr, long *ret, long init);
extern int test_exec(int testno, unsigned long pc, unsigned long msr);
extern char user_mfspr_mtrd[], user_mtspr_mtrc[];

#define SRR1	27
#define PID	48
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

static inline void do_tlbie(unsigned long rb, unsigned long rs)
{
	__asm__ volatile(".machine \"power10\"; tlbie %0,%1,0,1,1" : : "r" (rb), "r" (rs) : "memory");
}

/* RIC=2: also flush the page-walk and process-table caches */
static inline void do_tlbie_all(unsigned long rb, unsigned long rs)
{
	__asm__ volatile(".machine \"power10\"; tlbie %0,%1,2,1,1" : : "r" (rb), "r" (rs) : "memory");
}

/* ---- trace array access ------------------------------------------------- */

#define MTRC	730
#define MTRD	731

#define TRACE_LEN	2048

/* MTRC write fields */
#define TRC_EN		(1ul << 63)	/* capture enable */
#define TRC_REARM	(1ul << 62)	/* write pointer := 0, full := 0 */
#define TRC_ADDR(rec, word)	(((unsigned long)(rec) << 2) | (word))

/* MTRC read (status) fields */
#define ST_EN(s)	(((s) >> 63) & 1)
#define ST_FULL(s)	(((s) >> 62) & 1)
#define ST_WPTR(s)	(((s) >> 32) & 0xffff)
#define ST_RADDR(s)	((s) & 0xffff)

/* misc word (word 3) fields */
#define M_EVENT(m)	(((m) >> 48) & 0xf)
#define M_INVALID	(1ul << 30)

#define EV_WALK_START	1
#define EV_PART_DONE	2
#define EV_PROC_READ	3
#define EV_PTE_READ	4
#define EV_TLB_LOAD	5
#define EV_ERROR	6

/* value an mfspr must overwrite; catches an mfspr that writes nothing */
#define SENTINEL	0x5a5a5a5a5a5a5a5aul

static inline void trace_ctl(unsigned long v)
{
	mtspr(MTRC, v);
}

static inline unsigned long trace_status(void)
{
	unsigned long v = SENTINEL;

	__asm__ volatile("mfspr %0,730" : "+r" (v));
	return v;
}

static inline unsigned long trace_read(void)
{
	unsigned long v = SENTINEL;

	__asm__ volatile("mfspr %0,731" : "+r" (v));
	return v;
}

/* number of valid records */
static unsigned long trace_count(void)
{
	unsigned long st = trace_status();

	if (ST_FULL(st) || ST_WPTR(st) > TRACE_LEN)
		return TRACE_LEN;
	return ST_WPTR(st);
}

/* ---- output helpers ----------------------------------------------------- */

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

/* ---- MMU setup (same radix tree as tests/mmu) --------------------------- */

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
#define CHG		0x080
#define REF		0x100

#define DFLT_PERM	(PERM_WR | PERM_RD | REF | CHG)

unsigned long *pgdir = (unsigned long *) 0x10000;
unsigned long *pmdir = (unsigned long *) 0x11000;
unsigned long *proc_tbl = (unsigned long *) 0x12000;
unsigned long *part_tbl = (unsigned long *) 0x13000;
unsigned long free_ptr = 0x14000;

void init_mmu(void)
{
	/* set up partition table */
	store_pte(&part_tbl[1], (unsigned long)proc_tbl);
	/* set up process table */
	zero_memory(proc_tbl, 512 * sizeof(unsigned long));
	mtspr(PTCR, (unsigned long)part_tbl);
	mtspr(PID, 1);
	zero_memory(pgdir, 512 * sizeof(unsigned long));
	store_pte(&pgdir[0], 0x8000000000000000ul | (unsigned long) pmdir | 9);
	zero_memory(pmdir, 512 * sizeof(unsigned long));
	/* RTS = 8 (512GB address space), RPDS = 9 (512-entry top level) */
	store_pte(&proc_tbl[2 * 1], (unsigned long) pgdir | 0xa000000000000009ul);
	do_tlbie(0xc00, 0);	/* invalidate all TLB entries */
}

static inline unsigned long load_pte(unsigned long *p)
{
	unsigned long ret;

	__asm__ volatile("ldbrx %0,0,%1" : "=r" (ret) : "r" (p) : "memory");
	return ret;
}

static unsigned long *read_pmd(unsigned long i)
{
	return (unsigned long *) (load_pte(&pmdir[i]) & 0x00ffffffffffff00);
}

void map(void *ea, void *pa, unsigned long perm_attr)
{
	unsigned long epn = (unsigned long) ea >> 12;
	unsigned long i, j;
	unsigned long *ptep;

	i = (epn >> 9) & 0x1ff;
	j = epn & 0x1ff;
	if (pmdir[i] == 0) {
		zero_memory((void *)free_ptr, 512 * sizeof(unsigned long));
		store_pte(&pmdir[i], 0x8000000000000000 | free_ptr | 9);
		free_ptr += 512 * sizeof(unsigned long);
	}
	ptep = read_pmd(i);
	store_pte(&ptep[j], 0xc000000000000000 | ((unsigned long)pa & 0x00fffffffffff000) | perm_attr);
}

/* ---- trace array scanning ----------------------------------------------- */

/*
 * Search the captured records for one whose EA word matches ea and, if
 * event is non-zero, whose event field matches too.  Returns the record
 * index or -1.
 */
int find_record(unsigned long ea, unsigned long event)
{
	unsigned long n, i, w0, w3;

	n = trace_count();
	trace_ctl(TRC_ADDR(0, 0));
	for (i = 0; i < n; ++i) {
		w0 = trace_read();	/* EA */
		(void) trace_read();	/* PTCR */
		(void) trace_read();	/* descriptor */
		w3 = trace_read();	/* misc */
		if (w0 == ea && (event == 0 || M_EVENT(w3) == event))
			return i;
	}
	return -1;
}

/* ---- the tests ---------------------------------------------------------- */

long *va_a = (long *) 0x124000;
long *va_b = (long *) 0x125000;
long *va_unmapped = (long *) 0x126000;
long *mem_a = (long *) 0x20000;
long *mem_b = (long *) 0x21000;

/* an address that nothing else touches, so a load from it misses the dcache */
long *cold_line = (long *) 0x30000;

/*
 * Flush all cached translations, re-arm, do one load through ea, then
 * freeze.  Returns test_read's result (0, or 0x300 on a DSI).
 */
static int capture_walk(long *ea, long *val)
{
	int ret;

	do_tlbie_all(0xc00, 0);
	trace_ctl(TRC_EN | TRC_REARM);
	ret = test_read(ea, val, 0xdeadbeefd00d);
	trace_ctl(0);
	return ret;
}

/*
 * MTRC writes are reflected in the MTRC status.  If the SPRs are not
 * decoded, mfspr leaves the destination unchanged and the sentinel shows.
 */
int trace_test_1(void)
{
	unsigned long st;

	trace_ctl(TRC_REARM | TRC_ADDR(0, 0));
	st = trace_status();
	if (st == SENTINEL)
		return 1;
	if (ST_EN(st) || ST_FULL(st))
		return 2;
	if (ST_WPTR(st) != 0)
		return 3;
	if (ST_RADDR(st) != 0)
		return 4;

	trace_ctl(TRC_EN | 5);
	st = trace_status();
	if (!ST_EN(st))
		return 5;
	if (ST_RADDR(st) != 5)
		return 6;
	return 0;
}

/*
 * The first record after a re-arm is the WALK_START for the load.  Reading
 * MTRD walks its four words in order and moves on to the next record.
 */
int trace_test_2(void)
{
	unsigned long w0, w1, w3, w4, st;
	long val;

	if (capture_walk(va_a, &val))
		return 1;
	if (val != 0xbadc0ffee)
		return 2;

	trace_ctl(TRC_ADDR(0, 0));
	w0 = trace_read();
	w1 = trace_read();
	(void) trace_read();
	w3 = trace_read();
	st = trace_status();
	w4 = trace_read();

	if (w0 != (unsigned long) va_a)
		return 3;
	if (w1 != (unsigned long) part_tbl)
		return 4;
	if (M_EVENT(w3) != EV_WALK_START)
		return 5;
	if (ST_RADDR(st) != TRC_ADDR(1, 0))
		return 6;

	trace_ctl(TRC_ADDR(1, 0));
	if (trace_read() != w4)
		return 7;
	return 0;
}

/* A real page walk is captured as WALK_START with its EA in word 0. */
int trace_test_3(void)
{
	long val;

	if (capture_walk(va_a, &val))
		return 1;
	if (val != 0xbadc0ffee)
		return 2;
	if (ST_WPTR(trace_status()) == 0)
		return 3;
	if (find_record((unsigned long) va_a, EV_WALK_START) < 0)
		return 4;
	return 0;
}

/* With capture frozen, a new walk must not be recorded. */
int trace_test_4(void)
{
	unsigned long wptr;
	long val;

	/* capture is still frozen from test 3 */
	wptr = ST_WPTR(trace_status());
	do_tlbie_all(0xc00, 0);
	if (test_read(va_b, &val, 0xdeadbeefd00d))
		return 1;
	if (val != 0xfeedface)
		return 2;

	if (ST_WPTR(trace_status()) != wptr)
		return 3;
	if (find_record((unsigned long) va_b, 0) >= 0)
		return 4;
	return 0;
}

/*
 * A cold walk through the 3-level tree set up by init_mmu()/map() reads
 * the partition and process table entries, the pgdir and pmdir entries,
 * then the leaf PTE.  Failures return (record << 4) | check.
 */
#define NWALK	6

int trace_test_5(void)
{
	unsigned long epn = (unsigned long) va_a >> 12;
	unsigned long ev[NWALK], desc[NWALK], mask[NWALK];
	unsigned long w0, w1, w2, w3;
	long val;
	int i;

	ev[0] = EV_WALK_START;
	ev[1] = EV_PART_DONE;
	ev[2] = EV_PROC_READ;
	ev[3] = EV_PTE_READ;
	ev[4] = EV_PTE_READ;
	ev[5] = EV_TLB_LOAD;
	desc[1] = load_pte(&part_tbl[1]);
	desc[2] = load_pte(&proc_tbl[2 * 1]);
	desc[3] = load_pte(&pgdir[(epn >> 18) & 0x1ff]);
	desc[4] = load_pte(&pmdir[(epn >> 9) & 0x1ff]);
	desc[5] = load_pte(&read_pmd((epn >> 9) & 0x1ff)[epn & 0x1ff]);
	for (i = 1; i < NWALK; ++i)
		mask[i] = ~0ul;
	/* hardware may set R and C in the leaf PTE */
	mask[5] = ~(unsigned long) (REF | CHG);

	if (capture_walk(va_a, &val))
		return 1;
	if (val != 0xbadc0ffee)
		return 2;
	if (trace_count() != NWALK)
		return 3;

	trace_ctl(TRC_ADDR(0, 0));
	for (i = 0; i < NWALK; ++i) {
		w0 = trace_read();
		w1 = trace_read();
		w2 = trace_read();
		w3 = trace_read();
		if (w0 != (unsigned long) va_a)
			return (i << 4) | 1;
		if (w1 != (unsigned long) part_tbl)
			return (i << 4) | 2;
		if (M_EVENT(w3) != ev[i])
			return (i << 4) | 3;
		if (i > 0 && (w2 & mask[i]) != (desc[i] & mask[i]))
			return (i << 4) | 4;
	}
	return 0;
}

/* A load from an unmapped address records an ERROR with the invalid flag. */
int trace_test_6(void)
{
	unsigned long n, i, w0, w3 = 0;
	long val;

	if (capture_walk(va_unmapped, &val) != 0x300)
		return 1;

	n = trace_count();
	trace_ctl(TRC_ADDR(0, 0));
	for (i = 0; i < n; ++i) {
		w0 = trace_read();
		(void) trace_read();
		(void) trace_read();
		w3 = trace_read();
		if (w0 == (unsigned long) va_unmapped && M_EVENT(w3) == EV_ERROR)
			break;
	}
	if (i == n)
		return 2;
	if (!(w3 & M_INVALID))
		return 3;
	return 0;
}

/* mtspr MTRD completes and changes neither the read address nor status. */
int trace_test_7(void)
{
	unsigned long st0, st1;

	trace_ctl(TRC_ADDR(1, 2));
	st0 = trace_status();
	mtspr(MTRD, 0x123456789abcdef0ul);
	st1 = trace_status();
	if (ST_RADDR(st0) != TRC_ADDR(1, 2))
		return 1;
	if (st1 != st0)
		return 2;
	return 0;
}

static int user_test(char *fn)
{
	unsigned long msr;
	int vec;

	__asm__ volatile("mtdec %0" : : "r" (0x7fffffff));
	__asm__ volatile("mfmsr %0" : "=r" (msr));
	vec = test_exec(0, (unsigned long) fn, msr | MSR_PR);
	if (vec != 0x700)
		return 1;
	/* privileged instruction type */
	msr |= MSR_PR | MSR_EE | MSR_IR | MSR_DR;
	if (mfspr(SRR1) != (msr | 0x40000))
		return 2;
	return 0;
}

/* mfspr MTRD and mtspr MTRC in problem state are privileged instructions. */
int trace_test_8(void)
{
	int ret;

	ret = user_test(user_mfspr_mtrd);
	if (ret)
		return ret;
	ret = user_test(user_mtspr_mtrc);
	if (ret)
		return ret + 2;
	return 0;
}

/*
 * Seek, load from a line that misses the dcache, then two MTRD reads
 * back to back.  They must return words 0 and 1 of the record.
 */
int trace_test_9(void)
{
	unsigned long w0, w1, v0, v1;
	long val, dummy;

	if (capture_walk(va_a, &val))
		return 1;

	trace_ctl(TRC_ADDR(0, 0));
	w0 = trace_read();
	w1 = trace_read();
	if (w0 != (unsigned long) va_a || w1 != (unsigned long) part_tbl)
		return 2;

	__asm__ volatile("mtspr 730,%4\n\t"
			 "ld %0,0(%3)\n\t"
			 "mfspr %1,731\n\t"
			 "mfspr %2,731"
			 : "=&r" (dummy), "=&r" (v0), "=&r" (v1)
			 : "b" (cold_line), "r" (TRC_ADDR(0, 0))
			 : "memory");
	(void) dummy;

	if (v0 != w0)
		return 3;
	if (v1 != w1)
		return 4;
	return 0;
}

/* ---- driver ------------------------------------------------------------- */

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
		if (ret < 10)
			putchar(ret + '0');
		else
			print_hex(ret);
		print_string("\r\n");
	}
}

int main(void)
{
	console_init();
	init_mmu();

	map(va_a, mem_a, DFLT_PERM);
	map(va_b, mem_b, DFLT_PERM);
	mem_a[0] = 0xbadc0ffee;
	mem_b[0] = 0xfeedface;
	/* user stubs for test 8 */
	map(user_mfspr_mtrd, user_mfspr_mtrd, REF | CHG | PERM_RD | PERM_EX);
	map(user_mtspr_mtrc, user_mtspr_mtrc, REF | CHG | PERM_RD | PERM_EX);

	do_test(1, trace_test_1);
	do_test(2, trace_test_2);
	do_test(3, trace_test_3);
	do_test(4, trace_test_4);
	do_test(5, trace_test_5);
	do_test(6, trace_test_6);
	do_test(7, trace_test_7);
	do_test(8, trace_test_8);
	do_test(9, trace_test_9);

	return fail;
}
