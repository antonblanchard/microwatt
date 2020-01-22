#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#include "sim_vhpi_c.h"

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

char *from_string(void *__p)
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

uint64_t from_std_logic_vector(unsigned char *p, unsigned long len)
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

void to_std_logic_vector(unsigned long val, unsigned char *p,
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
