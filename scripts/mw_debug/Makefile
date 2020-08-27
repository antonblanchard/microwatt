CFLAGS = -O2 -g -Wall -std=c99
# CFLAGS +=  -I urjtag/urjtag/include/ -L urjtag/urjtag/src/.libs/

all: mw_debug

mw_debug: mw_debug.c
	$(CC) -o $@ $^ $(CFLAGS) -lurjtag

clean:
	rm -f mw_debug
distclean:
	rm -f *~

