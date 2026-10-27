import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class UpdateChecker {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(progress: Double, received: Int64, total: Int64)
        case ready
        case failed(String)

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    enum ChecksumState: Equatable {
        case unknown
        case notProvided
        case verified
    }

    static let checkInterval: TimeInterval = 24 * 60 * 60
    static let launchDelay: Duration = .seconds(5)

    private enum Key {
        static let autoCheck = "updates.autoCheck"
        static let lastCheckAt = "updates.lastCheckAt"
        static let skippedVersion = "updates.skippedVersion"
        static let etag = "updates.etag"
        static let cachedRelease = "updates.cachedRelease"
    }

    private(set) var phase: Phase = .idle
    private(set) var release: UpdateRelease?
    private(set) var downloadedFile: URL?
    private(set) var checksumState: ChecksumState = .unknown
    private(set) var lastCheckAt: Date?
    private(set) var bannerDismissed = false

    @ObservationIgnored private let service: UpdateService
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let installedVersion: SemanticVersion
    @ObservationIgnored private let downloadsDirectory: URL
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let downloadConfiguration: URLSessionConfiguration
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let releasePageFallback = URL(string: "https://github.com/jiuxianzai/Mindscape/releases")!

    @ObservationIgnored private var isChecking = false
    @ObservationIgnored private var downloadCancelled = false
    @ObservationIgnored private var lastReportedProgress: Double = -1
    @ObservationIgnored private var activeDownload: FileDownloadOperation?
    @ObservationIgnored private var initialCheckTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var autoCheckEnabled: Bool {
        didSet {
            guard autoCheckEnabled != oldValue else { return }
            defaults.set(autoCheckEnabled, forKey: Key.autoCheck)
            if autoCheckEnabled {
                start()
            } else {
                initialCheckTask?.cancel()
                refreshTask?.cancel()
                initialCheckTask = nil
                refreshTask = nil
            }
        }
    }

    init(
        service: UpdateService? = nil,
        defaults: UserDefaults = .standard,
        installedVersion: SemanticVersion? = nil,
        downloadsDirectory: URL? = nil,
        now: @escaping () -> Date = Date.init,
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        fileManager: FileManager = .default,
        downloadConfiguration: URLSessionConfiguration = .ephemeral,
        session: URLSession? = nil
    ) {
        let version = installedVersion ?? Self.bundleVersion
        let downloads = downloadsDirectory
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        self.defaults = defaults
        self.installedVersion = version
        self.downloadsDirectory = downloads
        self.now = now
        self.openURL = openURL
        self.fileManager = fileManager
        self.downloadConfiguration = downloadConfiguration
        self.session = session ?? URLSession(configuration: downloadConfiguration)
        self.service = service ?? GitHubUpdateService(
            configuration: GitHubUpdateConfiguration(appVersion: version.description)
        )
        self.autoCheckEnabled = defaults.object(forKey: Key.autoCheck) as? Bool ?? false
        self.lastCheckAt = defaults.object(forKey: Key.lastCheckAt) as? Date
        self.release = Self.cachedRelease(from: defaults)
    }

    // MARK: - Public state

    var installedVersionDescription: String {
        installedVersion.description
    }

    var hasUpdate: Bool {
        phase == .available
    }

    var shouldShowBanner: Bool {
        hasUpdate && !bannerDismissed
    }

    var statusDescription: String {
        switch phase {
        case .idle:
            if let lastCheckAt {
                return String(localized: "上次检查：\(RelativeDate.short(lastCheckAt))")
            }
            return String(localized: "尚未检查")
        case .checking:
            return String(localized: "正在检查…")
        case .upToDate:
            return String(localized: "已是最新版本")
        case .available:
            return String(localized: "有可用更新")
        case .downloading:
            return String(localized: "正在下载…")
        case .ready:
            return String(localized: "更新已下载")
        case .failed:
            return String(localized: "检查失败")
        }
    }

    var downloadSizeDescription: String {
        guard let release else { return "" }
        let bytes = release.downloadSize
        guard bytes > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    // MARK: - Lifecycle

    func start() {
        guard autoCheckEnabled else { return }

        if initialCheckTask == nil {
            initialCheckTask = Task { [weak self] in
                try? await Task.sleep(for: Self.launchDelay)
                guard !Task.isCancelled else { return }
                await self?.check(manual: false)
            }
        }

        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(3600))
                    guard !Task.isCancelled else { return }
                    await self?.checkIfDue()
                }
            }
        }
    }

    private func checkIfDue() async {
        guard autoCheckEnabled, phase != .checking, !phase.isDownloading else { return }
        guard let lastCheckAt else { return }
        guard now().timeIntervalSince(lastCheckAt) >= Self.checkInterval else { return }
        await check(manual: false)
    }

    func check(manual: Bool) async {
        guard !isChecking, !phase.isDownloading else { return }
        if !manual, let lastCheckAt, now().timeIntervalSince(lastCheckAt) < Self.checkInterval {
            return
        }

        isChecking = true
        defer { isChecking = false }

        let previousPhase = phase
        phase = .checking

        do {
            let result = try await service.latestRelease(etag: defaults.string(forKey: Key.etag))
            let candidate: UpdateRelease
            switch result {
            case .notModified:
                guard let cached = release ?? Self.cachedRelease(from: defaults) else {
                    phase = .upToDate
                    return
                }
                candidate = cached
            case .release(let fetched, let etag):
                candidate = fetched
                if let etag, !etag.isEmpty {
                    defaults.set(etag, forKey: Key.etag)
                } else {
                    defaults.removeObject(forKey: Key.etag)
                }
                Self.cache(fetched, in: defaults)
            }

            release = candidate
            lastCheckAt = now()
            defaults.set(lastCheckAt, forKey: Key.lastCheckAt)
            apply(candidate, manual: manual)
        } catch {
            if manual {
                phase = .failed(Self.message(for: error))
            } else {
                phase = previousPhase == .available ? .available : .idle
            }
        }
    }

    private func apply(_ candidate: UpdateRelease, manual: Bool) {
        guard candidate.version > installedVersion else {
            phase = .upToDate
            return
        }

        if !manual, defaults.string(forKey: Key.skippedVersion) == candidate.version.description {
            phase = .idle
            return
        }

        phase = .available
        bannerDismissed = false
    }

    // MARK: - Banner & release page

    func dismissBanner() {
        bannerDismissed = true
    }

    func skipCurrentVersion() {
        guard let release else { return }
        defaults.set(release.version.description, forKey: Key.skippedVersion)
        bannerDismissed = true
        phase = .idle
    }

    func openReleasePage() {
        openURL(release?.pageURL ?? releasePageFallback)
    }

    // MARK: - Download

    func download() async {
        guard case .available = phase,
              let release,
              let asset = release.preferredAsset else { return }

        let fileName = Self.safeFileName(asset.name)
        let destination = downloadsDirectory.appendingPathComponent(fileName)

        downloadCancelled = false
        lastReportedProgress = -1
        downloadedFile = nil
        checksumState = .unknown
        phase = .downloading(progress: 0, received: 0, total: Int64(max(asset.byteCount, 0)))

        let operation = FileDownloadOperation(
            destination: destination,
            configuration: downloadConfiguration
        ) { [weak self] received, total in
            Task { @MainActor in
                self?.reportDownloadProgress(received: received, total: total)
            }
        }
        activeDownload = operation

        var request = URLRequest(url: asset.url)
        request.timeoutInterval = 60
        request.setValue(
            "Mindscape/\(installedVersion.description) (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let file = try await operation.start(with: request)
            activeDownload = nil
            await finishDownload(file: file, release: release)
        } catch {
            activeDownload = nil
            handleDownloadError(error)
        }
    }

    func cancelDownload() {
        guard phase.isDownloading else { return }
        downloadCancelled = true
        activeDownload?.cancel()
        activeDownload = nil
        phase = .available
    }

    private func reportDownloadProgress(received: Int64, total: Int64) {
        guard phase.isDownloading else { return }
        let expected = total > 0 ? total : Int64(release?.downloadSize ?? 0)
        let progress = expected > 0 ? min(1, Double(received) / Double(expected)) : 0

        guard progress - lastReportedProgress >= 0.01 || progress >= 1 else { return }
        lastReportedProgress = progress
        phase = .downloading(progress: progress, received: received, total: expected)
    }

    private func finishDownload(file: URL, release: UpdateRelease) async {
        guard !downloadCancelled else { return }

        if let checksumURL = release.checksumURL,
           let expected = await fetchChecksum(checksumURL) {
            do {
                let actual = try FileChecksum.sha256Hex(of: file)
                guard actual == expected else {
                    try? fileManager.removeItem(at: file)
                    phase = .failed(String(localized: "下载文件校验失败，已删除，请重新下载。"))
                    return
                }
                checksumState = .verified
            } catch {
                try? fileManager.removeItem(at: file)
                phase = .failed(String(localized: "无法读取下载文件：\(error.localizedDescription)"))
                return
            }
        } else {
            checksumState = .notProvided
        }

        downloadedFile = file
        phase = .ready
    }

    private func handleDownloadError(_ error: Error) {
        if downloadCancelled {
            downloadCancelled = false
            phase = .available
            return
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            phase = .available
            return
        }
        phase = .failed(String(localized: "下载失败：\(error.localizedDescription)"))
    }

    private func fetchChecksum(_ url: URL) async -> String? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "Mindscape/\(installedVersion.description) (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return FileChecksum.digest(in: text)
    }

    func openDownloaded() {
        guard let downloadedFile else { return }
        openURL(downloadedFile)
    }

    func revealDownloaded() {
        guard let downloadedFile else { return }
        NSWorkspace.shared.activateFileViewerSelecting([downloadedFile])
    }

    // MARK: - Helpers

    private static func message(for error: Error) -> String {
        guard let serviceError = error as? UpdateServiceError else {
            return String(localized: "检查更新失败：\(error.localizedDescription)")
        }
        return serviceError.errorDescription ?? String(localized: "检查更新失败。")
    }

    private static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Mindscape-update.dmg" : cleaned
    }

    private static func cache(_ release: UpdateRelease, in defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(release) else { return }
        defaults.set(data, forKey: Key.cachedRelease)
    }

    private static func cachedRelease(from defaults: UserDefaults) -> UpdateRelease? {
        guard let data = defaults.data(forKey: Key.cachedRelease) else { return nil }
        return try? JSONDecoder().decode(UpdateRelease.self, from: data)
    }

    static var bundleVersion: SemanticVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        return SemanticVersion(tag: raw) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }
}
