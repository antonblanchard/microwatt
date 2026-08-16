/*
 * Test for the MMU page-walk trace array (SPR 704 / SPR 705).
 *
 * The trace array lives in mmu.vhdl behind the HAS_MMU_TRACE generic, which
 * core_tb.vhdl enables for simulation.  Software reaches it through a pair of
 * SPRs which decode2.vhdl routes to the LDST pipe alongside DAR/DSISR/PID/PTCR:
 *
 *   mtspr 704, rX   control: capture enable / read-pointer seek / slot poke
 *   mfspr rX, 705   streaming read of the currently selected word
 *
 * Sub-tests:
 *   01  SPR round trip - poke a slot, read it straight back
 *   02  four-word streaming read and its pointer auto-advance
 *   03  a real page-walk lands in the array as EV_WALK_START with the right EA
 *   04  SPR704[63] = 0 freezes capture, so a later walk records nothing
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define MSR_DR	0x10

extern int test_read(long *addr, long *ret, long init);

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

/* RIC=2: also invalidate the page-walk and process-table caches, so the next
 * translation is a full cold walk from memory and therefore generates records. */
static inline void do_tlbie_all(unsigned long rb, unsigned long rs)
{
	__asm__ volatile(".machine \"power10\"; tlbie %0,%1,2,1,1" : : "r" (rb), "r" (rs) : "memory");
}

/* ---- trace array access ------------------------------------------------- */

/*
 * SPR 704 is a single packed control word:
 *
 *   [63]     capture enable (1 = capturing, 0 = frozen)
 *   [62:13]  data (50 bits) - written into the selected slot when non-zero
 *   [12:11]  word select     0 = EA, 1 = PTCR, 2 = PDE, 3 = misc
 *   [10:0]   record index (0 .. 2047)
 *
 * Every write seeks the read pointer to (index, word), so a poke can be read
 * back immediately.  A zero data field makes the write address-only, which is
 * how you seek without disturbing the slot contents.
 */
#define TR_SEEK(en, word, idx)		(((unsigned long)(en) << 63) | \
					 ((unsigned long)(word) << 11) | \
					 (unsigned long)(idx))
#define TR_POKE(en, word, idx, data)	(TR_SEEK(en, word, idx) | \
					 ((unsigned long)(data) << 13))

static inline void trace_ctl(unsigned long v)
{
	__asm__ volatile("mtspr 704,%0" : : "r" (v));
}

static inline unsigned long trace_read(void)
{
	unsigned long v;

	__asm__ volatile("mfspr %0,705" : "=r" (v));
	return v;
}

/* misc word (word 3) field extractors, matching the packing in mmu.vhdl */
#define M_EVENT(m)	(((m) >> 48) & 0xful)

#define EV_WALK_START	1ul

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

/* ---- MMU setup (same 2-level radix tree as tests/mmu) ------------------- */

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

static unsigned long *read_pmd(unsigned long i)
{
	unsigned long ret;

	__asm__ volatile("ldbrx %0,%1,%2" : "=r" (ret) : "b" (pmdir),
			 "r" (i * sizeof(unsigned long)));
	return (unsigned long *) (ret & 0x00ffffffffffff00);
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
 * Search the first NSCAN records for one whose EA word matches `ea`.  Returns
 * the record index, or -1 if there is no match.  If `event` is non-zero the
 * record's event field must match it too.
 *
 * The write pointer only returns to 0 on reset and firmware cannot rewind it,
 * so we scan a window rather than assuming records start at slot 0.
 */
#define NSCAN	32

int find_record(unsigned long ea, unsigned long event)
{
	unsigned long w0, w3;
	int i;

	/* seek to record 0, word 0; data field is zero so this is address-only */
	trace_ctl(TR_SEEK(0, 0, 0));

	for (i = 0; i < NSCAN; ++i) {
		/* four reads walk one record and land on the next */
		w0 = trace_read();	/* EA   */
		(void) trace_read();	/* PTCR */
		(void) trace_read();	/* PDE  */
		w3 = trace_read();	/* misc */

		if (w0 == ea && (event == 0 || M_EVENT(w3) == event))
			return i;
	}
	return -1;
}

/* ---- the tests ---------------------------------------------------------- */

long *va_a = (long *) 0x124000;
long *va_b = (long *) 0x125000;
long *mem_a = (long *) 0x8000;
long *mem_b = (long *) 0x9000;

/*
 * Poke a known value into a slot and read it straight back.
 *
 * This is the test that fails if decode2.vhdl does not route SPR 704/705 to
 * the LDST pipe: mfspr from an unimplemented SPR clears write_enable, so the
 * destination register is left untouched rather than being set to the slot
 * contents.
 */
int trace_test_1(void)
{
	unsigned long val;

	/* freeze capture so nothing else disturbs the array */
	trace_ctl(TR_SEEK(0, 0, 0));

	/* poke slot 100, word 0.  The poke also seeks the read pointer there. */
	trace_ctl(TR_POKE(0, 0, 100, 0x12345));

	val = trace_read();
	if (val != 0x12345)
		return 1;
	return 0;
}

/*
 * Four consecutive reads should return words 0..3 of a record in order, the
 * word select advancing after each read.
 */
int trace_test_2(void)
{
	unsigned long v0, v1, v2, v3;

	trace_ctl(TR_SEEK(0, 0, 0));

	trace_ctl(TR_POKE(0, 0, 101, 0x11111));
	trace_ctl(TR_POKE(0, 1, 101, 0x22222));
	trace_ctl(TR_POKE(0, 2, 101, 0x33333));
	trace_ctl(TR_POKE(0, 3, 101, 0x44444));

	/* address-only seek back to word 0 of the same record */
	trace_ctl(TR_SEEK(0, 0, 101));

	v0 = trace_read();
	v1 = trace_read();
	v2 = trace_read();
	v3 = trace_read();

	if (v0 != 0x11111)
		return 1;
	if (v1 != 0x22222)
		return 2;
	if (v2 != 0x33333)
		return 3;
	if (v3 != 0x44444)
		return 4;
	return 0;
}

/*
 * A real page walk should be captured: the MMU emits EV_WALK_START when it
 * leaves IDLE for a translation, with the effective address in word 0.
 */
int trace_test_3(void)
{
	long val;

	map(va_a, mem_a, DFLT_PERM);
	mem_a[0] = 0xbadc0ffee;

	/* enable capture, then force a cold walk */
	trace_ctl(TR_SEEK(1, 0, 0));
	do_tlbie_all(0xc00, 0);
	if (test_read(va_a, &val, 0xdeadbeefd00d))
		return 1;
	if (val != 0xbadc0ffee)
		return 2;

	/* freeze before reading back, so the scan itself is stable */
	trace_ctl(TR_SEEK(0, 0, 0));

	if (find_record((unsigned long) va_a, EV_WALK_START) < 0)
		return 3;
	return 0;
}

/*
 * With SPR704[63] = 0 the array is frozen, so a subsequent walk must not
 * appear anywhere in the scan window.
 */
int trace_test_4(void)
{
	long val;

	map(va_b, mem_b, DFLT_PERM);
	mem_b[0] = 0xfeedface;

	/* capture is still frozen from test 3 */
	do_tlbie_all(0xc00, 0);
	if (test_read(va_b, &val, 0xdeadbeefd00d))
		return 1;
	if (val != 0xfeedface)
		return 2;

	if (find_record((unsigned long) va_b, 0) >= 0)
		return 3;
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

	do_test(1, trace_test_1);
	do_test(2, trace_test_2);
	do_test(3, trace_test_3);
	do_test(4, trace_test_4);

	return fail;
}
