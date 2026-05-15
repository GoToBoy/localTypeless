.PHONY: generate generate-portable build build-portable test test-portable run run-portable install bootstrap-signing sign-installed clean

SCHEME = LocalTypeless
DEST_ARM = platform=macOS,arch=arm64
DEST_X86 = platform=macOS,arch=x86_64

# Both build flavors land artifacts under ./build/<arch>/, so CI (and humans)
# can find the produced .app at a predictable path.
ARM_BUILD = build/arm64
X86_BUILD = build/x86_64

# The Apple Silicon build is the one we install to /Applications — Intel users
# would build from `make build-portable` and install manually if needed.
APP = $(ARM_BUILD)/Build/Products/Debug/LocalTypeless.app
INSTALL_APP = /Applications/LocalTypeless.app
LOCAL_TYPELESS_CODE_SIGN_IDENTITY ?= Glossa Local Dev Code Signing

# ---- Apple Silicon (arm64): WhisperKit + MLX, full feature set ----

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) -quiet

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) -quiet

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

# ---- Portable (Intel / x86_64): no WhisperKit, no MLX, no LLM polish ----

generate-portable:
	xcodegen generate --spec project.portable.yml

build-portable: generate-portable
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) -quiet

test-portable: generate-portable
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) -quiet

run-portable: build-portable
	open $(X86_BUILD)/Build/Products/Debug/LocalTypeless.app

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj LocalTypelessPortable.xcodeproj
