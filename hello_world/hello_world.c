#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "io.h"
#include "microwatt_soc.h"

static char mw_logo[] =

"\n"
"   .oOOo.     \n"
" .\"      \". \n"
" ;  .mw.  ;   Microwatt, it works.\n"
"  . '  ' .    \n"
"   \\ || /    \n"
"    ;..;      \n"
"    ;..;      \n"
"    `ww'   \n";

int main(void)
{
	uint64_t gitinfo;
	uint8_t c;

	console_init();

	puts(mw_logo);

	gitinfo = readq(SYSCON_BASE + SYS_REG_GIT_INFO);
	for (int i = 0; i < 16; i++) {
		c = gitinfo % 16;
		if (c >= 10) putchar(0x61 + c - 10); else putchar(0x30 + c);
		gitinfo >>= 4;
	}

	while (1) {
		unsigned char c = getchar();
		putchar(c);
		if (c == 13) // if CR send LF
			putchar(10);
	}
}
