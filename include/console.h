#include <stddef.h>

void potato_uart_init(void);
void potato_uart_irq_en(void);
void potato_uart_irq_dis(void);
int getchar(void);
int putchar(int c);
int puts(const char *str);

#ifndef __USE_LIBC
size_t strlen(const char *s);
#endif
