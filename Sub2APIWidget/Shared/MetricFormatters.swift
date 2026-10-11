import Foundation

extension Date {
    /// Sentinel used by the tolerant date decoder for values it could not parse.
    /// Anything at or before year 1 means "unknown", never a real timestamp.
    var isUnknownTimestamp: Bool {
        timeIntervalSince1970 <= -62_000_000_000
    }
}

enum MetricFormatters {
    private static let percentFormatter: NumberFormatter = makeFormatter(maxDigits: 1)
    private static let preciseFormatter: NumberFormatter = makeFormatter(maxDigits: 2)
    private static let singleDigitFormatter: NumberFormatter = makeFormatter(maxDigits: 1)

    private static func makeFormatter(maxDigits: Int) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxDigits
        return formatter
    }

    static func percent(_ value: Double, digits: Int = 1) -> String {
        let formatter = digits >= 2 ? preciseFormatter : percentFormatter
        return "\(formatter.string(from: NSNumber(value: value)) ?? "0")%"
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        let formatter = digits >= 2 ? preciseFormatter : singleDigitFormatter
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    static func compactNumber(_ value: Int64) -> String {
        let absValue = abs(value)
        if absValue >= 100_000_000 {
            return "\(decimal(Double(value) / 100_000_000, digits: 1))亿"
        }
        if absValue >= 10_000 {
            return "\(decimal(Double(value) / 10_000, digits: 1))万"
        }
        return "\(value)"
    }

    static func ms(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) ms"
    }

    static func compactMS(_ value: Int?) -> String {
        guard let value else { return "--" }
        if value >= 1_000 {
            return "\(decimal(Double(value) / 1_000, digits: value >= 10_000 ? 0 : 1))s"
        }
        return "\(value)ms"
    }

    static func clockTime(_ date: Date?) -> String {
        guard let date, !date.isUnknownTimestamp else { return "--:--:--" }
        return date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .second(.twoDigits)
        )
    }

    static func relativeTime(_ date: Date?) -> String {
        guard let date, !date.isUnknownTimestamp else { return "--" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return clockTime(date) }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m 前" }
        return "\(minutes / 60)h 前"
    }
}
