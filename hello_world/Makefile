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

all: hello_world.hex

hello_world.elf: hello_world.o head.o console.o
	$(LD) $(LDFLAGS) -o hello_world.elf hello_world.o head.o console.o

hello_world.bin: hello_world.elf
	$(OBJCOPY) -O binary hello_world.elf hello_world.bin

hello_world.hex: hello_world.bin
	../scripts/bin2hex.py hello_world.bin > hello_world.hex

clean:
	@rm -f *.o hello_world.elf hello_world.bin hello_world.hex
