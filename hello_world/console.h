#include <stddef.h>

void potato_uart_init(void);
void potato_uart_irq_en(void);
void potato_uart_irq_dis(void);
int getchar(void);
void putchar(unsigned char c);
void putstr(const char *str, unsigned long len);
size_t strlen(const char *s);
