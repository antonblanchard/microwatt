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
#define PVR	287

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

/* Test reading the PVR */
.global test_mfpvr
test_mfpvr:
    mflr %r0
    std %r0, 16(%r1)
    stdu %r1, -32(%r1)

    /*
     * If r3 happened to already contain PVR_MICROWATT the test
     * would succeed even if the PVR is not implemented.
     */
    LOAD_IMM64(%r3, 0xdeadbeef)
    mfpvr %r3

    addi %r1, %r1, 32
    ld %r0, 16(%r1)
    mtlr %r0

    blr

/* Test writing the PVR does nothing */
.global test_mtpvr
test_mtpvr:
    mflr %r0
    std %r0, 16(%r1)
    stdu %r1, -32(%r1)

    LOAD_IMM64(%r3, 0xdeadbeef)
    mtspr PVR, %r3
    mfpvr %r3

    addi %r1, %r1, 32
    ld %r0, 16(%r1)
    mtlr %r0

    blr

/* Test that bdnz and bdnzl update CTR and LR correctly */
	.global	test_bdnzl
test_bdnzl:
	mflr	%r10
	mfcr	%r11
	li	%r0,0xf8
	mtctr	%r0
	lis	%r0,0x2000
	mtcr	%r0
	addpcis	%r9,0
1:	bdnztl	27,3f
2:	bdnzt	14,4f
3:	nop
4:	li	%r3,1
	addi	%r9,%r9,2b-1b
	mflr	%r8
	cmpd	%r8,%r9
	bne	9f
	mfctr	%r7
	cmpdi	%r7,0xf6
	bne	9f
	li	%r3,0
9:	mtlr	%r10
	blr

/* Test that a load that hits stores gets the correct data */
	.global test_loadhitstore
test_loadhitstore:
	addi	%r5,%r1,-16
	ld	%r0,0(%r5)
	li	%r0,0
	std	%r0,0(%r5)
	li	%r6,0x66
	li	%r7,0x77
	.balign	64
	nop
	nop
	nop
	nop
	stb	%r6,2(%r5)
	stb	%r7,3(%r5)
	ld	%r0,0(%r5)
	sldi	%r6,%r6,16
	sldi	%r7,%r7,24
	or	%r7,%r6,%r7
	subf	%r3,%r0,%r7
	blr

/* Test for double execution of addi */
.balign 64
	.global test_icbi
test_icbi:
1:	li	%r3,0
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	icbi	0,%r0
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	nop
	addi	%r3,%r3,1
	blr

	.global test_dcbz_near_store
test_dcbz_near_store:
	li	%r0,-1
	addi	%r10,%r1,-64
	# cacheline align stack pointer
	srdi	%r10,%r10,6
	sldi	%r10,%r10,6

	std	%r0,0(%r10)
	std	%r0,8(%r10)
	std	%r0,16(%r10)
	std	%r0,24(%r10)
	std	%r0,32(%r10)
	std	%r0,40(%r10)
	std	%r0,48(%r10)
	std	%r0,56(%r10)

	li	%r3,0xa5
	# Store to same cacheline as dcbz, although it doesn't seem
	# necessary to hit the issue.
	std	%r3,0(%r10)
	dcbz	0,%r10

	ld	%r0,0(%r10)
	ld	%r3,8(%r10)
	ld	%r4,16(%r10)
	ld	%r5,24(%r10)
	ld	%r6,32(%r10)
	ld	%r7,40(%r10)
	ld	%r8,48(%r10)
	ld	%r9,56(%r10)

	or	%r3,%r3,%r0
	or	%r3,%r3,%r4
	or	%r3,%r3,%r5
	or	%r3,%r3,%r6
	or	%r3,%r3,%r7
	or	%r3,%r3,%r8
	or	%r3,%r3,%r9

	blr
