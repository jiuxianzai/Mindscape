import Foundation

/// 更新检查只关心 `主.次.修订` 三段数字，构建号与预发布标签只参与排序。
struct SemanticVersion: Hashable, Comparable, Codable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    /// 接受 `0.5.3`、`v0.5.3`、`0.5`、`0.5.3-beta.1`。
    init?(tag: String) {
        var value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("v") || value.hasPrefix("V") {
            value.removeFirst()
        }
        guard !value.isEmpty else { return nil }

        let pieces = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(pieces[0])
        let prerelease = pieces.count > 1 ? String(pieces[1]) : nil

        let components = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(components.count) else { return nil }

        var numbers: [Int] = []
        for component in components {
            guard !component.isEmpty, component.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(component), number >= 0 else {
                return nil
            }
            numbers.append(number)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
        self.prerelease = (prerelease?.isEmpty == false) ? prerelease : nil
    }

    var description: String {
        var value = "\(major).\(minor).\(patch)"
        if let prerelease {
            value += "-\(prerelease)"
        }
        return value
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _):
            // 正式版高于同号预发布版
            return false
        case (_, nil):
            return true
        case let (left?, right?):
            return Self.prereleaseIsOrderedBefore(left, right)
        }
    }

    private static func prereleaseIsOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.split(separator: ".")
        let right = rhs.split(separator: ".")
        for (a, b) in zip(left, right) {
            if a == b { continue }
            if let ai = Int(a), let bi = Int(b) { return ai < bi }
            if Int(a) != nil { return true }
            if Int(b) != nil { return false }
            return a < b
        }
        return left.count < right.count
    }
}
