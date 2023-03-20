#include <stdint.h>
#include <stdbool.h>

#include "console.h"
#include "liteuart_console.h"
#include "microwatt_soc.h"
#include "io.h"

#define UART_BAUDS 115200

static uint64_t uart_base;

/* From Linux liteuart.c */
#define OFF_RXTX	0x00
#define OFF_TXFULL	0x04
#define OFF_RXEMPTY	0x08
#define OFF_EV_STATUS	0x0c
#define OFF_EV_PENDING	0x10
#define OFF_EV_ENABLE	0x14

/* From litex uart.h */
#define UART_EV_TX	0x1
#define UART_EV_RX	0x2

/* Modified version of csr.h */
/* uart */
static inline uint32_t uart_rxtx_read(void) {
	return readl(uart_base + OFF_RXTX);
}

static inline void uart_rxtx_write(uint32_t v) {
	writel(v, uart_base + OFF_RXTX);
}

static inline uint32_t uart_txfull_read(void) {
	return readl(uart_base + OFF_TXFULL);
}

static inline uint32_t uart_rxempty_read(void) {
	return readl(uart_base + OFF_RXEMPTY);
}

static inline uint32_t uart_ev_status_read(void) {
	return readl(uart_base + OFF_EV_STATUS);
}

// static inline uint32_t uart_ev_status_tx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 0) & mask );
// }
// static inline uint32_t uart_ev_status_tx_read(void) {
// 	uint32_t word = uart_ev_status_read();
// 	return uart_ev_status_tx_extract(word);
// }

// static inline uint32_t uart_ev_status_rx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 1) & mask );
// }
// static inline uint32_t uart_ev_status_rx_read(void) {
// 	uint32_t word = uart_ev_status_read();
// 	return uart_ev_status_rx_extract(word);
// }

static inline uint32_t uart_ev_pending_read(void) {
	return readl(uart_base + OFF_EV_PENDING);
}
static inline void uart_ev_pending_write(uint32_t v) {
	writel(v, uart_base + OFF_EV_PENDING);
}

