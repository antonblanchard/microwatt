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
#define XICS_ICP_BASE   0xc0004000  /* Interrupt controller */
#define XICS_ICS_BASE   0xc0005000  /* Interrupt controller */
#define SPI_FCTRL_BASE  0xc0006000  /* SPI flash controller registers */
#define DRAM_CTRL_BASE	0xc8000000  /* LiteDRAM control registers */
#define SPI_FLASH_BASE  0xf0000000  /* SPI Flash memory map */
#define DRAM_INIT_BASE  0xff000000  /* Internal DRAM init firmware */

/*
 * Interrupt numbers
 */
#define IRQ_UART0       0

/*
 * Register definitions for the syscon registers
 */

#define SYS_REG_SIGNATURE		0x00
#define SYS_REG_INFO			0x08
#define   SYS_REG_INFO_HAS_UART 		(1ull << 0)
#define   SYS_REG_INFO_HAS_DRAM 		(1ull << 1)
#define   SYS_REG_INFO_HAS_BRAM 		(1ull << 2)
#define   SYS_REG_INFO_HAS_SPI_FLASH 		(1ull << 3)
#define SYS_REG_BRAMINFO		0x10
#define   SYS_REG_BRAMINFO_SIZE_MASK		0xfffffffffffffull
#define SYS_REG_DRAMINFO		0x18
#define   SYS_REG_DRAMINFO_SIZE_MASK		0xfffffffffffffull
#define SYS_REG_CLKINFO			0x20
#define   SYS_REG_CLKINFO_FREQ_MASK		0xffffffffffull
#define SYS_REG_CTRL			0x28
#define   SYS_REG_CTRL_DRAM_AT_0		(1ull << 0)
#define   SYS_REG_CTRL_CORE_RESET		(1ull << 1)
#define   SYS_REG_CTRL_SOC_RESET		(1ull << 2)
#define SYS_REG_DRAMINITINFO		0x30
#define SYS_REG_SPI_INFO		0x38
#define   SYS_REG_SPI_INFO_FLASH_OFF_MASK	0xffffffff



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

/*
 * Register definitions for the SPI controller
 */
#define SPI_REG_DATA       		0x00 /* Byte access: single wire transfer */
#define SPI_REG_DATA_DUAL       	0x01 /* Byte access: dual wire transfer */
#define SPI_REG_DATA_QUAD       	0x02 /* Byte access: quad wire transfer */
#define SPI_REG_CTRL			0x04 /* Reset and manual mode control */
#define   SPI_REG_CTRL_RESET            	0x01  /* reset all registers */
#define   SPI_REG_CTRL_MANUAL_CS	        0x02  /* assert CS, enable manual mode */
#define   SPI_REG_CTRL_CKDIV_SHIFT		8     /* clock div */
#define   SPI_REG_CTRL_CKDIV_MASK		(0xff << SPI_REG_CTRL_CKDIV_SHIFT)
#define SPI_REG_AUTO_CFG		0x08 /* Automatic map configuration */
#define   SPI_REG_AUTO_CFG_CMD_SHIFT		0     /* Command to use for reads */
#define   SPI_REG_AUTO_CFG_CMD_MASK		(0xff << SPI_REG_AUTO_CFG_CMD_SHIFT)
#define   SPI_REG_AUTO_CFG_DUMMIES_SHIFT        8     /* # dummy cycles */
#define   SPI_REG_AUTO_CFG_DUMMIES_MASK         (0x7  << SPI_REG_AUTO_CFG_DUMMIES_SHIFT)
#define   SPI_REG_AUTO_CFG_MODE_SHIFT           11    /* SPI wire mode */
#define   SPI_REG_AUTO_CFG_MODE_MASK            (0x3  << SPI_REG_AUTO_CFG_MODE_SHIFT)
#define     SPI_REG_AUT_CFG_MODE_SINGLE         (0 << 11)
#define     SPI_REG_AUT_CFG_MODE_DUAL           (2 << 11)
#define     SPI_REG_AUT_CFG_MODE_QUAD           (3 << 11)
#define   SPI_REG_AUTO_CFG_ADDR4                (1u << 13) /* 3 or 4 addr bytes */
#define   SPI_REG_AUTO_CFG_CKDIV_SHIFT          16    /* clock div */
#define   SPI_REG_AUTO_CFG_CKDIV_MASK           (0xff << SPI_REG_AUTO_CFG_CKDIV_SHIFT)
#define   SPI_REG_AUTO_CFG_CSTOUT_SHIFT         24    /* CS timeout */
#define   SPI_REG_AUTO_CFG_CSTOUT_MASK          (0x3f << SPI_REG_AUTO_CFG_CSTOUT_SHIFT)


#endif /* __MICROWATT_SOC_H */
