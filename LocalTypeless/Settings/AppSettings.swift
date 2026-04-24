import Foundation
import Observation

enum ASRLanguageMode: String, Sendable, CaseIterable {
    case auto, en, zh
}

enum UILanguageMode: String, Sendable, CaseIterable {
    case system, en, zhHans
}

@MainActor
@Observable
final class AppSettings {

    private let storage: SettingsStorage

    init(storage: SettingsStorage = UserDefaultsSettingsStorage()) {
        self.storage = storage
        self._hotkeyBinding = Self.loadBinding(storage: storage) ?? .default
        self._hotkeyMode = HotkeyMode(
            rawValue: storage.string(forKey: "hotkeyMode") ?? "") ?? .toggle
        self._asrLanguageMode = ASRLanguageMode(
            rawValue: storage.string(forKey: "asrLanguageMode") ?? "") ?? .auto
        self._uiLanguageMode = UILanguageMode(
            rawValue: storage.string(forKey: "uiLanguageMode") ?? "") ?? .system
        self._polishPromptOverride = storage.string(forKey: "polishPromptOverride") ?? ""
        self._audioRetentionEnabled = storage.bool(forKey: "audioRetentionEnabled")
        self._audioRetentionDays = storage.contains("audioRetentionDays")
            ? storage.integer(forKey: "audioRetentionDays") : 7
        self._launchAtLogin = storage.bool(forKey: "launchAtLogin")
        self._pasteMethod = PasteMethod(
            rawValue: storage.string(forKey: "pasteMethod") ?? "") ?? .cgEvent
        self._preserveClipboard = storage.contains("preserveClipboard")
            ? storage.bool(forKey: "preserveClipboard") : true
        self._pauseMediaDuringRecording = storage.bool(forKey: "pauseMediaDuringRecording")
    }

    // MARK: - Properties

    private var _hotkeyBinding: HotkeyBinding
    var hotkeyBinding: HotkeyBinding {
        get { _hotkeyBinding }
        set {
            _hotkeyBinding = newValue
            if let data = try? JSONEncoder().encode(newValue) {
                storage.set(data, forKey: "hotkeyBinding")
            }
        }
    }

    private var _hotkeyMode: HotkeyMode
    var hotkeyMode: HotkeyMode {
        get { _hotkeyMode }
        set { _hotkeyMode = newValue; storage.set(newValue.rawValue, forKey: "hotkeyMode") }
    }

    private var _asrLanguageMode: ASRLanguageMode
    var asrLanguageMode: ASRLanguageMode {
        get { _asrLanguageMode }
        set { _asrLanguageMode = newValue; storage.set(newValue.rawValue, forKey: "asrLanguageMode") }
    }

    private var _uiLanguageMode: UILanguageMode
    var uiLanguageMode: UILanguageMode {
        get { _uiLanguageMode }
        set { _uiLanguageMode = newValue; storage.set(newValue.rawValue, forKey: "uiLanguageMode") }
    }

    private var _polishPromptOverride: String
    var polishPromptOverride: String {
        get { _polishPromptOverride }
        set { _polishPromptOverride = newValue; storage.set(newValue, forKey: "polishPromptOverride") }
    }

    private var _audioRetentionEnabled: Bool
    var audioRetentionEnabled: Bool {
        get { _audioRetentionEnabled }
        set { _audioRetentionEnabled = newValue; storage.set(newValue, forKey: "audioRetentionEnabled") }
    }

    private var _audioRetentionDays: Int
    var audioRetentionDays: Int {
        get { _audioRetentionDays }
        set { _audioRetentionDays = newValue; storage.set(newValue, forKey: "audioRetentionDays") }
    }

    private var _launchAtLogin: Bool
    var launchAtLogin: Bool {
        get { _launchAtLogin }
        set { _launchAtLogin = newValue; storage.set(newValue, forKey: "launchAtLogin") }
    }

    private var _pasteMethod: PasteMethod
    var pasteMethod: PasteMethod {
        get { _pasteMethod }
        set { _pasteMethod = newValue; storage.set(newValue.rawValue, forKey: "pasteMethod") }
    }

    private var _preserveClipboard: Bool
    var preserveClipboard: Bool {
        get { _preserveClipboard }
        set { _preserveClipboard = newValue; storage.set(newValue, forKey: "preserveClipboard") }
    }

    private var _pauseMediaDuringRecording: Bool
    var pauseMediaDuringRecording: Bool {
        get { _pauseMediaDuringRecording }
        set { _pauseMediaDuringRecording = newValue; storage.set(newValue, forKey: "pauseMediaDuringRecording") }
    }

    func resetPolishPrompt() { polishPromptOverride = "" }

    // MARK: - UI language

    /// Apply the persisted UI language preference to `UserDefaults.standard`
    /// so Foundation uses it on next launch. `.system` removes the override.
    static func applyUILanguagePreference(_ mode: UILanguageMode) {
        let key = "AppleLanguages"
        switch mode {
        case .system:
            UserDefaults.standard.removeObject(forKey: key)
        case .en:
            UserDefaults.standard.set(["en"], forKey: key)
        case .zhHans:
            UserDefaults.standard.set(["zh-Hans"], forKey: key)
        }
    }

    private static func loadBinding(storage: SettingsStorage) -> HotkeyBinding? {
        guard let data = storage.data(forKey: "hotkeyBinding") else { return nil }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }
}
