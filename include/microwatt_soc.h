#ifndef __MICROWATT_SOC_H
#define __MICROWATT_SOC_H

/*
 * Definitions for the syscon registers
 */
#define SYSCON_BASE	0xc0000000

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

/* Definition for the "Potato" UART */
#define UART_BASE	0xc0002000

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
