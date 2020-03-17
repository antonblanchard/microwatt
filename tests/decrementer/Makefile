ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
        CROSS_COMPILE = powerpc64le-linux-
        endif
        endif

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -Os -g -Wall -std=c99 -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections -I ../../hello_world
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds

all: decrementer.hex

decrementer.elf: decrementer.o head.o ../../hello_world/console.o
	$(LD) $(LDFLAGS) -o decrementer.elf decrementer.o head.o ../../hello_world/console.o

decrementer.bin: decrementer.elf
	$(OBJCOPY) -O binary decrementer.elf decrementer.bin

decrementer.hex: decrementer.bin
	../../scripts/bin2hex.py decrementer.bin > decrementer.hex

clean:
	@rm -f *.o decrementer.elf decrementer.bin decrementer.hex
