#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C"
{
#endif

int usb_getchar(void);
bool usb_havechar(void);
int usb_putchar(int c);
int usb_puts(const char *str);
void usb_console_init(void);

#ifdef __cplusplus
}
#endif
