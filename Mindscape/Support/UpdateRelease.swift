import Foundation

struct ReleaseAsset: Hashable, Codable {
    let name: String
    let byteCount: Int
    let url: URL
}

/// 一次「最新版本」查询的归一化结果，API / Atom / 302 三个通道都落到这里。
struct UpdateRelease: Hashable, Codable {
    let tag: String
    let version: SemanticVersion
    let title: String
    let notes: String
    let publishedAt: Date?
    let pageURL: URL
    let dmg: ReleaseAsset?
    let zip: ReleaseAsset?

    var preferredAsset: ReleaseAsset? {
        dmg ?? zip
    }

    var checksumURL: URL? {
        preferredAsset?.url.appendingPathExtension("sha256")
    }

    var downloadSize: Int {
        preferredAsset?.byteCount ?? 0
    }
}
