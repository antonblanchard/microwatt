#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "microwatt_soc.h"
#include "io.h"

#define UART_FREQ 115200

/*
 * Core UART functions to implement for a port
 */

static uint64_t potato_uart_base;

static uint64_t potato_uart_reg_read(int offset)
{
	return readq(potato_uart_base + offset);
}

static void potato_uart_reg_write(int offset, uint64_t val)
{
	writeq(val, potato_uart_base + offset);
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
	uint64_t proc_freq;

	potato_uart_base = UART_BASE;
	proc_freq = readq(SYSCON_BASE + SYS_REG_CLKINFO) & SYS_REG_CLKINFO_FREQ_MASK;

	potato_uart_reg_write(POTATO_CONSOLE_CLOCK_DIV, potato_uart_divisor(proc_freq, UART_FREQ));
}

void potato_uart_irq_en(void)
{
	potato_uart_reg_write(POTATO_CONSOLE_IRQ_EN, 0xff);
}

void potato_uart_irq_dis(void)
{
	potato_uart_reg_write(POTATO_CONSOLE_IRQ_EN, 0x00);
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

int puts(const char *str)
{
	unsigned int i;

	for (i = 0; *str; i++) {
		char c = *(str++);
		if (c == 10)
			putchar(13);
		putchar(c);
	}
	return 0;
}

#ifndef __USE_LIBC
size_t strlen(const char *s)
{
	size_t len = 0;

	while (*s++)
		len++;

	return len;
}
#endif
