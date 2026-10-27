import Foundation
import XCTest
@testable import Mindscape

final class AgentSkillInstallerTests: XCTestCase {
    private var home: URL!
    private let resources = AgentSkillResources(
        skill: Data("# Mindscape skill".utf8),
        openapi: Data("{}".utf8),
        examples: Data("# Examples".utf8),
        version: "1.0"
    )

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeSkillTests-\(UUID().uuidString)", isDirectory: true)
        for path in [".claude", ".codex", ".dsh", ".config/opencode", ".config/opencode/skills"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(path, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: home)
    }

    func testDetectsAndInstallsAllTargets() throws {
        let installer = AgentSkillInstaller(home: home, resources: resources)
        for target in AgentSkillInstaller.Target.allCases {
            XCTAssertTrue(installer.isDetected(target), target.rawValue)
            XCTAssertEqual(installer.state(for: target), .notInstalled)
        }

        for target in AgentSkillInstaller.Target.allCases {
            let result = try installer.install(target: target)
            XCTAssertEqual(result.version, "1.0")
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.path + "/SKILL.md"))
        }

        let canonical = home.appendingPathComponent(".agents/skills/mindscape/VERSION")
        XCTAssertEqual(try String(contentsOf: canonical, encoding: .utf8), "1.0")
        let openCodeSkill = home.appendingPathComponent(".config/opencode/skills/mindscape/VERSION")
        XCTAssertEqual(try String(contentsOf: openCodeSkill, encoding: .utf8), "1.0")

        let codex = try String(contentsOf: home.appendingPathComponent(".codex/AGENTS.md"), encoding: .utf8)
        XCTAssertTrue(codex.contains("mindscape:agent-skill:begin"))
        XCTAssertTrue(codex.contains("SKILL.md"))

    }

    func testReinstallUpdatesWithoutDuplicatingBlock() throws {
        var installer = AgentSkillInstaller(home: home, resources: resources)
        _ = try installer.install(target: .codex)
        _ = try installer.install(target: .codex)

        let path = home.appendingPathComponent(".codex/AGENTS.md")
        let text = try String(contentsOf: path, encoding: .utf8)
        XCTAssertEqual(text.components(separatedBy: "mindscape:agent-skill:begin").count - 1, 1)

        installer = AgentSkillInstaller(
            home: home,
            resources: AgentSkillResources(
                skill: resources.skill,
                openapi: resources.openapi,
                examples: resources.examples,
                version: "2.0"
            )
        )
        XCTAssertEqual(installer.state(for: .codex), .outdated(version: "1.0"))
        _ = try installer.install(target: .codex)
        XCTAssertEqual(installer.state(for: .codex), .installed(version: "2.0"))
    }

    func testBundledSkillResourcesArePackaged() {
        XCTAssertNotNil(AgentSkillResources.bundled, "App bundle 应包含 SKILL.md / openapi.json / examples.md / VERSION")
    }

    func testBundledResourcesInstallIntoHome() throws {
        let resources = try XCTUnwrap(AgentSkillResources.bundled)
        let installer = AgentSkillInstaller(home: home, resources: resources)
        let result = try installer.install(target: .claude)
        XCTAssertEqual(result.version, resources.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path + "/openapi.json"))
    }

    func testMissingResourcesFails() {
        let installer = AgentSkillInstaller(home: home, resources: nil)
        XCTAssertThrowsError(try installer.install(target: .claude))
    }

    func testPreservesExistingAgentsContent() throws {
        let agents = home.appendingPathComponent(".codex/AGENTS.md")
        try "# 用户自己的规则\n".write(to: agents, atomically: true, encoding: .utf8)

        _ = try AgentSkillInstaller(home: home, resources: resources).install(target: .codex)
        let text = try String(contentsOf: agents, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# 用户自己的规则"))
        XCTAssertTrue(text.contains("mindscape:agent-skill:begin"))
    }
}