// static inline uint32_t uart_ev_pending_tx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 0) & mask );
// }
// static inline uint32_t uart_ev_pending_tx_read(void) {
// 	uint32_t word = uart_ev_pending_read();
// 	return uart_ev_pending_tx_extract(word);
// }
// static inline uint32_t uart_ev_pending_tx_replace(uint32_t oldword, uint32_t plain_value) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return (oldword & (~(mask << 0))) | (mask & plain_value)<< 0 ;
// }
// static inline void uart_ev_pending_tx_write(uint32_t plain_value) {
// 	uint32_t oldword = uart_ev_pending_read();
// 	uint32_t newword = uart_ev_pending_tx_replace(oldword, plain_value);
// 	uart_ev_pending_write(newword);
// }
// #define CSR_UART_EV_PENDING_RX_OFFSET 1
// #define CSR_UART_EV_PENDING_RX_SIZE 1
// static inline uint32_t uart_ev_pending_rx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 1) & mask );
// }
// static inline uint32_t uart_ev_pending_rx_read(void) {
// 	uint32_t word = uart_ev_pending_read();
// 	return uart_ev_pending_rx_extract(word);
// }
// static inline uint32_t uart_ev_pending_rx_replace(uint32_t oldword, uint32_t plain_value) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return (oldword & (~(mask << 1))) | (mask & plain_value)<< 1 ;
// }
// static inline void uart_ev_pending_rx_write(uint32_t plain_value) {
// 	uint32_t oldword = uart_ev_pending_read();
// 	uint32_t newword = uart_ev_pending_rx_replace(oldword, plain_value);
// 	uart_ev_pending_write(newword);
// }
// #define CSR_UART_EV_ENABLE_ADDR (CSR_BASE + 0x814L)
// #define CSR_UART_EV_ENABLE_SIZE 1
// static inline uint32_t uart_ev_enable_read(void) {
// 	return csr_read_simple(CSR_BASE + 0x814L);
// }
static inline void uart_ev_enable_write(uint32_t v) {
	writel(v, uart_base + OFF_EV_ENABLE);
}
// #define CSR_UART_EV_ENABLE_TX_OFFSET 0
// #define CSR_UART_EV_ENABLE_TX_SIZE 1
// static inline uint32_t uart_ev_enable_tx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 0) & mask );
// }
// static inline uint32_t uart_ev_enable_tx_read(void) {
// 	uint32_t word = uart_ev_enable_read();
// 	return uart_ev_enable_tx_extract(word);
// }
// static inline uint32_t uart_ev_enable_tx_replace(uint32_t oldword, uint32_t plain_value) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return (oldword & (~(mask << 0))) | (mask & plain_value)<< 0 ;
// }
// static inline void uart_ev_enable_tx_write(uint32_t plain_value) {
// 	uint32_t oldword = uart_ev_enable_read();
// 	uint32_t newword = uart_ev_enable_tx_replace(oldword, plain_value);
// 	uart_ev_enable_write(newword);
// }
// #define CSR_UART_EV_ENABLE_RX_OFFSET 1
// #define CSR_UART_EV_ENABLE_RX_SIZE 1
// static inline uint32_t uart_ev_enable_rx_extract(uint32_t oldword) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return ( (oldword >> 1) & mask );
// }
// static inline uint32_t uart_ev_enable_rx_read(void) {
// 	uint32_t word = uart_ev_enable_read();
// 	return uart_ev_enable_rx_extract(word);
// }
// static inline uint32_t uart_ev_enable_rx_replace(uint32_t oldword, uint32_t plain_value) {
// 	uint32_t mask = ((1 << 1)-1);
// 	return (oldword & (~(mask << 1))) | (mask & plain_value)<< 1 ;
// }
// static inline void uart_ev_enable_rx_write(uint32_t plain_value) {
// 	uint32_t oldword = uart_ev_enable_read();
// 	uint32_t newword = uart_ev_enable_rx_replace(oldword, plain_value);
// 	uart_ev_enable_write(newword);
// }
// #define CSR_UART_TUNING_WORD_ADDR (CSR_BASE + 0x818L)
// #define CSR_UART_TUNING_WORD_SIZE 1
// static inline uint32_t uart_tuning_word_read(void) {
// 	return csr_read_simple(CSR_BASE + 0x818L);
// }
// static inline void uart_tuning_word_write(uint32_t v) {
// 	csr_write_simple(v, CSR_BASE + 0x818L);
// }
// #define CSR_UART_CONFIGURED_ADDR (CSR_BASE + 0x81cL)
// #define CSR_UART_CONFIGURED_SIZE 1
// static inline uint32_t uart_configured_read(void) {
// 	return csr_read_simple(CSR_BASE + 0x81cL);
// }
// static inline void uart_configured_write(uint32_t v) {
// 	csr_write_simple(v, CSR_BASE + 0x81cL);
// }

// end of csr code

static char uart_read(void)
{
	char c;
	while (uart_rxempty_read());
	c = uart_rxtx_read();
	uart_ev_pending_write(UART_EV_RX);
	return c;
}

static int uart_read_nonblock(void)
{
	return (uart_rxempty_read() == 0);
}

static void uart_write(char c)
{
	while (uart_txfull_read());
	uart_rxtx_write(c);
	uart_ev_pending_write(UART_EV_TX);
}

static void uart_init(void)
{
	uart_ev_pending_write(uart_ev_pending_read());
	uart_ev_enable_write(UART_EV_TX | UART_EV_RX);
}

// static void uart_sync(void)
// {
// 	while (uart_txfull_read());
// }

int usb_getchar(void)
{
	return uart_read();
}

bool usb_havechar(void)
{
	return uart_read_nonblock();
}

int usb_putchar(int c)
{
	uart_write(c);
	return c;
}

int usb_puts(const char *str)
{
	unsigned int i;

	for (i = 0; *str; i++) {
		char c = *(str++);
		if (c == 10)
			usb_putchar(13);
		usb_putchar(c);
	}
	return 0;
}

void usb_console_init(void)
{
	uart_base = UARTUSB_BASE;
	uart_init();
}

