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

char *strcpy(char *dst, const char *src);
char *strcpy(char *dst, const char *src)
{
	char *ptr = dst;

	do {
		*ptr++ = *src;
	} while (*src++ != 0);

	return dst;
}
