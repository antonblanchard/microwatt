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

#define STACK_TOP 0x2000

/* Load an immediate 64-bit value into a register */
#define LOAD_IMM64(r, e)			\
	lis     r,(e)@highest;			\
	ori     r,r,(e)@higher;			\
	rldicr  r,r, 32, 31;			\
	oris    r,r, (e)@h;			\
	ori     r,r, (e)@l;

	.section ".head","ax"

	/*
	 * Microwatt currently enters in LE mode at 0x0, so we don't need to
	 * do any endian fix ups
	 */
	. = 0
.global _start
_start:
	b	boot_entry

.global boot_entry
boot_entry:
	/* setup stack */
	LOAD_IMM64(%r1, STACK_TOP - 0x100)
	LOAD_IMM64(%r12, main)
	mtctr	%r12
	bctrl
	attn // terminate on exit
	b .

/* test to see if end up at the instruction after the rfid */
.global dec_test_1
dec_test_1:
	li	%r3, 0
	mtdec	%r3
	LOAD_IMM64(%r3, dec_test_1_rfid)
	mtsrr0	%r3
	LOAD_IMM64(%r3, 0x9000000000008003)
	mtsrr1	%r3
	li	%r3, 1 // preload with a fail code
	rfid
dec_test_1_rfid:
	b	1f // should be skipped
	b	1f // should be skipped
	li	%r3, 0
	blr
1:
	li	%r3, 1
	blr


/* test to see if end up at the instruction after the rfid */
.global dec_test_2
dec_test_2:
	li	%r3, 0x100
	mtdec	%r3
	LOAD_IMM64(%r3, dec_test_2_rfid)
	mtsrr0	%r3
	LOAD_IMM64(%r3, 0x9000000000008003)
	mtsrr1	%r3
	li	%r3, 1 // preload with a fail code
	rfid
dec_test_2_rfid:
	b	.  // should wait here and then be skipped
	b	1f // should be skipped
	li	%r3, 0
	blr
1:
	li	%r3, 1
	blr


/* test mtmsrd */
.global dec_test_3
dec_test_3:
	LOAD_IMM64(%r3, 0x9000000000000003)
	mtmsrd	%r3	// EE off
	li	%r3, 0x0 // shouldn't fire right away
	mtdec	%r3
	b	2f
	nop
	b	1f // shouln't get here
2:
	LOAD_IMM64(%r3, 0x9000000000008003)
	mtmsrd	%r3	// EE on
	b	1f // shouln't get here
	b	1f // shouln't get here

	li	%r3, 0
	blr
1:
	li	%r3, 1
	blr

#define EXCEPTION(nr)		\
	.= nr			;\
	b	.

	/* More exception stubs */
	EXCEPTION(0x300)
	EXCEPTION(0x380)
	EXCEPTION(0x400)
	EXCEPTION(0x480)
	EXCEPTION(0x500)
	EXCEPTION(0x600)
	EXCEPTION(0x700)
	EXCEPTION(0x800)

	. = 0x900
	mtsprg0	%r3
	LOAD_IMM64(%r3, 0x000000000ffffff)
	mtdec	%r3
	mfsrr0	%r3
	addi	%r3, %r3, 8 // skip 2 instructions
	mtsrr0  %r3
	mfsprg0	%r3
	rfid

	EXCEPTION(0x980)
	EXCEPTION(0xa00)
	EXCEPTION(0xb00)
	EXCEPTION(0xc00)
	EXCEPTION(0xd00)
	EXCEPTION(0xe00)
	EXCEPTION(0xe20)
	EXCEPTION(0xe40)
	EXCEPTION(0xe60)
	EXCEPTION(0xe80)
	EXCEPTION(0xf00)
	EXCEPTION(0xf20)
	EXCEPTION(0xf40)
	EXCEPTION(0xf60)
	EXCEPTION(0xf80)
#if 0
	EXCEPTION(0x1000)
	EXCEPTION(0x1100)
	EXCEPTION(0x1200)
	EXCEPTION(0x1300)
	EXCEPTION(0x1400)
	EXCEPTION(0x1500)
	EXCEPTION(0x1600)
#endif


