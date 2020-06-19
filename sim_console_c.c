#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <poll.h>
#include "sim_vhpi_c.h"

/* Should we exit simulation on ctrl-c or pass it through? */
#define EXIT_ON_CTRL_C

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

void sim_console_read(unsigned char *__rt)
{
	int ret;
	unsigned long val = 0;

	enable_raw_mode();

	ret = read(STDIN_FILENO, &val, 1);
	if (ret != 1) {
		fprintf(stderr, "%s: read of stdin returns %d\n", __func__, ret);
		exit(1);
	}

	//fprintf(stderr, "read returns %c\n", val);

	to_std_logic_vector(val, __rt, 64);
}

void sim_console_poll(unsigned char *__rt)
{
	int ret;
	struct pollfd fdset[1];
	uint8_t val = 0;

	enable_raw_mode();

	memset(fdset, 0, sizeof(fdset));

	fdset[0].fd = STDIN_FILENO;
	fdset[0].events = POLLIN;

	ret = poll(fdset, 1, 0);
	//fprintf(stderr, "poll returns %d\n", ret);

	if (ret == 1) {
		if (fdset[0].revents & POLLIN)
			val = 1;
//		fprintf(stderr, "poll revents: 0x%x\n", fdset[0].revents);
	}

	to_std_logic_vector(val, __rt, 64);
}

void sim_console_write(unsigned char *__rs)
{
	uint8_t val;

	val = from_std_logic_vector(__rs, 64);

	fprintf(stderr, "%c", val);
}
