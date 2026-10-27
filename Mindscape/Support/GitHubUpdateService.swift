import Foundation

enum UpdateServiceError: LocalizedError, Equatable {
    case rateLimited(retryAt: Date?)
    case notFound
    case noRelease
    case invalidResponse
    case httpStatus(Int)
    case offline
    case cancelled

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return String(localized: "GitHub 暂时限制了请求频率，请稍后再试。")
        case .notFound, .noRelease:
            return String(localized: "还没有可用的发布版本。")
        case .invalidResponse:
            return String(localized: "更新信息格式不正确。")
        case .httpStatus(let code):
            return String(format: String(localized: "服务器返回了 %d。"), code)
        case .offline:
            return String(localized: "网络不可用，请检查网络后重试。")
        case .cancelled:
            return String(localized: "操作已取消。")
        }
    }
}

enum UpdateServiceResult {
    case notModified
    case release(UpdateRelease, etag: String?)
}

protocol UpdateService: AnyObject {
    func latestRelease(etag: String?) async throws -> UpdateServiceResult
}

struct GitHubUpdateConfiguration {
    var repository = "jiuxianzai/Mindscape"
    var appVersion = "0"
    var assetBaseName = "Mindscape"
    var timeout: TimeInterval = 10
    /// Atom / 302 兜底时没有 assets 列表，需要 HEAD 一次确认包存在并拿到大小。
    var probeConstructedAssets = true

    var apiURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    var atomURL: URL {
        URL(string: "https://github.com/\(repository)/releases.atom")!
    }

    var latestPageURL: URL {
        URL(string: "https://github.com/\(repository)/releases/latest")!
    }

    func pageURL(tag: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/tag/\(tag)")!
    }

    func assetURL(tag: String, version: String, ext: String) -> URL {
        URL(string: "https://github.com/\(repository)/releases/download/\(tag)/\(assetBaseName)-\(version).\(ext)")!
    }

    var userAgent: String {
        "\(assetBaseName)/\(appVersion) (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))"
    }
}

/// GitHub Releases 通道：API 优先，限流时降级 Atom，再降级 302。
final class GitHubUpdateService: UpdateService {
    private let configuration: GitHubUpdateConfiguration
    private let session: URLSession

