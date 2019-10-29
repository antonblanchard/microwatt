#include <stdint.h>
#include <stdbool.h>

#define GPIO0_BASE 0xc1000000ull

#define GPIO_PORT_INCREMENT	0x100
#define GPIO_IN				0x08
#define GPIO_OUT			0x10
#define GPIO_SET			0x18
#define GPIO_CLEAR			0x20
#define GPIO_TYPE_0			0x28
#define GPIO_TYPE_1			0x30
#define GPIO_TYPE_2			0x38
#define GPIO_TYPE_3			0x40

enum gpio_type {
	GPIO_TYPE_INPUT = 0x00,
	GPIO_TYPE_INT_LEVEL_LOW = 0x02,
	GPIO_TYPE_INT_LEVEL_HIGH = 0x03,
	GPIO_TYPE_INT_EDGE_FALL = 0x04,
	GPIO_TYPE_INT_EDGE_RISE = 0x05,
	GPIO_TYPE_OUTPUT = 0x07,
};

/**
 * Set the type of GPIO
 * @param port the GPIO port
 * @param pin the pin within the port
 * @param type the type
 */
static void gpio_set_type(uint8_t port, uint8_t pin, enum gpio_type type)
{
	uint64_t val;
	uint64_t addr = GPIO0_BASE + port * GPIO_PORT_INCREMENT;

	/* Advance to the type register for the pin, pin is left as the pin
	 * pin offset within the register
	 */
	if (pin < 16) {
		addr += GPIO_TYPE_0;
	} else if (pin < 32) {
		addr += GPIO_TYPE_1;
		pin -= 16;
	} else if (pin < 48) {
		addr += GPIO_TYPE_2;
		pin -= 32;
	} else {
		addr += GPIO_TYPE_3;
		pin -= 48;
	}

	val = *(volatile uint64_t *)addr; // Fetch the current set of types
	val &= ~(0x7 << (pin * 4)); // Mask out the old value
	val |= type << (pin * 4); // add in the new type
	*(volatile uint64_t *)addr = val; // write it back
}

/**
 * Toggle a GPIO
 * @param port the GPIO port
 * @param pin the pin within the port
 * @param val the value to output
 */
static void gpio_toggle(uint8_t port, uint8_t pin)
{
	/* Writing to GPIO_IN toggles the pin. This allows us to save a
	 * read/modify/write operation to output GPIO.
	 */
	uint64_t addr = GPIO0_BASE + port * GPIO_PORT_INCREMENT + GPIO_IN;

	*(volatile uint64_t *)addr = 1ul << pin;
}

/**
 * Burn some CPU cycles
 */
static void busyloop(void)
{
	// volatile to force a memory access on each iteration
	uint64_t volatile count = 50000000;
	while (count--) {}
}


int main(void)
{
	gpio_set_type(0, 0, GPIO_TYPE_OUTPUT);

	while (1) {
		gpio_toggle(0, 0);
		busyloop();
	}
}
