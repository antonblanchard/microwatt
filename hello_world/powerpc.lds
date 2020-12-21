SECTIONS
{
	_start = .;
	. = 0;
	.head : {
		KEEP(*(.head))
 	}
	. = 0x400;
	.text : { *(.text) }
	. = 0xA00;
	.data : { *(.data) }
	.bss : { *(.bss) }
}
