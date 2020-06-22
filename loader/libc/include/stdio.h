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

#ifndef _STDIO_H
#define _STDIO_H

#include <stdarg.h>
#include "stddef.h"

#define EOF (-1)

int _printf(const char *format, ...) __attribute__((format (printf, 1, 2)));

#ifndef pr_fmt
#define pr_fmt(fmt) fmt
#endif

#define printf(f, ...) do { _printf(pr_fmt(f), ##__VA_ARGS__); } while(0)

int snprintf(char *str, size_t size, const char *format, ...)  __attribute__((format (printf, 3, 4)));
int vsnprintf(char *str, size_t size, const char *format, va_list);

int putchar(int ch);
int puts(const char *str);

#endif
