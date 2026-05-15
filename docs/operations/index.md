# Operations

Everything a contributor needs to build, test, debug, and ship.

## Build and run

Requires macOS 14+, Xcode 15.3+, and `xcodegen` (`brew install xcodegen`).

```sh
make bootstrap-signing # ensure the stable local signing identity exists
make generate   # regenerate LocalTypeless.xcodeproj from project.yml
make build      # xcodebuild build -scheme LocalTypeless
make run        # launch build/Debug/LocalTypeless.app
make install    # install, sign, and open /Applications/LocalTypeless.app
make clean      # wipe build/, DerivedData, generated xcodeproj
```

The Xcode project is generated from `project.yml`. Edit `project.yml`, then `make generate`. Don't hand-edit `LocalTypeless.xcodeproj/`.

## Local development signing

LocalTypeless needs a stable local signing identity when installing to `/Applications`. macOS TCC permissions for Microphone, Accessibility, and Input Monitoring are tied to the app's code requirement. If a developer installs ad-hoc-signed builds, System Settings can show permissions as enabled while TCC still rejects the current binary.

The default local identity is:

```sh
Glossa Local Dev Code Signing
```

Run this once on a development Mac:

```sh
make bootstrap-signing
```

That target runs [`scripts/ensure-local-signing-identity.sh`](../../scripts/ensure-local-signing-identity.sh). The script keeps the private key in the user's login Keychain and does not write a reusable private key into the repo. If the identity is missing, it creates a self-signed code-signing certificate, imports it into the login Keychain, and trusts it for code signing.

After bootstrapping, use:

```sh
make install
```

`make install` builds the app, copies it to `/Applications/LocalTypeless.app`, signs it with the stable identity, and opens it. The first install after creating or changing the identity still needs a one-time re-grant of Microphone, Accessibility, and Input Monitoring permissions for `/Applications/LocalTypeless.app`.

To verify the installed app's requirement:

```sh
codesign -dr - /Applications/LocalTypeless.app
```

If a different local identity is required, override it explicitly:

```sh
make install LOCAL_TYPELESS_CODE_SIGN_IDENTITY="Your Local Code Signing Name"
```

## CI

GitHub Actions builds, signs, and uploads artifacts for both flavors on every push and PR. See [ci.md](ci.md) for the workflow shape, signing-secret setup, and the user install experience.

## Testing

```sh
make test       # xcodebuild test (with LOCAL_TYPELESS_SKIP_MODEL_TESTS=1)
```

The `LOCAL_TYPELESS_SKIP_MODEL_TESTS=1` env var is wired into the `LocalTypeless` test scheme. Tests that need real model downloads (e.g. `WhisperKitASRServiceTests`, `MLXPolishServiceTests`) short-circuit when it is set. Unset to run the full matrix locally — expect multi-GB downloads on first run.

Test targets in `LocalTypelessTests/`:

- Pure-logic: `DictationPipelineTests`, `StateMachineTests`, `HotkeyModeTests`, `HotkeyBindingTests`, `AudioBufferTests`, `AppSettingsTests`, `FirstRunStateTests`, `DefaultPromptsTests`, `ModelStatusStoreTests`, `AudioStoreTests`, `SQLiteHistoryStoreTests`, `PermissionCheckerTests`.
- Stubs for the pipeline: `StubASRService`, `StubPolishService` (also used by `DictationPipelineTests` for the happy path).
- Model-gated: `WhisperKitASRServiceTests`, `MLXPolishServiceTests`.
- `LocalizationCoverageTests` asserts every `String(localized:)` key in the app has both `en` and `zh-Hans` translations.

## Permissions

First launch triggers `OnboardingView` (guarded by `FirstRunState.onboardingCompleted`). Users can re-open it from **Settings → Advanced → Reopen welcome tour**.

Three permissions are checked by `PermissionChecker`:

| Kind | Framework | Required for | Fallback if denied |
|------|-----------|--------------|-------------------|
| `microphone` | AVFoundation | Audio capture | None — recording is blocked |
| `accessibility` | ApplicationServices (`AXIsProcessTrusted`) | Paste injection + global hotkey | Text stays on pasteboard; user pastes manually |
| `inputMonitoring` | IOKit HID (`IOHIDCheckAccess`) | Global hotkey capture via `CGEventTap` | Modifier-only hotkeys don't fire |

Only microphone has a runtime prompt (`AVCaptureDevice.requestAccess`). Accessibility and Input Monitoring open System Settings via `x-apple.systempreferences:` URLs.

## Logging

All logs go through [`Support/Logger.swift`](../../LocalTypeless/Support/Logger.swift) using `os.Logger`. Subsystem: `com.localtypeless.app`. Categories: `hotkey`, `recorder`, `asr`, `polish`, `injector`, `history`, `state`, `menu`.

View in Console.app: filter by subsystem `com.localtypeless.app`. Dynamic fields are marked `privacy: .public` only when safe — do not mark transcript content public.

## Filesystem layout

`~/Library/Application Support/local-typeless/`

```
local-typeless/
  history.sqlite        # GRDB, single `dictation` table
  audio/                # optional — only when audio retention is enabled
    <uuid>.wav          # mono Float32 @ 16 kHz, pruned by AudioStore
```

WhisperKit and MLX manage their own model caches under Application Support as well (HuggingFace-style layout). The app treats those as opaque and only consumes `ModelStatusStore.isReady`.
