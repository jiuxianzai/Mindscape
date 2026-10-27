import XCTest
@testable import Mindscape

final class ThemePolicyTests: XCTestCase {
    func testPaperIsOnlyAvailableInLightAppearance() {
        XCTAssertTrue(ThemePolicy.allows("paper", isDark: false))
        XCTAssertFalse(ThemePolicy.allows("paper", isDark: true))
        XCTAssertEqual(ThemePolicy.adjusted("paper", isDark: true), "midnight")
        XCTAssertEqual(ThemePolicy.adjusted("paper", isDark: false), "paper")
    }

    func testOtherThemesRemainAvailableInDark() {
        for theme in MapTheme.all where theme.id != "paper" {
            XCTAssertTrue(ThemePolicy.allows(theme.id, isDark: true), theme.id)
        }
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
