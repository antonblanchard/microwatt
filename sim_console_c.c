#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <poll.h>


#define vhpi0	2	/* forcing 0 */
#define vhpi1	3	/* forcing 1 */

static uint64_t from_std_logic_vector(unsigned char *p, unsigned long len)
{
	unsigned long ret = 0;

	if (len > 64) {
		fprintf(stderr, "%s: invalid length %lu\n", __func__, len);
		exit(1);
	}

	for (unsigned long i = 0; i < len; i++) {
		unsigned char bit;

		if (*p == vhpi0) {
			bit = 0;
		} else if (*p == vhpi1) {
			bit = 1;
		} else {
			fprintf(stderr, "%s: bad bit %d\n", __func__, *p);
			bit = 0;
		}

		ret = (ret << 1) | bit;
		p++;
	}

	return ret;
}

static void to_std_logic_vector(unsigned long val, unsigned char *p,
				unsigned long len)
{
	if (len > 64) {
		fprintf(stderr, "%s: invalid length %lu\n", __func__, len);
		exit(1);
	}

	for (unsigned long i = 0; i < len; i++) {
		if ((val >> (len-1-i) & 1))
			*p = vhpi1;
		else
			*p = vhpi0;

		p++;
	}
}

static struct termios oldt;

static void restore_termios(void)
{
	tcsetattr(STDIN_FILENO, TCSANOW, &oldt);
}

static void nonblocking(void)
{
	static bool initialized = false;

	if (!initialized) {
		static struct termios newt;

		tcgetattr(STDIN_FILENO, &oldt);
		newt = oldt;
		newt.c_lflag &= ~(ICANON|ECHO);

		newt.c_iflag &= ~(BRKINT | ICRNL | INPCK | ISTRIP | IXON);
		newt.c_oflag &= ~(OPOST);
		newt.c_cflag |= (CS8);
		newt.c_lflag &= ~(ECHO | ICANON | IEXTEN | ISIG);

		tcsetattr(STDIN_FILENO, TCSANOW, &newt);
		initialized = true;
		atexit(restore_termios);
	}
}

void sim_console_read(unsigned char *__rt)
{
	int ret;
	unsigned long val = 0;

	nonblocking();

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

	nonblocking();

	memset(fdset, 0, sizeof(fdset));

	fdset[0].fd = STDIN_FILENO;
	fdset[0].events = POLLIN;

	ret = poll(fdset, 1, 0);
	//fprintf(stderr, "poll returns %d\n", ret);

	if (ret == 1)
		val = 1;

	to_std_logic_vector(val, __rt, 64);
}

void sim_console_write(unsigned char *__rs)
{
	uint8_t val;

	val = from_std_logic_vector(__rs, 64);

	fprintf(stderr, "%c", val);
}
