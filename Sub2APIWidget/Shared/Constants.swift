import Foundation

enum AppConstants {
    static let appGroupID = "group.top.jeffreyhjh.Sub2APIWidget"
    static let bundleID = "top.jeffreyhjh.Sub2APIWidget"
    static let agentBundleID = "top.jeffreyhjh.Sub2APIWidget.Agent"
    static let widgetBundleID = "top.jeffreyhjh.Sub2APIWidget.WidgetExtension"
    static let defaultInstanceID = "rorii-production"
    static let defaultInstanceName = "Rorii Sub2API"
    static let defaultBaseURL = URL(string: "https://api.rorii.xyz")!
    static let defaultDashboardPath = "/admin/ops"
}

/// Settings shared between the app and the background agent. Both processes
/// read the same App Group defaults so a refresh interval chosen in the UI is
/// picked up by the login item without any extra plumbing.
enum BackgroundPreferences {
    private enum Key {
        static let refreshInterval = "monitor.refreshInterval"
        static let monitoringEnabled = "monitor.enabled"
        static let backgroundServiceDesired = "monitor.backgroundServiceDesired"
        static let registeredHelperFingerprint = "monitor.registeredHelperFingerprint"
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: AppConstants.appGroupID) ?? .standard
    }

    static var refreshInterval: RefreshInterval {
        get {
            RefreshInterval(rawValue: defaults.integer(forKey: Key.refreshInterval)) ?? .five
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.refreshInterval)
        }
    }

    static var monitoringEnabled: Bool {
        get {
            guard defaults.object(forKey: Key.monitoringEnabled) != nil else { return true }
            return defaults.bool(forKey: Key.monitoringEnabled)
        }
        set {
            defaults.set(newValue, forKey: Key.monitoringEnabled)
        }
    }

    static var backgroundServiceDesired: Bool {
        get {
            guard defaults.object(forKey: Key.backgroundServiceDesired) != nil else { return true }
            return defaults.bool(forKey: Key.backgroundServiceDesired)
        }
        set {
            defaults.set(newValue, forKey: Key.backgroundServiceDesired)
        }
    }

    static var registeredHelperFingerprint: String? {
        get {
            defaults.string(forKey: Key.registeredHelperFingerprint)
        }
        set {
            defaults.set(newValue, forKey: Key.registeredHelperFingerprint)
        }
    }

    static func displayConfig(for instance: InstanceConfig) -> WidgetDisplayConfig {
        WidgetDisplayConfig(
            id: "\(instance.id)-platform-all",
            instanceID: instance.id,
            kind: .platformActivity,
            platformFilter: nil,
            refreshIntervalSec: refreshInterval.rawValue,
            timeRange: .fiveMinutes,
            maxAccounts: 6
        )
    }
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
    case accountMonitor

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .platformActivity: "平台活动"
        case .serverHealth: "服务器状态"
        case .accountMonitor: "账号监控"
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
