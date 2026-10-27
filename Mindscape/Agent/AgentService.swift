import AppKit
import Foundation

@MainActor
final class AgentService {
    private let store: DocumentStore
    private let appVersion: String
    private let onChange: (UUID?) -> Void
    private let skillInstaller: AgentSkillInstaller?
    private let openAPIData: Data?
    private let skillData: Data?

    init(
        store: DocumentStore,
        appVersion: String = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0",
        skillInstaller: AgentSkillInstaller? = AgentSkillInstaller(),
        openAPIData: Data? = AgentResources.data(named: "openapi", extension: "json"),
        skillData: Data? = AgentResources.data(named: "SKILL", extension: "md"),
        onChange: @escaping (UUID?) -> Void
    ) {
        self.store = store
        self.appVersion = appVersion
        self.skillInstaller = skillInstaller
        self.openAPIData = openAPIData
        self.skillData = skillData
        self.onChange = onChange
    }

    func handle(_ request: AgentHTTPRequest) -> AgentHTTPResponse {
        do {
            return try route(request)
        } catch let error as AgentAPIError {
            return Self.errorResponse(error)
        } catch {
            return Self.errorResponse(AgentAPIError(
                status: 500,
                code: "internal_error",
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Routing

    private func route(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        let parts = AgentPath.components(request.path)
        guard parts.first == "v1" else {
            throw AgentAPIError.notFound("未知接口")
        }

        switch (request.method, parts.count > 1 ? parts[1] : "") {
        case ("GET", "health"):
            return .json(AgentSuccessEnvelope(data: AgentHealth(status: "ok", version: appVersion, apiVersion: 1)))
        case ("GET", "openapi.json"):
            guard let data = openAPIData else { throw AgentAPIError(status: 500, code: "missing_resource", message: "OpenAPI 文档未打包") }
            return AgentHTTPResponse(status: 200, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
        case ("GET", "skill.md"):
            guard let data = skillData else { throw AgentAPIError(status: 500, code: "missing_resource", message: "Skill 文档未打包") }
            return AgentHTTPResponse(status: 200, headers: ["Content-Type": "text/markdown; charset=utf-8"], body: data)
        case ("POST", "skill") where parts.count == 3 && parts[2] == "install":
            return try installSkill(request)
        case ("GET", "folders") where parts.count == 2:
            return .json(AgentSuccessEnvelope(data: try store.folders().map(AgentFolderDTO.init)))
        case ("POST", "folders") where parts.count == 2:
            return try createFolder(request)
        case ("PATCH", "folders") where parts.count == 3:
            return try updateFolder(request, parts: parts)
        case ("DELETE", "folders") where parts.count == 3:
            return try deleteFolder(parts: parts)
        case ("GET", "maps") where parts.count == 2:
            return try listMaps(request)
        case ("GET", "maps") where parts.count == 3:
            return try showMap(parts: parts)
        case ("POST", "maps") where parts.count == 2:
            return try createMap(request)
        case ("POST", "maps") where parts.count >= 4:
            return try mapAction(request, parts: parts)
        case ("PATCH", "maps") where parts.count == 3:
            return try updateMap(request, parts: parts)
        case ("DELETE", "maps") where parts.count == 3:
            return try deleteMap(request, parts: parts)
        case ("PATCH", "maps") where parts.count >= 4:
            return try mapAction(request, parts: parts)
        case ("DELETE", "maps") where parts.count >= 4:
            return try mapAction(request, parts: parts)
        case ("POST", "import") where parts.count == 2:
            return try importMap(request)
        default:
            throw AgentAPIError.notFound("未知接口：\(request.method) \(request.path)")
        }
    }

    // MARK: - Skills

    private func installSkill(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        guard let installer = skillInstaller else {
            throw AgentAPIError(status: 503, code: "unavailable", message: "当前环境不支持安装 Skill")
        }
        let body: AgentSkillInstallBody = try decode(request.body)
        guard let target = AgentSkillInstaller.Target(rawValue: body.target) else {
            throw AgentAPIError.badRequest("未知 Agent：\(body.target)")
        }
        let result = try installer.install(target: target)
        return .json(AgentSuccessEnvelope(data: AgentSkillInstallResult(
            target: target.rawValue,
            path: result.path,
            version: result.version
        )))
    }

    // MARK: - Folders

    private func createFolder(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        let body: AgentCreateFolderBody = try decode(request.body)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AgentAPIError.badRequest("目录名不能为空") }
        try validateLength(name, field: "目录名", max: 120)

        var parentID: UUID?
        if let raw = body.parentId, !raw.isEmpty {
            parentID = try AgentPath.uuid(raw, name: "parentId")
            guard try store.folders().contains(where: { $0.id == parentID }) else {
                throw AgentAPIError.notFound("父目录不存在")
            }
        }

        let folder = try store.createFolder(name: name, parentID: parentID)
        onChange(nil)
        return .json(AgentSuccessEnvelope(data: AgentFolderDTO(folder)), status: 201)
    }

    private func updateFolder(_ request: AgentHTTPRequest, parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count == 3 else { throw AgentAPIError.notFound("目录 ID 缺失") }
        let id = try AgentPath.uuid(parts[2], name: "folderId")
        guard try store.folders().contains(where: { $0.id == id }) else {
            throw AgentAPIError.notFound("目录不存在")
        }
        let body: AgentRenameFolderBody = try decode(request.body)
        let name = body.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AgentAPIError.badRequest("目录名不能为空") }
        try store.renameFolder(id, name: name)
        onChange(nil)
        return .json(AgentSuccessEnvelope(data: ["id": id.uuidString, "name": name]))
    }

    private func deleteFolder(parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count == 3 else { throw AgentAPIError.notFound("目录 ID 缺失") }
        let id = try AgentPath.uuid(parts[2], name: "folderId")
        guard try store.folders().contains(where: { $0.id == id }) else {
            throw AgentAPIError.notFound("目录不存在")
        }
        try store.deleteFolder(id)
        onChange(nil)
        return .json(AgentSuccessEnvelope(data: ["deleted": id.uuidString]))
    }

    // MARK: - Maps

    private func listMaps(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        let includeDeleted = request.query["includeDeleted"] == "true"
        var records = try store.list(includeDeleted: includeDeleted)
        if let folder = request.query["folderId"], !folder.isEmpty {
            let id = try AgentPath.uuid(folder, name: "folderId")
            records = records.filter { $0.folderID == id }
        }
        return .json(AgentSuccessEnvelope(data: records.map(AgentMapSummary.init)))
    }

    private func createMap(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        let body: AgentCreateMapBody = try decode(request.body)
        let template = MapTemplate(rawValue: body.template ?? "blank") ?? .blank
        let layout = MapLayout(rawValue: body.layout ?? "") ?? .mindMap
        let requestedTheme = body.theme.flatMap { id in MapTheme.all.first(where: { $0.id == id }) }?.id ?? MapTheme.defaultThemeID
        let themeID = ThemePolicy.adjusted(requestedTheme, isDark: NSApplication.shared.isDarkAppearance)

        var folderID: UUID?
        if let raw = body.folderId, !raw.isEmpty {
            folderID = try AgentPath.uuid(raw, name: "folderId")
            guard try store.folders().contains(where: { $0.id == folderID }) else {
                throw AgentAPIError.notFound("目录不存在")
            }
        }

        var map = template.makeMap(themeID: themeID, layout: layout)
        if let rootText = body.rootText, !rootText.isEmpty, let rootID = map.rootIDs.first,
           let index = map.nodes.firstIndex(where: { $0.id == rootID }) {
            map.nodes[index].text = rootText
        }
        let title = body.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty { try validateLength(title, field: "标题", max: 200) }
        map.title = (title?.isEmpty == false ? title : nil) ?? map.primaryHeadText
        map.createdAt = Date()
        map.updatedAt = Date()
        try store.save(map, folderID: folderID)
        onChange(nil)
        return .json(AgentSuccessEnvelope(data: AgentMapDTO(map: map, folderID: folderID)), status: 201)
    }

    private func showMap(parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count == 3 else { throw AgentAPIError.notFound("导图 ID 缺失") }
        let id = try AgentPath.uuid(parts[2], name: "mapId")
        guard let map = try store.load(id: id) else { throw AgentAPIError.notFound("导图不存在") }
        let folderID = try store.list(includeDeleted: true).first(where: { $0.id == id })?.folderID
        return .json(AgentSuccessEnvelope(data: AgentMapDTO(map: map, folderID: folderID)))
    }

    private func updateMap(_ request: AgentHTTPRequest, parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count == 3 else { throw AgentAPIError.notFound("导图 ID 缺失") }
        let id = try AgentPath.uuid(parts[2], name: "mapId")
        var map = try loadMap(id)
        let body: AgentUpdateMapBody = try decode(request.body)

        if let title = body.title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw AgentAPIError.badRequest("标题不能为空") }
            map.title = trimmed
        }
        if let layout = body.layout {
            guard let parsed = MapLayout(rawValue: layout) else {
                throw AgentAPIError.badRequest("未知布局：\(layout)")
            }
            map.layout = parsed
        }
        if let theme = body.theme {
            guard MapTheme.all.contains(where: { $0.id == theme }) else {
                throw AgentAPIError.badRequest("未知主题：\(theme)")
            }
            guard ThemePolicy.allows(theme, isDark: NSApplication.shared.isDarkAppearance) else {
                throw AgentAPIError.badRequest("「纸白」仅浅色外观可用，深色下请使用「深空」。")
            }
            map.themeID = theme
        }
        map.updatedAt = Date()
        try store.save(map)

        if let raw = body.folderId {
            if raw.isEmpty {
                try store.setFolder(documentID: id, folderID: nil)
            } else {
                let folderID = try AgentPath.uuid(raw, name: "folderId")
                guard try store.folders().contains(where: { $0.id == folderID }) else {
                    throw AgentAPIError.notFound("目录不存在")
                }
                try store.setFolder(documentID: id, folderID: folderID)
            }
        }

        onChange(id)
        let folderID = try store.list(includeDeleted: true).first(where: { $0.id == id })?.folderID
        return .json(AgentSuccessEnvelope(data: AgentMapDTO(map: map, folderID: folderID)))
    }

    private func deleteMap(_ request: AgentHTTPRequest, parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count == 3 else { throw AgentAPIError.notFound("导图 ID 缺失") }
        let id = try AgentPath.uuid(parts[2], name: "mapId")
        guard try store.load(id: id) != nil else { throw AgentAPIError.notFound("导图不存在") }
        if request.query["permanent"] == "true" {
            try store.deletePermanently(id)
        } else {
            try store.trash(id)
        }
        onChange(id)
        return .json(AgentSuccessEnvelope(data: ["deleted": id.uuidString]))
    }

    // MARK: - Map actions (nodes / export / batch)

    private func mapAction(_ request: AgentHTTPRequest, parts: [String]) throws -> AgentHTTPResponse {
        guard parts.count >= 4 else { throw AgentAPIError.notFound("导图动作缺失") }
        let id = try AgentPath.uuid(parts[2], name: "mapId")
        let action = parts[3]

        switch action {
        case "nodes":
            return try nodeRoute(request, mapID: id, parts: parts)
        case "export":
            return try exportMap(request, mapID: id)
        case "batch":
            return try batch(request, mapID: id)
        default:
            throw AgentAPIError.notFound("未知导图动作：\(action)")
        }
    }

    private func nodeRoute(_ request: AgentHTTPRequest, mapID: UUID, parts: [String]) throws -> AgentHTTPResponse {
        if parts.count == 4, request.method == "POST" {
            return try addNode(request, mapID: mapID)
        }
        guard parts.count >= 5 else { throw AgentAPIError.notFound("节点 ID 缺失") }
        let nodeID = try AgentPath.uuid(parts[4], name: "nodeId")
        if parts.count == 6, parts[5] == "move", request.method == "POST" {
            return try moveNode(request, mapID: mapID, nodeID: nodeID)
        }
        guard parts.count == 5 else { throw AgentAPIError.notFound("未知节点操作") }
        switch request.method {
        case "PATCH":
            return try updateNode(request, mapID: mapID, nodeID: nodeID)
        case "DELETE":
            return try deleteNode(mapID: mapID, nodeID: nodeID)
        default:
            throw AgentAPIError.notFound("未知节点操作")
        }
    }

    private func addNode(_ request: AgentHTTPRequest, mapID: UUID) throws -> AgentHTTPResponse {
        let body: AgentAddNodeBody = try decode(request.body)
        var map = try loadMap(mapID)

        var parentID: UUID?
        if let raw = body.parentId, !raw.isEmpty {
            parentID = try AgentPath.uuid(raw, name: "parentId")
            guard map.node(parentID!) != nil else { throw AgentAPIError.notFound("父节点不存在") }
        }

        let text = body.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw AgentAPIError.badRequest("节点文字不能为空") }
        try validateLength(text, field: "节点文字", max: 10_000)
        if let note = body.note { try validateLength(note, field: "备注", max: 100_000) }

        let order: Int
        if let index = body.index {
            order = index
        } else if let parentID {
            order = (map.children(of: parentID).map(\.order).max() ?? -1) + 1
        } else {
            order = (map.rootIDs.compactMap { map.node($0)?.order }.max() ?? -1) + 1
        }

        let node = MindNode(
            parentID: parentID,
            text: text,
            note: body.note ?? "",
            icon: body.icon?.isEmpty == true ? nil : body.icon,
            collapsed: body.collapsed ?? false,
            order: order,
            colorHex: body.color?.isEmpty == true ? nil : body.color
        )
        map.nodes.append(node)
        map.updatedAt = Date()
        try store.save(map)
        onChange(mapID)
        return .json(AgentSuccessEnvelope(data: AgentNodeDTO(node)), status: 201)
    }

