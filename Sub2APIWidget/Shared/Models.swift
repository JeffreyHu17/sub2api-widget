import Foundation

struct InstanceConfig: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var baseURL: URL
    var dashboardPath: String
    /// Tolerated as absent on decode: losing this non-essential field previously
    /// failed the whole instances.json decode and silently reverted the user to
    /// the default production instance. A memberwise default alone is not enough
    /// because Codable's synthesized `init(from:)` ignores defaults, so this is
    /// written out explicitly.
    var createdAt: Date

    init(
        id: String,
        name: String,
        baseURL: URL,
        dashboardPath: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.dashboardPath = dashboardPath
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decode(URL.self, forKey: .baseURL)
        dashboardPath = try container.decode(String.self, forKey: .dashboardPath)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }

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
    var accountID: Int64? = nil
    var accountIDs: [Int64]? = nil

    /// Single source of truth for which accounts a widget displays: `accountIDs`
    /// when the user picked several, otherwise the legacy single `accountID`.
    /// Empty means "auto-select schedulable accounts".
    var selectedAccountIDs: [Int64] {
        if let accountIDs, !accountIDs.isEmpty { return accountIDs }
        if let accountID { return [accountID] }
        return []
    }

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
        timeRange: .fiveMinutes,
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
    var dataState: SnapshotDataState? = .available
    var accounts: [AccountMonitor]? = nil

    var monitoredAccounts: [AccountMonitor] { accounts ?? [] }

    var isStale: Bool {
        isStale(at: Date())
    }

    func isStale(at date: Date) -> Bool {
        dataState != .available || staleReason != nil || expiresAt < date
    }

    /// Fabricated sample data for the WidgetKit gallery preview ONLY.
    ///
    /// Never return this from a real render path: a monitoring tool displaying
    /// invented figures (e.g. "226 openai accounts, health 92") destroys user
    /// trust. `Sub2APIProvider.placeholder(in:)` is the only sanctioned caller —
    /// real paths must use `unavailable(instanceID:reason:)`.
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

    static func unavailable(
        instanceID: String = AppConstants.defaultInstanceID,
        reason: String = "暂无监控数据",
        authState: AuthState = .signedOut
    ) -> MonitorSnapshot {
        MonitorSnapshot(
            instanceID: instanceID,
            generatedAt: Date(),
            expiresAt: Date(),
            platforms: PlatformID.allCases.map {
                PlatformActivity(
                    platform: $0,
                    currentInUse: 0,
                    maxCapacity: 0,
                    waitingInQueue: 0,
                    loadPercent: 0,
                    activeAccounts: [],
                    availableCount: 0,
                    totalAccounts: 0,
                    rateLimitedCount: 0,
                    errorCount: 0
                )
            },
            server: .empty,
            authState: authState,
            staleReason: reason,
            diagnostics: .empty,
            dataState: authState.isAuthenticated ? .unavailable : .signedOut
        )
    }
}

enum SnapshotDataState: String, Codable {
    case available
    case partial
    case unavailable
    case signedOut
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

struct AccountMonitor: Codable, Identifiable, Hashable {
    var id: Int64
    var name: String
    var platform: String
    var type: String
    var status: AccountHealthStatus
    var statusMessage: String?
    var schedulable: Bool
    var currentInUse: Int
    var maxConcurrency: Int
    var waitingInQueue: Int
    var activeSessions: Int?
    var maxSessions: Int?
    var currentRPM: Int?
    var baseRPM: Int?
    var quotas: [AccountQuotaWindow]
    var lastUsedAt: Date?
    var recoveryAt: Date?
    var quotaUpdatedAt: Date? = nil
    var quotaSource: String? = nil

    var loadPercent: Double {
        guard maxConcurrency > 0 else { return 0 }
        return min(max(Double(currentInUse) / Double(maxConcurrency) * 100, 0), 100)
    }

    var platformDisplayName: String {
        PlatformID(rawValue: platform)?.shortName ?? platform.uppercased()
    }

    var eligibleForAutomaticMonitoring: Bool {
        schedulable && status != .disabled
    }
}

enum AccountHealthStatus: String, Codable, Hashable {
    case healthy
    case busy
    case rateLimited
    case overloaded
    case error
    case unavailable
    case disabled

    var displayName: String {
        switch self {
        case .healthy: "正常"
        case .busy: "活动中"
        case .rateLimited: "限流"
        case .overloaded: "过载"
        case .error: "异常"
        case .unavailable: "不可用"
        case .disabled: "已停用"
        }
    }

    var sortPriority: Int {
        switch self {
        case .error: 7
        case .rateLimited: 6
        case .overloaded: 5
        case .busy: 4
        case .unavailable: 3
        case .disabled: 2
        case .healthy: 1
        }
    }
}

struct AccountQuotaWindow: Codable, Identifiable, Hashable {
    var kind: String
    var label: String
    var used: Double
    var limit: Double
    var resetAt: Date?

    var id: String { kind }
    var usedPercent: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit * 100, 0), 100)
    }
    var remaining: Double { max(limit - used, 0) }
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

    static let empty = ServerHealth(
        healthScore: 0,
        requestCount: 0,
        tokenConsumed: 0,
        qps: RateSummary(current: 0, peak: 0, avg: 0),
        tps: RateSummary(current: 0, peak: 0, avg: 0),
        slaPercent: 0,
        errorRate: 0,
        upstreamErrorRate: 0,
        durationP99: nil,
        ttftP99: nil,
        cpuPercent: nil,
        memoryPercent: nil,
        memoryUsedMB: nil,
        memoryTotalMB: nil,
        dbStatus: .unknown,
        redisStatus: .unknown,
        goroutines: nil,
        queueDepth: nil,
        jobStatus: .unknown
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

    static let empty = RefreshDiagnostics(
        lastFetchAt: nil,
        nextFetchAt: nil,
        lastSnapshotWriteAt: nil,
        lastWidgetReloadRequestAt: nil,
        lastWidgetRenderAt: nil,
        lastError: nil
    )
}

struct APIEnvelope<T: Decodable>: Decodable {
    var code: Int?
    var message: String?
    var data: T?
}
