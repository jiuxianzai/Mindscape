import Foundation

enum RelativeDate {
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static func short(_ date: Date) -> String {
        let interval = max(Date().timeIntervalSince(date), 0)
        if interval < 60 { return "刚刚" }
        if interval < 3600 { return "\(Int(interval / 60)) 分钟前" }
        if interval < 86_400 { return "\(Int(interval / 3600)) 小时前" }
        if interval < 86_400 * 7 { return "\(Int(interval / 86_400)) 天前" }
        return absoluteFormatter.string(from: date)
    }

    static func full(_ date: Date) -> String {
        absoluteFormatter.string(from: date)
    }
}
