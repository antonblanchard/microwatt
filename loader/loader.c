#include <stdint.h>
#include <errno.h>
#include <string.h>
#include <stdbool.h>
#include "stdio.h"

#include "io.h"
#include "microwatt_soc.h"
#include "console.h"
#include "elf64.h"

#define DTB_ADDR	0x01000000UL
#define DTBIMAGE_ADDR 	0x00500000UL

#ifdef DEBUG
#define debug(...) printf(__VA_ARGS__)
#else
#define debug(...) do {} while(0)
#endif

int _printf(const char *fmt, ...)
{
        int count;
        char buffer[128];
        va_list ap;

        va_start(ap, fmt);
        count = vsnprintf(buffer, sizeof(buffer), fmt, ap);
        va_end(ap);
        puts(buffer);
        return count;
}

static inline void flush_cpu_icache(void)
{
	__asm__ volatile ("icbi 0,0; isync" : : : "memory");
}

static void print_hex(unsigned long val)
{
	int i, nibbles = sizeof(val)*2;
	char buf[sizeof(val)*2+1];

	for (i = nibbles-1;  i >= 0;  i--) {
		buf[i] = (val & 0xf) + '0';
		if (buf[i] > '9')
			buf[i] += ('a'-'0'-10);
		val >>= 4;
	}
	buf[nibbles] = '\0';
	puts(buf);
}

static void fl_read(void *dst, uint32_t offset, uint32_t size)
{
	memcpy(dst, (void *)(unsigned long)(SPI_FLASH_BASE + offset), size);
}

static unsigned long boot_flash(unsigned int offset)
{
	Elf64_Ehdr ehdr;
	Elf64_Phdr ph;
	unsigned int i, poff, size, off;
	void *addr;

	fl_read(&ehdr, offset, sizeof(ehdr));
	if (!IS_ELF(ehdr) || ehdr.e_ident[EI_CLASS] != ELFCLASS64) {
		puts("Doesn't look like an elf64\n");
		return -1UL;
	}
	if (ehdr.e_ident[EI_DATA] != ELFDATA2LSB ||
	    ehdr.e_machine != EM_PPC64) {
		puts("Not a ppc64le binary\n");
		return -1UL;
	}

	poff = offset + ehdr.e_phoff;
	for (i = 0; i < ehdr.e_phnum; i++) {
		fl_read(&ph, poff, sizeof(ph));
		if (ph.p_type != PT_LOAD)
			continue;

		/* XXX Add bound checking ! */
		size = ph.p_filesz;
		addr = (void *)ph.p_vaddr;
		off  = offset + ph.p_offset;
		debug("Copy segment %d (0x%x bytes) to %p\n", i, size, addr);
		fl_read(addr, off, size);
		poff += ehdr.e_phentsize;
	}

	if (poff == offset + ehdr.e_phoff) {
		puts("Did not find any loadable sections\n");
		return -1UL;
	}

	debug("Found entry point: %x\n", ehdr.e_entry);

	flush_cpu_icache();
	return ehdr.e_entry;
}

int main(void)
{
	unsigned long fl_off = 0;
	potato_uart_init();
	unsigned long payload, dtb;
	void __attribute__((noreturn)) (*enter_kernel)(unsigned long fdt,
			     unsigned long entry,
			     unsigned long of);


	puts("\nMicrowatt Loader ("__DATE__" "__TIME__"\n\n");

	writeq(SYS_REG_CTRL_DRAM_AT_0, SYSCON_BASE + SYS_REG_CTRL);
	flush_cpu_icache();

	puts("Load binaries into SDRAM and select option to start:\n\n");
	puts("vmlinux.bin and dtb:\n");
	puts(" mw_debug -b jtag stop load vmlinux.bin load microwatt.dtb 0x1000000 start\n");
	puts(" press 'l' to start'\n\n");

	puts("dtbImage.microwatt:\n");
	puts(" mw_debug -b jtag stop load dtbImage.microwatt 0x500000 start\n");
	puts(" press 'w' to start'\n\n");

	if (readq(SYSCON_BASE + SYS_REG_INFO) & SYS_REG_INFO_HAS_SPI_FLASH) {
		unsigned long val = readq(SYSCON_BASE + SYS_REG_SPI_INFO);
		fl_off = val & SYS_REG_SPI_INFO_FLASH_OFF_MASK;

		puts("Flash:\n");
		puts(" To boot a binary from flash, write it to "); print_hex(fl_off); puts("\n");
		puts(" press 'f' to start'\n\n");
	}

	while (1) {
		switch (getchar()) {
		case 'l':
			payload = 0;
			dtb = DTB_ADDR;
			goto load;
		case 'w':
			payload = DTBIMAGE_ADDR;
			goto load;
		case 'f':
			payload = boot_flash(fl_off);
			if (payload == -1UL)
				continue;
			goto load;
		default:
			continue;
		}
	}

load:
	puts("Entering payload at "); print_hex(payload); puts("...\n");

	enter_kernel = (void *)payload;

	enter_kernel(dtb, 0, 0);
}
