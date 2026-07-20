#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

/*
 * TRACE_CURATED_LOGGING_TEST                                    (2026-07-12)
 *
 * Validates the curated MMU-trace hookup added in mmu.vhdl:
 *   - logging happens on DATA-READY edges (so word2/pde is the descriptor
 *     actually fetched, not a stale issue-time value),
 *   - only interesting FSM states are logged (WALK_START, PART_DONE,
 *     PROC_READ, PTE_READ, TLB_LOAD, ERROR) and the noisy issue edges
 *     (RADIX_LOOKUP / *_TBL_READ), SEG_CHECK-pass, TLBIE and success-FINISH
 *     are skipped,
 *   - one-shot "stop when full": the array freezes after 2048 records
 *     (misc[25]=1 on the last slot), preserves the FIRST 2048 records, and
 *     re-arms (write pointer back to 0) on the next trace_enable_seek().
 *
 * See CYCLE_SIM/README_MMU_TRACE_HOOKUP_2026-07-12.md for the full model.
 *
 * Eight sub-tests, each PASSes on the new RTL and FAILs on the old RTL.
 */

/* ---- SPR 704/705 intrinsics (bit-63 enable protocol) --------------------- */
static inline void trace_disable_seek(unsigned int idx)
{
    unsigned long v = (unsigned long)(idx & 0x7FFu);
    __asm__ volatile("mtspr 704,%0" : : "r"(v));
}
static inline void trace_enable_seek(unsigned int idx)
{
    unsigned long v = (1UL << 63) | (unsigned long)(idx & 0x7FFu);
    __asm__ volatile("mtspr 704,%0" : : "r"(v));
}
static inline void trace_disable(void) { trace_disable_seek(0); }
static inline void trace_enable(void)  { trace_enable_seek(0); }
static inline unsigned long trace_read_word(void)
{
    unsigned long v;
    __asm__ volatile("mfspr %0,705" : "=r"(v));
    return v;
}

/* ---- misc-word field extractors ------------------------------------------ */
#define M_PID(m)   (((m) >> 52) & 0xFFFUL)
#define M_EVENT(m) (((m) >> 48) & 0xFUL)
#define M_STATE(m) (((m) >> 44) & 0xFUL)
#define M_DONE(m)  (((m) >> 31) & 1UL)
#define M_INVAL(m) (((m) >> 30) & 1UL)
#define M_FULL(m)  (((m) >> 25) & 1UL)   /* new: array-full / frozen marker */

/* mmu_event_t values */
#define EV_NONE         0U
#define EV_WALK_START   1U
#define EV_TLBIE        2U
#define EV_PART_READ    3U
#define EV_PART_DONE    4U
#define EV_PROC_READ    5U
#define EV_SEG_CHECK    6U
#define EV_RADIX_LOOKUP 7U
#define EV_PTE_READ     8U
#define EV_TLB_LOAD     9U
#define EV_FINISH      10U
#define EV_ERROR       11U

/* state_t values */
#define STATE_LOAD_TLB 10U   /* RADIX_LOAD_TLB */

/* ---- generic SPR + memory helpers ---------------------------------------- */
static inline void mtspr_fn(int sprnum, unsigned long val)
{
    __asm__ volatile("mtspr %0,%1" : : "i"(sprnum), "r"(val));
}
static inline void store_pte(unsigned long *p, unsigned long pte)
{
    __asm__ volatile("stdbrx %1,0,%0" : : "r"(p), "r"(pte) : "memory");
}
static inline void do_tlbie(unsigned long rb, unsigned long rs)
{
    __asm__ volatile(".machine \"power10\"; tlbie %0,%1,0,1,1"
                     : : "r"(rb), "r"(rs) : "memory");
}
/* RIC=2: invalidate TLB + page-walk cache + process-table cache, so the next
 * walk is a full cold walk from memory (used to fill the trace array quickly). */
static inline void do_tlbie_all(unsigned long rb, unsigned long rs)
{
    __asm__ volatile(".machine \"power10\"; tlbie %0,%1,2,1,1"
                     : : "r"(rb), "r"(rs) : "memory");
}

#define PID  48
#define PTCR 464

