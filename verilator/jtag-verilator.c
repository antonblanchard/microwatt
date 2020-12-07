#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>

#undef DEBUG

/* XXX Make that some parameter */
#define TCP_PORT	13245

static int fd = -1;
static int cfd = -1;

static void open_socket(void)
{
	struct sockaddr_in addr;
	int opt, rc, flags;

	if (fd >= 0 || fd < -1)
		return;

	signal(SIGPIPE, SIG_IGN);
	fd = socket(AF_INET, SOCK_STREAM, 0);
	if (fd < 0) {
		fprintf(stderr, "Failed to open debug socket !\r\n");
		goto fail;
	}

	rc = 0;
	flags = fcntl(fd, F_GETFL);
	if (flags >= 0)
		rc = fcntl(fd, F_SETFL, flags | O_NONBLOCK);
	if (flags < 0 || rc < 0) {
		fprintf(stderr, "Failed to configure debug socket !\r\n");
	}

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(TCP_PORT);
	addr.sin_addr.s_addr = htonl(INADDR_ANY);
	opt = 1;
	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
	rc = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
	if (rc < 0) {
		fprintf(stderr, "Failed to bind debug socket !\r\n");
		goto fail;
	}
	rc = listen(fd,1);
	if (rc < 0) {
		fprintf(stderr, "Failed to listen to debug socket !\r\n");
		goto fail;
	}
	fprintf(stdout, "Debug socket ready\r\n");
	return;
fail:
	if (fd >= 0)
		close(fd);
	fd = -2;
}

static void check_connection(void)
{
	struct sockaddr_in addr;
	socklen_t addr_len = sizeof(addr);

	cfd = accept(fd, (struct sockaddr *)&addr, &addr_len);
	if (cfd < 0)
		return;
	fprintf(stdout, "Debug client connected !\r\n");
}

static bool read_one_byte(char *c)
{
	struct pollfd fdset[1];
	int rc;

	if (fd == -1)
		open_socket();
	if (fd < 0)
		return false;
	if (cfd < 0)
		check_connection();
	if (cfd < 0)
		return false;

	memset(fdset, 0, sizeof(fdset));
	fdset[0].fd = cfd;
	fdset[0].events = POLLIN;
	rc = poll(fdset, 1, 0);
	if (rc <= 0)
		return false;
	rc = read(cfd, c, 1);
	if (rc != 1) {
		fprintf(stderr, "Debug read error, assuming client disconnected !\r\n");
		close(cfd);
		cfd = -1;
		return false;
	}

#ifdef DEBUG
	fprintf(stderr, "Got message: %c\n", *c);
#endif

	return true;
}

static void write_one_byte(char c)
{
	int rc;

#ifdef DEBUG
	fprintf(stderr, "Sending message: %c\n", c);
#endif

	rc = write(cfd, &c, 1);
	if (rc != 1) {
		fprintf(stderr, "JTAG write error, disconnecting\n");
		close(cfd);
		cfd = -1;
	}
}

struct jtag_in {
	uint8_t tck;
	uint8_t tms;
	uint8_t tdi;
	uint8_t trst;
};

static struct jtag_in jtag_in;

struct jtag_in jtag_one_cycle(uint8_t tdo)
{
	char c;

	if (read_one_byte(&c) == false)
		goto out;

	// Write request
	if ((c >= '0') && (c <= '7')) {
		uint8_t val = c - '0';

		jtag_in.tck = (val >> 2) & 1;
		jtag_in.tms = (val >> 1) & 1;
		jtag_in.tdi = (val >> 0) & 1;

		goto out;
	}

	// Reset request
	if ((c >= 'r') && (c <= 'u')) {
		uint8_t val = c - 'r';

		jtag_in.trst = (val >> 1) & 1;
	}

	switch (c) {
		case 'B':	// Blink on
		case 'b':	// Blink off
			goto out;

		case 'R':	// Read request
			write_one_byte(tdo + '0');
			goto out;

		case 'Q':	// Quit request
			fprintf(stderr, "Disconnecting JTAG\n");
			close(cfd);
			cfd = -1;
			goto out;

		default:
			printf("Unknown JTAG command %c\n", c);
	}

out:
	return jtag_in;
}
