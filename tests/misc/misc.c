#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

#define PVR_MICROWATT 0x00630000

extern long test_addpcis_1(void);
extern long test_addpcis_2(void);
extern long test_mfpvr(void);
extern long test_mtpvr(void);
extern long test_bdnzl(void);

// i < 100
void print_test_number(int i)
{
	puts(TEST);
	putchar(48 + i/10);
	putchar(48 + i%10);
	putchar(':');
}

int main(void)
{
	int fail = 0;

	console_init();

	print_test_number(1);
	if (test_addpcis_1() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(2);
	if (test_addpcis_2() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(3);
	if (test_mfpvr() != PVR_MICROWATT) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(4);
	if (test_mtpvr() != PVR_MICROWATT) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(5);
	if (test_bdnzl() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	return fail;
}
