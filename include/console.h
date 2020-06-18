#include <stddef.h>

void console_init(void);
void console_set_irq_en(bool rx_irq, bool tx_irq);
int getchar(void);
int putchar(int c);
int puts(const char *str);

#ifndef __USE_LIBC
size_t strlen(const char *s);
#endif
