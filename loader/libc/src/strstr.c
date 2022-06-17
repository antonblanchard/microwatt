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
int strncmp(const char *s1, const char *s2, size_t n);
char *strstr(const char *hay, const char *needle);
char *strstr(const char *hay, const char *needle)
{
	char *pos;
	size_t hlen, nlen;

	if (hay == NULL || needle == NULL)
		return NULL;
	
	hlen = strlen(hay);
	nlen = strlen(needle);
	if (nlen < 1)
		return (char *)hay;

	for (pos = (char *)hay; pos < hay + hlen; pos++) {
		if (strncmp(pos, needle, nlen) == 0) {
			return pos;
		}
	}

	return NULL;
}

