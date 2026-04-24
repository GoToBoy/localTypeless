import XCTest

final class LocalizationCoverageTests: XCTestCase {

    func test_every_localized_key_has_en_and_zhHans() throws {
        let projectRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // .../LocalTypelessTests/
            .deletingLastPathComponent()   // repo root

        // 1. Collect keys from source
        let sourceRoot = projectRoot.appendingPathComponent("LocalTypeless")
        let keys = try collectLocalizedKeys(under: sourceRoot)
        XCTAssertGreaterThan(keys.count, 10, "expected more than 10 localized keys, got \(keys.count)")

        // 2. Load catalog
        let catalogURL = sourceRoot.appendingPathComponent("Resources/Localizable.xcstrings")
        let data = try Data(contentsOf: catalogURL)
        let catalog = try JSONDecoder().decode(StringCatalog.self, from: data)

        // 3. Assert coverage
        var missingEn: [String] = []
        var missingZh: [String] = []
        for key in keys.sorted() {
            guard let entry = catalog.strings[key] else {
                missingEn.append(key)
                missingZh.append(key)
                continue
            }
            if entry.localizations["en"]?.stringUnit.state != "translated" {
                missingEn.append(key)
            }
            if entry.localizations["zh-Hans"]?.stringUnit.state != "translated" {
                missingZh.append(key)
            }
        }

        XCTAssertTrue(missingEn.isEmpty, "Missing en translations: \(missingEn)")
        XCTAssertTrue(missingZh.isEmpty, "Missing zh-Hans translations: \(missingZh)")
    }

    // MARK: - Support types

    private struct StringCatalog: Decodable {
        let strings: [String: Entry]

        struct Entry: Decodable {
            let localizations: [String: Localization]
        }

        struct Localization: Decodable {
            let stringUnit: StringUnit
        }

        struct StringUnit: Decodable {
            let state: String
            let value: String
        }
    }

    /// Scan .swift files under `root` for static string literals used in localized APIs.
    ///
    /// Keys that contain Swift interpolation `\(` are skipped — runtime key resolution
    /// produces a format-specifier form (e.g. `"Error: %@"`) that is catalogued separately.
    ///
    /// The test file itself is excluded to prevent phantom keys from the regex patterns
    /// appearing as catalogue requirements.
    private func collectLocalizedKeys(under root: URL) throws -> Set<String> {
        var keys: Set<String> = []
        let fm = FileManager.default
        let selfPath = URL(fileURLWithPath: #file).standardized.path
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "LocalizationCoverageTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot enumerate \(root.path)"])
        }

        let patterns: [NSRegularExpression] = try [
            // String(localized: "...")
            NSRegularExpression(pattern: #"String\(localized:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // Text("..."), Label("..."), Button("..."), Section("..."), Picker("..."), Toggle("...")
            NSRegularExpression(pattern: #"(?:Text|Label|Button|Section|Picker|Toggle)\(\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // NSMenuItem(title: "...")
            NSRegularExpression(pattern: #"NSMenuItem\(title:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
            // menu.addItem(withTitle: "...")
            NSRegularExpression(pattern: #"addItem\(withTitle:\s*"([^"\\]*(?:\\.[^"\\]*)*)""#),
        ]

        for case let url as URL in enumerator where url.pathExtension == "swift" {
            // Skip this test file to avoid phantom keys from the regex patterns above
            guard url.standardized.path != selfPath else { continue }

            let source = try String(contentsOf: url)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for regex in patterns {
                regex.enumerateMatches(in: source, range: range) { match, _, _ in
                    guard let match, match.numberOfRanges >= 2,
                          let r = Range(match.range(at: 1), in: source) else { return }
                    let key = String(source[r])

                    // Skip empty keys
                    guard !key.isEmpty else { return }

                    // Skip interpolated strings — the format-specifier form (e.g. "Error: %@")
                    // is catalogued separately and will be hit by its own regex match path.
                    guard !key.contains("\\(") else { return }

                    // Skip obvious SF Symbol / system image names: no spaces, only letters/digits/dots
                    let looksLikeSymbol = !key.contains(" ") && key.allSatisfy {
                        $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-"
                    }
                    guard !looksLikeSymbol else { return }

                    keys.insert(key)
                }
            }
        }
        return keys
    }
}
