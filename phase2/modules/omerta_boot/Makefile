# OMERTA iOS -- phase2 pongoOS module build
#
# Mirrors upstream checkra1n/PongoOS's example/testmodule/Makefile exactly
# (same flags, same target triple) so this module links against the same
# ABI the real pongoOS build produces. PONGO_SRC must point at a checked-out
# copy of checkra1n/PongoOS (the CI workflow clones it to ../../pongo-src;
# override PONGO_SRC for a local build).

PONGO_SRC ?= ../../pongo-src

ifndef $(HOST_OS)
	ifeq ($(OS),Windows_NT)
		HOST_OS = Windows
	else
		HOST_OS := $(shell uname -s)
	endif
endif

ifeq ($(HOST_OS),Darwin)
	EMBEDDED_CC         ?= xcrun -sdk iphoneos clang
	STRIP               ?= strip
else
ifeq ($(HOST_OS),Linux)
	EMBEDDED_CC         ?= clang
	EMBEDDED_LDFLAGS    ?= -fuse-ld=/usr/bin/ld64
	STRIP               ?= cctools-strip
endif
endif

DEP                     := $(PONGO_SRC)/newlib
LIB                     := $(DEP)/aarch64-none-darwin
BUILD                   := build

EMBEDDED_LD_FLAGS       ?= -nostdlib -static -Wl,-fatal_warnings -Wl,-dead_strip -Wl,-Z $(EMBEDDED_LDFLAGS)
EMBEDDED_CC_FLAGS       ?= --target=arm64-apple-ios12.0 -Wall -Wunused-label -Werror -O3 -flto -ffreestanding -U__nonnull -nostdlibinc -DTARGET_OS_OSX=0 -DTARGET_OS_MACCATALYST=0 -I$(LIB)/include $(EMBEDDED_LD_FLAGS) $(EMBEDDED_CFLAGS)

MODULE_LDFLAGS          ?= -Wl,-kext
MODULE_CC_FLAGS         ?= -I$(PONGO_SRC)/apple-include/ -I$(PONGO_SRC)/example/include/ $(MODULE_LDFLAGS)

MODULE_C                := main.c

.PHONY: all clean

all: $(BUILD)/omerta_boot

$(BUILD)/omerta_boot: Makefile $(MODULE_C) | $(BUILD)
	$(EMBEDDED_CC) -o $@ $(EMBEDDED_CC_FLAGS) $(MODULE_CC_FLAGS) $(MODULE_C)

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)
