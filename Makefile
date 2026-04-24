.PHONY: generate build test run clean

SCHEME = LocalTypeless
DEST = platform=macOS

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -quiet

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -quiet

run: build
	open build/Debug/LocalTypeless.app

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj
