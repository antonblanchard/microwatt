/******************************************************************************
 * Copyright (c) 2004, 2008 IBM Corporation
 * All rights reserved.
 * This program and the accompanying materials
 * are made available under the terms of the BSD License
 * which accompanies this distribution, and is available at
 * http://www.opensource.org/licenses/bsd-license.php
 *
 * Contributors:
 *     IBM Corporation - initial implementation
 *****************************************************************************/

#define CACHE_LINE_SIZE 128

#include <stddef.h>

void *memset(void *dest, int c, size_t size);
void *memset(void *dest, int c, size_t size)
{
	unsigned char *d = (unsigned char *)dest;
	unsigned long big_c = 0;

	if (c) {
		big_c = c;
		big_c |= (big_c << 8) | big_c;
		big_c |= (big_c << 16) | big_c;
		big_c |= (big_c << 32) | big_c;
	}
	while (size >= 8 && c == 0) {
		*((unsigned long *)d) = big_c;
		d+=8;
		size-=8;
	}

	while (size-- > 0) {
		*d++ = (unsigned char)c;
	}

	return dest;
}
