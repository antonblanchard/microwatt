#pragma once

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

void console_init(void);
void console_set_irq_en(bool rx_irq, bool tx_irq);
int getchar(void);
bool console_havechar(void);
int putchar(int c);
int puts(const char *str);

#ifndef __USE_LIBC
size_t strlen(const char *s);
#endif

#ifdef __cplusplus
}
#endif
