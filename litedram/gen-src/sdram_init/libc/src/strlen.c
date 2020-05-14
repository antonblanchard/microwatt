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

size_t strlen(const char *s);
size_t strlen(const char *s)
{
	size_t len = 0;

	while (*s != 0) {
		len += 1;
		s += 1;
	}

	return len;
}

size_t strnlen(const char *s, size_t n);
size_t strnlen(const char *s, size_t n)
{
	size_t len = 0;

	while (*s != 0 && n) {
		len += 1;
		s += 1;
		n--;
	}

	return len;
}
