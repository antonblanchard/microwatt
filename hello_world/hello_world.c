#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "io.h"
#include "microwatt_soc.h"

static char mw_logo1[] =
"\n"
"   .oOOo.     \n"
" .\"      \". \n"
" ;  .mw.  ;   Microwatt, it works.\n"
"  . '  ' .    \n"
"   \\ || /     HDL Git SHA1: ";

static char mw_logo2[] =
"\n"
"    ;..;      \n"
"    ;..;      \n"
"    `ww'      \n\n";

int main(void)
{
	uint64_t gitinfo;
	uint8_t c;
        bool dirty;

	console_init();

	puts(mw_logo1);

	gitinfo = readq(SYSCON_BASE + SYS_REG_GIT_INFO);
        dirty = gitinfo >> 63;
	for (int i = 0; i < 14; i++) {
		c = (gitinfo >> 52) & 0xf;
		if (c >= 10)
                        putchar(0x61 + c - 10); // a-f
                else
                        putchar(0x30 + c); // 0-9
		gitinfo <<= 4;
	}
        if (dirty)
                puts("-dirty");
	puts(mw_logo2);

	while (1) {
		unsigned char c = getchar();
		putchar(c);
		if (c == 13) // if CR send LF
			putchar(10);
	}
}
