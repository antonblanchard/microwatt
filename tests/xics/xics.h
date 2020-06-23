#include <stdint.h>
#include "microwatt_soc.h"
#include "io.h"

#define XICS_XIRR_POLL 0x0
#define XICS_XIRR      0x4
#define XICS_RESV      0x8
#define XICS_MFRR      0xC

#define bswap32(x) (uint32_t)__builtin_bswap32((uint32_t)(x))

uint8_t icp_read8(int offset)
{
	return readb(XICS_ICP_BASE + offset);
}

void icp_write8(int offset, uint8_t val)
{
	writeb(val, XICS_ICP_BASE + offset);
}

uint32_t icp_read32(int offset)
{
	return bswap32(readl(XICS_ICP_BASE + offset));
}

static inline void icp_write32(int offset, uint32_t val)
{
	writel(bswap32(val), XICS_ICP_BASE + offset);
}

uint32_t ics_read_xive(int irq)
{
	return bswap32(readl(XICS_ICS_BASE + 0x800 + (irq << 2)));
}

void ics_write_xive(uint32_t val, int irq)
{
	writel(bswap32(val), XICS_ICS_BASE + 0x800 + (irq << 2));
}

