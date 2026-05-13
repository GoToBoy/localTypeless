# References

External dependencies, data formats, and interface contracts.

## Swift Package dependencies

Pinned in `project.yml`:

| Package | Version | Role |
|---------|---------|------|
| [GRDB.swift](https://github.com/groue/GRDB.swift) | 6.29.0+ | SQLite ORM used by `SQLiteHistoryStore` |
| [WhisperKit](https://github.com/argmaxinc/WhisperKit) | 0.13.0+ | CoreML Whisper loader + inference; exposed via `WhisperKitASRService` |
| [mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples) | 2.25.0+ | `MLXLLM` + `MLXLMCommon`; wraps Qwen2.5-3B-Instruct-4bit for `MLXPolishService` |

## Models (HuggingFace)

Fetched on first use (user-initiated, never automatic):

- **Whisper:** `argmaxinc/whisperkit-coreml` → `openai_whisper-large-v3-turbo`
- **Polish LLM:** Qwen2.5-3B-Instruct in MLX 4-bit format

## Localization

- Catalog: [`LocalTypeless/Resources/Localizable.xcstrings`](../../LocalTypeless/Resources/Localizable.xcstrings) — Xcode String Catalog format (`xcstrings`).
- Languages: `en` (development language), `zh-Hans`.
- Every `String(localized:)` call in the app must have both. `LocalizationCoverageTests` enforces coverage; CI fails on missing keys.
- Runtime language override: `AppSettings.uiLanguageMode ∈ {.system, .en, .zhHans}` — writes to `AppleLanguages` in `UserDefaults.standard`. `.system` removes the override so Foundation uses the OS default. Applied on launch and on every settings change.

## History schema

SQLite via GRDB. Single table, managed by [`Persistence/SQLiteHistoryStore.swift`](../../LocalTypeless/Persistence/SQLiteHistoryStore.swift):

```sql
CREATE TABLE dictation (
    id INTEGER PRIMARY KEY,
    started_at TEXT NOT NULL,           -- ISO 8601
    duration_ms INTEGER NOT NULL,
    raw_transcript TEXT NOT NULL,
    polished_text TEXT NOT NULL,        -- equals raw_transcript on polish failure
    language TEXT NOT NULL,             -- BCP-47 from WhisperKit
    target_app_bundle_id TEXT,
    target_app_name TEXT
);
CREATE INDEX idx_dictation_started_at ON dictation(started_at DESC);
```

## Settings keys

`UserDefaults` keys owned by `AppSettings`:

| Key | Type | Default |
|-----|------|---------|
| `hotkeyBinding` | JSON `HotkeyBinding` | double-tap right ⌥ |
| `hotkeyMode` | `HotkeyMode.rawValue` | `toggle` |
| `asrLanguageMode` | `ASRLanguageMode.rawValue` | `auto` |
| `uiLanguageMode` | `UILanguageMode.rawValue` | `system` |
| `polishPromptOverride` | `String` | `""` (uses `DefaultPrompts`) |
| `audioRetentionEnabled` | `Bool` | `false` |
| `audioRetentionDays` | `Int` | `7` |
| `launchAtLogin` | `Bool` | `false` |
| `pasteMethod` | `PasteMethod.rawValue` | `cgEvent` |
| `preserveClipboard` | `Bool` | `true` |
| `pauseMediaDuringRecording` | `Bool` | `false` |
| `onboardingCompleted` | `Bool` | `false` (owned by `FirstRunState`) |

## Entitlements

See [`LocalTypeless/Resources/LocalTypeless.entitlements`](../../LocalTypeless/Resources/LocalTypeless.entitlements):

- `com.apple.security.app-sandbox = false` — we need system-wide accessibility + input monitoring.
- `com.apple.security.device.audio-input = true` — mic access.

`Info.plist` usage strings: `NSMicrophoneUsageDescription`, `NSAccessibilityUsageDescription`. Set in `project.yml`.
