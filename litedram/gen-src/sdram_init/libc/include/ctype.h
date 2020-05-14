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

#ifndef _CTYPE_H
#define _CTYPE_H

#include <compiler.h>

int __attrconst isdigit(int c);
int __attrconst isxdigit(int c);
int __attrconst isprint(int c);
int __attrconst isspace(int c);

int __attrconst tolower(int c);
int __attrconst toupper(int c);

#endif