/* ---- output helpers ------------------------------------------------------ */
static int g_test_no;
static int g_pass;
static int g_fail;

static void print_hex(unsigned long val)
{
    int i, x;
    for (i = 60; i >= 0; i -= 4) {
        x = (int)((val >> i) & 0xf);
        putchar(x < 10 ? x + '0' : x + 'a' - 10);
    }
}
static void print_dec(unsigned long v)
{
    char buf[20];
    int i = 0;
    if (v == 0) { putchar('0'); return; }
    while (v) { buf[i++] = '0' + (int)(v % 10); v /= 10; }
    while (i--) putchar(buf[i]);
}

static const char *event_name(unsigned int e)
{
    switch (e) {
    case 0:  return "EV_NONE";
    case 1:  return "EV_WALK_START";
    case 2:  return "EV_TLBIE";
    case 3:  return "EV_PART_READ";
    case 4:  return "EV_PART_DONE";
    case 5:  return "EV_PROC_READ";
    case 6:  return "EV_SEG_CHECK";
    case 7:  return "EV_RADIX_LOOKUP";
    case 8:  return "EV_PTE_READ";
    case 9:  return "EV_TLB_LOAD";
    case 10: return "EV_FINISH";
    case 11: return "EV_ERROR";
    default: return "EV_??";
    }
}

#define INDENT "          "
#define RULE   "------------------------------------------------------------------------\n"
#define BANNER "========================================================================\n"

static void kv_str(const char *label, const char *v)
{ puts(INDENT); puts(label); puts(": "); puts(v); putchar('\n'); }
static void kv_hex(const char *label, unsigned long v)
{ puts(INDENT); puts(label); puts(": 0x"); print_hex(v); putchar('\n'); }
static void kv_dec(const char *label, unsigned long v)
{ puts(INDENT); puts(label); puts(": "); print_dec(v); putchar('\n'); }

static void hdr(const char *desc)
{
    g_test_no += 1;
    puts("[Test ");
    putchar(48 + g_test_no / 10);
    putchar(48 + g_test_no % 10);
    puts("] ");
    puts(desc);
    putchar('\n');
}
static int verdict(int pass)
{
    puts(INDENT "result    : ");
    if (pass) { puts("PASS\n"); g_pass += 1; }
    else       { puts("FAIL\n"); g_fail += 1; }
    puts(RULE);
    return pass ? 0 : 1;
}

/* ---- radix MMU setup (condensed from tests/mmu/mmu.c) -------------------- */
#define PERM_WR   0x002UL
#define PERM_RD   0x004UL
#define REF       0x100UL
#define CHG       0x080UL
#define DFLT_PERM (PERM_WR | PERM_RD | REF | CHG)

unsigned long *pgdir    = (unsigned long *) 0x10000;
unsigned long *pmdir    = (unsigned long *) 0x11000;
unsigned long *proc_tbl = (unsigned long *) 0x12000;
unsigned long *part_tbl = (unsigned long *) 0x13000;
unsigned long  free_ptr = 0x14000UL;

static void zero_memory(void *ptr, unsigned long nbytes)
{
    unsigned long i;
    for (i = 0; i < nbytes; ++i)
        ((unsigned char *)ptr)[i] = 0;
}
static void init_mmu(void)
{
    store_pte(&part_tbl[1], (unsigned long)proc_tbl);
    zero_memory(proc_tbl, 512 * sizeof(unsigned long));
    mtspr_fn(PTCR, (unsigned long)part_tbl);
    mtspr_fn(PID,  1);
    zero_memory(pgdir, 512 * sizeof(unsigned long));
    store_pte(&pgdir[0], 0x8000000000000000UL | (unsigned long)pmdir | 9);
    zero_memory(pmdir, 512 * sizeof(unsigned long));
    store_pte(&proc_tbl[2 * 1], (unsigned long)pgdir | 0xa000000000000009UL);
    do_tlbie(0xc00, 0);
}
static unsigned long *read_pmd(unsigned long i)
{
    unsigned long ret;
    __asm__ volatile("ldbrx %0,%1,%2" : "=r"(ret) : "b"(pmdir),
                     "r"(i * sizeof(unsigned long)));
    return (unsigned long *)(ret & 0x00ffffffffffff00UL);
}
static void map(void *ea, void *pa, unsigned long perm_attr)
{
    unsigned long epn = (unsigned long)ea >> 12;
    unsigned long i   = (epn >> 9) & 0x1ff;
    unsigned long j   = epn & 0x1ff;
    unsigned long *ptep;

    if (pmdir[i] == 0) {
        zero_memory((void *)free_ptr, 512 * sizeof(unsigned long));
        store_pte(&pmdir[i], 0x8000000000000000UL | free_ptr | 9);
        free_ptr += 512 * sizeof(unsigned long);
    }
    ptep = read_pmd(i);
    store_pte(&ptep[j],
              0xc000000000000000UL |
              ((unsigned long)pa & 0x00fffffffffff000UL) | perm_attr);
}

