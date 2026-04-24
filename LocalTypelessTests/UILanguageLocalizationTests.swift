import XCTest
@testable import LocalTypeless

/// Guards the i18n chain end-to-end: the app bundle ships both English and
/// Simplified Chinese localization tables, and representative UI strings
/// resolve to translated values in each. If any of these fail, either the
/// `.lproj` folders didn't make it into the bundle or strings in the
/// catalog have slipped out of translation.
@MainActor
final class UILanguageLocalizationTests: XCTestCase {

    /// Representative keys covering settings tabs, onboarding, menu bar, and
    /// model-download UI. If any of these lose their Chinese translation we
    /// want a test failure, not a silent fallback to English.
    private let sampleKeys: [String] = [
        "Hotkey",
        "Speech",
        "Auto-detect",
        "Settings...",
        "ASR model",
        "Microphone",
        "Download",
        "Restart the app to see the change everywhere.",
    ]

    func test_bundle_advertises_en_and_zh_hans() {
        let locs = Set(Bundle(for: AppSettings.self).localizations)
        XCTAssertTrue(locs.contains("en"), "English localization missing from bundle")
        XCTAssertTrue(locs.contains("zh-Hans"), "Simplified Chinese localization missing from bundle")
    }

    func test_zh_hans_strings_differ_from_source_keys() throws {
        let bundle = Bundle(for: AppSettings.self)
        let zhPath = try XCTUnwrap(
            bundle.path(forResource: "zh-Hans", ofType: "lproj"),
            "zh-Hans.lproj not found in app bundle"
        )
        let zhBundle = try XCTUnwrap(Bundle(path: zhPath))

        for key in sampleKeys {
            let translated = zhBundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertNotEqual(
                translated, key,
                "Key \(key.debugDescription) has no zh-Hans translation (returned the key itself)"
            )
        }
    }

    func test_en_strings_resolve_to_source_text() throws {
        let bundle = Bundle(for: AppSettings.self)
        let enPath = try XCTUnwrap(
            bundle.path(forResource: "en", ofType: "lproj"),
            "en.lproj not found in app bundle"
        )
        let enBundle = try XCTUnwrap(Bundle(path: enPath))

        for key in sampleKeys {
            let translated = enBundle.localizedString(forKey: key, value: nil, table: nil)
            XCTAssertEqual(translated, key, "English key \(key.debugDescription) should equal itself")
        }
    }

    func test_applyUILanguagePreference_writes_apple_languages() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "AppleLanguages")

        AppSettings.applyUILanguagePreference(.zhHans)
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["zh-Hans"])

        AppSettings.applyUILanguagePreference(.en)
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["en"])

        // `.system` removes the app-domain override so Foundation resolves the
        // value from NSGlobalDomain on next launch. `array(forKey:)` on the
        // standard defaults reads across domains, so to verify the override
        // was actually cleared we inspect the app's persistent domain directly.
        AppSettings.applyUILanguagePreference(.system)
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        let appDomain = defaults.persistentDomain(forName: bundleID) ?? [:]
        XCTAssertNil(appDomain["AppleLanguages"],
                     ".system must remove the app-level AppleLanguages override")
    }
}
