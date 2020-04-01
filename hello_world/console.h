#include <stddef.h>

void potato_uart_init(void);
int getchar(void);
void putchar(unsigned char c);
void putstr(const char *str, unsigned long len);
size_t strlen(const char *s);
