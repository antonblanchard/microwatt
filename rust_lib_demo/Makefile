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
ASFLAGS = $(CFLAGS)
LDFLAGS = -T powerpc.lds

RUSTLIB = target/powerpc64le-unknown-linux-gnu/release/libmylib.a

all: hello_world.hex

run:
	-ln -sf hello_world.bin main_ram.bin
	../core_tb > /dev/null

$(RUSTLIB): src/lib.rs
	RUSTFLAGS="-C target-feature=-vsx,-altivec,-hard-float" xargo build --release

size:
	size hello_world.elf

dump:
	powerpc64le-linux-gnu-objdump -S hello_world.elf | less

hello_world.elf: hello_world.o console.o head.o $(RUSTLIB)
	$(LD) $(LDFLAGS) -o $@ $^

hello_world.bin: hello_world.elf
	$(OBJCOPY) -O binary $^ $@

hello_world.hex: hello_world.bin
	../scripts/bin2hex.py $^ > $@

clean:
	cargo clean
	@rm -f *.o hello_world.elf hello_world.bin hello_world.hex
