#define _POSIX_C_SOURCE 200809L
#define _GNU_SOURCE

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <getopt.h>
#include <poll.h>
#include <signal.h>
#include <fcntl.h>
#include <netdb.h>
#include <ctype.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <urjtag/urjtag.h>
#include <inttypes.h>

#define DBG_WB_ADDR		0x00
#define DBG_WB_DATA		0x01
#define DBG_WB_CTRL		0x02

#define DBG_CORE_CTRL		0x10
#define  DBG_CORE_CTRL_STOP		(1 << 0)
#define  DBG_CORE_CTRL_RESET		(1 << 1)
#define  DBG_CORE_CTRL_ICRESET		(1 << 2)
#define  DBG_CORE_CTRL_STEP		(1 << 3)
#define  DBG_CORE_CTRL_START		(1 << 4)

#define DBG_CORE_STAT		0x11
#define  DBG_CORE_STAT_STOPPING		(1 << 0)
#define  DBG_CORE_STAT_STOPPED		(1 << 1)
#define  DBG_CORE_STAT_TERM		(1 << 2)

#define DBG_CORE_NIA		0x12
#define DBG_CORE_MSR		0x13

#define DBG_CORE_GSPR_INDEX	0x14
#define DBG_CORE_GSPR_DATA	0x15

#define DBG_LOG_ADDR		0x16
#define DBG_LOG_DATA		0x17

static bool debug;

struct backend {
	int (*init)(const char *target);
	int (*reset)(void);
	int (*command)(uint8_t op, uint8_t addr, uint64_t *data);
};
static struct backend *b;

static void check(int r, const char *failstr)
{
	if (r >= 0)
		return;
	fprintf(stderr, "Error %s\n", failstr);
	exit(1);
}

/* -------------- SIM backend -------------- */

static int sim_fd = -1;

static int sim_init(const char *target)
{
	struct sockaddr_in saddr;
	struct hostent *hp;
	const char *p, *host;
	int port, rc;

	if (!target)
		target = "localhost:13245";
	p = strchr(target, ':');
	host = strndup(target, p - target);
	if (p && *p)
		p++;
	else
		p = "13245";
	port = strtoul(p, NULL, 10);
	if (debug)
		printf("Opening sim backend host '%s' port %d\n", host, port);

	sim_fd = socket(PF_INET, SOCK_STREAM, 0);
	if (sim_fd < 0) {
		fprintf(stderr, "Error opening socket: %s\n",
			strerror(errno));
		return -1;
	}
	hp = gethostbyname(host);
	if (!hp) {
		fprintf(stderr,"Unknown host '%s'\n", host);
		return -1;
	}
	memcpy(&saddr.sin_addr, hp->h_addr, hp->h_length);
	saddr.sin_port = htons(port);
	saddr.sin_family = PF_INET;
	rc = connect(sim_fd, (struct sockaddr *)&saddr, sizeof(saddr));
	if (rc < 0) {
		close(sim_fd);
		fprintf(stderr,"Connection to '%s' failed: %s\n",
			host, strerror(errno));
		return -1;
	}
	return 0;
}

static int sim_reset(void)
{
	return 0;
}

static void add_bits(uint8_t **p, int *b, uint64_t d, int c)
{
	uint8_t md = 1 << *b;
	uint64_t ms = 1;

	while (c--) {
		if (d & ms)
			(**p) |= md;
		ms <<= 1;
		if (*b == 7) {
			*b = 0;
			(*p)++;
			md = 1;
		} else {
			(*b)++;
			md <<= 1;
		}
	}
}

static uint64_t read_bits(uint8_t **p, int *b, int c)
{
	uint8_t ms = 1 << *b;
	uint64_t md = 1;
	uint64_t d = 0;

	while (c--) {
		if ((**p) & ms)
			d |= md;
		md <<= 1;
		if (*b == 7) {
			*b = 0;
			(*p)++;
			ms = 1;
		} else {
			(*b)++;
			ms <<= 1;
		}
	}
	return d;
}

static int sim_command(uint8_t op, uint8_t addr, uint64_t *data)
{
	uint8_t buf[16], *p;
	uint64_t d = data ? *data : 0;
	int r, b = 0;

	memset(buf, 0, 16);
	p = buf+1;
	add_bits(&p, &b, op, 2);
	add_bits(&p, &b, d, 64);
	add_bits(&p, &b, addr, 8);
	if (b)
		p++;
	buf[0] = 74;
	if (0)
	{
		int i;

		for (i=0; i<(p-buf); i++)
			printf("%02x ", buf[i]);
		printf("\n");
	}
	r = write(sim_fd, buf, p - buf);
	if (r < 0) {
		fprintf(stderr, "failed to write sim command\n");
		return -1;
	}
	r = read(sim_fd, buf, sizeof(buf));
	if (0 && r > 0) {
		int i;

		for (i=0; i<r; i++)
			printf("%02x ", buf[i]);
		printf("\n");
	}
	p = buf+1;
	b = 0;
	r = read_bits(&p, &b, 2);
	if (data)
		*data = read_bits(&p, &b, 64);
	return r;
}

static struct backend sim_backend = {
	.init	= sim_init,
	.reset = sim_reset,
	.command = sim_command,
};

/* -------------- JTAG backend -------------- */

static urj_chain_t *jc;

static int jtag_init(const char *target)
{
	const char *sep;
	const char *cable;
	char *params[] = { NULL, };
	urj_part_t *p;
	uint32_t id;
	int rc, part;

	if (!target)
		target = "DigilentHS1";
	sep = strchr(target, ':');
	cable = strndup(target, sep - target);
	if (sep && *sep) {
		fprintf(stderr, "jtag cable params not supported yet\n");
		return -1;
	}
	if (debug)
		printf("Opening jtag backend cable '%s'\n", cable);

	jc = urj_tap_chain_alloc();
	if (!jc) {
		fprintf(stderr, "Failed to alloc JTAG\n");
		return -1;
	}
	jc->main_part = 0;

	rc = urj_tap_chain_connect(jc, cable, params);
	if (rc != URJ_STATUS_OK) {
		fprintf(stderr, "JTAG cable detect failed\n");
		return -1;
	}

	/* XXX Hard wire part 0, that might need to change (use params and detect !) */
	rc = urj_tap_manual_add(jc, 6);
	if (rc < 0) {
		fprintf(stderr, "JTAG failed to add part !\n");
		return -1;
	}
	if (jc->parts == NULL || jc->parts->len == 0) {
		fprintf(stderr, "JTAG Something's wrong after adding part !\n");
		return -1;
	}
	urj_part_parts_set_instruction(jc->parts, "BYPASS");

	jc->active_part = part = 0;

	p = urj_tap_chain_active_part(jc);
	if (!p) {
		fprintf(stderr, "Failed to get active JTAG part\n");
		return -1;
	}
	rc = urj_part_data_register_define(p, "IDCODE_REG", 32);
	if (rc != URJ_STATUS_OK) {
		fprintf(stderr, "JTAG failed to add IDCODE_REG register !\n");
		return -1;
	}
	if (urj_part_instruction_define(p, "IDCODE", "001001", "IDCODE_REG") == NULL) {
		fprintf(stderr, "JTAG failed to add IDCODE instruction !\n");
		return -1;
	}
	rc = urj_part_data_register_define(p, "USER2_REG", 74);
	if (rc != URJ_STATUS_OK) {
		fprintf(stderr, "JTAG failed to add USER2_REG register !\n");
		return -1;
	}
	if (urj_part_instruction_define(p, "USER2", "000011", "USER2_REG") == NULL) {
		fprintf(stderr, "JTAG failed to add USER2 instruction !\n");
		return -1;
	}
	urj_part_set_instruction(p, "IDCODE");
	urj_tap_chain_shift_instructions(jc);
	urj_tap_chain_shift_data_registers(jc, 1);
        id = urj_tap_register_get_value(p->active_instruction->data_register->out);
	printf("Found device ID: 0x%08x\n", id);
	urj_part_set_instruction(p, "USER2");
	urj_tap_chain_shift_instructions(jc);

	return 0;
}

static int jtag_reset(void)
{
	return 0;
}

