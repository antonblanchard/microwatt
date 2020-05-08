static inline void flush_cpu_dcache(void) { }
static inline void flush_l2_cache(void) { }

#define CONFIG_CPU_NOP "nop"
#define CONFIG_CLOCK_FREQUENCY 100000000

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
