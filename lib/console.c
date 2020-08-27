#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "microwatt_soc.h"
#include "io.h"

#define UART_BAUDS 115200

/*
 * Core UART functions to implement for a port
 */

bool uart_is_std;

static uint64_t uart_base;

static unsigned long uart_divisor(unsigned long uart_freq, unsigned long bauds)
{
	return uart_freq / (bauds * 16);
}

static uint64_t potato_uart_reg_read(int offset)
{
	return readq(uart_base + offset);
}

static void potato_uart_reg_write(int offset, uint64_t val)
{
	writeq(val, uart_base + offset);
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

static void potato_uart_init(uint64_t uart_freq)
{
	unsigned long div = uart_divisor(uart_freq, UART_BAUDS) - 1;
	potato_uart_reg_write(POTATO_CONSOLE_CLOCK_DIV, div);
}

static void potato_uart_set_irq_en(bool rx_irq, bool tx_irq)
{
	uint64_t en = 0;

	if (rx_irq)
		en |= POTATO_CONSOLE_IRQ_RX;
	if (tx_irq)
		en |= POTATO_CONSOLE_IRQ_TX;
	potato_uart_reg_write(POTATO_CONSOLE_IRQ_EN, en);
}

static bool std_uart_rx_empty(void)
{
	return !(readb(uart_base + UART_REG_LSR) & UART_REG_LSR_DR);
}

static uint8_t std_uart_read(void)
{
	return readb(uart_base + UART_REG_RX);
}

static bool std_uart_tx_full(void)
{
	return !(readb(uart_base + UART_REG_LSR) & UART_REG_LSR_THRE);
}

static void std_uart_write(uint8_t c)
{
	writeb(c, uart_base + UART_REG_TX);
}

static void std_uart_set_irq_en(bool rx_irq, bool tx_irq)
{
	uint8_t ier = 0;

	if (tx_irq)
		ier |= UART_REG_IER_THRI;
	if (rx_irq)
		ier |= UART_REG_IER_RDI;
	writeb(ier, uart_base + UART_REG_IER);
}

static void std_uart_init(uint64_t uart_freq)
{
	unsigned long div = uart_divisor(uart_freq, UART_BAUDS);
	
	writeb(UART_REG_LCR_DLAB,     uart_base + UART_REG_LCR);
	writeb(div & 0xff,            uart_base + UART_REG_DLL);
	writeb(div >> 8,              uart_base + UART_REG_DLM);
	writeb(UART_REG_LCR_8BIT,     uart_base + UART_REG_LCR);
	writeb(UART_REG_MCR_DTR |
	       UART_REG_MCR_RTS,      uart_base + UART_REG_MCR);
	writeb(UART_REG_FCR_EN_FIFO |
	       UART_REG_FCR_CLR_RCVR |
	       UART_REG_FCR_CLR_XMIT, uart_base + UART_REG_FCR);
}

int getchar(void)
{
	if (uart_is_std) {
		while (std_uart_rx_empty())
			/* Do nothing */ ;
		return std_uart_read();
	} else {
		while (potato_uart_rx_empty())
			/* Do nothing */ ;
		return potato_uart_read();
	}
}

int putchar(int c)
{
	if (uart_is_std) {
		while(std_uart_tx_full())
			/* Do Nothing */;
		std_uart_write(c);
	} else {
		while (potato_uart_tx_full())
			/* Do Nothing */;
		potato_uart_write(c);
	}
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

void console_init(void)
{
	uint64_t sys_info;
	uint64_t proc_freq;
	uint64_t uart_info = 0;
	uint64_t uart_freq = 0;

	proc_freq = readq(SYSCON_BASE + SYS_REG_CLKINFO) & SYS_REG_CLKINFO_FREQ_MASK;
	sys_info  = readq(SYSCON_BASE + SYS_REG_INFO);

	if (sys_info & SYS_REG_INFO_HAS_LARGE_SYSCON) {
		uart_info = readq(SYSCON_BASE + SYS_REG_UART0_INFO);
		uart_freq = uart_info & 0xffffffff;
	}
	if (uart_freq == 0)
		uart_freq = proc_freq;

	uart_base = UART_BASE;
	if (uart_info & SYS_REG_UART_IS_16550) {
		uart_is_std = true;
		std_uart_init(proc_freq);
	} else {
		uart_is_std = false;
		potato_uart_init(proc_freq);
	}
}

void console_set_irq_en(bool rx_irq, bool tx_irq)
{
	if (uart_is_std)
		std_uart_set_irq_en(rx_irq, tx_irq);
	else
		potato_uart_set_irq_en(rx_irq, tx_irq);
}
