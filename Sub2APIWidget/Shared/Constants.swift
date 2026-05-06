import Foundation

enum AppConstants {
    static let appGroupID = "group.top.jeffreyhjh.Sub2APIWidget"
    static let bundleID = "top.jeffreyhjh.Sub2APIWidget"
    static let widgetBundleID = "top.jeffreyhjh.Sub2APIWidget.WidgetExtension"
    static let defaultInstanceID = "rorii-production"
    static let defaultInstanceName = "Rorii Sub2API"
    static let defaultBaseURL = URL(string: "https://api.rorii.xyz")!
    static let defaultDashboardPath = "/admin/ops"
}

enum PlatformID: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openai
    case gemini
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: "ANTHROPIC"
        case .openai: "OPENAI"
        case .gemini: "GEMINI"
        case .antigravity: "ANTIGRAVITY"
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: "Claude"
        case .openai: "OpenAI"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        }
    }
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case platformActivity
    case serverHealth

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .platformActivity: "平台活动"
        case .serverHealth: "服务器状态"
        }
    }
}

enum TimeRange: String, Codable, CaseIterable, Identifiable {
    case fiveMinutes = "5m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case sixHours = "6h"
    case twentyFourHours = "24h"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fiveMinutes: "近 5 分钟"
        case .thirtyMinutes: "近 30 分钟"
        case .oneHour: "近 1 小时"
        case .sixHours: "近 6 小时"
        case .twentyFourHours: "近 24 小时"
        }
    }
}

enum RefreshInterval: Int, Codable, CaseIterable, Identifiable {
    case five = 5
    case fifteen = 15
    case thirty = 30

    var id: Int { rawValue }
    var displayName: String { "\(rawValue)s" }
}
