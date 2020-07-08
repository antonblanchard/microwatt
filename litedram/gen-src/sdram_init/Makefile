#### Directories

include variables.mak
OBJ = $(BUILD_DIR)/obj

LXINC_DIR=$(LXSRC_DIR)/include

PROGRAM = sdram_init
OBJECTS = $(OBJ)/head.o $(OBJ)/main.o $(OBJ)/sdram.o $(OBJ)/memtest.o $(OBJ)/console.o

#### Compiler

ARCH = $(shell uname -m)
ifneq ("$(ARCH)", "ppc64")
ifneq ("$(ARCH)", "ppc64le")
        CROSS_COMPILE = powerpc64le-linux-gnu-
        endif
        endif

CC = $(CROSS_COMPILE)gcc
LD = $(CROSS_COMPILE)ld
OBJCOPY = $(CROSS_COMPILE)objcopy

#### Flags

CPPFLAGS = -nostdinc -D__USE_LIBC $(EXTRA_CFLAGS)

# These includes must be first ...
CPPFLAGS += -I$(GENINC_DIR) -I$(SRC_DIR)/include -I$(SRC_DIR)/../../../include -I$(SRC_DIR)/libc/include 

# .. and these last, otherwise litex overrides some of our stuff
CPPFLAGS += -I$(LXSRC_DIR) -I$(LXINC_DIR) -I$(LXINC_DIR)/base -I$(LXSRC_DIR)/liblitedram

CPPFLAGS += -isystem $(shell $(CC) -print-file-name=include)
CFLAGS = -Os -g -Wall -std=c99 -m64 -mabi=elfv2 -msoft-float -mno-string -mno-multiple -mno-vsx -mno-altivec -mlittle-endian -fno-stack-protector -mstrict-align -ffreestanding -fdata-sections -ffunction-sections -fno-delete-null-pointer-checks 
ASFLAGS = $(CPPFLAGS) $(CFLAGS)
LDFLAGS = -static -nostdlib -T $(OBJ)/$(PROGRAM).lds --gc-sections

#### Pretty print

ifeq ($(V),1)
define Q
  $(2)
endef
else
define Q
  @echo "	[$1] " $(shell basename $3)
  @$(2)
endef
endif

#### Rules. This is a bit crappy, I'm sure we can do better with the
####        handling of the various path, but this will have to do
####        until I can be bothered getting my head around the finer
####        points of Makefiles

all: objdir $(OBJ)/$(PROGRAM).hex

$(OBJ)/sdram.o: $(LXSRC_DIR)/liblitedram/sdram.c
	$(call Q,CC, $(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@, $@)
$(OBJ)/memtest.o: $(LXSRC_DIR)/libbase/memtest.c
	$(call Q,CC, $(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@, $@)
$(OBJ)/console.o: $(SRC_DIR)/../../../lib/console.c
	$(call Q,CC, $(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@, $@)
$(OBJ)/%.o : $(SRC_DIR)/%.c
	$(call Q,CC, $(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@, $@)
$(OBJ)/%.o : $(SRC_DIR)/%.S
	$(call Q,AS, $(CC) $(ASFLAGS) -c $< -o $@, $@)
$(OBJ)/%.o : $(SRC_DIR)/libc/src/%.c
	$(call Q,CC, $(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@, $@)
$(OBJ)/%.lds : $(SRC_DIR)/%.lds.S
	$(call Q,CC, $(CC) $(CPPFLAGS) -P -E $< -o $@, $@)

LIBC_SRC := $(wildcard $(SRC_DIR)/libc/src/*.c)
LIBC_OBJ := $(patsubst $(SRC_DIR)/libc/src/%.c, $(OBJ)/%.o,$(LIBC_SRC))
$(OBJ)/libc.o: $(LIBC_OBJ)
	$(call Q,LD, $(LD) -r -o $@ $^, $@)

$(OBJ)/$(PROGRAM).elf: $(OBJECTS) $(OBJ)/libc.o $(OBJ)/$(PROGRAM).lds
	$(call Q,LD, $(LD) $(LDFLAGS) -o $@ $(OBJECTS) $(OBJ)/libc.o, $@)

$(OBJ)/$(PROGRAM).bin: $(OBJ)/$(PROGRAM).elf
	$(call Q,OC, $(OBJCOPY) -O binary -S $^ $@, $@)

$(OBJ)/$(PROGRAM).hex: $(OBJ)/$(PROGRAM).bin
	$(call Q,HX, $(SRC_DIR)/bin2hex.py $^ > $@, $@)

objdir:
	@mkdir -p $(OBJ)
