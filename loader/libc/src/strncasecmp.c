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

#include <ctype.h>

int strncasecmp(const char *s1, const char *s2, size_t n);
int strncasecmp(const char *s1, const char *s2, size_t n)
{
	if (n < 1)
		return 0;

	while (*s1 != 0 && *s2 != 0 && --n > 0) {
		if (toupper(*s1) != toupper(*s2))
			break;
		++s1;
		++s2;
	}

	return toupper(*s1) - toupper(*s2);
}

