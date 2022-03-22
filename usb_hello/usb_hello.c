#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "liteuart_console.h"

#include "microwatt_soc.h"
#include "io.h"

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

static void print_hex(unsigned long val, int ndigits)
{
	int i, x;

	for (i = (ndigits - 1) * 4; i >= 0; i -= 4) {
		x = (val >> i) & 0xf;
		if (x >= 10)
			putchar(x + 'a' - 10);
		else
			putchar(x + '0');
	}
}

int main(void)
{
	console_init();
	usb_console_init();

	puts(mw_logo);

	for (int i = 0; i <= 0x14; i+=4) {
		unsigned long val = readl(UART0_BASE + i);
		puts("reg 0x");
		print_hex(i, 2);
		puts(" = 0x");
		print_hex(val, 8);
		puts("\n");
	}
	puts("printed\n");
	for (int i = 0; i <= 0x14; i+=4) {
		unsigned long val = readl(UART0_BASE + i);
		puts("reg 0x");
		print_hex(i, 2);
		puts(" = 0x");
		print_hex(val, 8);
		puts("\n");
	}
	puts("printed\n");

	usb_puts(mw_logo);

	while (1) {
		// puts(mw_logo);
		// usb_puts(mw_logo);
		unsigned char c = usb_getchar();
		putchar(c);
		usb_putchar(c);
		if (c == 13) // if CR send LF
			putchar(10);
	}
}
