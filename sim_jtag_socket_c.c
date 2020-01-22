#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include "sim_vhpi_c.h"

/* XXX Make that some parameter */
#define TCP_PORT	13245
#define MAX_PACKET	32

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

void sim_jtag_read_msg(unsigned char *out_msg, unsigned char *out_size)
{
	unsigned char data[MAX_PACKET];
	unsigned char size = 0;
	struct pollfd fdset[1];
	int rc, i;

	if (fd == -1)
		open_socket();
	if (fd < 0)
		goto finish;
	if (cfd < 0)
		check_connection();
	if (cfd < 0)
		goto finish;

	memset(fdset, 0, sizeof(fdset));
	fdset[0].fd = cfd;
	fdset[0].events = POLLIN;
	rc = poll(fdset, 1, 0);
	if (rc <= 0)
		goto finish;
	rc = read(cfd, data, MAX_PACKET);
	if (rc < 0)
		fprintf(stderr, "Debug read error, assuming client disconnected !\r\n");
	if (rc == 0)
		fprintf(stdout, "Debug client disconnected !\r\n");
	if (rc <= 0) {
		close(cfd);
		cfd = -1;
		goto finish;
	}

#if 0
	fprintf(stderr, "Got message:\n\r");
	{
		for (i=0; i<rc; i++)
			fprintf(stderr, "%02x ", data[i]);
		fprintf(stderr, "\n\r");
	}
#endif
	size = data[0]; /* Size in bits */

	/* Special sizes */
	if (size == 255) {
		/* JTAG reset, message to translate */
		goto finish;
	}

	if (((rc - 1) * 8) < size) {
		fprintf(stderr, "Debug short read: %d bytes for %d bits, truncating\r\n",
			rc - 1, size);
		size = (rc - 1) * 8;
	}

	for (i = 0; i < size; i++) {
		int byte = i >> 3;
		int bit = 1 << (i & 7);
		out_msg[i] = (data[byte+1] & bit) ? vhpi1 : vhpi0;
	}
finish:
	to_std_logic_vector(size, out_size, 8);
}

void sim_jtag_write_msg(unsigned char *in_msg, unsigned char *in_size)
{
	unsigned char data[MAX_PACKET];
	unsigned char size;
	int rc, i;

	size = from_std_logic_vector(in_size, 8);
	data[0] = size;
	for (i = 0; i < size; i++) {
		int byte = i >> 3;
		int bit = 1 << (i & 7);
		if (in_msg[i] == vhpi1)
			data[byte+1] |= bit;
		else
			data[byte+1] &= ~bit;
	}
	rc = (size + 7) / 8;

#if 0
	fprintf(stderr, "Sending response:\n\r");
	{
		for (i=0; i<rc; i++)
			fprintf(stderr, "%02x ", data[i]);
		fprintf(stderr, "\n\r");
	}
#endif

	rc = write(cfd, data, rc);
	if (rc < 0)
		fprintf(stderr, "Debug write error, ignoring\r\n");
}

