SDK := $(shell xcrun --show-sdk-path)
KH := $(SDK)/System/Library/Frameworks/Kernel.framework/Headers
OUT := build/PredatorWMI.kext
CXXFLAGS := -arch x86_64 -mkernel -fapple-kext -nostdinc -nostdlib -fno-rtti -fno-exceptions -fno-builtin \
  -std=c++17 -O2 -Wall -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
  -isysroot $(SDK) -I$(KH) -mmacosx-version-min=26.0
CFLAGS := $(filter-out -std=c++17 -fno-rtti -fapple-kext,$(CXXFLAGS))

all: $(OUT) build/predator-rgb

$(OUT): kext/WMIBridge.cpp kext/WMIBridge.hpp kext/info.c kext/Info.plist
	mkdir -p $(OUT)/Contents/MacOS build/obj
	xcrun clang++ $(CXXFLAGS) -c kext/WMIBridge.cpp -o build/obj/WMIBridge.o
	xcrun clang $(CFLAGS) -c kext/info.c -o build/obj/info.o
	xcrun clang++ -arch x86_64 -isysroot $(SDK) -mmacosx-version-min=26.0 -nostdlib -Xlinker -kext \
	  build/obj/WMIBridge.o build/obj/info.o -lkmod -lkmodc++ -lcc_kext -o $(OUT)/Contents/MacOS/PredatorWMI
	cp kext/Info.plist $(OUT)/Contents/Info.plist
	codesign -f -s - $(OUT)

build/predator-rgb: cli/predator-rgb.c
	mkdir -p build
	xcrun clang -O2 -Wall -framework IOKit -framework CoreFoundation cli/predator-rgb.c -o $@

clean:
	rm -rf build
.PHONY: all clean
