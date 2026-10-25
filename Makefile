PROJECT := PromptPolish.xcodeproj
SCHEME  := PromptPolish
DERIVED := build/DerivedData
APP     := $(DERIVED)/Build/Products/Debug/PromptPolish.app
XCB     := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination 'platform=macOS,arch=arm64' -derivedDataPath $(DERIVED)

.PHONY: generate build test run clean

generate:
	xcodegen generate --quiet

build: generate
	$(XCB) build -quiet

test: generate
	$(XCB) test -quiet

run: build
	-pkill -x PromptPolish
	open $(APP)

clean:
	rm -rf build $(PROJECT)
