.PHONY: generate build test run install bootstrap-signing sign-installed clean

SCHEME = LocalTypeless
DEST = platform=macOS
DERIVED_DATA = build
APP = $(DERIVED_DATA)/Build/Products/Debug/LocalTypeless.app
INSTALL_APP = /Applications/LocalTypeless.app
LOCAL_TYPELESS_CODE_SIGN_IDENTITY ?= Glossa Local Dev Code Signing

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(DERIVED_DATA) -quiet

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST)' -derivedDataPath $(DERIVED_DATA) -quiet

run: build
	open $(APP)

install: bootstrap-signing build
	ditto $(APP) $(INSTALL_APP)
	$(MAKE) sign-installed
	open $(INSTALL_APP)

bootstrap-signing:
	scripts/ensure-local-signing-identity.sh "$(LOCAL_TYPELESS_CODE_SIGN_IDENTITY)"

sign-installed:
	@test -n "$(LOCAL_TYPELESS_CODE_SIGN_IDENTITY)" || (echo "Set LOCAL_TYPELESS_CODE_SIGN_IDENTITY to a valid codesigning identity."; exit 1)
	codesign --force --deep --sign "$(LOCAL_TYPELESS_CODE_SIGN_IDENTITY)" --entitlements LocalTypeless/Resources/LocalTypeless.entitlements $(INSTALL_APP)

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj
