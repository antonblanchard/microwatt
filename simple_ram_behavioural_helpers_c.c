#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>

#undef DEBUG

#define ALIGN_UP(VAL, SIZE)	(((VAL) + ((SIZE)-1)) & ~((SIZE)-1))

#define vhpi0	2	/* forcing 0 */
#define vhpi1	3	/* forcing 1 */

struct int_bounds
{
	int left;
	int right;
	char dir;
	unsigned int len;
};

struct fat_pointer
{
	void *base;
	struct int_bounds *bounds;
};

static char *from_string(void *__p)
{
	struct fat_pointer *p = __p;
	unsigned long len = p->bounds->len;
	char *m;

	m = malloc(len+1);
	if (!m) {
		perror("malloc");
		exit(1);
	}

	memcpy(m, p->base, len);
	m[len] = 0x0;

	return m;
}

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

#define MAX_REGIONS 128

struct ram_behavioural {
	char *filename;
	unsigned long size;
	void *m;
};

static struct ram_behavioural behavioural_regions[MAX_REGIONS];
static unsigned long region_nr;

unsigned long behavioural_initialize(void *__f, unsigned long size)
{
	struct ram_behavioural *r;
	int fd;
	struct stat buf;
	unsigned long tmp_size;
	void *mem;

	if (region_nr == MAX_REGIONS) {
		fprintf(stderr, "%s: too many regions, bump MAX_REGIONS\n", __func__);
		exit(1);
	}

	r = &behavioural_regions[region_nr];

	r->filename = from_string(__f);
	r->size = ALIGN_UP(size, getpagesize());

	fd = open(r->filename, O_RDWR);
	if (fd == -1) {
		fprintf(stderr, "%s: could not open %s\n", __func__,
			r->filename);
		exit(1);
	}

	if (fstat(fd, &buf)) {
		perror("fstat");
		exit(1);
	}

	/* XXX Do we need to truncate the underlying file? */
	tmp_size = ALIGN_UP(buf.st_size, getpagesize());

	if (r->size > tmp_size) {
		void *m;

		/*
		 * We have to pad the file. Allocate the total size, then
		 * create a space for the file.
		 */
		mem = mmap(NULL, r->size, PROT_READ|PROT_WRITE,
				MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
		if (mem == MAP_FAILED) {
			perror("mmap");
			exit(1);
		}

		if (tmp_size) {
			munmap(mem, tmp_size);

			m = mmap(mem, tmp_size, PROT_READ|PROT_WRITE,
					MAP_PRIVATE|MAP_FIXED, fd, 0);
			if (m == MAP_FAILED) {
				perror("mmap");
				exit(1);
			}
			if (m != mem) {
				fprintf(stderr, "%s: mmap(MAP_FIXED) failed\n",
					__func__);
				exit(1);
			}
		}
	} else {
		mem = mmap(NULL, tmp_size, PROT_READ|PROT_WRITE, MAP_PRIVATE,
				fd, 0);
		if (mem == MAP_FAILED) {
			perror("mmap");
			exit(1);
		}
	}

	behavioural_regions[region_nr].m = mem;
	return region_nr++;
}

void behavioural_read(unsigned char *__val, unsigned char *__addr,
			unsigned long sel, int identifier)
{
	struct ram_behavioural *r;
	unsigned long val = 0;
	unsigned long addr = from_std_logic_vector(__addr, 64);
	unsigned char *p;

	if (identifier > region_nr) {
		fprintf(stderr, "%s: bad index %d\n", __func__, identifier);
		exit(1);
	}

	r = &behavioural_regions[identifier];

	for (unsigned long i = 0; i < 8; i++) {
#if 0
		/* sel only used on writes */
		if (!(sel & (1UL << i)))
			continue;
#endif

		if ((addr + i) > r->size) {
			fprintf(stderr, "%s: bad memory access %lx %lx\n", __func__,
				addr+i, r->size);
			exit(1);
		}

		p = (unsigned char *)(((unsigned long)r->m) + addr + i);
		val |= (((unsigned long)*p) << (i*8));
	}

#ifdef DEBUG
	printf("MEM behave %d read  %016lx addr %016lx sel %02lx\n", identifier, val,
		addr, sel);
#endif

	to_std_logic_vector(val, __val, 64);
}

void behavioural_write(unsigned char *__val, unsigned char *__addr,
			unsigned int sel, int identifier)
{
	struct ram_behavioural *r;
	unsigned long val = from_std_logic_vector(__val, 64);
	unsigned long addr = from_std_logic_vector(__addr, 64);
	unsigned char *p;

	if (identifier > region_nr) {
		fprintf(stderr, "%s: bad index %d\n", __func__, identifier);
		exit(1);
	}

	r = &behavioural_regions[identifier];

	p = (unsigned char *)(((unsigned long)r->m) + addr);

#ifdef DEBUG
	printf("MEM behave %d write %016lx addr %016lx sel %02x\n", identifier, val,
		addr, sel);
#endif

	for (unsigned long i = 0; i < 8; i++) {
		if (!(sel & (1UL << i)))
			continue;

		if ((addr + i) > r->size) {
			fprintf(stderr, "%s: bad memory access %lx %lx\n", __func__,
				addr+i, r->size);
			exit(1);
		}

		p = (unsigned char *)(((unsigned long)r->m) + addr + i);
		*p = (val >> (i*8)) & 0xff;
	}
}
