SECTIONS
{
	_start = .;
	. = 0;
	.head : {
		KEEP(*(.head))
 	}
	. = 0x2000;
	.text : { *(.text) }
	. = 0x4000;
	.data : { *(.data) }
	.bss : { *(.bss) }
}
