.PHONY: generate generate-portable build build-portable test test-portable \
        build-ci build-portable-ci test-ci test-portable-ci sign-ci \
        run run-portable install bootstrap-signing sign-installed clean

SCHEME = LocalTypeless
DEST_ARM = platform=macOS,arch=arm64
DEST_X86 = platform=macOS,arch=x86_64

# Both build flavors land artifacts under ./build/<arch>/, so CI (and humans)
# can find the produced .app at a predictable path.
ARM_BUILD = build/arm64
X86_BUILD = build/x86_64

# Apple Silicon flavor builds the .app we install to /Applications — Intel
# users build from `make build-portable` and install manually if needed.
APP = $(ARM_BUILD)/Build/Products/Debug/LocalTypeless.app
APP_PORTABLE = $(X86_BUILD)/Build/Products/Debug/LocalTypeless.app
INSTALL_APP = /Applications/LocalTypeless.app
LOCAL_TYPELESS_CODE_SIGN_IDENTITY ?= Glossa Local Dev Code Signing
ENTITLEMENTS = LocalTypeless/Resources/LocalTypeless.entitlements

# Local dev keeps `-quiet` so xcodebuild noise doesn't drown the terminal. CI
# targets drop it so failures actually surface in workflow logs.
LOCAL_XCB_FLAGS = -quiet

# ---- Apple Silicon (arm64): WhisperKit + MLX, full feature set ----

generate:
	xcodegen generate

build: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) $(LOCAL_XCB_FLAGS)

test: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) $(LOCAL_XCB_FLAGS)

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
	codesign --force --deep --sign "$(LOCAL_TYPELESS_CODE_SIGN_IDENTITY)" --entitlements $(ENTITLEMENTS) $(INSTALL_APP)

# ---- Portable (Intel / x86_64): no WhisperKit, no MLX, no LLM polish ----

generate-portable:
	xcodegen generate --spec project.portable.yml

build-portable: generate-portable
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) $(LOCAL_XCB_FLAGS)

test-portable: generate-portable
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) $(LOCAL_XCB_FLAGS)

run-portable: build-portable
	open $(APP_PORTABLE)

# ---- CI targets ----
#
# CI builds an .app unsigned, then `make sign-ci` codesigns it with an identity
# previously imported into the current keychain via the workflow's keychain
# step. Tests use ad-hoc / unsigned settings so an empty keychain doesn't break
# them. No `-quiet` flag — real errors must reach workflow logs.

CI_XCB_FLAGS = \
	CODE_SIGN_IDENTITY="" \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=NO

build-ci: generate
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) $(CI_XCB_FLAGS)

build-portable-ci: generate-portable
	xcodebuild build -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) $(CI_XCB_FLAGS)

test-ci: generate
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_ARM)' \
		-project LocalTypeless.xcodeproj \
		-derivedDataPath $(ARM_BUILD) $(CI_XCB_FLAGS)

test-portable-ci: generate-portable
	xcodebuild test -scheme $(SCHEME) -destination '$(DEST_X86)' \
		-project LocalTypelessPortable.xcodeproj \
		-derivedDataPath $(X86_BUILD) $(CI_XCB_FLAGS)

# Sign whichever .app the caller points at with CI_SIGN_APP. The identity is
# expected to already live in the current keychain (see the workflow step that
# imports MACOS_SIGNING_CERTIFICATE_P12_BASE64). `--options runtime` opts the
# binary into the hardened runtime so it's ready for Gatekeeper / notarization
# later without re-signing.
sign-ci:
	@test -n "$(CI_SIGN_IDENTITY)" || (echo "Set CI_SIGN_IDENTITY (the CN of the cert in keychain)."; exit 1)
	@test -n "$(CI_SIGN_APP)" || (echo "Set CI_SIGN_APP (path to the .app to sign)."; exit 1)
	codesign --force --deep --options runtime \
		--sign "$(CI_SIGN_IDENTITY)" \
		--entitlements $(ENTITLEMENTS) \
		"$(CI_SIGN_APP)"
	codesign --verify --verbose=2 "$(CI_SIGN_APP)"

clean:
	rm -rf build DerivedData LocalTypeless.xcodeproj LocalTypelessPortable.xcodeproj
