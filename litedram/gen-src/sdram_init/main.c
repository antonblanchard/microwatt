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
	int i;

	/* Init the UART */
	potato_uart_init();

	/*
	 * Let things settle ... not sure why but the UART is
	 * not happy otherwise. The PLL might need to settle ?
	 */
	for (i = 0; i < 10000; i++)
		readb(UART_BASE + POTATO_CONSOLE_STATUS);
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
	printf("\n");
	val = readq(SYSCON_BASE + SYS_REG_BRAMINFO);
	printf("          BRAM: %lld KB\n", val / 1024);
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		val = readq(SYSCON_BASE + SYS_REG_DRAMINFO);
		printf("          DRAM: %lld MB\n", val / (1024 * 1024));
	}
	val = readq(SYSCON_BASE + SYS_REG_CLKINFO);
	printf("           CLK: %lld MHz\n", val / 1000000);

	printf("\n");
	if (ftr & SYS_REG_INFO_HAS_DRAM) {
		printf("LiteDRAM built from Migen %s and LiteX %s\n",
		       MIGEN_GIT_SHA1, LITEX_GIT_SHA1);
		sdrinit();
	}
	printf("Booting from BRAM...\n");
}
