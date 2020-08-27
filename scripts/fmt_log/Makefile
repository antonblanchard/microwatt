CFLAGS = -O2 -g -Wall -std=c99

all: fmt_log

fmt_log: fmt_log.c
	$(CC) -o $@ $^ $(CFLAGS)

clean:
	rm -f fmt_log
distclean:
	rm -f *~

