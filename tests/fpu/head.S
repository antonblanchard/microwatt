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
	LOAD_IMM64(%r10, die)
	mtsprg0	%r10
	LOAD_IMM64(%r12, main)
	mtctr	%r12
	bctrl
die:	attn // terminate on exit
	b .

.global trapit
trapit:
	mflr	%r0
	std	%r0,16(%r1)
	stdu	%r1,-256(%r1)
	mtsprg1	%r1
	r = 14
	.rept	18
	std	r,r*8(%r1)
	r = r + 1
	.endr
	mfcr	%r0
	stw	%r0,13*8(%r1)
	LOAD_IMM64(%r10, ret)
	mtsprg0	%r10
	mr	%r12,%r4
	mtctr	%r4
	bctrl
ret:
	mfsprg1	%r1
	LOAD_IMM64(%r10, die)
	mtsprg0	%r10
	r = 14
	.rept	18
	ld	r,r*8(%r1)
	r = r + 1
	.endr
	lwz	%r0,13*8(%r1)
	mtcr	%r0
	ld	%r0,256+16(%r1)
	addi	%r1,%r1,256
	mtlr	%r0
	blr

	.global do_rfid
do_rfid:
	mtsrr1	%r3
	LOAD_IMM64(%r4, do_blr)
	mtsrr0	%r4
	rfid
	blr

	.global do_blr
do_blr:
	blr

#define EXCEPTION(nr)		\
	.= nr			;\
	mfsprg0	%r0		;\
	mtctr	%r0		;\
	li	%r3,nr		;\
	bctr

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
