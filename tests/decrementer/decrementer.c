#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define TEST "Test "
#define PASS "PASS\n"
#define FAIL "FAIL\n"

extern int dec_test_1(void);
extern int dec_test_2(void);
extern int dec_test_3(void);

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
	if (dec_test_1() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	print_test_number(2);
	if (dec_test_2() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);


	print_test_number(3);
	if (dec_test_3() != 0) {
		fail = 1;
		puts(FAIL);
	} else
		puts(PASS);

	return fail;
}
