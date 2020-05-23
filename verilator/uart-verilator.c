#include <signal.h>
#include <poll.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include <termios.h>
#include <stdlib.h>

/* Should we exit simulation on ctrl-c or pass it through? */
#define EXIT_ON_CTRL_C

#define BAUD 115200
/* Round to nearest */
#define BITWIDTH ((CLK_FREQUENCY+(BAUD/2))/BAUD)

/*
 * Our UART uses 16x oversampling, so at 50 MHz and 115200 baud
 * each sample is: 50000000/(115200*16) = 27 clock cycles. This
 * means each bit is off by 0.47% so for 8 bits plus a start and
 * stop bit the errors add to be 4.7%.
 */
static double error = 0.05;

enum state {
	IDLE, START_BIT, BITS, STOP_BIT, ERROR
};

static enum state tx_state = IDLE;
static unsigned long tx_countbits;
static unsigned char tx_bits;
static unsigned char tx_byte;
static unsigned char tx_prev;

/*
 * Return an error if the transition is not close enough to the start or
 * the end of an expected bit.
 */
static bool is_error(unsigned long bits)
{
	double e = 1.0 * tx_countbits / BITWIDTH;

	if ((e <= (1.0-error)) && (e >= error))
		return true;

	return false;
}

void uart_tx(unsigned char tx)
{
	switch (tx_state) {
		case IDLE:
			if (tx == 0) {
				tx_state = START_BIT;
				tx_countbits = BITWIDTH;
				tx_bits = 0;
				tx_byte = 0;
			}
			break;

		case START_BIT:
			tx_countbits--;
			if (tx == 1) {
				if (is_error(tx_countbits)) {
					printf("START_BIT error %ld %ld\n", BITWIDTH, tx_countbits);
					tx_countbits = BITWIDTH*2;
					tx_state = ERROR;
					break;
				}
			}

			if (tx_countbits == 0) {
				tx_state = BITS;
				tx_countbits = BITWIDTH;
			}
			break;

		case BITS:
			tx_countbits--;
			if (tx_countbits == BITWIDTH/2) {
				tx_byte = tx_byte | (tx << tx_bits);
				tx_bits = tx_bits + 1;
			}

			if (tx != tx_prev) {
				if (is_error(tx_countbits)) {
					printf("BITS error %ld %ld\n", BITWIDTH, tx_countbits);
					tx_countbits = BITWIDTH*2;
					tx_state = ERROR;
					break;
				}
			}

			if (tx_countbits == 0) {
				if (tx_bits == 8) {
					tx_state = STOP_BIT;
				}
				tx_countbits = BITWIDTH;
			}
			break;

		case STOP_BIT:
			tx_countbits--;

			if (tx == 0) {
				if (is_error(tx_countbits)) {
					printf("STOP_BIT error %ld %ld\n", BITWIDTH, tx_countbits);
					tx_countbits = BITWIDTH*2;
					tx_state = ERROR;
					break;
				}
				/* Go straight to idle */
				write(STDOUT_FILENO, &tx_byte, 1);
				tx_state = IDLE;
			}

			if (tx_countbits == 0) {
				write(STDOUT_FILENO, &tx_byte, 1);
				tx_state = IDLE;
			}
			break;

		case ERROR:
			tx_countbits--;
			if (tx_countbits == 0) {
				tx_state = IDLE;
			}

			break;
	}

	tx_prev = tx;
}

static struct termios oldt;

static void disable_raw_mode(void)
{
	tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
}

static void enable_raw_mode(void)
{
	static bool initialized = false;

	if (!initialized) {
		static struct termios newt;

		tcgetattr(STDIN_FILENO, &oldt);
		newt = oldt;
		cfmakeraw(&newt);
#ifdef EXIT_ON_CTRL_C
		newt.c_lflag |= ISIG;
#endif
		tcsetattr(STDIN_FILENO, TCSANOW, &newt);
		initialized = true;
		atexit(disable_raw_mode);
	}
}

static int nonblocking_read(unsigned char *c)
{
	int ret;
	unsigned long val = 0;
	struct pollfd fdset[1];

	enable_raw_mode();

	memset(fdset, 0, sizeof(fdset));

	fdset[0].fd = STDIN_FILENO;
	fdset[0].events = POLLIN;

	ret = poll(fdset, 1, 0);
	if (ret == 0)
		return false;

	ret = read(STDIN_FILENO, &val, 1);
	if (ret != 1) {
		fprintf(stderr, "%s: read of stdin returns %d\n", __func__, ret);
		exit(1);
	}

	if (ret == 1) {
		*c = val;
		return true;
	} else {
		return false;
	}
}

static enum state rx_state = IDLE;
static unsigned char rx_char;
static unsigned long rx_countbits;
static unsigned char rx_bit;
static unsigned char rx = 1;

/* Avoid calling poll() too much */
#define RX_INTERVAL 10000
static unsigned long rx_sometimes;

unsigned char uart_rx(void)
{
	unsigned char c;

	switch (rx_state) {
		case IDLE:
			if (rx_sometimes++ >= RX_INTERVAL) {
				rx_sometimes = 0;

				if (nonblocking_read(&c)) {
					rx_state = START_BIT;
					rx_char = c;
					rx_countbits = BITWIDTH;
					rx_bit = 0;
					rx = 0;
				}
			}

			break;

		case START_BIT:
			rx_countbits--;
			if (rx_countbits == 0) {
				rx_state = BITS;
				rx_countbits = BITWIDTH;
				rx = rx_char & 1;
			}
			break;

		case BITS:
			rx_countbits--;
			if (rx_countbits == 0) {
				rx_bit = rx_bit + 1;
				if (rx_bit == 8) {
					rx = 1;
					rx_state = STOP_BIT;
				} else {
					rx = (rx_char >> rx_bit) & 1;
				}
				rx_countbits = BITWIDTH;
			}
			break;

		case STOP_BIT:
			rx_countbits--;
			if (rx_countbits == 0) {
				rx_state = IDLE;
			}
			break;
	}

	return rx;
}
