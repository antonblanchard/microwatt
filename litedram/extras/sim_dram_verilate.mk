OPT_FAST=-O3 -fstrict-aliasing
OPT_SLOW=-O3 -fstrict-aliasing

top_all: top_all2

include Vlitedram_core.mk

top_all2: default $(VK_GLOBAL_OBJS)

.PHONY: top_all top_all2
