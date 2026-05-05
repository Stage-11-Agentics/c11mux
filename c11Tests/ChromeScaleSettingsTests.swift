import XCTest

#if canImport(c11_DEV)
@testable import c11_DEV
#elseif canImport(c11)
@testable import c11
#endif

/// Unit tests for `ChromeScaleSettings` — preset enum, multiplier table, and
/// the parameter-seam `preset(defaults:)` resolver. (C11-6)
final class ChromeScaleSettingsTests: XCTestCase {

    // MARK: - preset(for:)

    func testPresetForNilFallsBackToDefault() {
        XCTAssertEqual(ChromeScaleSettings.preset(for: nil), .standard)
    }

    func testPresetForEmptyStringFallsBackToDefault() {
        XCTAssertEqual(ChromeScaleSettings.preset(for: ""), .standard)
    }

    func testPresetForUnknownStringFallsBackToDefault() {
        XCTAssertEqual(ChromeScaleSettings.preset(for: "tiny"), .standard)
    }

    func testPresetForKnownStringsResolves() {
        XCTAssertEqual(ChromeScaleSettings.preset(for: "compact"), .compact)
        XCTAssertEqual(ChromeScaleSettings.preset(for: "standard"), .standard)
        XCTAssertEqual(ChromeScaleSettings.preset(for: "large"), .large)
        XCTAssertEqual(ChromeScaleSettings.preset(for: "extraLarge"), .extraLarge)
    }

    // MARK: - preset(defaults:)

    func testPresetDefaultsRoundtripsThroughUserDefaults() {
        let suite = "ChromeScaleSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(ChromeScaleSettings.preset(defaults: defaults), .standard)

        defaults.set("large", forKey: ChromeScaleSettings.presetKey)
        XCTAssertEqual(ChromeScaleSettings.preset(defaults: defaults), .large)

        defaults.set("extraLarge", forKey: ChromeScaleSettings.presetKey)
        XCTAssertEqual(ChromeScaleSettings.preset(defaults: defaults), .extraLarge)
    }

    func testPresetDefaultsFallsBackOnGarbage() {
        let suite = "ChromeScaleSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("not-a-preset", forKey: ChromeScaleSettings.presetKey)
        XCTAssertEqual(ChromeScaleSettings.preset(defaults: defaults), .standard)
    }

    // MARK: - multiplier(for:)

    func testMultiplierTable() {
        XCTAssertEqual(ChromeScaleSettings.multiplier(for: .compact),    0.90, accuracy: 0.0001)
        XCTAssertEqual(ChromeScaleSettings.multiplier(for: .standard),   1.00, accuracy: 0.0001)
        XCTAssertEqual(ChromeScaleSettings.multiplier(for: .large),      1.12, accuracy: 0.0001)
        XCTAssertEqual(ChromeScaleSettings.multiplier(for: .extraLarge), 1.25, accuracy: 0.0001)
    }

    // MARK: - Preset.displayName

    func testEveryPresetHasNonEmptyDisplayName() {
        for preset in ChromeScaleSettings.Preset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty, "Empty displayName for preset \(preset.rawValue)")
        }
    }

    // MARK: - Preset basics

    func testAllCasesContainsFour() {
        XCTAssertEqual(ChromeScaleSettings.Preset.allCases.count, 4)
    }

    func testIdMatchesRawValue() {
        for preset in ChromeScaleSettings.Preset.allCases {
            XCTAssertEqual(preset.id, preset.rawValue)
        }
    }
}
