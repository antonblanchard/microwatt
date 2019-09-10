/******************************************************************************
 * Copyright (c) 2004, 2008, 2012 IBM Corporation
 * All rights reserved.
 * This program and the accompanying materials
 * are made available under the terms of the BSD License
 * which accompanies this distribution, and is available at
 * http://www.opensource.org/licenses/bsd-license.php
 *
 * Contributors:
 *     IBM Corporation - initial implementation
 *****************************************************************************/

#ifndef _ASSERT_H
#define _ASSERT_H

#define assert(cond)						\
	do { if (!(cond)) {					\
		     assert_fail(__FILE__			\
				 ":" stringify(__LINE__)	\
				 ":" stringify(cond));	}	\
	} while(0)

void __attribute__((noreturn)) assert_fail(const char *msg);

#define stringify(expr)		stringify_1(expr)
/* Double-indirection required to stringify expansions */
#define stringify_1(expr)	#expr

#endif
