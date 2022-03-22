ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
	CROSS_COMPILE ?= powerpc64le-linux-gnu-
endif
endif

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -Os -g -Wall -std=c99 -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections -I../include
CFLAGS += -Werror -Wextra
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds

all: usb_hello.hex

console.o: ../lib/console.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

liteuart_console.o: ../lib/liteuart_console.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

usb_hello.elf: usb_hello.o head.o console.o liteuart_console.o
	$(LD) $(LDFLAGS) -o $@ $^

usb_hello.bin: usb_hello.elf
	$(OBJCOPY) -O binary $^ $@

usb_hello.hex: usb_hello.bin
	../scripts/bin2hex.py $^ > $@

clean:
	@rm -f *.o usb_hello.elf usb_hello.bin usb_hello.hex
distclean: clean
	rm -f *~

