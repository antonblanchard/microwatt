#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "console.h"

#define HELLO_WORLD "Hello World\r\n"

int main(void)
{
	potato_uart_init();

	putstr(HELLO_WORLD, strlen(HELLO_WORLD));

	while (1) {
		unsigned char c = getchar();
		putchar(c);
	}
}
