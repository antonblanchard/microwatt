#include <unistd.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <stdio.h>

#include <generated/git.h>

#include "microwatt_soc.h"
#include "io.h"
#include "sdram.h"
#include "console.h"

int _printf(const char *fmt, ...)
{
	int count;
	char buffer[320];
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

void main(void)
{
	unsigned long long ftr, val;

	/* Init the UART */
	potato_uart_init();

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
	printf("\n");
	if (ftr & SYS_REG_INFO_HAS_BRAM) {
		val = readq(SYSCON_BASE + SYS_REG_BRAMINFO) & SYS_REG_BRAMINFO_SIZE_MASK;
		printf("          BRAM: %lld KB\n", val / 1024);
	}
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		val = readq(SYSCON_BASE + SYS_REG_DRAMINFO) & SYS_REG_DRAMINFO_SIZE_MASK;
		printf("          DRAM: %lld MB\n", val / (1024 * 1024));
		val = readq(SYSCON_BASE + SYS_REG_DRAMINITINFO);
		printf("     DRAM INIT: %lld KB\n", val / 1024);
	}
	val = readq(SYSCON_BASE + SYS_REG_CLKINFO) & SYS_REG_CLKINFO_FREQ_MASK;
	printf("           CLK: %lld MHz\n", val / 1000000);

	printf("\n");
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		printf("LiteDRAM built from Migen %s and LiteX %s\n",
		       MIGEN_GIT_SHA1, LITEX_GIT_SHA1);
		sdrinit();
	}
	if (ftr & SYS_REG_INFO_HAS_BRAM)
		printf("Booting from BRAM...\n");
	else {
		void *s = (void *)(DRAM_INIT_BASE + 0x4000);
		void *d = (void *)DRAM_BASE;
		int  sz = (0x10000 - 0x4000);
		printf("Copying payload to DRAM...\n");
		memcpy(d, s, sz);
		printf("Booting from DRAM...\n");
		flush_cpu_icache();
	}
}
