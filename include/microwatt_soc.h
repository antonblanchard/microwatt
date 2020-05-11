#ifndef __MICROWATT_SOC_H
#define __MICROWATT_SOC_H

/*
 * Microwatt SoC memory map
 */

#define MEMORY_BASE     0x00000000  /* "Main" memory alias, either BRAM or DRAM */
#define DRAM_BASE       0x40000000  /* DRAM if present */
#define BRAM_BASE       0x80000000  /* Internal BRAM */

#define SYSCON_BASE	0xc0000000  /* System control regs */
#define UART_BASE	0xc0002000  /* UART */
#define XICS_BASE   	0xc0004000  /* Interrupt controller */
#define DRAM_CTRL_BASE	0xc0100000  /* LiteDRAM control registers */
#define DRAM_INIT_BASE  0xf0000000  /* Internal DRAM init firmware */

/*
 * Register definitions for the syscon registers
 */

#define SYS_REG_SIGNATURE		0x00
#define SYS_REG_INFO			0x08
#define   SYS_REG_INFO_HAS_UART 		(1ull << 0)
#define   SYS_REG_INFO_HAS_DRAM 		(1ull << 1)
#define SYS_REG_BRAMINFO		0x10
#define SYS_REG_DRAMINFO		0x18
#define SYS_REG_CLKINFO			0x20
#define SYS_REG_CTRL			0x28
#define   SYS_REG_CTRL_DRAM_AT_0		(1ull << 0)
#define   SYS_REG_CTRL_CORE_RESET		(1ull << 1)
#define   SYS_REG_CTRL_SOC_RESET		(1ull << 2)

/*
 * Register definitions for the potato UART
 */
#define POTATO_CONSOLE_TX		0x00
#define POTATO_CONSOLE_RX		0x08
#define POTATO_CONSOLE_STATUS		0x10
#define   POTATO_CONSOLE_STATUS_RX_EMPTY		0x01
#define   POTATO_CONSOLE_STATUS_TX_EMPTY		0x02
#define   POTATO_CONSOLE_STATUS_RX_FULL			0x04
#define   POTATO_CONSOLE_STATUS_TX_FULL			0x08
#define POTATO_CONSOLE_CLOCK_DIV	0x18
#define POTATO_CONSOLE_IRQ_EN		0x20


#endif /* __MICROWATT_SOC_H */
