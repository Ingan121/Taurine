TARGETNAME = TaurineHeadless
OUTDIR ?= bin

SWIFTC = xcrun -sdk iphoneos swiftc -target $(ARCH)-apple-ios14.0 -framework SwiftZSTD -F /Users/ijunseo/Library/Developer/Xcode/DerivedData/SwiftZSTD-dwdqqbxfmvoxiffuugbrxcwuuhei/Build/Products/Debug-iphoneos
CC = xcrun -sdk iphoneos clang -arch $(ARCH) -target $(ARCH)-apple-ios14.0
CXX = xcrun -sdk iphoneos clang -arch $(ARCH) -target $(ARCH)-apple-ios14.0 -std=c++11
LDID = ldid

.PHONY: all clean

all: fat

SWIFTFLAGS = -Xcc "-Iinclude" -Xcc -DENABLE_XPC
CFLAGS = -Iinclude -DENABLE_XPC -miphoneos-version-min=14.0

DEBUG ?= 0
SERIAL = 0

LOG_FILES =
ifeq ($(DEBUG), 1)
	SWIFTFLAGS += -D DEBUG
	CFLAGS += -DDEBUG
else
	SWIFTFLAGS += -O
	CFLAGS += -O3
	CFLAGS += -DVERSION_COMMIT_COUNT='"The people who are crazy enough to think they can change the world are the ones who do"'
	CFLAGS += -DVERSION_COMMIT_SHA='"I Used To Be An Adventurer Like You, Then I Took An Arrow In The Knee."'
endif

$(OUTDIR):
	mkdir -p $(OUTDIR)

%-$(ARCH).o: %.c
	$(CC) -c -o $@ $< $(CFLAGS)

%-$(ARCH).co: %.cc
	$(CXX) -c -o $@ $< $(CFLAGS)

%-$(ARCH).co: %.cpp
	$(CXX) -c -o $@ $< $(CFLAGS)

%-$(ARCH).mo: %.m
	$(CC) -c -o $@ $< $(CFLAGS)

$(OUTDIR)/$(TARGETNAME)-$(ARCH): main.swift ASN1Parser+IM4P.swift ASN1Parser.swift LZSSDecoder.swift electra.swift kernelPatchfinder.swift offsets.swift amfidtakeover.swift entitleMe.swift machoparse.swift remount.swift bootstrap.swift extractKernel.swift swiftUtil.swift bootstrapUtils.swift kernSlide.swift nvram.swift vnodeUtil.swift krw-$(ARCH).mo libgeneral_exception-$(ARCH).co KernelRwWrapper-$(ARCH).co KernelRW-$(ARCH).co cutils-$(ARCH).o jailbreak_daemonUser-$(ARCH).o signPAC-$(ARCH).o | $(OUTDIR)
	$(SWIFTC) -o $@ $^ -import-objc-header Taurine-Bridging-Header.h $(SWIFTFLAGS) -framework IOKit -lc++
	strip $@
	$(LDID) -Ksigncert.p12 -Sent.plist $@
	rm *.o

fat:
	$(MAKE) $(OUTDIR)/$(TARGETNAME)-arm64 ARCH=arm64 DEBUG=$(DEBUG)
	$(MAKE) $(OUTDIR)/$(TARGETNAME)-arm64e ARCH=arm64e DEBUG=$(DEBUG)
	lipo -create $(OUTDIR)/$(TARGETNAME)-arm64 $(OUTDIR)/$(TARGETNAME)-arm64e -output $(OUTDIR)/$(TARGETNAME)
	rm $(OUTDIR)/$(TARGETNAME)-arm64 $(OUTDIR)/$(TARGETNAME)-arm64e

clean:
	rm -f $(OUTDIR)/$(TARGETNAME) $(OUTDIR)/$(TARGETNAME)-arm64 $(OUTDIR)/$(TARGETNAME)-arm64e *.o *.co *.mo
