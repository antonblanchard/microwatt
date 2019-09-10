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

#include <stddef.h>
#include <stdint.h>

void *memcpy(void *dest, const void *src, size_t n);
void *memcpy(void *dest, const void *src, size_t n)
{
	void *ret = dest;

	while (n >= 8) {
		*(uint64_t *)dest = *(uint64_t *)src;
		dest += 8;
		src += 8;
		n -= 8;
	}

	while (n > 0) {
		*(uint8_t *)dest = *(uint8_t *)src;
		dest += 1;
		src += 1;
		n -= 1;
	}

	return ret;
}
