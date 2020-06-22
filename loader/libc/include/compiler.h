/* Copyright 2013-2014 IBM Corp.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * 	http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef __COMPILER_H
#define __COMPILER_H

#ifndef __ASSEMBLY__

#include <stddef.h>

/* Macros for various compiler bits and pieces */
#define __packed		__attribute__((packed))
#define __align(x)		__attribute__((__aligned__(x)))
#define __unused		__attribute__((unused))
#define __used			__attribute__((used))
#define __section(x)		__attribute__((__section__(x)))
#define __noreturn		__attribute__((noreturn))
/* not __const as this has a different meaning (const) */
#define __attrconst		__attribute__((const))
#define __warn_unused_result	__attribute__((warn_unused_result))
#define __noinline		__attribute__((noinline))

#if 0 /* Provided by gcc stddef.h */
#define offsetof(type,m)	__builtin_offsetof(type,m)
#endif

#define __nomcount		__attribute__((no_instrument_function))

/* Compiler barrier */
static inline void barrier(void)
{
//	asm volatile("" : : : "memory");
}

#endif /* __ASSEMBLY__ */

/* Stringification macro */
#define __tostr(x)	#x
#define tostr(x)	__tostr(x)

#endif /* __COMPILER_H */
