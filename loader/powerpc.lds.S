#include <microwatt_soc.h>

#define BASE_ADDR	BRAM_BASE

SECTIONS
{
	. = BASE_ADDR;
	.head : {
		KEEP(*(.head))
	}

	.text : { *(.text*) *(.sfpr) *(.rodata*) }
	.data : { *(.data*) }
	.bss : { *(.bss*) }

	/DISCARD/ : {
                *(.note.*)
                *(.comment)
        }
}
