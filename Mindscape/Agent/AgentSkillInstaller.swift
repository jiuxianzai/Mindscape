import Foundation

struct AgentSkillResources {
    let skill: Data
    let openapi: Data
    let examples: Data
    let version: String

    static var bundled: AgentSkillResources? {
        guard let skill = AgentResources.data(named: "SKILL", extension: "md"),
              let openapi = AgentResources.data(named: "openapi", extension: "json"),
              let examples = AgentResources.data(named: "examples", extension: "md"),
              let versionData = AgentResources.data(named: "VERSION", extension: nil),
              let version = String(data: versionData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !version.isEmpty else {
            return nil
        }
        return AgentSkillResources(skill: skill, openapi: openapi, examples: examples, version: version)
    }
}

struct AgentSkillInstaller {
    enum Target: String, CaseIterable, Identifiable {
        case claude
        case codex
        case dsh
        case opencode

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claude: return "Claude Code"
            case .codex: return "Codex"
            case .dsh: return "DSH"
            case .opencode: return "OpenCode"
            }
        }
    }

    enum InstallState: Equatable {
        case notDetected
        case notInstalled
        case installed(version: String)
        case outdated(version: String)

        var label: String {
            switch self {
            case .notDetected: return "未检测到"
            case .notInstalled: return "未安装"
            case .installed: return "已安装"
            case .outdated: return "可更新"
            }
        }
    }

    struct InstallResult {
        let path: String
        let version: String
    }

    private let home: URL
    private let resources: AgentSkillResources?
    private let fileManager: FileManager

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        resources: AgentSkillResources? = .bundled,
        fileManager: FileManager = .default
    ) {
        self.home = home
        self.resources = resources
        self.fileManager = fileManager
    }

    var canonicalDirectory: URL {
        home.appendingPathComponent(".agents/skills/mindscape", isDirectory: true)
    }

    var prompt: String {
        "请阅读 \(canonicalDirectory.path)/SKILL.md，然后通过 Mindscape 本地 OpenAPI 帮我创建一张思维导图。"
    }

    func state(for target: Target) -> InstallState {
        guard isDetected(target) else { return .notDetected }
        guard let installed = installedVersion(for: target) else { return .notInstalled }
        let current = resources?.version ?? "0"
        return installed == current ? .installed(version: installed) : .outdated(version: installed)
    }

    func isDetected(_ target: Target) -> Bool {
        switch target {
        case .claude:
            return fileManager.fileExists(atPath: home.appendingPathComponent(".claude").path)
        case .codex:
            return fileManager.fileExists(atPath: home.appendingPathComponent(".codex").path)
        case .dsh:
            return fileManager.fileExists(atPath: home.appendingPathComponent(".dsh").path)
        case .opencode:
            return fileManager.fileExists(atPath: home.appendingPathComponent(".config/opencode").path)
                || fileManager.fileExists(atPath: home.appendingPathComponent(".agents").path)
        }
    }

    func install(target: Target) throws -> InstallResult {
        guard let resources else {
            throw InstallerError.missingResources
        }
        try writeCanonical(resources)

        switch target {
        case .claude:
            let destination = home.appendingPathComponent(".claude/skills/mindscape", isDirectory: true)
            try copySkill(to: destination)
            return InstallResult(path: destination.path, version: resources.version)
        case .dsh:
            let destination = home.appendingPathComponent(".dsh/skills/mindscape", isDirectory: true)
            try copySkill(to: destination)
            return InstallResult(path: destination.path, version: resources.version)
        case .opencode:
            let openCodeSkills = home.appendingPathComponent(".config/opencode/skills", isDirectory: true)
            if fileManager.fileExists(atPath: openCodeSkills.path) {
                let destination = openCodeSkills.appendingPathComponent("mindscape", isDirectory: true)
                try copySkill(to: destination)
                return InstallResult(path: destination.path, version: resources.version)
            }
            if fileManager.fileExists(atPath: home.appendingPathComponent(".config/opencode").path) {
                try upsertManagedBlock(
                    in: home.appendingPathComponent(".config/opencode/AGENTS.md"),
                    canonical: canonicalDirectory
                )
            }
            return InstallResult(path: canonicalDirectory.path, version: resources.version)
        case .codex:
            try upsertManagedBlock(
                in: home.appendingPathComponent(".codex/AGENTS.md"),
                canonical: canonicalDirectory
            )
            return InstallResult(path: canonicalDirectory.path, version: resources.version)
        }
    }

    func installAllDetected() throws -> [Target: InstallResult] {
        var results: [Target: InstallResult] = [:]
        for target in Target.allCases where isDetected(target) {
            results[target] = try install(target: target)
        }
        return results
    }

    // MARK: - Files

    private func writeCanonical(_ resources: AgentSkillResources) throws {
        try write(resources.skill, to: canonicalDirectory.appendingPathComponent("SKILL.md"))
        try write(resources.openapi, to: canonicalDirectory.appendingPathComponent("openapi.json"))
        try write(resources.examples, to: canonicalDirectory.appendingPathComponent("examples.md"))
        try write(Data(resources.version.utf8), to: canonicalDirectory.appendingPathComponent("VERSION"))
    }

    private func copySkill(to destination: URL) throws {
        // 保留用户可能做的符号链接（例如 OpenCode 共享 Claude 的 skills 目录）。
        if let resolved = try? destination.resolvingSymlinksInPath(),
           resolved.path != destination.path {
            try writeCanonical(try requireResources())
            try write(try requireResources().skill, to: resolved.appendingPathComponent("SKILL.md"))
            try write(try requireResources().openapi, to: resolved.appendingPathComponent("openapi.json"))
            try write(try requireResources().examples, to: resolved.appendingPathComponent("examples.md"))
            try write(Data(try requireResources().version.utf8), to: resolved.appendingPathComponent("VERSION"))
            return
        }

        try? fileManager.removeItem(at: destination)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let resources = try requireResources()
        try write(resources.skill, to: destination.appendingPathComponent("SKILL.md"))
        try write(resources.openapi, to: destination.appendingPathComponent("openapi.json"))
        try write(resources.examples, to: destination.appendingPathComponent("examples.md"))
        try write(Data(resources.version.utf8), to: destination.appendingPathComponent("VERSION"))
    }

    private func requireResources() throws -> AgentSkillResources {
        guard let resources else { throw InstallerError.missingResources }
        return resources
    }

    private func write(_ data: Data, to url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func installedVersion(for target: Target) -> String? {
        let url: URL
        switch target {
        case .claude:
            url = home.appendingPathComponent(".claude/skills/mindscape/VERSION")
        case .dsh:
            url = home.appendingPathComponent(".dsh/skills/mindscape/VERSION")
        case .opencode:
            let openCode = home.appendingPathComponent(".config/opencode/skills/mindscape/VERSION")
            url = fileManager.fileExists(atPath: openCode.path)
                ? openCode
                : canonicalDirectory.appendingPathComponent("VERSION")
        case .codex:
            url = canonicalDirectory.appendingPathComponent("VERSION")
        }
        guard let data = try? Data(contentsOf: url),
              let value = String(data: data, encoding: .utf8) else { return nil }
        let version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return version.isEmpty ? nil : version
    }

    // MARK: - AGENTS.md managed block

    private func upsertManagedBlock(in url: URL, canonical: URL) throws {
        let block = """
        <!-- mindscape:agent-skill:begin -->
        ## Mindscape

        For any Mindscape mind map task, read `\(canonical.path)/SKILL.md` first, then use the local OpenAPI gateway as documented there. Never print or persist the access token. Ask the user before destructive operations.
        <!-- mindscape:agent-skill:end -->
        """

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if existing.isEmpty {
            try write(Data((block + "\n").utf8), to: url)
            return
        }

        let begin = "<!-- mindscape:agent-skill:begin -->"
        let end = "<!-- mindscape:agent-skill:end -->"
        let updated: String
        if let start = existing.range(of: begin),
           let finish = existing.range(of: end, range: start.upperBound..<existing.endIndex) {
            updated = existing.replacingCharacters(in: start.lowerBound..<finish.upperBound, with: block)
        } else {
            try? fileManager.copyItem(
                at: url,
                to: url.deletingLastPathComponent()
                    .appendingPathComponent("\(url.lastPathComponent).bak-mindscape-\(Int(Date().timeIntervalSince1970))")
            )
            updated = existing.trimmingCharacters(in: .newlines) + "\n\n" + block + "\n"
        }
        try write(Data(updated.utf8), to: url)
    }
}

enum InstallerError: LocalizedError {
    case missingResources

    var errorDescription: String? {
        switch self {
        case .missingResources: return "App 内置的 Agent Skill 资源缺失"
        }
    }
}
