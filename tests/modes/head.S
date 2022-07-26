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
	LOAD_IMM64(%r10,__bss_start)
	LOAD_IMM64(%r11,__bss_end)
	subf	%r11,%r10,%r11
	addi	%r11,%r11,63
	srdi.	%r11,%r11,6
	beq	2f
	mtctr	%r11
1:	dcbz	0,%r10
	addi	%r10,%r10,64
	bdnz	1b

2:	LOAD_IMM64(%r1,__stack_top)
	li	%r0,0
	stdu	%r0,-16(%r1)
	mtsprg2	%r0
	LOAD_IMM64(%r12, main)
	mtctr	%r12
	bctrl
	attn // terminate on exit
	b .

exception:
	mfsprg2	%r0
	cmpdi	%r0,0
	bne	call_ret
	attn

#define EXCEPTION(nr)		\
	.= nr			;\
	li	%r3,nr		;\
	b	exception

	EXCEPTION(0x300)
	EXCEPTION(0x380)
	EXCEPTION(0x400)
	EXCEPTION(0x480)
	EXCEPTION(0x500)
	EXCEPTION(0x600)
	EXCEPTION(0x700)
	EXCEPTION(0x800)
	EXCEPTION(0x900)
	EXCEPTION(0x980)
	EXCEPTION(0xa00)
	EXCEPTION(0xb00)
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

	. = 0x1000
	/*
	 * This page gets mapped at various locations and
	 * the tests try to execute from it.
	 * r3 contains the test number.
	 */
	.globl	test_code
test_code:
	nop
	nop
	mflr	%r9
	cmpdi	%r3,1
	beq	test_1
	cmpdi	%r3,2
	beq	test_2
	cmpdi	%r3,3
	beq	test_3
	li	%r3,0
	blr

	/* test a doubleword load from memory */
test_1:	ld	%r3,0(%r4)
	blr

	/* test a branch from the page at fffff000 */
test_2:
	b	test_2a + 0x1000
test_2a:
	b	test_2b - 0x1000
test_2b:
	beq	test_2c + 0x1000
test_2c:
	beq	test_2d - 0x1000
test_2d:
	li	%r3,0
	blr

test_return:
	mflr	%r3
	mtlr	%r9
	blr
	. = 0x1ffc
	/* test a branch with link from the 4G-4 address */
test_3:	bl	test_return

	.globl	test_code_end
test_code_end:

	. = 0x2000
	/*
	 * Call a function in a context with a given MSR value.
	 * r3, r4 = args; r5 = function; r6 = MSR
	 */
	.globl	callit
callit:
	mflr	%r0
	std	%r0,16(%r1)
	stdu	%r1,-256(%r1)
	mfcr	%r8
	stw	%r8,100(%r1)
	std	%r13,104(%r1)
	std	%r14,112(%r1)
	std	%r15,120(%r1)
	std	%r16,128(%r1)
	std	%r17,136(%r1)
	std	%r18,144(%r1)
	std	%r19,152(%r1)
	std	%r20,160(%r1)
	std	%r21,168(%r1)
	std	%r22,176(%r1)
	std	%r23,184(%r1)
	std	%r24,192(%r1)
	std	%r25,200(%r1)
	std	%r26,208(%r1)
	std	%r27,216(%r1)
	std	%r28,224(%r1)
	std	%r29,232(%r1)
	std	%r30,240(%r1)
	std	%r31,248(%r1)
	li	%r0,restore@l
	mtsprg0	%r0
	mtsprg1	%r1
	mtsprg2	%r2
	mfmsr	%r9
	mtsprg3	%r9
	li	%r10,call_ret@l
	mtlr	%r10
	mtsrr0	%r5
	mtsrr1	%r6
	mr	%r12,%r5
	rfid
call_ret:
	tdi	0,%r0,0x48	/* b .+8 if wrong endian */
	b	2f		/* if endian OK */
	/* reverse-endian version of instructions from 2: on */
	.long	0xa642107c
	.long	0xa642937c
	.long	0xa602ba7c
	.long	0xa602db7c
	.long	0xa643b07c
	.long	0xa643d37c
	.long	0xa6031a7c
	.long	0xa6039b7c
	.long	0x2400004c
2:	mfsprg0	%r0
	mfsprg3	%r4
	mfsrr0	%r5
	mfsrr1	%r6
	mtsprg0	%r5
	mtsprg3	%r6
	mtsrr0	%r0
	mtsrr1	%r4
	rfid
restore:
	mfsprg1	%r1
	mfsprg2	%r2
	li	%r7,0
	mtsprg2	%r7
	lwz	%r8,100(%r1)
	mtcr	%r8
	ld	%r13,104(%r1)
	ld	%r14,112(%r1)
	ld	%r15,120(%r1)
	ld	%r16,128(%r1)
	ld	%r17,136(%r1)
	ld	%r18,144(%r1)
	ld	%r19,152(%r1)
	ld	%r20,160(%r1)
	ld	%r21,168(%r1)
	ld	%r22,176(%r1)
	ld	%r23,184(%r1)
	ld	%r24,192(%r1)
	ld	%r25,200(%r1)
	ld	%r26,208(%r1)
	ld	%r27,216(%r1)
	ld	%r28,224(%r1)
	ld	%r29,232(%r1)
	ld	%r30,240(%r1)
	ld	%r31,248(%r1)
	addi	%r1,%r1,256
	ld	%r0,16(%r1)
	mtlr	%r0
	blr
