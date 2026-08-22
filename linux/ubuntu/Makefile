CC ?= cc
CFLAGS ?= -O2 -g -Wall -Wextra -Wpedantic
PKGS = gtk4 json-glib-1.0

.PHONY: all clean
all: arc-ubuntu

arc-ubuntu: arc-ubuntu.c
	$(CC) $(CFLAGS) $< -o $@ $$(pkg-config --cflags --libs $(PKGS))

clean:
	rm -f arc-ubuntu
