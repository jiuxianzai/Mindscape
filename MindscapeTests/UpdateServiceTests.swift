import XCTest
@testable import Mindscape

final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> Result<(HTTPURLResponse, Data), Error>)?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        switch handler(request) {
        case .success(let (response, data)):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum Stub {
    static func response(
        _ url: URL,
        _ status: Int,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/2",
            headerFields: headers
        )!
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return configuration
    }
}

final class SemanticVersionTests: XCTestCase {
    func testParsing() {
        XCTAssertEqual(SemanticVersion(tag: "v0.5.10")?.description, "0.5.10")
        XCTAssertEqual(SemanticVersion(tag: "0.5")?.description, "0.5.0")
        XCTAssertEqual(SemanticVersion(tag: "1")?.description, "1.0.0")
        XCTAssertEqual(SemanticVersion(tag: "  v1.2.3  ")?.description, "1.2.3")
        XCTAssertNil(SemanticVersion(tag: ""))
        XCTAssertNil(SemanticVersion(tag: "v"))
        XCTAssertNil(SemanticVersion(tag: "release-1.0"))
        XCTAssertNil(SemanticVersion(tag: "1.2.3.4"))
        XCTAssertNil(SemanticVersion(tag: "1.a.3"))
    }

    func testOrdering() {
        XCTAssertLessThan(SemanticVersion(tag: "0.5.9")!, SemanticVersion(tag: "0.5.10")!)
        XCTAssertLessThan(SemanticVersion(tag: "0.5.3")!, SemanticVersion(tag: "0.6.0")!)
        XCTAssertLessThan(SemanticVersion(tag: "0.9.9")!, SemanticVersion(tag: "1.0.0")!)
        XCTAssertLessThan(SemanticVersion(tag: "1.0.0-beta.2")!, SemanticVersion(tag: "1.0.0")!)
        XCTAssertLessThan(SemanticVersion(tag: "1.0.0-beta.2")!, SemanticVersion(tag: "1.0.0-beta.10")!)
        XCTAssertEqual(SemanticVersion(tag: "0.5")!, SemanticVersion(tag: "0.5.0")!)
    }
}

final class ReleaseParsingTests: XCTestCase {
    private let apiJSON = """
    {
      "tag_name": "v0.5.4",
      "name": "Mindscape 0.5.4",
      "body": "## 改进\\n\\n- 下载更新更稳",
      "html_url": "https://github.com/jiuxianzai/Mindscape/releases/tag/v0.5.4",
      "published_at": "2026-10-26T12:00:00Z",
      "prerelease": false,
      "draft": false,
      "assets": [
        {
          "name": "Mindscape-0.5.4.dmg",
          "size": 4135000,
          "browser_download_url": "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.dmg"
        },
        {
          "name": "Mindscape-0.5.4.zip",
          "size": 3570000,
          "browser_download_url": "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.zip"
        }
      ]
    }
    """

    private let atomXML = """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>Release notes from Mindscape</title>
      <entry>
        <id>tag:github.com,2008:Repository/1/v0.5.4</id>
        <updated>2026-10-26T12:00:00Z</updated>
        <link rel="alternate" type="text/html" href="https://github.com/jiuxianzai/Mindscape/releases/tag/v0.5.4"/>
        <title>Mindscape 0.5.4</title>
        <content type="html">&lt;p&gt;本地优先的思维导图 &lt;strong&gt;0.5.4&lt;/strong&gt;。&lt;/p&gt;&lt;h2&gt;改进&lt;/h2&gt;&lt;ul&gt;&lt;li&gt;检查更新&lt;/li&gt;&lt;li&gt;下载完成后校验 &amp;lt;code&amp;gt;SHA-256&amp;lt;/code&amp;gt;&lt;/li&gt;&lt;/ul&gt;</content>
      </entry>
    </feed>
    """

    func testAPIDecodingAndAssetSelection() async throws {
        StubURLProtocol.handler = { request in
            .success((Stub.response(request.url!, 200), Data(self.apiJSON.utf8)))
        }
        let service = GitHubUpdateService(
            configuration: GitHubUpdateConfiguration(appVersion: "0.5.3"),
            session: Stub.session()
        )

        let result = try await service.latestRelease(etag: nil)
        guard case .release(let release, let etag) = result else {
            return XCTFail("expected release")
        }
        XCTAssertEqual(release.version, SemanticVersion(tag: "0.5.4"))
        XCTAssertEqual(release.dmg?.name, "Mindscape-0.5.4.dmg")
        XCTAssertEqual(release.dmg?.byteCount, 4_135_000)
        XCTAssertEqual(release.preferredAsset?.url.lastPathComponent, "Mindscape-0.5.4.dmg")
        XCTAssertEqual(release.notes, "改进\n\n• 下载更新更稳")
        XCTAssertNotNil(release.publishedAt)
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.com/jiuxianzai/Mindscape/releases/tag/v0.5.4")
        XCTAssertNil(etag)
    }

    func testRateLimitFallsBackToAtom() async throws {
        StubURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.host == "api.github.com" {
                return .success((Stub.response(url, 403, headers: ["X-RateLimit-Reset": "1800000000"]), Data()))
            }
            if url.path.hasSuffix(".atom") {
                return .success((Stub.response(url, 200), Data(self.atomXML.utf8)))
            }
            return .success((Stub.response(url, 404), Data()))
        }

