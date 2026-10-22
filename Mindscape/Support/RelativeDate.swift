import Foundation

enum RelativeDate {
    static func short(_ date: Date) -> String {
        let interval = max(Date().timeIntervalSince(date), 0)
        if interval < 60 { return String(localized: "刚刚") }
        if interval < 86_400 * 7 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: Date())
        }
        return full(date)
    }

    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
