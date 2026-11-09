# AISSD Gen-1 sim-first smoke build (host C stubs; not FPGA).
CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude
LDFLAGS ?=

STUB_SRCS := \
	src/stubs/io_desc.c \
	src/stubs/ftl_hooks.c \
	src/stubs/qos_fdp.c \
	src/stubs/nand_model.c

STUB_OBJS := $(STUB_SRCS:.c=.o)

.PHONY: all smoke clean

all: smoke

build/smoke_io_desc: tests/smoke_io_desc.c $(STUB_OBJS)
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDFLAGS)

src/stubs/%.o: src/stubs/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

smoke: build/smoke_io_desc
	./build/smoke_io_desc

clean:
	rm -rf build $(STUB_OBJS)
