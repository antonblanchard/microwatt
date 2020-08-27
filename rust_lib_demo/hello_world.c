#include <stdint.h>
#include <stdbool.h>

#include "console.h"

void rust_main();

void crash()
{
	void (*fun_ptr)() = (void(*)()) 0xdeadbeef;
	(*fun_ptr)();
}

void init_bss()
{
	extern int _bss, _ebss;
	int *p = &_bss;
	while (p < &_ebss) {
		*p++ = 0;
	}
}

#define HELLO_WORLD "Hello World\n"

int main(void)
{
	init_bss();
	console_init();

	puts(HELLO_WORLD);

	rust_main();
	crash();

	while (1)
		;
}