static int jtag_command(uint8_t op, uint8_t addr, uint64_t *data)
{
	urj_part_t *p = urj_tap_chain_active_part(jc);
	urj_part_instruction_t *insn;
	urj_data_register_t *dr;
	uint64_t d = data ? *data : 0;
	int rc;

	if (!p)
		return -1;
	insn = p->active_instruction;
	if (!insn)
		return -1;
	dr = insn->data_register;
	if (!dr)
		return -1;
	rc = urj_tap_register_set_value_bit_range(dr->in, op, 1, 0);
	if (rc != URJ_STATUS_OK)
		return -1;
	rc = urj_tap_register_set_value_bit_range(dr->in, d, 65, 2);
	if (rc != URJ_STATUS_OK)
		return -1;
	rc = urj_tap_register_set_value_bit_range(dr->in, addr, 73, 66);
	if (rc != URJ_STATUS_OK)
		return -1;
	rc = urj_tap_chain_shift_data_registers(jc, 1);
	if (rc != URJ_STATUS_OK)
		return -1;
	rc = urj_tap_register_get_value_bit_range(dr->out, 1, 0);
	if (data)
		*data = urj_tap_register_get_value_bit_range(dr->out, 65, 2);
	return rc;
}

static struct backend jtag_backend = {
	.init	= jtag_init,
	.reset = jtag_reset,
	.command = jtag_command,
};

static int dmi_read(uint8_t addr, uint64_t *data)
{
	int rc;

	rc = b->command(1, addr, data);
	if (rc < 0)
		return rc;
	for (;;) {
		rc = b->command(0, 0, data);
		if (rc < 0)
			return rc;
		if (rc == 0)
			return 0;
		if (rc != 3)
			fprintf(stderr, "Unknown status code %d !\n", rc);
	}
}

static int dmi_write(uint8_t addr, uint64_t data)
{
	int rc;

	rc = b->command(2, addr, &data);
	if (rc < 0)
		return rc;
	for (;;) {
		rc = b->command(0, 0, NULL);
		if (rc < 0)
			return rc;
		if (rc == 0)
			return 0;
		if (rc != 3)
			fprintf(stderr, "Unknown status code %d !\n", rc);
	}
}

static void core_status(void)
{
	uint64_t stat, nia, msr;
	const char *statstr, *statstr2;

	check(dmi_read(DBG_CORE_STAT, &stat), "reading core status");
	check(dmi_read(DBG_CORE_NIA, &nia), "reading core NIA");
	check(dmi_read(DBG_CORE_MSR, &msr), "reading core MSR");

	if (debug)
		printf("Core status = 0x%llx\n", (unsigned long long)stat);
	statstr = "running";
	statstr2 = "";
	if (stat & DBG_CORE_STAT_STOPPED) {
		statstr = "stopped";
		if (!(stat & DBG_CORE_STAT_STOPPING))
			statstr2 = " (restarting?)";
		else if (stat & DBG_CORE_STAT_TERM)
			statstr2 = " (terminated)";
	} else if (stat & DBG_CORE_STAT_STOPPING)
		statstr = "stopping";
	else if (stat & DBG_CORE_STAT_TERM)
		statstr = "odd state (TERM but no STOP)";
	printf("Core: %s%s\n", statstr, statstr2);
	printf(" NIA: %016" PRIx64 "\n", nia);
	printf(" MSR: %016" PRIx64 "\n", msr);
}

static void core_stop(void)
{
	check(dmi_write(DBG_CORE_CTRL, DBG_CORE_CTRL_STOP), "stopping core");
}

static void core_start(void)
{
	check(dmi_write(DBG_CORE_CTRL, DBG_CORE_CTRL_START), "starting core");
}

static void core_reset(void)
{
	check(dmi_write(DBG_CORE_CTRL, DBG_CORE_CTRL_RESET), "resetting core");
}

static void core_step(void)
{
	uint64_t stat;

	check(dmi_read(DBG_CORE_STAT, &stat), "reading core status");

	if (!(stat & DBG_CORE_STAT_STOPPED)) {
		printf("Core not stopped !\n");
		return;
	}
	check(dmi_write(DBG_CORE_CTRL, DBG_CORE_CTRL_STEP), "stepping core");
}

static void icache_reset(void)
{
	check(dmi_write(DBG_CORE_CTRL, DBG_CORE_CTRL_ICRESET), "resetting icache");
}

static const char *fast_spr_names[] =
{
	"lr", "ctr", "srr0", "srr1", "hsrr0", "hsrr1",
	"sprg0", "sprg1", "sprg2", "sprg3",
	"hsprg0", "hsprg1", "xer"
};

