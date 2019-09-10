SECTIONS
{
	. = 0xffff0000;
	start = .;
	.head : {
		KEEP(*(.head))
 	}
	. = 0xffff1000;
	.text : { *(.text*) *(.sfpr) *(.rodata*) }
	.data : { *(.data*) }
	.bss : { *(.bss*) }
}
