import Foundation

@main
struct MindscapeCLI {
    static func main() async {
        do {
            try await run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as AgentClientError {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(error.exitCode)
        } catch {
            FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(_ raw: [String]) async throws {
        var tokens = raw
        var gatewayURL = AgentClient.defaultGatewayURL
        var launchApp = true
        var pretty = false

        if let index = tokens.firstIndex(of: "--gateway"), index + 1 < tokens.count {
            gatewayURL = URL(fileURLWithPath: tokens[index + 1])
            tokens.removeSubrange(index...index + 1)
        }
        if let index = tokens.firstIndex(of: "--no-launch") {
            launchApp = false
            tokens.remove(at: index)
        }
        if let index = tokens.firstIndex(of: "--pretty") {
            pretty = true
            tokens.remove(at: index)
        }

        guard let command = tokens.first else {
            printHelp()
            return
        }
        if command == "help" || command == "--help" || command == "-h" {
            printHelp()
            return
        }

        let client = AgentClient(gatewayURL: gatewayURL, launchApp: launchApp)

        switch command {
        case "health":
            try await emit(client.request(method: "GET", path: "v1/health"), pretty: pretty)
        case "url":
            let gateway = try await client.ensureGateway()
            print(gateway.url.absoluteString)
        case "guide":
            try await emit(client.request(method: "GET", path: "v1/skill.md"), pretty: false, raw: true)
        case "openapi":
            try await emit(client.request(method: "GET", path: "v1/openapi.json"), pretty: pretty, raw: !pretty)
        case "skill":
            try await skill(Array(tokens.dropFirst()), client: client, pretty: pretty)
        case "folder":
            try await folder(Array(tokens.dropFirst()), client: client, pretty: pretty)
        case "map":
            try await maps(Array(tokens.dropFirst()), client: client, pretty: pretty)
        case "node":
            try await node(Array(tokens.dropFirst()), client: client, pretty: pretty)
        case "api":
            try await genericAPI(Array(tokens.dropFirst()), client: client, pretty: pretty)
        default:
            throw CLIError.usage("未知命令：\(command)。运行 mindscape help 查看用法。")
        }
    }

    // MARK: - Skills

    private static func skill(_ tokens: [String], client: AgentClient, pretty: Bool) async throws {
        let parsed = parse(tokens)
        guard parsed.positional.first == "install" else {
            throw CLIError.usage("用法：mindscape skill install --target claude|codex|dsh|opencode|all")
        }
        let target = parsed.values["target"] ?? "all"
        if target == "all" {
            var results: [Any] = []
            for name in ["claude", "codex", "dsh", "opencode"] {
                do {
                    let (data, _) = try await client.request(
                        method: "POST", path: "v1/skill/install", body: ["target": name]
                    )
                    if let object = try? JSONSerialization.jsonObject(with: data) {
                        results.append(object)
                    }
                } catch {
                    results.append(["ok": false, "target": name, "error": error.localizedDescription])
                }
            }
            let data = try JSONSerialization.data(withJSONObject: results, options: pretty ? [.prettyPrinted] : [])
            print(String(data: data, encoding: .utf8) ?? "")
            return
        }
        try await emit(
            client.request(method: "POST", path: "v1/skill/install", body: ["target": target]),
            pretty: pretty
        )
    }

    // MARK: - Folders

    private static func folder(_ tokens: [String], client: AgentClient, pretty: Bool) async throws {
        let parsed = parse(tokens)
        guard let action = parsed.positional.first else {
            throw CLIError.usage("用法：mindscape folder list|create|rename|delete ...")
        }
        switch action {
        case "list":
            try await emit(client.request(method: "GET", path: "v1/folders"), pretty: pretty)
        case "create":
            guard let name = parsed.positional.dropFirst().first ?? parsed.values["name"] else {
                throw CLIError.usage("用法：mindscape folder create <name> [--parent ID]")
            }
            var body: [String: Any] = ["name": name]
            if let parent = parsed.values["parent"] { body["parentId"] = parent }
            try await emit(client.request(method: "POST", path: "v1/folders", body: body), pretty: pretty)
        case "rename":
            guard parsed.positional.count >= 3 else {
                throw CLIError.usage("用法：mindscape folder rename <id> <name>")
            }
            try await emit(client.request(
                method: "PATCH",
                path: "v1/folders/\(parsed.positional[1])",
                body: ["name": parsed.positional[2]]
            ), pretty: pretty)
        case "delete":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape folder delete <id>")
            }
            try await emit(client.request(method: "DELETE", path: "v1/folders/\(parsed.positional[1])"), pretty: pretty)
        default:
            throw CLIError.usage("未知 folder 命令：\(action)")
        }
    }

    // MARK: - Maps

    private static func maps(_ tokens: [String], client: AgentClient, pretty: Bool) async throws {
        let parsed = parse(tokens)
        guard let action = parsed.positional.first else {
            throw CLIError.usage("用法：mindscape map list|create|show|tree|rename|move|delete|export|import ...")
        }
        switch action {
        case "list":
            var query: [URLQueryItem] = []
            if let folder = parsed.values["folder"] { query.append(.init(name: "folderId", value: folder)) }
            if parsed.switches.contains("include-deleted") { query.append(.init(name: "includeDeleted", value: "true")) }
            try await emit(client.request(method: "GET", path: "v1/maps", query: query), pretty: pretty)
        case "create":
            guard let title = parsed.positional.dropFirst().first ?? parsed.values["title"] else {
                throw CLIError.usage("用法：mindscape map create <title> [--folder ID] [--layout] [--theme] [--template]")
            }
            var body: [String: Any] = ["title": title]
            if let folder = parsed.values["folder"] { body["folderId"] = folder }
            if let layout = parsed.values["layout"] { body["layout"] = layout }
            if let theme = parsed.values["theme"] { body["theme"] = theme }
            if let template = parsed.values["template"] { body["template"] = template }
            if let root = parsed.values["root-text"] { body["rootText"] = root }
            try await emit(client.request(method: "POST", path: "v1/maps", body: body), pretty: pretty)
        case "show":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape map show <id>")
            }
            try await emit(client.request(method: "GET", path: "v1/maps/\(parsed.positional[1])"), pretty: pretty)
        case "tree":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape map tree <id>")
            }
            let (data, _) = try await client.request(method: "GET", path: "v1/maps/\(parsed.positional[1])")
            try printTree(data)
        case "rename":
            guard parsed.positional.count >= 3 else {
                throw CLIError.usage("用法：mindscape map rename <id> <title>")
            }
            try await emit(client.request(
                method: "PATCH",
                path: "v1/maps/\(parsed.positional[1])",
                body: ["title": parsed.positional[2]]
            ), pretty: pretty)
        case "move":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape map move <id> --folder <id>|--root")
            }
            let folder: String
            if parsed.switches.contains("root") {
                folder = ""
            } else if let value = parsed.values["folder"] {
                folder = value
            } else {
                throw CLIError.usage("用法：mindscape map move <id> --folder <id>|--root")
            }
            try await emit(client.request(
                method: "PATCH",
                path: "v1/maps/\(parsed.positional[1])",
                body: ["folderId": folder]
            ), pretty: pretty)
        case "delete":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape map delete <id> [--permanent]")
            }
            let query = parsed.switches.contains("permanent")
                ? [URLQueryItem(name: "permanent", value: "true")]
                : []
            try await emit(client.request(
                method: "DELETE", path: "v1/maps/\(parsed.positional[1])", query: query
            ), pretty: pretty)
        case "export":
            guard parsed.positional.count >= 2, let format = parsed.values["format"], let out = parsed.values["out"] else {
                throw CLIError.usage("用法：mindscape map export <id> --format md|opml|json|png|pdf --out <path>")
            }
            var body: [String: Any] = ["format": exportFormat(format), "path": out]
            if let scale = parsed.values["scale"].flatMap(Int.init) { body["scale"] = scale }
            try await emit(client.request(
                method: "POST", path: "v1/maps/\(parsed.positional[1])/export", body: body
            ), pretty: pretty)
        case "import":
            guard let file = parsed.values["file"] else {
                throw CLIError.usage("用法：mindscape map import --file <path> [--folder ID]")
            }
            var body: [String: Any] = ["path": file]
            if let folder = parsed.values["folder"] { body["folderId"] = folder }
            if let layout = parsed.values["layout"] { body["layout"] = layout }
            if let theme = parsed.values["theme"] { body["theme"] = theme }
            try await emit(client.request(method: "POST", path: "v1/import", body: body), pretty: pretty)
        default:
            throw CLIError.usage("未知 map 命令：\(action)")
        }
    }

    // MARK: - Nodes

    private static func node(_ tokens: [String], client: AgentClient, pretty: Bool) async throws {
        let parsed = parse(tokens)
        guard let action = parsed.positional.first else {
            throw CLIError.usage("用法：mindscape node add|set|move|delete ...")
        }
        switch action {
        case "add":
            guard parsed.positional.count >= 2 else {
                throw CLIError.usage("用法：mindscape node add <mapId> --parent <nodeId> --text <text>")
            }
            var body: [String: Any] = ["text": parsed.values["text"] ?? ""]
            if let parent = parsed.values["parent"] { body["parentId"] = parent }
            if let note = parsed.values["note"] { body["note"] = note }
            if let icon = parsed.values["icon"] { body["icon"] = icon }
            if let color = parsed.values["color"] { body["color"] = color }
            if let index = parsed.values["index"].flatMap(Int.init) { body["index"] = index }
            try await emit(client.request(
                method: "POST", path: "v1/maps/\(parsed.positional[1])/nodes", body: body
            ), pretty: pretty)
        case "set":
            guard parsed.positional.count >= 3 else {
                throw CLIError.usage("用法：mindscape node set <mapId> <nodeId> [--text] [--note] [--icon] [--color] [--collapsed]")
            }
            var body: [String: Any] = [:]
            if let value = parsed.values["text"] { body["text"] = value }
            if let value = parsed.values["note"] { body["note"] = value }
            if let value = parsed.values["icon"] { body["icon"] = value }
            if let value = parsed.values["color"] { body["color"] = value }
            if let value = parsed.values["collapsed"] { body["collapsed"] = (value as NSString).boolValue }
            guard !body.isEmpty else { throw CLIError.usage("至少提供一个要修改的字段") }
            try await emit(client.request(
                method: "PATCH", path: "v1/maps/\(parsed.positional[1])/nodes/\(parsed.positional[2])", body: body
            ), pretty: pretty)
        case "move":
            guard parsed.positional.count >= 3 else {
                throw CLIError.usage("用法：mindscape node move <mapId> <nodeId> --parent <nodeId|null> [--index n]")
            }
            var body: [String: Any] = [:]
            let parent = parsed.values["parent"]
            body["parentId"] = (parent == nil || parent == "null" || parent == "") ? NSNull() : parent!
            if let index = parsed.values["index"].flatMap(Int.init) { body["index"] = index }
            try await emit(client.request(
                method: "POST",
                path: "v1/maps/\(parsed.positional[1])/nodes/\(parsed.positional[2])/move",
                body: body
            ), pretty: pretty)
        case "delete":
            guard parsed.positional.count >= 3 else {
                throw CLIError.usage("用法：mindscape node delete <mapId> <nodeId>")
            }
            try await emit(client.request(
                method: "DELETE", path: "v1/maps/\(parsed.positional[1])/nodes/\(parsed.positional[2])"
            ), pretty: pretty)
        default:
            throw CLIError.usage("未知 node 命令：\(action)")
        }
    }

    // MARK: - Generic

    private static func genericAPI(_ tokens: [String], client: AgentClient, pretty: Bool) async throws {
        let parsed = parse(tokens)
        guard parsed.positional.count >= 2 else {
            throw CLIError.usage("用法：mindscape api <METHOD> <PATH> [--body JSON]")
        }
        let method = parsed.positional[0].uppercased()
        let path = parsed.positional[1]
        var body: [String: Any]?
        if let raw = parsed.values["body"], let data = raw.data(using: .utf8) {
            body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        try await emit(client.request(method: method, path: path, body: body), pretty: pretty)
    }

    // MARK: - Output

    private static func emit(
        _ result: (Data, Int),
        pretty: Bool,
        raw: Bool = false
    ) throws {
        let data = result.0
        if raw {
            print(String(data: data, encoding: .utf8) ?? "")
            return
        }
        if pretty,
           let object = try? JSONSerialization.jsonObject(with: data),
           let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            print(String(data: formatted, encoding: .utf8) ?? "")
        } else {
            print(String(data: data, encoding: .utf8) ?? "")
        }
    }

    private static func printTree(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let nodes = payload["nodes"] as? [[String: Any]],
              let roots = payload["rootIds"] as? [String] else {
            throw CLIError.usage("无法解析导图结构")
        }
        let byParent = Dictionary(grouping: nodes) { ($0["parentId"] as? String) ?? "" }
        func walk(_ id: String, _ depth: Int) {
            guard let node = nodes.first(where: { ($0["id"] as? String) == id }) else { return }
            print(String(repeating: "  ", count: depth) + "- " + ((node["text"] as? String) ?? ""))
            for child in (byParent[id] ?? []).sorted(by: { (($0["order"] as? Int) ?? 0) < (($1["order"] as? Int) ?? 0) }) {
                if let childID = child["id"] as? String { walk(childID, depth + 1) }
            }
        }
        for rootID in roots { walk(rootID, 0) }
    }

    // MARK: - Parsing

    private struct Parsed {
        var positional: [String] = []
        var values: [String: String] = [:]
        var switches: Set<String> = []
    }

    private static func parse(_ tokens: [String]) -> Parsed {
        var result = Parsed()
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token.hasPrefix("--") {
                let raw = String(token.dropFirst(2))
                if let equals = raw.firstIndex(of: "=") {
                    let key = String(raw[..<equals])
                    result.values[key] = String(raw[raw.index(after: equals)...])
                    index += 1
                } else if index + 1 < tokens.count, !tokens[index + 1].hasPrefix("--") {
                    result.values[raw] = tokens[index + 1]
                    index += 2
                } else {
                    result.switches.insert(raw)
                    index += 1
                }
            } else {
                result.positional.append(token)
                index += 1
            }
        }
        return result
    }

    private static func exportFormat(_ value: String) -> String {
        switch value.lowercased() {
        case "md", "markdown": return "markdown"
        case "opml": return "opml"
        case "json": return "json"
        case "png": return "png"
        case "pdf": return "pdf"
        default: return value.lowercased()
        }
    }

    private static func printHelp() {
        print("""
        mindscape — operate Mindscape mind maps from the command line

        Usage:
          mindscape health
          mindscape url
          mindscape guide
          mindscape openapi
          mindscape skill install --target claude|codex|dsh|opencode|all

          mindscape folder list
          mindscape folder create <name> [--parent <id>]
          mindscape folder rename <id> <name>
          mindscape folder delete <id>

          mindscape map list [--folder <id>] [--include-deleted]
          mindscape map create <title> [--folder <id>] [--layout <name>] [--theme <id>] [--template blank|project|meeting|reading|swot|weekly]
          mindscape map show <id>
          mindscape map tree <id>
          mindscape map rename <id> <title>
          mindscape map move <id> --folder <id>|--root
          mindscape map delete <id> [--permanent]
          mindscape map export <id> --format md|opml|json|png|pdf --out <path> [--scale 1-3]
          mindscape map import --file <path> [--folder <id>]

          mindscape node add <mapId> --parent <nodeId> --text <text> [--note ...] [--icon ...] [--color ...]
          mindscape node set <mapId> <nodeId> [--text ...] [--note ...] [--icon ...] [--color ...] [--collapsed true|false]
          mindscape node move <mapId> <nodeId> --parent <nodeId|null> [--index n]
          mindscape node delete <mapId> <nodeId>

          mindscape api <METHOD> <PATH> [--body '<json>']

        Global options:
          --gateway <path>   Override the gateway descriptor path
          --no-launch        Do not try to launch Mindscape
          --pretty           Pretty-print JSON output

        All commands print JSON envelopes: {"ok":true,"data":...} or {"ok":false,"error":{...}}.
        The gateway only listens on 127.0.0.1 and requires a per-session bearer token.
        """)
    }
}

enum CLIError: LocalizedError {
    case usage(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message): return message
        }
    }
}

extension AgentClientError {
    var exitCode: Int32 {
        switch self {
        case .gatewayUnavailable: return 3
        case .http: return 4
        case .invalidResponse: return 5
        }
    }
}
