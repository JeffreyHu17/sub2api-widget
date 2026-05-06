import Foundation

struct InstanceConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: URL
    var dashboardPath: String
    var createdAt: Date

    static let production = InstanceConfig(
        id: AppConstants.defaultInstanceID,
        name: AppConstants.defaultInstanceName,
        baseURL: AppConstants.defaultBaseURL,
        dashboardPath: AppConstants.defaultDashboardPath,
        createdAt: Date(timeIntervalSince1970: 1_767_145_600)
    )
}

struct WidgetDisplayConfig: Codable, Identifiable, Hashable {
    var id: String
    var instanceID: String
    var kind: WidgetKind
    var platformFilter: PlatformID?
    var refreshIntervalSec: Int
    var timeRange: TimeRange
    var maxAccounts: Int

    static let defaultActivity = WidgetDisplayConfig(
        id: "default-activity",
        instanceID: AppConstants.defaultInstanceID,
        kind: .platformActivity,
        platformFilter: nil,
        refreshIntervalSec: RefreshInterval.five.rawValue,
        timeRange: .fiveMinutes,
        maxAccounts: 6
    )

    static let defaultServer = WidgetDisplayConfig(
        id: "default-server",
        instanceID: AppConstants.defaultInstanceID,
        kind: .serverHealth,
        platformFilter: nil,
        refreshIntervalSec: RefreshInterval.fifteen.rawValue,
        timeRange: .oneHour,
        maxAccounts: 0
    )
}

struct MonitorSnapshot: Codable, Identifiable {
    var id: String { instanceID }
    var instanceID: String
    var generatedAt: Date
    var expiresAt: Date
    var platforms: [PlatformActivity]
    var server: ServerHealth
    var authState: AuthState
    var staleReason: String?
    var diagnostics: RefreshDiagnostics

    var isStale: Bool {
        staleReason != nil || expiresAt < Date()
    }

    static func placeholder(instanceID: String = AppConstants.defaultInstanceID) -> MonitorSnapshot {
        MonitorSnapshot(
            instanceID: instanceID,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(30),
            platforms: PlatformID.allCases.map {
                PlatformActivity(
                    platform: $0,
                    currentInUse: $0 == .openai ? 1 : 0,
                    maxCapacity: $0 == .openai ? 577 : ($0 == .anthropic ? 112 : 19),
                    waitingInQueue: $0 == .openai ? 24 : 0,
                    loadPercent: $0 == .openai ? 0.2 : 0,
                    activeAccounts: $0 == .openai ? [
                        ActiveAccount(
                            accountID: 186,
                            accountName: "rorii-openai-main-account-long-name@example.com",
                            platform: .openai,
                            groupName: "default",
                            currentInUse: 1,
                            maxCapacity: 8,
                            waitingInQueue: 2,
                            loadPercent: 12.5,
                            status: "active",
                            isRateLimited: false,
                            hasError: false
                        )
                    ] : [],
                    availableCount: $0 == .openai ? 186 : ($0 == .anthropic ? 1 : 1),
                    totalAccounts: $0 == .openai ? 226 : ($0 == .anthropic ? 13 : 4),
                    rateLimitedCount: $0 == .openai ? 24 : 1,
                    errorCount: $0 == .openai ? 14 : 0
                )
            },
            server: ServerHealth.placeholder,
            authState: .sample,
            staleReason: nil,
            diagnostics: .init(lastFetchAt: Date(), nextFetchAt: Date().addingTimeInterval(5), lastSnapshotWriteAt: Date(), lastWidgetReloadRequestAt: Date(), lastWidgetRenderAt: Date(), lastError: nil)
        )
    }
}

struct PlatformActivity: Codable, Identifiable {
    var id: String { platform.rawValue }
    var platform: PlatformID
    var currentInUse: Int
    var maxCapacity: Int
    var waitingInQueue: Int
    var loadPercent: Double
    var activeAccounts: [ActiveAccount]
    var availableCount: Int
    var totalAccounts: Int
    var rateLimitedCount: Int
    var errorCount: Int

    var hasActivity: Bool {
        currentInUse > 0 || waitingInQueue > 0 || activeAccounts.contains { $0.hasActivity }
    }
}

struct ActiveAccount: Codable, Identifiable, Hashable {
    var accountID: Int64
    var accountName: String
    var platform: PlatformID
    var groupName: String
    var currentInUse: Int
    var maxCapacity: Int
    var waitingInQueue: Int
    var loadPercent: Double
    var status: String
    var isRateLimited: Bool
    var hasError: Bool

    var id: Int64 { accountID }

    var hasActivity: Bool {
        currentInUse > 0 || waitingInQueue > 0
    }
}

struct ServerHealth: Codable {
    var healthScore: Int
    var requestCount: Int64
    var tokenConsumed: Int64
    var qps: RateSummary
    var tps: RateSummary
    var slaPercent: Double
    var errorRate: Double
    var upstreamErrorRate: Double
    var durationP99: Int?
    var ttftP99: Int?
    var cpuPercent: Double?
    var memoryPercent: Double?
    var memoryUsedMB: Int64?
    var memoryTotalMB: Int64?
    var dbStatus: ServiceStatus
    var redisStatus: ServiceStatus
    var goroutines: Int?
    var queueDepth: Int?
    var jobStatus: ServiceStatus

    static let placeholder = ServerHealth(
        healthScore: 92,
        requestCount: 130,
        tokenConsumed: 13_466_000,
        qps: RateSummary(current: 0, peak: 0, avg: 0),
        tps: RateSummary(current: 1_868.7, peak: 3_740.5, avg: 1_868.7),
        slaPercent: 100,
        errorRate: 0,
        upstreamErrorRate: 0,
        durationP99: 138_393,
        ttftP99: 46_193,
        cpuPercent: 8.4,
        memoryPercent: 11.1,
        memoryUsedMB: 106,
        memoryTotalMB: 957,
        dbStatus: .ok,
        redisStatus: .ok,
        goroutines: 77,
        queueDepth: 0,
        jobStatus: .ok
    )
}

struct RateSummary: Codable, Hashable {
    var current: Double
    var peak: Double
    var avg: Double
}

enum ServiceStatus: String, Codable {
    case ok
    case warning
    case error
    case unknown

    var displayName: String {
        switch self {
        case .ok: "正常"
        case .warning: "警告"
        case .error: "异常"
        case .unknown: "未知"
        }
    }
}

struct AuthState: Codable {
    var isAuthenticated: Bool
    var userEmail: String?
    var tokenExpiresAt: Date?

    static let signedOut = AuthState(isAuthenticated: false, userEmail: nil, tokenExpiresAt: nil)
    static let sample = AuthState(isAuthenticated: true, userEmail: "admin@sub2api.local", tokenExpiresAt: Date().addingTimeInterval(3600))
}

struct RefreshDiagnostics: Codable {
    var lastFetchAt: Date?
    var nextFetchAt: Date?
    var lastSnapshotWriteAt: Date?
    var lastWidgetReloadRequestAt: Date?
    var lastWidgetRenderAt: Date?
    var lastError: String?
}

struct APIEnvelope<T: Decodable>: Decodable {
    var code: Int?
    var message: String?
    var data: T
}
