/******************************************************************************
 * Copyright (c) 2004, 2008, 2019 IBM Corporation
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

char *strrchr(const char *s, int c);
char *strrchr(const char *s, int c)
{
	char *last = NULL;
	char cb = c;

	while (*s != 0) {
		if (*s == cb)
			last = (char *)s;
		s += 1;
	}

	return last;
}
