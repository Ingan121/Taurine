PROGS := fileproviderctl_internal
CC    ?= clang
STRIP ?= strip

TARGET_SYSROOT ?= $(shell xcrun -sdk iphoneos --show-sdk-path)

CFLAGS  += -Os -isysroot $(TARGET_SYSROOT) -miphoneos-version-min=14.0 -arch arm64
LDLFAGS += -lSystem

all: $(PROGS)

clean:
	rm -f $(PROGS)

%: %.c
	$(CC) $(CFLAGS) $(LDFLAGS) $< -o $@
	$(STRIP) $@
	ldid -Sent.plist -Ksigncert.p12 $@

.PHONY: all clean
