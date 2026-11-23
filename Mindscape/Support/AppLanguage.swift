import AppKit
import Foundation

/// 界面语言。写入 App 自身的 `AppleLanguages`（与系统设置 → 语言与地区 → 应用程序 等价），
/// 下次启动时 Foundation 才会按新语言解析资源包，所以切换后需要重新打开 App。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    /// 菜单里的显示名。英文与中文都用自己的写法，不受当前界面语言影响。
    var displayName: String {
        switch self {
        case .system: return String(localized: "跟随系统")
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }

    var languageCodes: [String]? {
        switch self {
        case .system: return nil
        case .english: return ["en"]
        case .simplifiedChinese: return ["zh-Hans"]
        }
    }

    /// 当前 App 自己设过的语言（没有就代表跟随系统）。
    static var stored: AppLanguage {
        guard let domain = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? ""),
              let codes = domain["AppleLanguages"] as? [String],
              let first = codes.first else { return .system }
        if first.hasPrefix("zh") { return .simplifiedChinese }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// 只写偏好，不重启；重启后生效。
    func apply() {
        let defaults = UserDefaults.standard
        if let codes = languageCodes {
            defaults.set(codes, forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.synchronize()
    }

    /// 以新语言重新拉起当前 App，并退出本进程。
    static func relaunch() {
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.8; /usr/bin/open -n \"" + path + "\""]
        try? process.run()
        NSApp.terminate(nil)
    }
}
