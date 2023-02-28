#pragma once

int usb_getchar(void);
bool usb_havechar(void);
int usb_putchar(int c);
int usb_puts(const char *str);
void usb_console_init(void);
