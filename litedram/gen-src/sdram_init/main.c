#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>

#include <generated/git.h>

#include "console.h"
#include "microwatt_soc.h"
#include "io.h"
#include "sdram.h"
#include "elf64.h"

#define FLASH_LOADER_USE_MAP

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

void flush_cpu_dcache(void)
{
}

void flush_cpu_icache(void)
{
	__asm__ volatile ("icbi 0,0; isync" : : : "memory");
}

#define SPI_CMD_RDID		0x9f
#define SPI_CMD_READ		0x03
#define SPI_CMD_DUAL_FREAD	0x3b
#define SPI_CMD_QUAD_FREAD	0x6b
#define SPI_CMD_RDCR            0x35
#define SPI_CMD_WREN		0x06
#define SPI_CMD_PP		0x02
#define SPI_CMD_RDSR		0x05
#define SPI_CMD_WWR		0x01

static void fl_cs_on(void)
{
	writeb(SPI_REG_CTRL_MANUAL_CS, SPI_FCTRL_BASE + SPI_REG_CTRL);
}

static void fl_cs_off(void)
{
	writeb(0, SPI_FCTRL_BASE + SPI_REG_CTRL);
	__asm__ volatile("nop");
	__asm__ volatile("nop");
	__asm__ volatile("nop");
	__asm__ volatile("nop");
	__asm__ volatile("nop");
}

static void wait_wip(void)
{
	for (;;) {
		uint8_t sr;

		fl_cs_on();
		writeb(SPI_CMD_RDSR, SPI_FCTRL_BASE + SPI_REG_DATA);
		sr = readb(SPI_FCTRL_BASE + SPI_REG_DATA);
		fl_cs_off();
		if ((sr & 1) == 0)
			break;
	}
}

static void send_wren(void)
{
	fl_cs_on();
	writeb(SPI_CMD_WREN, SPI_FCTRL_BASE + SPI_REG_DATA);
	fl_cs_off();
}

static void check_spansion_quad_mode(void)
{
	uint8_t cf1;

	writeb(SPI_CMD_RDCR, SPI_FCTRL_BASE + SPI_REG_DATA);
	fl_cs_on();
	writeb(SPI_CMD_RDCR, SPI_FCTRL_BASE + SPI_REG_DATA);
	cf1 = readb(SPI_FCTRL_BASE + SPI_REG_DATA);
	fl_cs_off();
	printf(" Cypress/Spansion (CF1=%02x)", cf1);
	if (cf1 & 0x02)
		return;
	printf("  enabling QUAD");
	send_wren();
	fl_cs_on();
	writeb(SPI_CMD_WWR, SPI_FCTRL_BASE + SPI_REG_DATA); 
	writeb(0x00, SPI_FCTRL_BASE + SPI_REG_DATA); 
	writeb(cf1 | 0x02, SPI_FCTRL_BASE + SPI_REG_DATA); 
	writeb(0, SPI_FCTRL_BASE + SPI_REG_CTRL);
	fl_cs_off();
	wait_wip();
}

static bool check_flash(void)
{
	bool quad = false;
	uint8_t id[3];

	fl_cs_on();
	writeb(SPI_CMD_RDID, SPI_FCTRL_BASE + SPI_REG_DATA);
	id[0] = readb(SPI_FCTRL_BASE + SPI_REG_DATA);
	id[1] = readb(SPI_FCTRL_BASE + SPI_REG_DATA);
	id[2] = readb(SPI_FCTRL_BASE + SPI_REG_DATA);
	fl_cs_off();
	printf("  SPI FLASH ID: %02x%02x%02x", id[0], id[1], id[2]);

	if ((id[0] | id[1] | id[2]) == 0 ||
	    (id[0] & id[1] & id[2]) == 0xff)
		return false;

	/* Supported flash types for quad mode */
	if (id[0] == 0x01 &&
	    (id[1] == 0x02 || id[1] == 0x20) &&
	    (id[2] == 0x18 || id[2] == 0x19)) {
		check_spansion_quad_mode();
		quad = true;
	}
	if (id[0] == 0x20 && id[1] == 0xba && id[2] == 0x18) {
		printf(" Micron");
		quad = true;
	}
	if (quad) {
		uint32_t cfg;
		printf(" [quad IO mode]");

		/* Preserve the default clock div for the board */
		cfg = readl(SPI_FCTRL_BASE + SPI_REG_AUTO_CFG);
		cfg &= SPI_REG_AUTO_CFG_CKDIV_MASK;

		/* Enable quad mode, 8 dummy clocks, 32 cycles CS timeout */
		cfg |= SPI_CMD_QUAD_FREAD |
			(0x07 << SPI_REG_AUTO_CFG_DUMMIES_SHIFT) |
			SPI_REG_AUT_CFG_MODE_QUAD |
			(0x20 << SPI_REG_AUTO_CFG_CSTOUT_SHIFT);
		writel(cfg, SPI_FCTRL_BASE + SPI_REG_AUTO_CFG);
	}
	printf("\n");

	return true;
}

static bool fl_read(void *dst, uint32_t offset, uint32_t size)
{
	uint8_t *d = dst;

#ifdef FLASH_LOADER_USE_MAP
	memcpy(d, (void *)(unsigned long)(SPI_FLASH_BASE + offset), size);
#else
	if (size < 1)
		return false;
	fl_cs_on();
	writeb(SPI_CMD_QUAD_FREAD, SPI_FCTRL_BASE + SPI_REG_DATA);
	writeb(offset >> 16, SPI_FCTRL_BASE + SPI_REG_DATA);
	writeb(offset >>  8, SPI_FCTRL_BASE + SPI_REG_DATA);
	writeb(offset, SPI_FCTRL_BASE + SPI_REG_DATA);
	writeb(0x00, SPI_FCTRL_BASE + SPI_REG_DATA);
	while(size--)
		*(d++) = readb(SPI_FCTRL_BASE + SPI_REG_DATA_QUAD);
	fl_cs_off();
#endif

	return true;
}

