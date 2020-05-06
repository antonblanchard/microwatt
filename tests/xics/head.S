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

#define STACK_TOP 0x4000

/* Load an immediate 64-bit value into a register */
#define LOAD_IMM64(r, e)			\
	lis     r,(e)@highest;			\
	ori     r,r,(e)@higher;			\
	rldicr  r,r, 32, 31;			\
	oris    r,r, (e)@h;			\
	ori     r,r, (e)@l;

	.section ".head","ax"

	/* Microwatt currently enters in LE mode at 0x0 */
	. = 0
.global _start
_start:
	LOAD_IMM64(%r12, 0x000000000ffffff)
	mtdec	%r12
	LOAD_IMM64(%r12, 0x9000000000008003)
	mtmsrd	%r12	// EE on
	/* setup stack */
	LOAD_IMM64(%r1, STACK_TOP - 0x100)
	LOAD_IMM64(%r12, main)
	mtctr	%r12
	bctrl
	attn // terminate on exit
	b .

#define EXCEPTION(nr)		\
	.= nr			;\
	b	.

	/* More exception stubs */
	EXCEPTION(0x300)
	EXCEPTION(0x380)
	EXCEPTION(0x400)
	EXCEPTION(0x480)
	. = 0x500
	b	__isr

	EXCEPTION(0x600)
	EXCEPTION(0x700)
	EXCEPTION(0x800)
	EXCEPTION(0x900)
	EXCEPTION(0x980)
	EXCEPTION(0xa00)
	EXCEPTION(0xb00)
	EXCEPTION(0xc00)
	EXCEPTION(0xd00)

//  ISR data

#define REDZONE_SIZE    (512)
#define REG_SAVE_SIZE	((32 + 5)*8)
#define STACK_FRAME_C_MINIMAL   64

#define SAVE_NIA	(32*8)
#define SAVE_LR		(33*8)
#define SAVE_CTR	(34*8)
#define SAVE_CR		(35*8)
#define SAVE_SRR1	(36*8)

__isr:
/*
 * Assume where we are coming from has a stack and can save there.
 * We save the full register set. Since we are calling out to C, we
 * could just save the ABI volatile registers
 */
	stdu	%r1,-(REG_SAVE_SIZE+REDZONE_SIZE)(%r1)
	std	%r0,   1*8(%r1)
//	std	%r1,   1*8(%r1)
	std	%r2,   2*8(%r1)
	std	%r3,   3*8(%r1)
	std	%r4,   4*8(%r1)
	std	%r5,   5*8(%r1)
	std	%r6,   6*8(%r1)
	std	%r7,   7*8(%r1)
	std	%r8,   8*8(%r1)
	std	%r9,   9*8(%r1)
	std	%r10, 10*8(%r1)
	std	%r11, 11*8(%r1)
	std	%r12, 12*8(%r1)
	std	%r13, 13*8(%r1)
	std	%r14, 14*8(%r1)
	std	%r15, 15*8(%r1)
	std	%r16, 16*8(%r1)
	std	%r17, 17*8(%r1)
	std	%r18, 18*8(%r1)
	std	%r19, 19*8(%r1)
	std	%r20, 20*8(%r1)
	std	%r21, 21*8(%r1)
	std	%r22, 22*8(%r1)
	std	%r23, 23*8(%r1)
	std	%r24, 24*8(%r1)
	std	%r25, 25*8(%r1)
	std	%r26, 26*8(%r1)
	std	%r27, 27*8(%r1)
	std	%r28, 28*8(%r1)
	std	%r29, 29*8(%r1)
	std	%r30, 30*8(%r1)
	std	%r31, 31*8(%r1)
	mfsrr0	%r0
	std	%r0,  SAVE_NIA*8(%r1)
	mflr	%r0
	std	%r0,  SAVE_LR*8(%r1)
	mfctr	%r0
	std	%r0,  SAVE_CTR*8(%r1)
	mfcr	%r0
	std	%r0,  SAVE_CR*8(%r1)
	mfsrr1	%r0
	std	%r0,  SAVE_SRR1*8(%r1)

	stdu	%r1,-STACK_FRAME_C_MINIMAL(%r1)
	LOAD_IMM64(%r3, isr)
	mtctr	%r3,
	bctrl
	nop
	ld	%r1, 0(%r1)

	ld	%r0,   1*8(%r1)
//	ld	%r1,   1*8(%r1) // do this at rfid
	ld	%r2,   2*8(%r1)
//	ld	%r3,   3*8(%r1) // do this at rfid
	ld	%r4,   4*8(%r1)
	ld	%r5,   5*8(%r1)
	ld	%r6,   6*8(%r1)
	ld	%r7,   7*8(%r1)
	ld	%r8,   8*8(%r1)
	ld	%r9,   9*8(%r1)
	ld	%r10, 10*8(%r1)
	ld	%r11, 11*8(%r1)
	ld	%r12, 12*8(%r1)
	ld	%r13, 13*8(%r1)
	ld	%r14, 14*8(%r1)
	ld	%r15, 15*8(%r1)
	ld	%r16, 16*8(%r1)
	ld	%r17, 17*8(%r1)
	ld	%r18, 18*8(%r1)
	ld	%r19, 19*8(%r1)
	ld	%r20, 20*8(%r1)
	ld	%r21, 21*8(%r1)
	ld	%r22, 22*8(%r1)
	ld	%r23, 23*8(%r1)
	ld	%r24, 24*8(%r1)
	ld	%r25, 25*8(%r1)
	ld	%r26, 26*8(%r1)
	ld	%r27, 27*8(%r1)
	ld	%r28, 28*8(%r1)
	ld	%r29, 29*8(%r1)
	ld	%r30, 30*8(%r1)
	ld	%r31, 31*8(%r1)

	ld	%r3, SAVE_LR*8(%r1)
	mtlr	%r3
	ld	%r3, SAVE_CTR*8(%r1)
	mtctr	%r3
	ld	%r3, SAVE_CR*8(%r1)
	mtcr	%r3
	ld	%r3, SAVE_SRR1*8(%r1)
	mtsrr1	%r3
	ld	%r3, SAVE_NIA*8(%r1)
	mtsrr0	%r3

	/* restore %r3 */
	ld	%r3, 3*8(%r1)

	/* do final fixup r1 */
	ld	%r1, 0*8(%r1)

	rfid
