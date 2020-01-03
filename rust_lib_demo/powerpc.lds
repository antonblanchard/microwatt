SECTIONS
{
	_start = .;
	. = 0;
	.head : {
		KEEP(*(.head))
 	}
	. = 0x1000;
	.text : { *(.text) }
	. = 0x1f000;
	.data : { *(.data) }
	. = ALIGN(4);
        _bss = .;         /* define a global symbol at bss start; used by startup code */
	.bss : { *(.bss) }
	. = ALIGN(4);
        _ebss = .;         /* define a global symbol at bss end; used by startup code */
}
