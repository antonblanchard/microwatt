SECTIONS
{
	. = 0;
	.head : {
		KEEP(*(.head))
 	}
	. = 0x1000;
	.text : { *(.text) }
	. = 0x2a000;
	.data : { *(.data) }
	.rodata : { *(.rodata) }
	.bss : { *(.bss) }
}