static void gpr_read(uint64_t reg, uint64_t count)
{
	uint64_t data;

	reg &= 0x3f;
	if (reg + count > 64)
		count = 64 - reg;
	for (; count != 0; --count, ++reg) {
		check(dmi_write(DBG_CORE_GSPR_INDEX, reg), "setting GPR index");
		data = 0xdeadbeef;
		check(dmi_read(DBG_CORE_GSPR_DATA, &data), "reading GPR data");
		if (reg <= 31)
			printf("r%"PRId64, reg);
		else if ((reg - 32) < sizeof(fast_spr_names) / sizeof(fast_spr_names[0]))
			printf("%s", fast_spr_names[reg - 32]);
		else
			printf("gspr%"PRId64, reg);
		printf(":\t%016"PRIx64"\n", data);
	}
}

static void mem_read(uint64_t addr, uint64_t count)
{
	uint64_t data;
	int i, rc;

	rc = dmi_write(DBG_WB_CTRL, 0x7ff);
	if (rc < 0)
		return;
	rc = dmi_write(DBG_WB_ADDR, addr);
	if (rc < 0)
		return;
	for (i = 0; i < count; i++) {
		rc = dmi_read(DBG_WB_DATA, &data);
		if (rc < 0)
			return;
		printf("%016llx: %016llx\n",
		       (unsigned long long)addr,
		       (unsigned long long)data);
		addr += 8;
	}
}

static void mem_write(uint64_t addr, uint64_t data)
{
	check(dmi_write(DBG_WB_CTRL, 0x7ff), "writing WB_CTRL");
	check(dmi_write(DBG_WB_ADDR, addr), "writing WB_ADDR");
	check(dmi_write(DBG_WB_DATA, data), "writing WB_DATA");
}

static void load(const char *filename, uint64_t addr)
{
	uint64_t data;
	int fd, rc, count;

	fd = open(filename, O_RDONLY);
	if (fd < 0) {
		fprintf(stderr, "Failed to open '%s': %s\n", filename, strerror(errno));
		exit(1);
	}
	check(dmi_write(DBG_WB_CTRL, 0x7ff), "writing WB_CTRL");
	check(dmi_write(DBG_WB_ADDR, addr), "writing WB_ADDR");
	count = 0;
	for (;;) {
		data = 0;
		rc = read(fd, &data, 8);
		if (rc <= 0)
			break;
		// if (rc < 8) XXX fixup endian ?
		check(dmi_write(DBG_WB_DATA, data), "writing WB_DATA");
		count += 8;
		if (!(count % 1024)) {
			printf("%x...\r", count);
			fflush(stdout);
		}
	}
	close(fd);
	printf("%x done.\n", count);
}

static void save(const char *filename, uint64_t addr, uint64_t size)
{
	uint64_t data;
	int fd, rc, count;

	fd = open(filename, O_WRONLY | O_CREAT, 00666);
	if (fd < 0) {
		fprintf(stderr, "Failed to open '%s': %s\n", filename, strerror(errno));
		exit(1);
	}
	check(dmi_write(DBG_WB_CTRL, 0x7ff), "writing WB_CTRL");
	check(dmi_write(DBG_WB_ADDR, addr), "writing WB_ADDR");
	count = 0;
	for (;;) {
		check(dmi_read(DBG_WB_DATA, &data), "reading WB_DATA");
		rc = write(fd, &data, 8);
		if (rc <= 0) {
			fprintf(stderr, "Failed to write: %s\n", strerror(errno));
			break;
		}
		count += 8;
		if (!(count % 1024)) {
			printf("%x...\r", count);
			fflush(stdout);
		}
		if (count >= size)
			break;
	}
	close(fd);
	printf("%x done.\n", count);
}

#define LOG_STOP	0x80000000ull

static void log_start(void)
{
	check(dmi_write(DBG_LOG_ADDR, 0), "writing LOG_ADDR");
}

