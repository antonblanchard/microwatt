ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
	CROSS_COMPILE ?= powerpc64le-linux-gnu-
endif
endif

PYTHON3 ?= python3
MW_DEBUG ?= mw_debug
BRAM_ADDRESS ?= 0x80000000

# Use make V=1 for a verbose build.
ifndef V
        Q_CC=     @echo '      [CC] ' $@;
        Q_LINK=   @echo '    [LINK] ' $@;
        Q_OBJCOPY=@echo ' [OBJCOPY] ' $@;
        Q_PYTHON= @echo '  [PYTHON] ' $@;
endif

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

CFLAGS = -Os -g -Wall -std=c99 -msoft-float -mno-string -mno-multiple \
	 -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector \
	 -mstrict-align -ffreestanding -nostdinc -flto \
	 -Ilibc/include/ -I../include -isystem $(shell $(CC) -print-file-name=include) \
	 -D__USE_LIBC
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds -static -nostdlib -Wl,--gc-sections -Wl,--build-id=none

LIBC_SRC := libc/src/isdigit.c libc/src/memcmp.c libc/src/strcat.c \
	libc/src/strncasecmp.c libc/src/strtok.c libc/src/vsnprintf.c \
	libc/src/isprint.c libc/src/memcpy.c libc/src/strchr.c libc/src/strncmp.c \
	libc/src/strtol.c libc/src/isspace.c libc/src/memmove.c libc/src/strcmp.c \
	libc/src/strncpy.c libc/src/strtoul.c libc/src/isxdigit.c libc/src/memset.c \
	libc/src/strcpy.c libc/src/strrchr.c libc/src/tolower.c libc/src/memchr.c \
	libc/src/strcasecmp.c libc/src/strlen.c libc/src/strstr.c libc/src/toupper.c
LIBC_OBJ := $(LIBC_SRC:.c=.o)

COMPILE.c = $(Q_CC)$(CC) $(CFLAGS) $(CPPFLAGS) $(TARGET_ARCH) -c
COMPILE.S = $(Q_CC)$(CC) $(CFLAGS) $(CPPFLAGS) $(TARGET_ARCH) -c

all: loader.hex

load: loader.bin
	$(MW_DEBUG) -b jtag load $^ $(BRAM_ADDRESS)

%.lds : %.lds.S
	$(Q_CC)$(CC) -I../include -P -E $< -o $@

loader.elf: loader.o head.o ../lib/console.o $(LIBC_OBJ) | powerpc.lds
	$(Q_LINK)$(CC) $(LDFLAGS) -o $@ $^
	@size $@

loader.bin: loader.elf
	$(Q_OBJCOPY)$(OBJCOPY) -O binary $^ $@

loader.hex: loader.bin
	$(Q_PYTHON)$(PYTHON3) ../scripts/bin2hex.py $^ > $@

.PHONY:
clean:
	@rm -f *.o $(LIBC_OBJ) ../lib/console.o loader.elf loader.bin loader.hex powerpc.lds
