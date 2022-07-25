#include <stdint.h>
#include <stdbool.h>

#include "console.h"


#define asm     __asm__ volatile

#define MMCR0   795
#define MMCR1   798
#define MMCR2   785
#define MMCRA   786
#define PMC1    771
#define PMC2    772
#define PMC3    773
#define PMC4    774
#define PMC5    775
#define PMC6    776

#define MMCR0_FC    0x80000000 // Freeze Counters
#define PMC1SEL_FC  0xFC000000 // Load Completed
#define PMC2SEL_F0  0x00F00000 // Store Completed

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

static inline unsigned long mfspr(int sprnum)
{
	unsigned long val;

	asm("mfspr %0,%1" : "=r" ((unsigned long) val) : "i" (sprnum));
	return val;
}

static inline void mtspr(int sprnum, unsigned long val)
{
	asm("mtspr %0,%1" : : "i" (sprnum), "r" ((unsigned long) val));
}

void print_test_number(int i)
{
	puts(TEST);
	putchar(48 + i/10);
	putchar(48 + i%10);
	putchar(':');
}

void reset_pmu() {
	mtspr(MMCR0, MMCR0_FC);
	mtspr(MMCR1, 0);
	mtspr(PMC1, 0);
	mtspr(PMC2, 0);
	mtspr(PMC3, 0);
	mtspr(PMC4, 0);
	mtspr(PMC5, 0);
	mtspr(PMC6, 0);
}

/*
	Sets PMC1 to count finished load instructions
	Runs 50 load instructions
	Expects PMC1 to be 50 at the end
*/
int test_load_complete()
{
	reset_pmu();
	unsigned long volatile b = 0;
	mtspr(MMCR1, PMC1SEL_FC);
	mtspr(MMCR0, 0);

	for(int i = 0; i < 50; i++)
		++b;

	mtspr(MMCR0, MMCR0_FC);

	return mfspr(PMC1) == 50;
}

/*
	Sets PMC2 to count finished store instructions
	Runs 50 store instructions
	Expects PMC2 to be 50 at the end
*/
int test_store_complete()
{
	reset_pmu();
	unsigned long volatile b = 0;
	mtspr(MMCR1, PMC2SEL_F0);
	mtspr(MMCR0, 0);

	for(int i = 0; i < 50; i++)
		++b;

	mtspr(MMCR0, MMCR0_FC);

	return mfspr(PMC2) == 50;
}

/*
	Allow PMC5 to count finished instructions
	Runs a loop 50 times
	Expects PMC5 to be more than zero at the end
*/
int test_instruction_complete()
{
	reset_pmu();
	unsigned long volatile b = 0;
	mtspr(MMCR0, 0);

	for(int i = 0; i < 50; i++)
		++b;

	mtspr(MMCR0, MMCR0_FC);

	return mfspr(PMC5) > 0;
}

/*
	Allow PMC6 to count cycles
	Runs a loop 50 times
	Expects PMC6 to be more than zero at the end
*/
int test_count_cycles()
{
    reset_pmu();
    unsigned long volatile b = 0;
    mtspr(MMCR0, 0);

    for(int i = 0; i < 50; i++)
	    ++b;

    mtspr(MMCR0, MMCR0_FC);

    return mfspr(PMC6) > 0;
}

int main(void)
{
    int fail = 0;

    console_init();

    print_test_number(1);
	if (test_load_complete() != 1) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(2);
	if (test_store_complete() != 1) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(3);
	if (test_instruction_complete() == 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(4);
	if (test_count_cycles() == 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

    return fail;
}
