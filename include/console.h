#include <stddef.h>

void potato_uart_init(void);
void potato_uart_irq_en(void);
void potato_uart_irq_dis(void);
int getchar(void);
int putchar(int c);
void putstr(const char *str, unsigned long len);
int puts(const char *str);
size_t strlen(const char *s);
