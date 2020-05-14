CFLAGS = -O2 -g -Wall -std=c99

all: mw_debug

mw_debug: mw_debug.c
	$(CC) -o $@ $^ -lurjtag

clean:
	rm -f mw_debug
distclean:
	rm -f *~

