# AISSD Gen-1 sim-first + hardware-sim build (not FPGA bitstream).
CC      ?= gcc
CFLAGS  ?= -std=c11 -Wall -Wextra -Werror -O2
CPPFLAGS += -Iinclude
LDFLAGS ?=

STUB_SRCS := \
	src/stubs/io_desc.c \
	src/stubs/ftl_hooks.c \
	src/stubs/qos_fdp.c \
	src/stubs/nand_model.c

PROTO_SRCS := \
	src/proto/host_traffic.c \
	src/proto/proto_ctrl.c

STUB_OBJS := $(STUB_SRCS:.c=.o)
PROTO_OBJS := $(PROTO_SRCS:.c=.o)

.PHONY: all smoke proto hw-sim sim-hw clean

all: smoke proto

build/smoke_io_desc: tests/smoke_io_desc.c $(STUB_OBJS)
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDFLAGS)

build/proto_demo: tests/proto_demo.c $(STUB_OBJS) $(PROTO_OBJS)
	@mkdir -p build
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $^ $(LDFLAGS)

src/stubs/%.o: src/stubs/%.c
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

src/proto/%.o: src/proto/%.c
	@mkdir -p src/proto
	$(CC) $(CPPFLAGS) $(CFLAGS) -c -o $@ $<

smoke: build/smoke_io_desc
	./build/smoke_io_desc

proto: build/proto_demo
	./build/proto_demo

# Hardware simulation (Verilator preferred; Icarus fallback). See docs/hw-sim-prototype.md
hw-sim sim-hw:
	@chmod +x scripts/run_hw_sim.sh
	./scripts/run_hw_sim.sh

clean:
	rm -rf build $(STUB_OBJS) $(PROTO_OBJS)