static void log_stop(void)
{
	uint64_t lsize, laddr, waddr;

	check(dmi_write(DBG_LOG_ADDR, LOG_STOP), "writing LOG_ADDR");
	check(dmi_read(DBG_LOG_ADDR, &laddr), "reading LOG_ADDR");
	waddr = laddr >> 32;
	for (lsize = 1; lsize; lsize <<= 1)
		if ((waddr >> 1) < lsize)
			break;
	waddr &= ~lsize;
	printf("Log size = %" PRIu64 " entries, ", lsize);
	printf("write ptr = %" PRIx64 "\n", waddr);
}

static void log_dump(const char *filename)
{
	FILE *f;
	uint64_t lsize, laddr, waddr;
	uint64_t orig_laddr;
	uint64_t i, ldata;

	f = fopen(filename, "w");
	if (f == NULL) {
		fprintf(stderr, "Failed to create '%s': %s\n", filename,
			strerror(errno));
		exit(1);
	}

	check(dmi_read(DBG_LOG_ADDR, &orig_laddr), "reading LOG_ADDR");
	if (!(orig_laddr & LOG_STOP))
		check(dmi_write(DBG_LOG_ADDR, LOG_STOP), "writing LOG_ADDR");

	waddr = orig_laddr >> 32;
	for (lsize = 1; lsize; lsize <<= 1)
		if ((waddr >> 1) < lsize)
			break;
	waddr &= ~lsize;
	printf("Log size = %" PRIu64 " entries\n", lsize);

	laddr = LOG_STOP | (waddr << 2);
	check(dmi_write(DBG_LOG_ADDR, laddr), "writing LOG_ADDR");

	for (i = 0; i < lsize * 4; ++i) {
		check(dmi_read(DBG_LOG_DATA, &ldata), "reading LOG_DATA");
		if (fwrite(&ldata, sizeof(ldata), 1, f) != 1) {
			fprintf(stderr, "Write error on %s\n", filename);
			exit(1);
		}
		if (!(i % 128)) {
			printf("%" PRIu64 "...\r", i * 8);
			fflush(stdout);
		}
	}
	fclose(f);
	printf("%" PRIu64 " done\n", lsize * 32);

	check(dmi_write(DBG_LOG_ADDR, orig_laddr), "writing LOG_ADDR");
}

static void usage(const char *cmd)
{
	fprintf(stderr, "Usage: %s -b <jtag|sim> <command> <args>\n", cmd);

	fprintf(stderr, "\n");
	fprintf(stderr, " CPU core:\n");
	fprintf(stderr, "  start\n");
	fprintf(stderr, "  stop\n");
	fprintf(stderr, "  step\n");
	fprintf(stderr, "  creset			core reset\n");
	fprintf(stderr, "  icreset			icache reset\n");

	fprintf(stderr, "\n");
	fprintf(stderr, " Memory:\n");
	fprintf(stderr, "  mr <hex addr> [count]\n");
	fprintf(stderr, "  mw <hex addr> <hex value>\n");
	fprintf(stderr, "  load <file> [addr]		If omitted address is 0\n");
	fprintf(stderr, "  save <file> <addr> <size>\n");

	fprintf(stderr, "\n");
	fprintf(stderr, " Registers:\n");
	fprintf(stderr, "  gpr <reg> [count]\n");
	fprintf(stderr, "  status\n");

	fprintf(stderr, "\n");
	fprintf(stderr, " Core logging:\n");
	fprintf(stderr, "  lstart			start logging\n");
	fprintf(stderr, "  lstop			stop logging\n");
	fprintf(stderr, "  ldump <file>			dump log to file\n");

	fprintf(stderr, "\n");
	fprintf(stderr, " JTAG:\n");
	fprintf(stderr, "  dmiread <hex addr>\n");
	fprintf(stderr, "  dmiwrite <hex addr> <hex value>\n");
	fprintf(stderr, "  quit\n");

	exit(1);
}