static unsigned long boot_flash(unsigned int offset)
{
	Elf64_Ehdr ehdr;
	Elf64_Phdr ph;
	unsigned int i, poff, size, off;
	void *addr;

	printf("Trying flash...\n");
	if (!fl_read(&ehdr, offset, sizeof(ehdr)))
		return -1ul;
	if (!IS_ELF(ehdr) || ehdr.e_ident[EI_CLASS] != ELFCLASS64) {
		printf("Doesn't look like an elf64\n");
		goto dump;
	}
	if (ehdr.e_ident[EI_DATA] != ELFDATA2LSB ||
	    ehdr.e_machine != EM_PPC64) {
		printf("Not a ppc64le binary\n");
		goto dump;
	}

	poff = offset + ehdr.e_phoff;
	for (i = 0; i < ehdr.e_phnum; i++) {
		if (!fl_read(&ph, poff, sizeof(ph)))
			goto dump;
		if (ph.p_type != PT_LOAD)
			continue;

		/* XXX Add bound checking ! */
		size = ph.p_filesz;
		addr = (void *)ph.p_vaddr;
		off  = offset + ph.p_offset;
		printf("Copy segment %d (0x%x bytes) to %p\n", i, size, addr);
		fl_read(addr, off, size);
		poff += ehdr.e_phentsize;
	}

	printf("Booting from DRAM at %x\n", (unsigned int)ehdr.e_entry);
	flush_cpu_icache();
	return ehdr.e_entry;
dump:	
	printf("HDR: %02x %02x %02x %02x %02x %02x %02x %02x\n",
	       ehdr.e_ident[0], ehdr.e_ident[1], ehdr.e_ident[2], ehdr.e_ident[3],
	       ehdr.e_ident[4], ehdr.e_ident[5], ehdr.e_ident[6], ehdr.e_ident[7]);
	return -1ul;
}

static void boot_sdram(void)
{
	void *s = (void *)(DRAM_INIT_BASE + 0x6000);
	void *d = (void *)DRAM_BASE;
	int  sz = (0x10000 - 0x6000);
	printf("Copying payload to DRAM...\n");
	memcpy(d, s, sz);
	printf("Booting from DRAM...\n");
	flush_cpu_icache();
}

uint64_t main(void)
{
	unsigned long ftr, val;
	unsigned int fl_off = 0;
	bool try_flash = false;

	/* Init the UART */
	console_init();

	printf("\n\nWelcome to Microwatt !\n\n");

	/* TODO: Add core version information somewhere in syscon, possibly
	 *       extracted from git
	 */
	printf(" Soc signature: %016llx\n",
	       (unsigned long long)readq(SYSCON_BASE + SYS_REG_SIGNATURE));
	printf("  Soc features: ");
	ftr = readq(SYSCON_BASE + SYS_REG_INFO);
	if (ftr & SYS_REG_INFO_HAS_UART)
		printf("UART ");
	if (ftr & SYS_REG_INFO_HAS_DRAM)
		printf("DRAM ");
	if (ftr & SYS_REG_INFO_HAS_BRAM)
		printf("BRAM ");
	if (ftr & SYS_REG_INFO_HAS_SPI_FLASH)
		printf("SPIFLASH ");
	if (ftr & SYS_REG_INFO_HAS_LITEETH)
		printf("ETHERNET ");
	printf("\n");
	if (ftr & SYS_REG_INFO_HAS_BRAM) {
		val = readq(SYSCON_BASE + SYS_REG_BRAMINFO) & SYS_REG_BRAMINFO_SIZE_MASK;
		printf("          BRAM: %ld KB\n", val / 1024);
	}
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		val = readq(SYSCON_BASE + SYS_REG_DRAMINFO) & SYS_REG_DRAMINFO_SIZE_MASK;
		printf("          DRAM: %ld MB\n", val / (1024 * 1024));
		val = readq(SYSCON_BASE + SYS_REG_DRAMINITINFO);
		printf("     DRAM INIT: %ld KB\n", val / 1024);
	}
	val = readq(SYSCON_BASE + SYS_REG_CLKINFO) & SYS_REG_CLKINFO_FREQ_MASK;
	printf("           CLK: %ld MHz\n", val / 1000000);
	if (ftr & SYS_REG_INFO_HAS_SPI_FLASH) {
		val = readq(SYSCON_BASE + SYS_REG_SPI_INFO);
		try_flash = check_flash();
		fl_off = val & SYS_REG_SPI_INFO_FLASH_OFF_MASK;
		printf(" SPI FLASH OFF: 0x%x bytes\n", fl_off);
		try_flash = true;
	}
	printf("\n");
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		printf("LiteDRAM built from Migen %s and LiteX %s\n",
		       MIGEN_GIT_SHA1, LITEX_GIT_SHA1);
		sdrinit();
	}
	if (ftr & SYS_REG_INFO_HAS_BRAM) {
		printf("Booting from BRAM...\n");
		return 0;
	}
	if (try_flash) {
		val = boot_flash(fl_off);
		if (val != (unsigned long)-1)
			return val;
	}
	boot_sdram();
	return 0;
}
