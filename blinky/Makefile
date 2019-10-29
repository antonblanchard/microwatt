ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
        CROSS_COMPILE ?= powerpc64le-linux-
        endif
        endif

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -Os -g -Wall -std=c99 -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections 
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds

all: blinky.hex

blinky.elf: blinky.o head.o
	$(LD) $(LDFLAGS) -o blinky.elf blinky.o head.o

blinky.bin: blinky.elf
	$(OBJCOPY) -O binary blinky.elf blinky.bin

blinky.hex: blinky.bin
	./bin2hex.py blinky.bin > blinky.hex

clean:
	@rm -f *.o blinky.elf blinky.bin blinky.hex
