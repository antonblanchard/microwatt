#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>

#include "sdram.h"

/*
 * Core UART functions to implement for a port
 */

static uint64_t potato_uart_base;

#define PROC_FREQ 100000000
#define UART_FREQ 115200
#define UART_BASE 0xc0002000
#define SYSCON_BASE 0xc0000000

#define POTATO_CONSOLE_TX		0x00
#define POTATO_CONSOLE_RX		0x08
#define POTATO_CONSOLE_STATUS		0x10
#define   POTATO_CONSOLE_STATUS_RX_EMPTY		0x01
#define   POTATO_CONSOLE_STATUS_TX_EMPTY		0x02
#define   POTATO_CONSOLE_STATUS_RX_FULL			0x04
#define   POTATO_CONSOLE_STATUS_TX_FULL			0x08
#define POTATO_CONSOLE_CLOCK_DIV	0x18
#define POTATO_CONSOLE_IRQ_EN		0x20

static inline uint8_t readb(unsigned long addr)
{
	__asm__ volatile("sync" : : : "memory");
	return *((volatile uint8_t *)addr);
}

static inline uint64_t readq(unsigned long addr)
{
	__asm__ volatile("sync" : : : "memory");
	return *((volatile uint64_t *)addr);
}

static inline void writeb(uint8_t val, unsigned long addr)
{
	__asm__ volatile("sync" : : : "memory");
	*((volatile uint8_t *)addr) = val;
}

static inline void writeq(uint64_t val, unsigned long addr)
{
	__asm__ volatile("sync" : : : "memory");
	*((volatile uint64_t *)addr) = val;
}

static uint8_t potato_uart_reg_read(int offset)
{
	return readb(potato_uart_base + offset);
}

static void potato_uart_reg_write(int offset, uint8_t val)
{
	writeb(val, potato_uart_base + offset);
}

static bool potato_uart_rx_empty(void)
{
	uint8_t val = potato_uart_reg_read(POTATO_CONSOLE_STATUS);

	return (val & POTATO_CONSOLE_STATUS_RX_EMPTY) != 0;
}

static int potato_uart_tx_full(void)
{
	uint8_t val = potato_uart_reg_read(POTATO_CONSOLE_STATUS);

	return (val & POTATO_CONSOLE_STATUS_TX_FULL) != 0;
}

static char potato_uart_read(void)
{
	return potato_uart_reg_read(POTATO_CONSOLE_RX);
}

static void potato_uart_write(char c)
{
	potato_uart_reg_write(POTATO_CONSOLE_TX, c);
}

static unsigned long potato_uart_divisor(unsigned long proc_freq,
					 unsigned long uart_freq)
{
	return proc_freq / (uart_freq * 16) - 1;
}

void potato_uart_init(void)
{
	potato_uart_base = UART_BASE;

	potato_uart_reg_write(POTATO_CONSOLE_CLOCK_DIV,
			      potato_uart_divisor(PROC_FREQ, UART_FREQ));
}

int getchar(void)
{
	while (potato_uart_rx_empty())
		/* Do nothing */ ;

	return potato_uart_read();
}

int putchar(int c)
{
	while (potato_uart_tx_full())
		/* Do Nothing */;

	potato_uart_write(c);
	return c;
}

void putstr(const char *str, unsigned long len)
{
	for (unsigned long i = 0; i < len; i++) {
		if (str[i] == '\n')
			putchar('\r');
		putchar(str[i]);
	}
}

int _printf(const char *fmt, ...)
{
	int count;
	char buffer[320];
	va_list ap;

	va_start(ap, fmt);
	count = vsnprintf(buffer, sizeof(buffer), fmt, ap);
	va_end(ap);
	putstr(buffer, count);
	return count;
}

void flush_cpu_dcache(void) { }
void flush_cpu_icache(void) { }
void flush_l2_cache(void) { }

void main(void)
{
	int i;

	// Let things settle ... not sure why but UART not happy otherwise
	potato_uart_init();
	for (i = 0; i < 10000; i++)
		potato_uart_reg_read(POTATO_CONSOLE_STATUS);
	printf("Welcome to Microwatt !\n");
	printf("       SIG: %016llx\n", (unsigned long long)readq(SYSCON_BASE + 0x00));
	printf("      INFO: %016llx\n", (unsigned long long)readq(SYSCON_BASE + 0x08));
	printf("  BRAMINFO: %016llx\n", (unsigned long long)readq(SYSCON_BASE + 0x10));
	printf("  DRAMINFO: %016llx\n", (unsigned long long)readq(SYSCON_BASE + 0x18));
	printf("      CTRL: %016llx\n", (unsigned long long)readq(SYSCON_BASE + 0x20));
	sdrinit();
	printf("Booting from BRAM...\n");
}