    init(configuration: GitHubUpdateConfiguration = GitHubUpdateConfiguration(),
         session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func latestRelease(etag: String?) async throws -> UpdateServiceResult {
        var firstError: Error?
        do {
            return try await fetchAPI(etag: etag)
        } catch {
            firstError = error
        }

        do {
            return try await fetchAtom()
        } catch {
            // Atom 也可能因为网络问题失败；继续试 302。
        }

        do {
            return try await fetchRedirect()
        } catch {
            throw firstError ?? error
        }
    }

    // MARK: - API

    private func fetchAPI(etag: String?) async throws -> UpdateServiceResult {
        var request = request(configuration.apiURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data
        let response: URLResponse
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }

        switch http.statusCode {
        case 304:
            return .notModified
        case 200:
            let payload: GitHubReleasePayload
            do {
                payload = try JSONDecoder().decode(GitHubReleasePayload.self, from: data)
            } catch {
                throw UpdateServiceError.invalidResponse
            }
            return .release(try makeRelease(from: payload),
                            etag: http.value(forHTTPHeaderField: "ETag"))
        case 403, 429:
            throw UpdateServiceError.rateLimited(retryAt: Self.rateLimitReset(from: http))
        case 404:
            throw UpdateServiceError.notFound
        default:
            throw UpdateServiceError.httpStatus(http.statusCode)
        }
    }

    private func makeRelease(from payload: GitHubReleasePayload) throws -> UpdateRelease {
        guard !payload.draft, !payload.prerelease else {
            throw UpdateServiceError.noRelease
        }
        guard let version = SemanticVersion(tag: payload.tagName) else {
            throw UpdateServiceError.invalidResponse
        }

        let assets: [ReleaseAsset] = payload.assets.compactMap { item in
            guard let url = URL(string: item.browserDownloadURL),
                  Self.isAllowedAssetURL(url, repository: configuration.repository) else {
                return nil
            }
            return ReleaseAsset(name: item.name, byteCount: item.size, url: url)
        }

        let dmg = pickAsset(from: assets, extension: "dmg", version: version)
        let zip = pickAsset(from: assets, extension: "zip", version: version)
        guard dmg != nil || zip != nil else {
            throw UpdateServiceError.noRelease
        }

        return UpdateRelease(
            tag: payload.tagName,
            version: version,
            title: payload.name?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                ?? "Mindscape \(version.description)",
            notes: ReleaseNotes.plainText(fromMarkdown: payload.body ?? ""),
            publishedAt: payload.publishedAt.flatMap(ISO8601DateFormatter.parse),
            pageURL: payload.htmlURL.flatMap(URL.init(string:)) ?? configuration.pageURL(tag: payload.tagName),
            dmg: dmg,
            zip: zip
        )
    }

    private func pickAsset(from assets: [ReleaseAsset], extension ext: String, version: SemanticVersion) -> ReleaseAsset? {
        let preferredName = "\(configuration.assetBaseName)-\(version.description).\(ext)".lowercased()
        if let exact = assets.first(where: { $0.name.lowercased() == preferredName }) {
            return exact
        }
        return assets.first(where: { $0.name.lowercased().hasSuffix(".\(ext)") })
    }

    // MARK: - Atom

    private func fetchAtom() async throws -> UpdateServiceResult {
        var request = request(configuration.atomURL)
        request.setValue("application/atom+xml", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            let result = try await session.data(for: request)
            data = result.0
            response = result.1
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 { throw UpdateServiceError.notFound }
            throw UpdateServiceError.httpStatus(http.statusCode)
        }
        guard let entry = ReleaseAtomParser.latestEntry(from: data),
              let version = SemanticVersion(tag: entry.tag) else {
            throw UpdateServiceError.noRelease
        }

        let release = await constructedRelease(
            tag: entry.tag,
            version: version,
            title: entry.title,
            notes: entry.notes,
            publishedAt: entry.updated,
            pageURL: entry.pageURL ?? configuration.pageURL(tag: entry.tag)
        )
        return .release(release, etag: nil)
    }

    // MARK: - 302

    private func fetchRedirect() async throws -> UpdateServiceResult {
        var request = request(configuration.latestPageURL, method: "HEAD")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let response: URLResponse
        do {
            let result = try await session.data(for: request)
            response = result.1
        } catch {
            throw Self.mapTransportError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw UpdateServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200:
            // 跟随重定向后 response.url 就是 release tag 地址。
            guard let finalURL = http.url,
                  let version = SemanticVersion(tag: finalURL.lastPathComponent) else {
                throw UpdateServiceError.invalidResponse
            }
            let tag = finalURL.lastPathComponent
            let release = await constructedRelease(
                tag: tag,
                version: version,
                title: "Mindscape \(version.description)",
                notes: "",
                publishedAt: nil,
                pageURL: finalURL
            )
            return .release(release, etag: nil)
        case 404:
            throw UpdateServiceError.notFound
        default:
            throw UpdateServiceError.httpStatus(http.statusCode)
        }
    }

    // MARK: - Helpers

    private func constructedRelease(
        tag: String,
        version: SemanticVersion,
        title: String,
        notes: String,
        publishedAt: Date?,
        pageURL: URL
    ) async -> UpdateRelease {
        let dmgURL = configuration.assetURL(tag: tag, version: version.description, ext: "dmg")
        let zipURL = configuration.assetURL(tag: tag, version: version.description, ext: "zip")

        var dmg: ReleaseAsset?
        var zip: ReleaseAsset?

        if configuration.probeConstructedAssets {
            async let dmgSize = probe(dmgURL)
            async let zipSize = probe(zipURL)
            let sizes = await (dmgSize, zipSize)
            if let size = sizes.0 {
                dmg = ReleaseAsset(name: dmgURL.lastPathComponent, byteCount: size, url: dmgURL)
            }
            if let size = sizes.1 {
                zip = ReleaseAsset(name: zipURL.lastPathComponent, byteCount: size, url: zipURL)
            }
        } else {
            dmg = ReleaseAsset(name: dmgURL.lastPathComponent, byteCount: 0, url: dmgURL)
            zip = ReleaseAsset(name: zipURL.lastPathComponent, byteCount: 0, url: zipURL)
        }

        return UpdateRelease(
            tag: tag,
            version: version,
            title: title,
            notes: notes,
            publishedAt: publishedAt,
            pageURL: pageURL,
            dmg: dmg,
            zip: zip
        )
    }

    private func probe(_ url: URL) async -> Int? {
        var request = request(url, method: "HEAD")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            let length = http.expectedContentLength
            return length > 0 ? Int(length) : 0
        } catch {
            return nil
        }
    }

    private func request(_ url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func isAllowedAssetURL(_ url: URL, repository: String) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else {
            return false
        }
        return url.path.hasPrefix("/\(repository)/releases/download/")
    }

    private static func rateLimitReset(from response: HTTPURLResponse) -> Date? {
        guard let raw = response.value(forHTTPHeaderField: "X-RateLimit-Reset"),
              let seconds = TimeInterval(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func mapTransportError(_ error: Error) -> UpdateServiceError {
        guard let urlError = error as? URLError else {
            return .invalidResponse
        }
        switch urlError.code {
        case .cancelled:
            return .cancelled
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return .offline
        default:
            return .invalidResponse
        }
    }
}

// MARK: - GitHub JSON

private struct GitHubReleasePayload: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int
        let browserDownloadURL: String

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlURL: String?
    let publishedAt: String?
    let prerelease: Bool
    let draft: Bool
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case prerelease
        case draft
        case assets
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
