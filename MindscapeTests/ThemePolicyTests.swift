import XCTest
@testable import Mindscape

final class ThemePolicyTests: XCTestCase {
    func testPaperIsOnlyAvailableInLightAppearance() {
        XCTAssertTrue(ThemePolicy.allows("paper", isDark: false))
        XCTAssertFalse(ThemePolicy.allows("paper", isDark: true))
        XCTAssertEqual(ThemePolicy.adjusted("paper", isDark: true), "midnight")
        XCTAssertEqual(ThemePolicy.adjusted("paper", isDark: false), "paper")
    }

    func testThemesOnlyMatchTheirBrightness() {
        for theme in MapTheme.all {
            XCTAssertTrue(ThemePolicy.allows(theme.id, isDark: theme.isDark), theme.id)
            XCTAssertFalse(ThemePolicy.allows(theme.id, isDark: !theme.isDark), theme.id)
        }
    }

    func testLegacyThemeBecomesPerFilePair() {
        var map = MindMap.blank(themeID: "blueprint")
        map.normalizeTheme(isDark: false)
        XCTAssertEqual(map.lightThemeID, "paper")
        XCTAssertEqual(map.darkThemeID, "blueprint")
        XCTAssertEqual(map.themeID, "paper")

        map.normalizeTheme(isDark: true)
        XCTAssertEqual(map.themeID, "blueprint")

        map.rememberTheme("neon", isDark: true)
        XCTAssertEqual(map.darkThemeID, "neon")
        XCTAssertEqual(map.themeID, "neon")
        map.normalizeTheme(isDark: false)
        XCTAssertEqual(map.themeID, "paper")
        map.normalizeTheme(isDark: true)
        XCTAssertEqual(map.themeID, "neon")
    }

    func testAppearanceModesCoverSystemLightDark() {
        XCTAssertEqual(AppearanceMode.allCases, [.system, .light, .dark])
        XCTAssertNil(AppearanceMode.system.appearance)
        XCTAssertNotNil(AppearanceMode.light.appearance)
        XCTAssertNotNil(AppearanceMode.dark.appearance)
    }
}

@MainActor
final class ThemeEditorTests: XCTestCase {
    func testEachAppearanceRemembersItsOwnTheme() throws {
        let previous = NSApplication.shared.appearance
        defer { NSApplication.shared.appearance = previous }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeThemePairTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DocumentStore(directory: directory)
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        let editor = MapEditor(map: MindMap.blank(themeID: "paper"), store: store)
        editor.setTheme("sand")
        XCTAssertEqual(editor.map.lightThemeID, "sand")
        XCTAssertEqual(editor.map.themeID, "sand")

        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        editor.syncThemeForAppearance()
        XCTAssertEqual(editor.map.themeID, "midnight")
        editor.setTheme("blueprint")
        XCTAssertEqual(editor.map.darkThemeID, "blueprint")

        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        editor.syncThemeForAppearance()
        XCTAssertEqual(editor.map.themeID, "sand")
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        editor.syncThemeForAppearance()
        XCTAssertEqual(editor.map.themeID, "blueprint")
    }

    func testSettingPaperInDarkFallsBackToMidnight() throws {
        let previous = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        defer { NSApplication.shared.appearance = previous }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeThemeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DocumentStore(directory: directory)
        let editor = MapEditor(map: MindMap.blank(themeID: "paper"), store: store)
        editor.setTheme("paper")
        XCTAssertEqual(editor.map.themeID, "midnight")
        XCTAssertEqual(editor.theme.id, "midnight")
    }
}
