import Foundation

extension String {
    /// 运行时按当前语言查表。用于 `Text(String)`、`Text(verbatim:)` 等不会自动本地化的场景。
    var l10n: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}
