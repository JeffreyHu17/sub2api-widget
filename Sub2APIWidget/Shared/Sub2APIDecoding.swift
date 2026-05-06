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
            let string = try container.decode(String.self)
            if let date = DateParsers.parseSub2APIDate(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
        }
        return decoder
    }
}

extension JSONEncoder {
    static var sub2api: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

enum DateParsers {
    static func parseSub2APIDate(_ string: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: string) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