    private func updateNode(_ request: AgentHTTPRequest, mapID: UUID, nodeID: UUID) throws -> AgentHTTPResponse {
        let body: AgentUpdateNodeBody = try decode(request.body)
        var map = try loadMap(mapID)
        guard let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else {
            throw AgentAPIError.notFound("节点不存在")
        }
        if let text = body.text {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AgentAPIError.badRequest("节点文字不能为空")
            }
            try validateLength(text, field: "节点文字", max: 10_000)
            map.nodes[index].text = text
        }
        if let note = body.note { map.nodes[index].note = note }
        if let icon = body.icon { map.nodes[index].icon = icon.isEmpty ? nil : icon }
        if let color = body.color { map.nodes[index].colorHex = color.isEmpty ? nil : color }
        if let collapsed = body.collapsed { map.nodes[index].collapsed = collapsed }
        map.updatedAt = Date()
        try store.save(map)
        onChange(mapID)
        return .json(AgentSuccessEnvelope(data: AgentNodeDTO(map.nodes[index])))
    }

    private func moveNode(_ request: AgentHTTPRequest, mapID: UUID, nodeID: UUID) throws -> AgentHTTPResponse {
        let body: AgentMoveNodeBody = try decode(request.body)
        var map = try loadMap(mapID)
        guard let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else {
            throw AgentAPIError.notFound("节点不存在")
        }

        var parentID: UUID?
        if let raw = body.parentId, !raw.isEmpty {
            parentID = try AgentPath.uuid(raw, name: "parentId")
            guard let parentID else { throw AgentAPIError.badRequest("父节点无效") }
            guard map.node(parentID) != nil else { throw AgentAPIError.notFound("父节点不存在") }
            guard parentID != nodeID else { throw AgentAPIError.conflict("不能把节点移动到自身下面") }
            guard !map.isDescendant(parentID, of: nodeID) else {
                throw AgentAPIError.conflict("不能把节点移动到自己的子树里")
            }
        }

        map.nodes[index].parentID = parentID
        map.nodes[index].order = body.index ?? nextOrder(in: map, parentID: parentID)
        map.updatedAt = Date()
        try store.save(map)
        onChange(mapID)
        return .json(AgentSuccessEnvelope(data: AgentNodeDTO(map.nodes[index])))
    }

    private func deleteNode(mapID: UUID, nodeID: UUID) throws -> AgentHTTPResponse {
        var map = try loadMap(mapID)
        guard map.node(nodeID) != nil else { throw AgentAPIError.notFound("节点不存在") }
        let ids = map.subtreeIDs(of: nodeID)
        guard map.nodes.count > ids.count else {
            throw AgentAPIError.conflict("不能删除导图的全部节点")
        }
        map.nodes.removeAll { ids.contains($0.id) }
        map.updatedAt = Date()
        try store.save(map)
        onChange(mapID)
        return .json(AgentSuccessEnvelope(data: ["deleted": ids.map(\.uuidString)]))
    }

    private func batch(_ request: AgentHTTPRequest, mapID: UUID) throws -> AgentHTTPResponse {
        let body: AgentBatchBody = try decode(request.body)
        guard !body.operations.isEmpty else { throw AgentAPIError.badRequest("operations 不能为空") }
        guard body.operations.count <= 500 else { throw AgentAPIError.badRequest("单次最多 500 个操作") }

        var map = try loadMap(mapID)
        for operation in body.operations {
            try apply(operation, to: &map)
        }
        map.updatedAt = Date()
        try store.save(map)
        onChange(mapID)
        return .json(AgentSuccessEnvelope(data: AgentMapDTO(
            map: map,
            folderID: try store.list(includeDeleted: true).first(where: { $0.id == mapID })?.folderID
        )))
    }

    private func apply(_ operation: AgentBatchOperation, to map: inout MindMap) throws {
        switch operation.op {
        case "addNode":
            var parentID: UUID?
            if let raw = operation.parentId, !raw.isEmpty {
                parentID = try AgentPath.uuid(raw, name: "parentId")
                guard map.node(parentID!) != nil else { throw AgentAPIError.notFound("父节点不存在") }
            }
            let text = operation.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { throw AgentAPIError.badRequest("节点文字不能为空") }
            try validateLength(text, field: "节点文字", max: 10_000)
            let order = operation.index ?? nextOrder(in: map, parentID: parentID)
            map.nodes.append(MindNode(
                parentID: parentID,
                text: text,
                note: operation.note ?? "",
                icon: operation.icon?.isEmpty == true ? nil : operation.icon,
                collapsed: operation.collapsed ?? false,
                order: order,
                colorHex: operation.color?.isEmpty == true ? nil : operation.color
            ))
        case "updateNode":
            guard let raw = operation.nodeId else { throw AgentAPIError.badRequest("updateNode 缺少 nodeId") }
            let nodeID = try AgentPath.uuid(raw, name: "nodeId")
            guard let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else {
                throw AgentAPIError.notFound("节点不存在")
            }
            if let text = operation.text {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AgentAPIError.badRequest("节点文字不能为空")
                }
                map.nodes[index].text = text
            }
            if let note = operation.note {
                try validateLength(note, field: "备注", max: 100_000)
                map.nodes[index].note = note
            }
            if let icon = operation.icon { map.nodes[index].icon = icon.isEmpty ? nil : icon }
            if let color = operation.color { map.nodes[index].colorHex = color.isEmpty ? nil : color }
            if let collapsed = operation.collapsed { map.nodes[index].collapsed = collapsed }
        case "deleteNode":
            guard let raw = operation.nodeId else { throw AgentAPIError.badRequest("deleteNode 缺少 nodeId") }
            let nodeID = try AgentPath.uuid(raw, name: "nodeId")
            guard map.node(nodeID) != nil else { throw AgentAPIError.notFound("节点不存在") }
            let ids = map.subtreeIDs(of: nodeID)
            guard map.nodes.count > ids.count else {
                throw AgentAPIError.conflict("不能删除导图的全部节点")
            }
            map.nodes.removeAll { ids.contains($0.id) }
        case "moveNode":
            guard let raw = operation.nodeId else { throw AgentAPIError.badRequest("moveNode 缺少 nodeId") }
            let nodeID = try AgentPath.uuid(raw, name: "nodeId")
            guard let index = map.nodes.firstIndex(where: { $0.id == nodeID }) else {
                throw AgentAPIError.notFound("节点不存在")
            }
            var parentID: UUID?
            if let rawParent = operation.parentId, !rawParent.isEmpty {
                parentID = try AgentPath.uuid(rawParent, name: "parentId")
                guard map.node(parentID!) != nil else { throw AgentAPIError.notFound("父节点不存在") }
                guard parentID != nodeID, !map.isDescendant(parentID!, of: nodeID) else {
                    throw AgentAPIError.conflict("不能移动到自身或自己的子树")
                }
            }
            map.nodes[index].parentID = parentID
            map.nodes[index].order = operation.index ?? nextOrder(in: map, parentID: parentID)
        default:
            throw AgentAPIError.badRequest("未知操作：\(operation.op)")
        }
    }

    // MARK: - Export / import

    private func exportMap(_ request: AgentHTTPRequest, mapID: UUID) throws -> AgentHTTPResponse {
        let body: AgentExportBody = try decode(request.body)
        guard let format = ExportFormat(rawValue: body.format) else {
            throw AgentAPIError.badRequest("未知导出格式：\(body.format)")
        }
        let map = try loadMap(mapID)
        let scale = min(max(body.scale ?? 2, 1), 3)
        let url = try resolveFileURL(path: body.path, expectedExtension: format.fileExtension)
        let layout = LayoutEngine.layout(map)
        let data = try ExportService.makeData(map: map, layout: layout, format: format, scale: CGFloat(scale))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return .json(AgentSuccessEnvelope(data: AgentExportResult(
            path: url.path,
            format: format.rawValue,
            bytes: data.count
        )))
    }

    private func importMap(_ request: AgentHTTPRequest) throws -> AgentHTTPResponse {
        let body: AgentImportBody = try decode(request.body)
        let url = try resolveReadableFileURL(path: body.path)
        let layout = MapLayout(rawValue: body.layout ?? "") ?? .mindMap
        let requestedTheme = body.theme.flatMap { id in MapTheme.all.first(where: { $0.id == id }) }?.id ?? MapTheme.defaultThemeID
        let theme = ThemePolicy.adjusted(requestedTheme, isDark: NSApplication.shared.isDarkAppearance)
        var map = try MapImporter.load(url: url, themeID: theme, layout: layout)
        map.title = url.deletingPathExtension().lastPathComponent
        map.updatedAt = Date()

        var folderID: UUID?
        if let raw = body.folderId, !raw.isEmpty {
            folderID = try AgentPath.uuid(raw, name: "folderId")
            guard try store.folders().contains(where: { $0.id == folderID }) else {
                throw AgentAPIError.notFound("目录不存在")
            }
        }
        try store.save(map, folderID: folderID)
        onChange(nil)
        guard let record = try store.list(includeDeleted: true).first(where: { $0.id == map.id }) else {
            throw AgentAPIError(status: 500, code: "internal_error", message: "导入后无法读取导图")
        }
        return .json(AgentSuccessEnvelope(data: AgentImportResult(map: AgentMapSummary(record))), status: 201)
    }

    // MARK: - Helpers

    private func loadMap(_ id: UUID) throws -> MindMap {
        guard let map = try store.load(id: id) else { throw AgentAPIError.notFound("导图不存在") }
        return map
    }

    private func nextOrder(in map: MindMap, parentID: UUID?) -> Int {
        if let parentID {
            return (map.children(of: parentID).map(\.order).max() ?? -1) + 1
        }
        return (map.rootIDs.compactMap { map.node($0)?.order }.max() ?? -1) + 1
    }

    private func decode<T: Decodable>(_ type: T.Type, from body: Data) throws -> T {
        guard !body.isEmpty else {
            throw AgentAPIError.badRequest("请求体不能为空")
        }
        do {
            return try JSONDecoder().decode(T.self, from: body)
        } catch {
            throw AgentAPIError.badRequest("JSON 格式不正确：\(error.localizedDescription)")
        }
    }

    private func decode<T: Decodable>(_ body: Data, as type: T.Type = T.self) throws -> T {
        try decode(type, from: body)
    }

    private func resolveFileURL(path: String, expectedExtension: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw AgentAPIError.badRequest("path 必须是绝对路径或 ~ 开头")
        }
        var url = URL(fileURLWithPath: expanded).standardizedFileURL
        if url.pathExtension.isEmpty {
            url.appendPathExtension(expectedExtension)
        }
        guard url.pathExtension.lowercased() == expectedExtension.lowercased() else {
            throw AgentAPIError.badRequest("文件扩展名必须是 .\(expectedExtension)")
        }
        try assertWritableLocation(url)
        return url
    }

    private func resolveReadableFileURL(path: String) throws -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw AgentAPIError.badRequest("path 必须是绝对路径或 ~ 开头")
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        try assertWritableLocation(url)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentAPIError.notFound("文件不存在：\(url.path)")
        }
        let ext = url.pathExtension.lowercased()
        guard ["md", "markdown", "opml", "xml", "json"].contains(ext) else {
            throw AgentAPIError.badRequest("只支持 Markdown / OPML / JSON 导入")
        }
        return url
    }

    private func assertWritableLocation(_ url: URL) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let tmp = "/tmp"
        let parent = url.deletingLastPathComponent().resolvingSymlinksInPath()
        let candidates = [
            parent.appendingPathComponent(url.lastPathComponent).standardizedFileURL.path,
            url.resolvingSymlinksInPath().standardizedFileURL.path
        ]
        for path in candidates {
            guard path.hasPrefix(home + "/") || path.hasPrefix(tmp + "/") else {
                throw AgentAPIError.forbidden("只允许写入用户目录或 /tmp")
            }
            guard !path.contains("/../") else {
                throw AgentAPIError.badRequest("路径不能包含 ..")
            }
        }
    }

    private func validateLength(_ value: String, field: String, max: Int) throws {
        guard value.count <= max else {
            throw AgentAPIError.badRequest("\(field)过长（最多 \(max) 字符）")
        }
    }

    private static func errorResponse(_ error: AgentAPIError) -> AgentHTTPResponse {
        let envelope = AgentErrorEnvelope(error: AgentErrorInfo(code: error.code, message: error.message))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(envelope)) ?? Data()
        return AgentHTTPResponse(
            status: error.status,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: data
        )
    }
}

// MARK: - Batch

struct AgentBatchBody: Decodable {
    let operations: [AgentBatchOperation]
}

struct AgentBatchOperation: Decodable {
    let op: String
    let nodeId: String?
    let parentId: String?
    let text: String?
    let note: String?
    let icon: String?
    let color: String?
    let collapsed: Bool?
    let index: Int?
}

// MARK: - Resources

enum AgentResources {
    static func url(named name: String, extension ext: String?) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "AgentSkill")
            ?? Bundle.main.url(forResource: name, withExtension: ext)
    }

    static func data(named name: String, extension ext: String?) -> Data? {
        guard let url = url(named: name, extension: ext) else { return nil }
        return try? Data(contentsOf: url)
    }
}
