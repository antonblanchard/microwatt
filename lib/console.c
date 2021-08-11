#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "microwatt_soc.h"
#include "io.h"

#define UART_BAUDS 115200

/*
 * Core UART functions to implement for a port
 */

static uint64_t uart_base;

static unsigned long uart_divisor(unsigned long uart_freq, unsigned long bauds)
{
	return uart_freq / (bauds * 16);
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
	while (std_uart_rx_empty())
		/* Do nothing */ ;
	return std_uart_read();
}

int putchar(int c)
{
	while(std_uart_tx_full())
		/* Do Nothing */;
	std_uart_write(c);
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
	std_uart_init(proc_freq);
}

void console_set_irq_en(bool rx_irq, bool tx_irq)
{
	std_uart_set_irq_en(rx_irq, tx_irq);
}
