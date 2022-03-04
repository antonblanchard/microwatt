ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
	CROSS_COMPILE ?= powerpc64le-linux-gnu-
endif
endif

CC = $(CROSS_COMPILE)gcc
CXX = $(CROSS_COMPILE)g++
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

COMMON_FLAGS = -Os -g -Wall -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections -I../include
COMMON_FLAGS += -Werror -Wextra
CXXFLAGS = $(COMMON_FLAGS) -std=c++14 -fno-exceptions
CFLAGS = $(COMMON_FLAGS) -std=c99
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds

all: usb_3d_game.hex

console.o: ../lib/console.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

liteuart_console.o: ../lib/liteuart_console.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@

usb_3d_game.elf: usb_3d_game.o head.o console.o liteuart_console.o
	$(LD) $(LDFLAGS) -o $@ $^

usb_3d_game.bin: usb_3d_game.elf
	$(OBJCOPY) -O binary $^ $@

usb_3d_game.hex: usb_3d_game.bin
	../scripts/bin2hex.py $^ > $@

usb_3d_game_emu: usb_3d_game.cpp
	c++ -g -Wall -std=c++14 -Werror -Wextra -o usb_3d_game_emu usb_3d_game.cpp -DEMULATE_TARGET

clean:
	@rm -f *.o usb_3d_game.elf usb_3d_game.bin usb_3d_game.hex usb_3d_game_emu
distclean: clean
	rm -f *~

