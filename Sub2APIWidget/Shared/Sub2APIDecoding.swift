import Foundation

struct AuthResponseDTO: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
    var tokenType: String?
    var user: UserDTO?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct TotpChallengeDTO: Decodable {
    var requires2FA: Bool
    var tempToken: String?
    var userEmailMasked: String?

    enum CodingKeys: String, CodingKey {
        case requires2FA = "requires_2fa"
        case tempToken = "temp_token"
        case userEmailMasked = "user_email_masked"
    }
}

struct UserDTO: Decodable {
    var id: Int64?
    var email: String?
    var role: String?
    var runMode: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case role
        case runMode = "run_mode"
    }
}

struct ConcurrencyResponseDTO: Decodable {
    var enabled: Bool
    var platform: [String: PlatformConcurrencyDTO]
    var account: [String: AccountConcurrencyDTO]
    var timestamp: Date?
}

struct PlatformConcurrencyDTO: Decodable {
    var platform: String
    var currentInUse: Int
    var maxCapacity: Int
    var loadPercentage: Double
    var waitingInQueue: Int

    enum CodingKeys: String, CodingKey {
        case platform
        case currentInUse = "current_in_use"
        case maxCapacity = "max_capacity"
        case loadPercentage = "load_percentage"
        case waitingInQueue = "waiting_in_queue"
    }
}

struct AccountConcurrencyDTO: Decodable {
    var accountID: Int64
    var accountName: String?
    var platform: String
    var groupID: Int64?
    var groupName: String?
    var currentInUse: Int
    var maxCapacity: Int
    var loadPercentage: Double
    var waitingInQueue: Int

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case accountName = "account_name"
        case platform
        case groupID = "group_id"
        case groupName = "group_name"
        case currentInUse = "current_in_use"
        case maxCapacity = "max_capacity"
        case loadPercentage = "load_percentage"
        case waitingInQueue = "waiting_in_queue"
    }
}

struct AvailabilityResponseDTO: Decodable {
    var enabled: Bool
    var platform: [String: PlatformAvailabilityDTO]
    var account: [String: AccountAvailabilityDTO]
    var timestamp: Date?
}

struct PlatformAvailabilityDTO: Decodable {
    var platform: String
    var totalAccounts: Int
    var availableCount: Int
    var rateLimitCount: Int
    var errorCount: Int

    enum CodingKeys: String, CodingKey {
        case platform
        case totalAccounts = "total_accounts"
        case availableCount = "available_count"
        case rateLimitCount = "rate_limit_count"
        case errorCount = "error_count"
    }
}

struct AccountAvailabilityDTO: Decodable {
    var accountID: Int64
    var accountName: String
    var platform: String
    var groupName: String?
    var status: String
    var isAvailable: Bool
    var isRateLimited: Bool
    var isOverloaded: Bool
    var hasError: Bool
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case accountID = "account_id"
        case accountName = "account_name"
        case platform
        case groupName = "group_name"
        case status
        case isAvailable = "is_available"
        case isRateLimited = "is_rate_limited"
        case isOverloaded = "is_overloaded"
        case hasError = "has_error"
        case errorMessage = "error_message"
    }
}

struct AccountsPageDTO: Decodable, Sendable {
    var items: [AccountListItemDTO]
    var total: Int64
    var page: Int
    var pageSize: Int
    var pages: Int

    enum CodingKeys: String, CodingKey {
        case items, total, page, pages
        case pageSize = "page_size"
    }
}

struct AccountListItemDTO: Decodable, Sendable {
    var id: Int64
    var name: String
    var platform: String
    var type: String
    var concurrency: Int
    var currentConcurrency: Int
    var status: String
    var errorMessage: String?
    var schedulable: Bool
    var lastUsedAt: Date?
    var rateLimitResetAt: Date?
    var overloadUntil: Date?
    var tempUnschedulableUntil: Date?
    var quotaLimit: Double?
    var quotaUsed: Double?
    var quotaDailyLimit: Double?
    var quotaDailyUsed: Double?
    var quotaWeeklyLimit: Double?
    var quotaWeeklyUsed: Double?
    var quotaDailyResetAt: String?
    var quotaWeeklyResetAt: String?
    var currentWindowCost: Double?
    var windowCostLimit: Double?
    var activeSessions: Int?
    var maxSessions: Int?
    var currentRPM: Int?
    var baseRPM: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, platform, type, concurrency, status, schedulable
        case currentConcurrency = "current_concurrency"
        case errorMessage = "error_message"
        case lastUsedAt = "last_used_at"
        case rateLimitResetAt = "rate_limit_reset_at"
        case overloadUntil = "overload_until"
        case tempUnschedulableUntil = "temp_unschedulable_until"
        case quotaLimit = "quota_limit"
        case quotaUsed = "quota_used"
        case quotaDailyLimit = "quota_daily_limit"
        case quotaDailyUsed = "quota_daily_used"
        case quotaWeeklyLimit = "quota_weekly_limit"
        case quotaWeeklyUsed = "quota_weekly_used"
        case quotaDailyResetAt = "quota_daily_reset_at"
        case quotaWeeklyResetAt = "quota_weekly_reset_at"
        case currentWindowCost = "current_window_cost"
        case windowCostLimit = "window_cost_limit"
        case activeSessions = "active_sessions"
        case maxSessions = "max_sessions"
        case currentRPM = "current_rpm"
        case baseRPM = "base_rpm"
    }
}