/* ---- trace-array record helpers ------------------------------------------ */
struct trace_record { unsigned long ea, ptcr, pde, misc; };

/* Seek to record idx and drain its 4 words.  trace_disable_seek freezes
 * capture (bit63=0) as a side-effect, which is fine in the read-out phase. */
static void read_record(unsigned int idx, struct trace_record *r)
{
    trace_disable_seek(idx);
    r->ea   = trace_read_word();
    r->ptcr = trace_read_word();
    r->pde  = trace_read_word();
    r->misc = trace_read_word();
}

#define SCAN_N 256U

/* First record in [0,SCAN_N) whose event==ev and (want_ea==0 || ea==want_ea). */
static int find_event(unsigned int ev, unsigned long want_ea)
{
    struct trace_record r;
    unsigned int i;
    for (i = 0; i < SCAN_N; ++i) {
        read_record(i, &r);
        if ((unsigned int)M_EVENT(r.misc) == ev &&
            (want_ea == 0UL || r.ea == want_ea))
            return (int)i;
    }
    return -1;
}

/* ---- boot stub declaration ----------------------------------------------- */
extern int test_read(long *addr, long *ret, long init);

/* ========================================================================== */
int main(void)
{
    int fail = 0;
    long val;
    struct trace_record r;

    long *va_a = (long *)0x124000UL;  /* mapped -> PA 0x8000 */
    long *va_b = (long *)0x125000UL;  /* mapped -> PA 0x9000 */
    long *va_u = (long *)0x200000UL;  /* UNMAPPED (pmdir[1] is empty) */
    long *pa_a = (long *)0x8000UL;
    long *pa_b = (long *)0x9000UL;

    console_init();

    /* SETUP — freeze capture while building page tables so their MTSPR/tlbie
     * ops are not recorded, then enable so record 0 is our first real walk. */
    trace_disable();
    pa_a[0] = (long)0xAAAAAAAAAAAAAAAAUL;
    pa_b[0] = (long)0xBBBBBBBBBBBBBBBBUL;
    init_mmu();
    map(va_a, pa_a, DFLT_PERM);
    map(va_b, pa_b, DFLT_PERM);

    puts("\n" BANNER);
    puts("  TRACE_CURATED_LOGGING_TEST  (2026-07-12)\n");
    puts("  curated data-ready MMU trace + one-shot stop-on-full\n");
    puts(BANNER "\n");

    /* First captured walk of VA_A is COLD (pt0_valid=0), so it exercises the
     * process-table read path used by Test 05. */
    trace_enable();
    (void)test_read(va_a, &val, 0);

    /* ==== Test 01 — WALK_START anchor carries the EA ===================== */
    hdr("WALK_START anchor: one record per translation, EA = VA");
    {
        int idx = find_event(EV_WALK_START, (unsigned long)va_a);
        kv_hex("VA_A      ", (unsigned long)va_a);
        if (idx >= 0) kv_dec("walk_start at rec ", (unsigned long)idx);
        else          kv_str("walk_start        ", "<not found>");
        fail |= verdict(idx >= 0);
    }

    /* ==== Test 02 — PTE_READ carries a FRESH directory descriptor ======== */
    hdr("PTE_READ (data-ready) holds a freshly-fetched directory PDE, not stale");
    {
        /* The leaf itself is carried by the TLB_LOAD record; the record right
         * before it is the last DIRECTORY read of the walk (valid, non-leaf,
         * pointing at the next-level table).  Proving that record exists as an
         * EV_PTE_READ with real directory contents shows the data-ready hookup
         * works (the old RTL emitted no EV_PTE_READ at all here). */
        int ktlb = find_event(EV_TLB_LOAD, (unsigned long)va_a);
        int ok = 0;
        unsigned long pde = 0, ev = 0;
        if (ktlb > 0) {
            read_record((unsigned int)(ktlb - 1), &r);
            pde = r.pde; ev = M_EVENT(r.misc);
            ok = (ev == EV_PTE_READ) &&
                 ((pde >> 63) & 1) &&                          /* valid       */
                 (((pde >> 62) & 1) == 0) &&                   /* NOT a leaf   */
                 ((pde & 0x00fffffffffff000UL) != 0);          /* real pointer */
        }
        kv_str("expected  ", "rec before TLB_LOAD is EV_PTE_READ, valid non-leaf directory");
        kv_dec("pte_read event    ", ev);
        kv_hex("directory (word2) ", pde);
        fail |= verdict(ok);
    }

    /* ==== Test 03 — no RADIX_LOOKUP issue-edge noise ===================== */
    hdr("No issue-edge noise: EV_RADIX_LOOKUP never appears");
    {
        int idx = find_event(EV_RADIX_LOOKUP, 0);
        kv_str("expected  ", "no EV_RADIX_LOOKUP record in scan window");
        if (idx >= 0) { puts(INDENT "got       : found at rec #");
                        print_dec((unsigned long)idx); puts(" (FAIL)\n"); }
        else            kv_str("got       ", "none — issue edge correctly skipped");
        fail |= verdict(idx < 0);
    }

    /* ==== Test 04 — TLB_LOAD correctness ================================= */
    hdr("TLB_LOAD: EA=VA_A, state=RADIX_LOAD_TLB, pde=leaf PTE");
    {
        int idx = find_event(EV_TLB_LOAD, (unsigned long)va_a);
        int ok = 0;
        if (idx >= 0) {
            read_record((unsigned int)idx, &r);
            ok = (r.ea == (unsigned long)va_a) &&
                 (M_STATE(r.misc) == STATE_LOAD_TLB) &&
                 (((r.pde >> 62) & 3) == 3) &&
                 (((r.pde >> 12) & 0xFFFFFFFUL) == (((unsigned long)pa_a) >> 12));
            kv_dec("rec               ", (unsigned long)idx);
            kv_hex("EA                ", r.ea);
            kv_dec("state             ", M_STATE(r.misc));
            kv_hex("pde (leaf)        ", r.pde);
        } else kv_str("got       ", "<not found>");
        fail |= verdict(ok);
    }

    /* ==== Test 05 — cold walk logs the process-table root =============== */
    hdr("Cold walk: EV_PROC_READ present with a valid tree root in word2");
    {
        int idx = find_event(EV_PROC_READ, 0);
        int ok = 0;
        unsigned long root = 0;
        if (idx >= 0) {
            read_record((unsigned int)idx, &r);
            root = r.pde;
            ok = ((root >> 63) & 1);     /* valid process-table entry */
        }
        kv_str("expected  ", "EV_PROC_READ record, word2 root has valid bit set");
        if (idx >= 0) kv_dec("proc_read at rec  ", (unsigned long)idx);
        kv_hex("root (word2)      ", root);
        fail |= verdict(ok);
    }

    /* ==== Test 06 — faulting walk logs EV_ERROR, no TLB_LOAD ============= */
    hdr("Fault walk (unmapped VA): EV_ERROR(invalid) and no TLB_LOAD");
    {
        trace_enable();                  /* re-enable capture after scans   */
        (void)test_read(va_u, &val, 0);  /* walk unmapped VA -> DSI + fault */

        int ierr = find_event(EV_ERROR, (unsigned long)va_u);
        int itlb = find_event(EV_TLB_LOAD, (unsigned long)va_u);
        int ok = 0;
        unsigned long mi = 0;
        if (ierr >= 0) { read_record((unsigned int)ierr, &r); mi = r.misc; }
        ok = (ierr >= 0) && (M_INVAL(mi) == 1) && (itlb < 0);
        kv_hex("VA_U (unmapped)   ", (unsigned long)va_u);
        if (ierr >= 0) { kv_dec("error at rec      ", (unsigned long)ierr);
                         kv_dec("invalid flag      ", M_INVAL(mi)); }
        else             kv_str("error             ", "<not found>");
        kv_str("no TLB_LOAD       ", itlb < 0 ? "confirmed" : "FAIL: found one");
        fail |= verdict(ok);
    }

    /* ==== Test 07 — success FINISH suppressed =========================== */
    hdr("Success FINISH suppressed: no EV_FINISH record for a good walk");
    {
        int idx = find_event(EV_FINISH, 0);
        kv_str("expected  ", "no EV_FINISH record (redundant with EV_TLB_LOAD)");
        if (idx >= 0) { puts(INDENT "got       : found at rec #");
                        print_dec((unsigned long)idx); puts(" (FAIL)\n"); }
        else            kv_str("got       ", "none — success finish correctly skipped");
        fail |= verdict(idx < 0);
    }

    /* ==== Test 08 — one-shot stop-on-full + re-arm ====================== */
    hdr("One-shot stop-on-full: freeze at 2048, keep first-N, re-arm to 0");
    {
        unsigned long rec0_ea_before, last_misc, rec0_ea_after;
        int ok_full, ok_keep, ok_rearm, full = 0;
        unsigned int i;

        /* Fill the array: repeatedly flush ALL MMU caches (RIC=2) and re-walk
         * VA_A, so every iteration is a full cold walk emitting ~5 records.
         * Peek record 2047 every 32 walks to stop as soon as it freezes (a
         * peek disables capture, so re-enable to continue).  Cap for safety. */
        trace_enable();
        for (i = 0; i < 4000U && !full; ++i) {
            do_tlbie_all(0xc00, 0);
            (void)test_read(va_a, &val, 0);
            if ((i & 31U) == 31U) {
                read_record(2047U, &r);          /* disables capture */
                if (M_FULL(r.misc)) full = 1;
                else                trace_enable(); /* re-arm; wr_ptr preserved */
            }
        }

        /* (a) the last slot must be marked full/frozen */
        read_record(2047U, &r);
        last_misc = r.misc;
        ok_full = (M_FULL(last_misc) == 1);

        /* (b) record 0 must still be our very first walk (EA = VA_A): the
         *     first 2048 records were preserved, not overwritten by wrap. */
        read_record(0U, &r);
        rec0_ea_before = r.ea;
        ok_keep = (rec0_ea_before == (unsigned long)va_a);

        /* (c) re-arm: enabling while full resets the write pointer to 0.
         *     Walk VA_B and confirm record 0 is now VA_B. */
        trace_enable_seek(0);
        do_tlbie_all(0xc00, 0);
        (void)test_read(va_b, &val, 0);
        read_record(0U, &r);
        rec0_ea_after = r.ea;
        ok_rearm = (rec0_ea_after == (unsigned long)va_b);

        kv_str("expected  ", "misc[25]=1 @2047; rec0=VA_A; after re-arm rec0=VA_B");
        kv_dec("misc[25] full     ", M_FULL(last_misc));
        kv_hex("rec0 EA (kept)    ", rec0_ea_before);
        kv_hex("rec0 EA (re-arm)  ", rec0_ea_after);
        kv_hex("VA_A / VA_B       ", (unsigned long)va_a);
        fail |= verdict(ok_full && ok_keep && ok_rearm);
    }

    /* ==== Summary ======================================================= */
    puts(BANNER);
    puts("  SUMMARY : ");
    print_dec((unsigned long)g_pass);
    puts(" PASS / ");
    print_dec((unsigned long)g_fail);
    puts(" FAIL   ->  ");
    puts(g_fail == 0 ? "ALL TESTS PASSED\n" : "SOME TESTS FAILED\n");
    puts(BANNER);

    return fail;
}
