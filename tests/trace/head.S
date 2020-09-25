/* Copyright 2020 Paul Mackerras, IBM Corp.
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
	mtsprg3	%r0
	mfsprg2	%r0
	cmpdi	%r0,0
	bne	call_ret
	attn

#define EXCEPTION(nr)		\
	.= nr			;\
	li	%r0,nr		;\
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

	. = 0x1000
	/*
	 * Call a function in a context with a given MSR value.
	 * r3, r4 = args; r5 = function, r6 = MSR,
	 * r7 = array in which to return r3 and r4
	 * Return value is trap number or 0.
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
	li	%r10,call_ret@l
	mtlr	%r10
	mtsprg0	%r7
	mtsprg1	%r1
	mtsprg2	%r2
	li	%r11,0
	mtsprg3	%r11
	mtsrr0	%r5
	mtsrr1	%r6
	rfid
call_ret:
	mfsprg0	%r7		/* restore regs in case of trap */
	mfsprg1	%r1
	mfsprg2	%r2
	li	%r0,0
	mtsprg2	%r0
	std	%r3,0(%r7)
	std	%r4,8(%r7)
	mfsprg3	%r3
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

	.global test1
test1:
	addi	%r3,%r4,1
	li	%r3,0
	blr

	.global test2
test2:
	ld	%r3,0(%r4)
	li	%r3,-1
	blr

	.global test3
test3:
	stw	%r3,0(%r4)
	li	%r3,-1
	blr

	.global test4
test4:
	dcbt	0,%r3
	li	%r3,-1
	blr

	.global test5
test5:
	dcbtst	0,%r3
	li	%r3,-1
	blr

	.global test6
test6:
	nop
	nop
	b	1f
	li	%r3,2
	blr
1:	li	%r3,1
	blr

	.global	test7
test7:
	li	%r4,1
	cmpwi	%r4,0
	bne	1f
	li	%r3,-1
1:	blr

	.global	test8
test8:
	lfd	%f0,0(%r3)
	blr