int main(int argc, char *argv[])
{
	const char *progname = argv[0];
	const char *target = NULL;
	int rc, i = 1;

	b = NULL;

	while(1) {
		int c, oindex;
		static struct option lopts[]  = {
			{ "help",	no_argument,       0, 'h' },
			{ "backend",	required_argument, 0, 'b' },
			{ "target",	required_argument, 0, 't' },
			{ "debug",	no_argument,       0, 'd' },
			{ 0, 0, 0, 0 }
		};
		c = getopt_long(argc, argv, "dhb:t:", lopts, &oindex);
		if (c < 0)
			break;
		switch(c) {
		case 'h':
			usage(progname);
			break;
		case 'b':
			if (strcmp(optarg, "sim") == 0)
				b = &sim_backend;
			else if (strcmp(optarg, "jtag") == 0)
				b = &jtag_backend;
			else {
				fprintf(stderr, "Unknown backend %s\n", optarg);
				exit(1);
			}
			break;
		case 't':
			target = optarg;
			break;
		case 'd':
			debug = true;
		}
	}

	if (b == NULL) {
		fprintf(stderr, "No backend selected\n");
		exit(1);
	}

	rc = b->init(target);
	if (rc < 0)
		exit(1);
	for (i = optind; i < argc; i++) {
		if (strcmp(argv[i], "dmiread") == 0) {
			uint8_t  addr;
			uint64_t data;

			if ((i+1) >= argc)
				usage(argv[0]);
			addr = strtoul(argv[++i], NULL, 16);
			dmi_read(addr, &data);
			printf("%02x: %016llx\n", addr, (unsigned long long)data);
		} else if (strcmp(argv[i], "dmiwrite") == 0) {
			uint8_t  addr;
			uint64_t data;

			if ((i+2) >= argc)
				usage(argv[0]);
			addr = strtoul(argv[++i], NULL, 16);
			data = strtoul(argv[++i], NULL, 16);
			dmi_write(addr, data);
		} else if (strcmp(argv[i], "creset") == 0) {
			core_reset();
		} else if (strcmp(argv[i], "icreset") == 0) {
			icache_reset();
		} else if (strcmp(argv[i], "stop") == 0) {
			core_stop();
		} else if (strcmp(argv[i], "start") == 0) {
			core_start();
		} else if (strcmp(argv[i], "step") == 0) {
			core_step();
		} else if (strcmp(argv[i], "quit") == 0) {
			dmi_write(0xff, 0);
		} else if (strcmp(argv[i], "status") == 0) {
			/* do nothing, always done below */
		} else if (strcmp(argv[i], "mr") == 0) {
			uint64_t addr, count = 1;

			if ((i+1) >= argc)
				usage(argv[0]);
			addr = strtoul(argv[++i], NULL, 16);
			if (((i+1) < argc) && isdigit(argv[i+1][0]))
				count = strtoul(argv[++i], NULL, 16);
			mem_read(addr, count);
		} else if (strcmp(argv[i], "mw") == 0) {
			uint64_t addr, data;

			if ((i+2) >= argc)
				usage(argv[0]);
			addr = strtoul(argv[++i], NULL, 16);
			data = strtoul(argv[++i], NULL, 16);
			mem_write(addr, data);
		} else if (strcmp(argv[i], "load") == 0) {
			const char *filename;
			uint64_t addr = 0;

			if ((i+1) >= argc)
				usage(argv[0]);
			filename = argv[++i];
			if (((i+1) < argc) && isdigit(argv[i+1][0]))
				addr = strtoul(argv[++i], NULL, 16);
			load(filename, addr);
		} else if (strcmp(argv[i], "save") == 0) {
			const char *filename;
			uint64_t addr, size;

			if ((i+3) >= argc)
				usage(argv[0]);
			filename = argv[++i];
			addr = strtoul(argv[++i], NULL, 16);
			size = strtoul(argv[++i], NULL, 16);
			save(filename, addr, size);
		} else if (strcmp(argv[i], "gpr") == 0) {
			uint64_t reg, count = 1;

			if ((i+1) >= argc)
				usage(argv[0]);
			reg = strtoul(argv[++i], NULL, 10);
			if (((i+1) < argc) && isdigit(argv[i+1][0]))
				count = strtoul(argv[++i], NULL, 10);
			gpr_read(reg, count);
		} else if (strcmp(argv[i], "lstart") == 0) {
			log_start();
		} else if (strcmp(argv[i], "lstop") == 0) {
			log_stop();
		} else if (strcmp(argv[i], "ldump") == 0) {
			const char *filename;

			if ((i+1) >= argc)
				usage(argv[0]);
			filename = argv[++i];
			log_dump(filename);
		} else {
			fprintf(stderr, "Unknown command %s\n", argv[i]);
			exit(1);
		}
	}
	core_status();
	return 0;
}
