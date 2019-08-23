#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

/*
 * Core UART functions to implement for a port
 */

static uint64_t potato_uart_base;

#define PROC_FREQ 100000000
#define UART_FREQ 115200
#define UART_BASE 0xc0002000

#define POTATO_CONSOLE_TX		0x00
#define POTATO_CONSOLE_RX		0x08
#define POTATO_CONSOLE_STATUS		0x10
#define   POTATO_CONSOLE_STATUS_RX_EMPTY		0x01
#define   POTATO_CONSOLE_STATUS_TX_EMPTY		0x02
#define   POTATO_CONSOLE_STATUS_RX_FULL			0x04
#define   POTATO_CONSOLE_STATUS_TX_FULL			0x08
#define POTATO_CONSOLE_CLOCK_DIV	0x18
#define POTATO_CONSOLE_IRQ_EN		0x20

static uint64_t potato_uart_reg_read(int offset)
{
	uint64_t addr;
	uint64_t val;

	addr = potato_uart_base + offset;

	val = *(volatile uint64_t *)addr;

	return val;
}

static void potato_uart_reg_write(int offset, uint64_t val)
{
	uint64_t addr;

	addr = potato_uart_base + offset;

	*(volatile uint64_t *)addr = val;
}

static int potato_uart_rx_empty(void)
{
	uint64_t val;

	val = potato_uart_reg_read(POTATO_CONSOLE_STATUS);

	if (val & POTATO_CONSOLE_STATUS_RX_EMPTY)
		return 1;

	return 0;
}

static int potato_uart_tx_full(void)
{
	uint64_t val;

	val = potato_uart_reg_read(POTATO_CONSOLE_STATUS);

	if (val & POTATO_CONSOLE_STATUS_TX_FULL)
		return 1;

	return 0;
}

static char potato_uart_read(void)
{
	uint64_t val;

	val = potato_uart_reg_read(POTATO_CONSOLE_RX);

	return (char)(val & 0x000000ff);
}

static void potato_uart_write(char c)
{
	uint64_t val;

	val = c;

	potato_uart_reg_write(POTATO_CONSOLE_TX, val);
}

static unsigned long potato_uart_divisor(unsigned long proc_freq, unsigned long uart_freq)
{
	return proc_freq / (uart_freq * 16) - 1;
}

void potato_uart_init(void)
{
	potato_uart_base = UART_BASE;

	potato_uart_reg_write(POTATO_CONSOLE_CLOCK_DIV, potato_uart_divisor(PROC_FREQ, UART_FREQ));
}

int getchar(void)
{
	while (potato_uart_rx_empty())
		/* Do nothing */ ;

	return potato_uart_read();
}

void putchar(unsigned char c)
{
	while (potato_uart_tx_full())
		/* Do Nothing */;

	potato_uart_write(c);
}

void putstr(const char *str, unsigned long len)
{
	for (unsigned long i = 0; i < len; i++) {
		putchar(str[i]);
	}
}

size_t strlen(const char *s)
{
	size_t len = 0;

	while (*s++)
		len++;

	return len;
}

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
