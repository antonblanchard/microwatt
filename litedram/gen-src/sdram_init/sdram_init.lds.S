#include "microwatt_soc.h"

SECTIONS
{
	. = DRAM_INIT_BASE;
	start = .;
	.head : {
		KEEP(*(.head))
	}
	. = DRAM_INIT_BASE | 0x1000;

	.text : { *(.text*) *(.sfpr) *(.rodata*) }
	.data : { *(.data*) }
	.bss : { *(.bss*) }
}
