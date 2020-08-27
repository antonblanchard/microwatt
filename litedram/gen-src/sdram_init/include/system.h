#ifndef __SYSTEM_H
#define __SYSTEM_H

#include <stdint.h>

#include "microwatt_soc.h"
#include "io.h"

#define CSR_ACCESSORS_DEFINED
#define CSR_BASE		DRAM_CTRL_BASE
#define CONFIG_CPU_NOP		"nop"

#ifdef __SIM__
#define MEMTEST_BUS_SIZE	512//16
#define MEMTEST_DATA_SIZE	1024//16
#define MEMTEST_ADDR_SIZE	128//16
#define CONFIG_SIM_DISABLE_DELAYS
#endif

extern void flush_cpu_dcache(void);
extern void flush_cpu_icache(void);
static inline void flush_l2_cache(void) { }

/* Fake timer stuff. LiteX should abstract this */
static inline void timer0_en_write(int e) { }
static inline void timer0_reload_write(int r) { }
static inline void timer0_load_write(int l) { }
static inline void timer0_update_value_write(int v) { }
static inline uint64_t timer0_value_read(void)
{
	uint64_t val;

	__asm__ volatile ("mfdec %0" : "=r" (val));
	return val;
}

static inline void init_progression_bar(int max) { }
static inline void show_progress(int now) { }

static inline void csr_write_simple(unsigned long v, unsigned long a)
{
	return writel(v, a);
}

static inline unsigned long csr_read_simple(unsigned long a)
{
	return readl(a);
}

#endif /* __SYSTEM_H */

