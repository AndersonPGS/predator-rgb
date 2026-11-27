SDK := $(shell xcrun --show-sdk-path)
KH := $(SDK)/System/Library/Frameworks/Kernel.framework/Headers
OUT := build/PredatorWMI.kext
CXXFLAGS := -arch x86_64 -mkernel -fapple-kext -nostdinc -nostdlib -fno-rtti -fno-exceptions -fno-builtin \
  -std=c++17 -O2 -Wall -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT \
  -isysroot $(SDK) -I$(KH) -mmacosx-version-min=26.0
CFLAGS := $(filter-out -std=c++17 -fno-rtti -fapple-kext,$(CXXFLAGS))

APP := build/PredatorRGB.app

all: $(OUT) build/predator-rgb $(APP)

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

$(APP): app/Sources/*.swift app/Info.plist app/AppIcon.icns
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp app/AppIcon.icns $(APP)/Contents/Resources/
	xcrun swiftc -O -parse-as-library -target x86_64-apple-macos13.0 -sdk $(SDK) app/Sources/*.swift -o $(APP)/Contents/MacOS/PredatorRGB
	cp app/Info.plist $(APP)/Contents/Info.plist
	codesign -f -s - $(APP)

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" app/Info.plist)

release: all
	rm -rf build/release && mkdir -p build/release/PredatorRGB-$(VERSION)
	cp -R $(OUT) $(APP) build/predator-rgb install.sh uninstall.sh LICENSE README.md build/release/PredatorRGB-$(VERSION)/
	cd build/release && ditto -c -k --keepParent PredatorRGB-$(VERSION) PredatorRGB-$(VERSION).zip
	@echo build/release/PredatorRGB-$(VERSION).zip

clean:
	rm -rf build
.PHONY: all clean release
