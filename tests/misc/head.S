/* Copyright 2013-2014 IBM Corp.
 * Copyrignt 2020 Shawn Anastasio
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


/* Test addpcis with an immediate operand of 0 (min) */
.global test_addpcis_1
test_addpcis_1:
    mflr %r0
    std %r0, 16(%r1)
    stdu %r1, -32(%r1)

    /* get address of 1 */
    bl 1f
    1: mflr %r4
    addpcis %r5, 0

    /*
     * At this point, r5 should equal r4 + 2*4
     * return 0 if they're equal.
     */
    addi %r4, %r4, 8

    sub %r3, %r4, %r5

    addi %r1, %r1, 32
    ld %r0, 16(%r1)
    mtlr %r0

    blr

/* Test addpcis with an immediate operand of 0xFFFF (max) */
.global test_addpcis_2
test_addpcis_2:
    mflr %r0
    std %r0, 16(%r1)
    stdu %r1, -32(%r1)

    /* get address of 1 */
    bl 1f
    1: mflr %r4
    addpcis %r5, 0xFFFF

    /*
     * Add 8 to r4 to bring it in line with addpcis' NIA.
     * Then add 0xFFFF shifted and compare.
     */
    addi %r4, %r4, 8
    addis %r4, %r4, 0xFFFF

    sub %r3, %r4, %r5

    addi %r1, %r1, 32
    ld %r0, 16(%r1)
    mtlr %r0

    blr