        let configuration = GitHubUpdateConfiguration(
            appVersion: "0.5.3",
            probeConstructedAssets: false
        )
        let service = GitHubUpdateService(configuration: configuration, session: Stub.session())

        let result = try await service.latestRelease(etag: nil)
        guard case .release(let release, _) = result else {
            return XCTFail("expected release from atom")
        }
        XCTAssertEqual(release.version, SemanticVersion(tag: "0.5.4"))
        XCTAssertEqual(release.dmg?.url.absoluteString,
                       "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.dmg")
        XCTAssertFalse(release.notes.contains("<p>"))
        XCTAssertTrue(release.notes.contains("改进"))
        XCTAssertTrue(release.notes.contains("SHA-256"))
        XCTAssertNotNil(release.publishedAt)
    }

    func testFallsBackToRedirectTag() async throws {
        StubURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.host == "api.github.com" {
                return .success((Stub.response(url, 403), Data()))
            }
            if url.path.hasSuffix(".atom") {
                return .success((Stub.response(url, 404), Data()))
            }
            let tagURL = URL(string: "https://github.com/jiuxianzai/Mindscape/releases/tag/v0.5.4")!
            return .success((Stub.response(tagURL, 200), Data()))
        }

        let configuration = GitHubUpdateConfiguration(
            appVersion: "0.5.3",
            probeConstructedAssets: false
        )
        let service = GitHubUpdateService(configuration: configuration, session: Stub.session())

        let result = try await service.latestRelease(etag: nil)
        guard case .release(let release, _) = result else {
            return XCTFail("expected release from redirect")
        }
        XCTAssertEqual(release.version, SemanticVersion(tag: "0.5.4"))
        XCTAssertEqual(release.dmg?.url.absoluteString,
                       "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.dmg")
        XCTAssertTrue(release.notes.isEmpty)
    }

    func test304IsReported() async throws {        StubURLProtocol.handler = { request in
            .success((Stub.response(request.url!, 304), Data()))
        }
        let service = GitHubUpdateService(
            configuration: GitHubUpdateConfiguration(appVersion: "0.5.3"),
            session: Stub.session()
        )
        let result = try await service.latestRelease(etag: "\"abc\"")
        if case .notModified = result {
            // expected
        } else {
            XCTFail("expected notModified")
        }
    }

    func testAssetURLValidation() {
        let repository = "jiuxianzai/Mindscape"
        XCTAssertTrue(GitHubUpdateService.isAllowedAssetURL(
            URL(string: "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.dmg")!,
            repository: repository
        ))
        XCTAssertFalse(GitHubUpdateService.isAllowedAssetURL(
            URL(string: "http://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/Mindscape-0.5.4.dmg")!,
            repository: repository
        ))
        XCTAssertFalse(GitHubUpdateService.isAllowedAssetURL(
            URL(string: "https://evil.example.com/jiuxianzai/Mindscape/releases/download/v0.5.4/x.dmg")!,
            repository: repository
        ))
        XCTAssertFalse(GitHubUpdateService.isAllowedAssetURL(
            URL(string: "https://github.com/someone/other/releases/download/v0.5.4/x.dmg")!,
            repository: repository
        ))
    }

    func testAtomHTMLConversion() {
        let text = ReleaseNotes.plainText(fromHTML: "<h2>标题</h2><ul><li>一</li><li>二</li></ul><p>a &amp; b</p>")
        XCTAssertTrue(text.contains("标题"))
        XCTAssertTrue(text.contains("• 一"))
        XCTAssertTrue(text.contains("a & b"))
        XCTAssertFalse(text.contains("<"))
    }

    func testMarkdownNotesKeepLineBreaks() {
        let markdown = """
        ## 修复

        - 修正 A
        - 修正 **B**

        见 [更新日志](https://example.com/changelog)。
        """
        let text = ReleaseNotes.plainText(fromMarkdown: markdown)
        XCTAssertEqual(text, "修复\n\n• 修正 A\n• 修正 B\n\n见 更新日志。")
        XCTAssertTrue(text.contains("\n\n"))
    }
}

final class UpdateDownloadTests: XCTestCase {
    func testSHA256OfFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(
            try FileChecksum.sha256Hex(of: url),
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
    }

    func testDigestParsing() {
        let digest = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        XCTAssertEqual(FileChecksum.digest(in: "\(digest)  Mindscape-0.5.4.dmg"), digest)
        XCTAssertEqual(FileChecksum.digest(in: digest.uppercased()), digest)
        XCTAssertNil(FileChecksum.digest(in: "not a digest"))
    }

    func testDownloadOperationDeallocatesAfterCompletion() async throws {
        StubURLProtocol.handler = { request in
            .success((
                Stub.response(request.url!, 200, headers: ["Content-Length": "5"]),
                Data("hello".utf8)
            ))
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeDownloadOp-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        weak var weakOperation: FileDownloadOperation?
        do {
            let operation = FileDownloadOperation(
                destination: directory.appendingPathComponent("test.dmg"),
                configuration: Stub.configuration()
            ) { _, _ in }
            weakOperation = operation

            let request = URLRequest(url: URL(string: "https://github.com/jiuxianzai/Mindscape/releases/download/v0.5.4/test.dmg")!)
            _ = try await operation.start(with: request)
        }

        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertNil(weakOperation, "下载完成后 URLSession 不应继续持有 delegate")
    }
}