struct DashboardSnapshotDTO: Decodable {
    var generatedAt: Date?
    var overview: DashboardOverviewDTO?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case overview
    }
}

struct DashboardOverviewDTO: Decodable {
    var healthScore: Int?
    var systemMetrics: SystemMetricsDTO?
    var jobHeartbeats: [JobHeartbeatDTO]?
    var requestCountTotal: Int64?
    var tokenConsumed: Int64?
    var sla: Double?
    var errorRate: Double?
    var upstreamErrorRate: Double?
    var qps: RateSummary?
    var tps: RateSummary?
    var duration: PercentilesDTO?
    var ttft: PercentilesDTO?

    enum CodingKeys: String, CodingKey {
        case healthScore = "health_score"
        case systemMetrics = "system_metrics"
        case jobHeartbeats = "job_heartbeats"
        case requestCountTotal = "request_count_total"
        case tokenConsumed = "token_consumed"
        case sla
        case errorRate = "error_rate"
        case upstreamErrorRate = "upstream_error_rate"
        case qps
        case tps
        case duration
        case ttft
    }
}

struct PercentilesDTO: Decodable {
    var p50: Int?
    var p90: Int?
    var p95: Int?
    var p99: Int?
    var avg: Int?
    var max: Int?

    enum CodingKeys: String, CodingKey {
        case p50 = "p50_ms"
        case p90 = "p90_ms"
        case p95 = "p95_ms"
        case p99 = "p99_ms"
        case avg = "avg_ms"
        case max = "max_ms"
    }
}

struct SystemMetricsDTO: Decodable {
    var cpuUsagePercent: Double?
    var memoryUsedMB: Int64?
    var memoryTotalMB: Int64?
    var memoryUsagePercent: Double?
    var dbOK: Bool?
    var redisOK: Bool?
    var goroutineCount: Int?
    var concurrencyQueueDepth: Int?

    enum CodingKeys: String, CodingKey {
        case cpuUsagePercent = "cpu_usage_percent"
        case memoryUsedMB = "memory_used_mb"
        case memoryTotalMB = "memory_total_mb"
        case memoryUsagePercent = "memory_usage_percent"
        case dbOK = "db_ok"
        case redisOK = "redis_ok"
        case goroutineCount = "goroutine_count"
        case concurrencyQueueDepth = "concurrency_queue_depth"
    }
}

struct JobHeartbeatDTO: Decodable {
    var jobName: String
    var lastError: String?

    enum CodingKeys: String, CodingKey {
        case jobName = "job_name"
        case lastError = "last_error"
    }
}

extension JSONDecoder {
    static var sub2api: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            // Some servers send epoch seconds/milliseconds as a JSON number rather
            // than an ISO8601 string, so accept both shapes before giving up.
            var text: String? = try? container.decode(String.self)
            if text == nil, let number = try? container.decode(Double.self) {
                text = String(number)
            }
            guard let value = text else { return Date.distantPast }
            if let date = DateParsers.parseSub2APIDate(value) {
                return date
            }
            if let epoch = TimeInterval(value), epoch.isFinite {
                return Date(timeIntervalSince1970: epoch > 1_000_000_000_000 ? epoch / 1000 : epoch)
            }
            // Degrade a malformed date instead of throwing: throwing here would fail
            // the decode of the ENTIRE snapshot, hiding all other valid metrics.
            return Date.distantPast
        }
        return decoder
    }
}

extension JSONEncoder {
    static var sub2api: JSONEncoder {
        let encoder = JSONEncoder()
        // prettyPrinted inflated snapshots ~47% for no benefit: these files are
        // machine-written and rewritten every poll cycle.
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum DateParsers {
    // Building an ISO8601DateFormatter costs ~326us (measured), so per-parse
    // allocation dominated decoding. These caches are guarded by `lock` because
    // Swift 6 concurrency checking rejects a non-Sendable global; ISO8601DateFormatter
    // has no thread-safety guarantee, hence the lock rather than an unchecked static.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fractionalCache: ISO8601DateFormatter?
    nonisolated(unsafe) private static var plainCache: ISO8601DateFormatter?
    nonisolated(unsafe) private static var spaceSeparatedCache: DateFormatter?

    private static var fractional: ISO8601DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let fractionalCache { return fractionalCache }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        fractionalCache = formatter
        return formatter
    }

    private static var plain: ISO8601DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let plainCache { return plainCache }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        plainCache = formatter
        return formatter
    }

    private static var spaceSeparated: DateFormatter {
        lock.lock()
        defer { lock.unlock() }
        if let spaceSeparatedCache { return spaceSeparatedCache }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        spaceSeparatedCache = formatter
        return formatter
    }

    static func parseSub2APIDate(_ string: String) -> Date? {
        if let date = fractional.date(from: string) {
            return date
        }
        if let date = plain.date(from: string) {
            return date
        }
        return spaceSeparated.date(from: string)
    }
}
