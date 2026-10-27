import Foundation
import XCTest
@testable import Mindscape

private final class StubUpdateService: UpdateService {
    private var results: [Result<UpdateServiceResult, Error>]
    private(set) var callCount = 0

    init(_ results: [Result<UpdateServiceResult, Error>]) {
        self.results = results
    }

    func latestRelease(etag: String?) async throws -> UpdateServiceResult {
        callCount += 1
        guard !results.isEmpty else {
            throw UpdateServiceError.invalidResponse
        }
        return try results.removeFirst().get()
    }
}

private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_700_000_000)

    func advance(hours: Double) {
        now = now.addingTimeInterval(hours * 3600)
    }
}

@MainActor
final class UpdateCheckerTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "MindscapeUpdateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeChecker(
        service: UpdateService,
        defaults: UserDefaults? = nil,
        installedVersion: String = "0.5.3",
        now: @escaping () -> Date = Date.init,
        downloads: URL? = nil,
        configuration: URLSessionConfiguration = .ephemeral,
        openURL: @escaping (URL) -> Void = { _ in },
        bannerAutoDismissDelay: Duration = .seconds(60)
    ) -> UpdateChecker {
        UpdateChecker(
            service: service,
            defaults: defaults ?? makeDefaults(),
            installedVersion: SemanticVersion(tag: installedVersion)!,
            downloadsDirectory: downloads,
            now: now,
            openURL: openURL,
            downloadConfiguration: configuration,
            bannerAutoDismissDelay: bannerAutoDismissDelay
        )
    }

    private func makeRelease(_ version: String) -> UpdateRelease {
        let semantic = SemanticVersion(tag: version)!
        let base = "https://github.com/jiuxianzai/Mindscape/releases/download/v\(version)"
        let dmg = ReleaseAsset(
            name: "Mindscape-\(version).dmg",
            byteCount: 5,
            url: URL(string: "\(base)/Mindscape-\(version).dmg")!
        )
        let zip = ReleaseAsset(
            name: "Mindscape-\(version).zip",
            byteCount: 5,
            url: URL(string: "\(base)/Mindscape-\(version).zip")!
        )
        return UpdateRelease(
            tag: "v\(version)",
            version: semantic,
            title: "Mindscape \(version)",
            notes: "## 改进\n\n- 检查更新",
            publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
            pageURL: URL(string: "https://github.com/jiuxianzai/Mindscape/releases/tag/v\(version)")!,
            dmg: dmg,
            zip: zip
        )
    }

    func testFindsNewerVersion() async {
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: "\"abc\""))])
        )
        await checker.check(manual: true)

        XCTAssertEqual(checker.phase, .available)
        XCTAssertTrue(checker.hasUpdate)
        XCTAssertTrue(checker.shouldShowBanner)
        XCTAssertEqual(checker.release?.version.description, "0.5.4")
        XCTAssertNotNil(checker.lastCheckAt)
        XCTAssertEqual(checker.installedVersionDescription, "0.5.3")
    }

    func testAutoCheckIsOffByDefault() {
        let checker = makeChecker(service: StubUpdateService([]))
        XCTAssertFalse(checker.autoCheckEnabled)
    }

    func testAutoCheckPreferencePersists() {
        let defaults = makeDefaults()
        let first = makeChecker(service: StubUpdateService([]), defaults: defaults)
        XCTAssertFalse(first.autoCheckEnabled)

        first.autoCheckEnabled = true
        let second = makeChecker(service: StubUpdateService([]), defaults: defaults)
        XCTAssertTrue(second.autoCheckEnabled)
    }

    func testFirstRunConsentIsOnlyAskedOnce() {
        let defaults = makeDefaults()
        let first = makeChecker(service: StubUpdateService([]), defaults: defaults)
        XCTAssertTrue(first.needsAutoCheckConsent)

        first.resolveAutoCheckConsent(accepted: false)
        XCTAssertFalse(first.needsAutoCheckConsent)
        XCTAssertFalse(first.autoCheckEnabled)

        let second = makeChecker(service: StubUpdateService([]), defaults: defaults)
        XCTAssertFalse(second.needsAutoCheckConsent, "只应询问一次")
        XCTAssertFalse(second.autoCheckEnabled)
    }

    func testAcceptingConsentEnablesAutoCheck() {
        let checker = makeChecker(service: StubUpdateService([]))
        XCTAssertTrue(checker.needsAutoCheckConsent)

        checker.resolveAutoCheckConsent(accepted: true)
        XCTAssertTrue(checker.autoCheckEnabled)
        XCTAssertFalse(checker.needsAutoCheckConsent)
    }

    func testExplicitPreferenceSkipsConsent() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: "updates.autoCheck")
        let checker = makeChecker(service: StubUpdateService([]), defaults: defaults)
        XCTAssertFalse(checker.needsAutoCheckConsent, "已经改过设置的用户不再弹窗")
    }

    func testBannerAutoDismissesAfterDelay() async {
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            bannerAutoDismissDelay: .milliseconds(60)
        )

        await checker.check(manual: true)
        XCTAssertTrue(checker.shouldShowBanner)

        try? await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(checker.shouldShowBanner)
        XCTAssertEqual(checker.phase, .available, "横幅消失不代表更新不可用")
    }

    func testSameVersionIsUpToDate() async {
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.3"), etag: nil))])
        )
        await checker.check(manual: true)
        XCTAssertEqual(checker.phase, .upToDate)
        XCTAssertFalse(checker.shouldShowBanner)
    }

    func testAutomaticCheckIsThrottledAndManualBypasses() async {
        let clock = TestClock()
        let service = StubUpdateService([
            .success(.release(makeRelease("0.5.4"), etag: nil)),
            .success(.release(makeRelease("0.5.4"), etag: nil))
        ])
        let checker = makeChecker(service: service, now: { clock.now })

        await checker.check(manual: false)
        XCTAssertEqual(service.callCount, 1)

        clock.advance(hours: 1)
        await checker.check(manual: false)
        XCTAssertEqual(service.callCount, 1, "24 小时内不应重复检查")

        await checker.check(manual: true)
        XCTAssertEqual(service.callCount, 2, "手动检查应绕过节流")
    }

    func testSkippedVersionIsNotShownAgainAutomatically() async {
        let clock = TestClock()
        let service = StubUpdateService([
            .success(.release(makeRelease("0.5.4"), etag: nil)),
            .success(.release(makeRelease("0.5.4"), etag: nil))
        ])
        let checker = makeChecker(service: service, now: { clock.now })

        await checker.check(manual: true)
        XCTAssertEqual(checker.phase, .available)

        checker.skipCurrentVersion()
        XCTAssertEqual(checker.phase, .idle)

        clock.advance(hours: 25)
        await checker.check(manual: false)
        XCTAssertEqual(checker.phase, .idle)
        XCTAssertEqual(service.callCount, 2)
    }

    func testSkippedVersionPersistsAcrossLaunch() async {
        let defaults = makeDefaults()
        let clock = TestClock()

        let first = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            defaults: defaults,
            now: { clock.now }
        )
        await first.check(manual: true)
        XCTAssertEqual(first.phase, .available)
        first.skipCurrentVersion()

        clock.advance(hours: 25)
        let secondService = StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))])
        let second = makeChecker(service: secondService, defaults: defaults, now: { clock.now })
        await second.check(manual: false)

        XCTAssertEqual(second.phase, .idle, "跳过记录应跨启动生效")
        XCTAssertEqual(secondService.callCount, 1)
    }

    func testManualCheckStillShowsSkippedVersion() async {
        let service = StubUpdateService([
            .success(.release(makeRelease("0.5.4"), etag: nil)),
            .success(.release(makeRelease("0.5.4"), etag: nil))
        ])
        let checker = makeChecker(service: service)

        await checker.check(manual: true)
        checker.skipCurrentVersion()
        XCTAssertEqual(checker.phase, .idle)

        await checker.check(manual: true)
        XCTAssertEqual(checker.phase, .available, "手动检查应忽略跳过记录")
    }

    func testOpenReleasePageUsesReleaseURL() async {
        var opened: URL?
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            openURL: { opened = $0 }
        )
        await checker.check(manual: true)
        checker.openReleasePage()

        XCTAssertEqual(opened, checker.release?.pageURL)
    }

    func testDismissBannerKeepsUpdateAvailable() async {
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))])
        )
        await checker.check(manual: true)
        checker.dismissBanner()

        XCTAssertEqual(checker.phase, .available)
        XCTAssertFalse(checker.shouldShowBanner)
    }

    func testBannerStaysHiddenWhenRecheckingSameVersion() async {
        let service = StubUpdateService([
            .success(.release(makeRelease("0.5.4"), etag: nil)),
            .success(.release(makeRelease("0.5.4"), etag: nil))
        ])
        let checker = makeChecker(service: service)

        await checker.check(manual: true)
        XCTAssertTrue(checker.shouldShowBanner)
        checker.dismissBanner()

        await checker.check(manual: true)
        XCTAssertEqual(checker.phase, .available)
        XCTAssertFalse(checker.shouldShowBanner, "同一版本被隐藏后，重新检查不应再弹横幅")
    }

    func testNotModifiedUsesCachedRelease() async {
        let checker = makeChecker(
            service: StubUpdateService([
                .success(.release(makeRelease("0.5.4"), etag: "\"abc\"")),
                .success(.notModified)
            ])
        )
        await checker.check(manual: true)
        await checker.check(manual: true)

        XCTAssertEqual(checker.phase, .available)
        XCTAssertEqual(checker.release?.version.description, "0.5.4")
    }

    func testManualFailureIsVisible() async {
        let checker = makeChecker(
            service: StubUpdateService([.failure(UpdateServiceError.rateLimited(retryAt: nil))])
        )
        await checker.check(manual: true)

        guard case .failed(let message) = checker.phase else {
            return XCTFail("expected failed, got \(checker.phase)")
        }
        XCTAssertTrue(message.contains("频率"))
    }

    func testAutomaticFailureStaysQuiet() async {
        let checker = makeChecker(
            service: StubUpdateService([.failure(UpdateServiceError.offline)])
        )
        await checker.check(manual: false)
        XCTAssertEqual(checker.phase, .idle)
    }

    func testDownloadVerifiesChecksumAndBecomesReady() async throws {
        let digest = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        StubURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.path.hasSuffix(".sha256") {
                return .success((Stub.response(url, 200), Data("\(digest)  file".utf8)))
            }
            return .success((
                Stub.response(url, 200, headers: ["Content-Length": "5"]),
                Data("hello".utf8)
            ))
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        var opened: URL?
        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            downloads: directory,
            configuration: Stub.configuration(),
            openURL: { opened = $0 }
        )

        await checker.check(manual: true)
        await checker.download()

        XCTAssertEqual(checker.phase, .ready)
        XCTAssertEqual(checker.checksumState, .verified)
        XCTAssertEqual(checker.downloadedFile?.lastPathComponent, "Mindscape-0.5.4.dmg")
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("Mindscape-0.5.4.dmg"), encoding: .utf8),
            "hello"
        )

        checker.openDownloaded()
        XCTAssertEqual(opened, checker.downloadedFile, "下载完成后应能打开安装包")
    }

    func testDownloadWithoutChecksumStillBecomesReady() async throws {
        StubURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.path.hasSuffix(".sha256") {
                return .success((Stub.response(url, 404), Data()))
            }
            return .success((
                Stub.response(url, 200, headers: ["Content-Length": "5"]),
                Data("hello".utf8)
            ))
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            downloads: directory,
            configuration: Stub.configuration()
        )

        await checker.check(manual: true)
        await checker.download()

        XCTAssertEqual(checker.phase, .ready)
        XCTAssertEqual(checker.checksumState, .notProvided)
    }

    func testChecksumMismatchDeletesDownload() async throws {
        StubURLProtocol.handler = { request in
            guard let url = request.url else { return .failure(URLError(.badURL)) }
            if url.path.hasSuffix(".sha256") {
                return .success((
                    Stub.response(url, 200),
                    Data(String(repeating: "a", count: 64).utf8)
                ))
            }
            return .success((
                Stub.response(url, 200, headers: ["Content-Length": "5"]),
                Data("hello".utf8)
            ))
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MindscapeUpdateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let checker = makeChecker(
            service: StubUpdateService([.success(.release(makeRelease("0.5.4"), etag: nil))]),
            downloads: directory,
            configuration: Stub.configuration()
        )

        await checker.check(manual: true)
        await checker.download()

        guard case .failed(let message) = checker.phase else {
            return XCTFail("expected failed, got \(checker.phase)")
        }
        XCTAssertTrue(message.contains("校验"))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: directory.appendingPathComponent("Mindscape-0.5.4.dmg").path)
        )
    }
}
