.PHONY: generate build test run clean

SCHEME = LocalTypeless
DEST = platform=macOS

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath build -quiet

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath build -quiet

run: build
	open build/Build/Products/Debug/LocalTypeless.app

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj
