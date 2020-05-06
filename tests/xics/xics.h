#include <stdint.h>

#define XICS_BASE 0xc0004000

static uint64_t xics_base = XICS_BASE;

#define XICS_XIRR_POLL 0x0
#define XICS_XIRR      0x4
#define XICS_RESV      0x8
#define XICS_MFRR      0xC

uint8_t xics_read8(int offset)
{
	uint32_t val;

	__asm__ volatile("lbzcix %0,%1,%2" : "=r" (val) : "b" (xics_base), "r" (offset));
	return val;
}

void xics_write8(int offset, uint8_t val)
{
	__asm__ volatile("stbcix %0,%1,%2" : : "r" (val), "b" (xics_base), "r" (offset));
}

uint32_t xics_read32(int offset)
{
	uint32_t val;

	__asm__ volatile("lwzcix %0,%1,%2" : "=r" (val) : "b" (xics_base), "r" (offset));
	return val;
}

void xics_write32(int offset, uint32_t val)
{
	__asm__ volatile("stwcix %0,%1,%2" : : "r" (val), "b" (xics_base), "r" (offset));
}
