#define STACK_TOP 0x4000

#define LOAD_IMM64(r, e)                        \
        lis     r,(e)@highest;                  \
        ori     r,r,(e)@higher;                 \
        rldicr   r,r,32,31;                     \
        oris     r,r,(e)@h;                     \
        ori     r,r,(e)@l;

        .section ".head","ax"

        . = 0
.global _start
_start:
        b       boot_entry

.global boot_entry
boot_entry:
        LOAD_IMM64(%r1, STACK_TOP - 0x100)
        LOAD_IMM64(%r12, main)
        mtctr   %r12
        bctrl
        attn
        b .
