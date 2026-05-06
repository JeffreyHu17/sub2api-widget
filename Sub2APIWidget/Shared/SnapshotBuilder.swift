import Foundation

enum SnapshotBuilder {
    static func build(
        instanceID: String,
        concurrency: ConcurrencyResponseDTO?,
        availability: AvailabilityResponseDTO?,
        dashboard: DashboardSnapshotDTO?,
        authState: AuthState,
        refreshInterval: Int,
        diagnostics: RefreshDiagnostics,
        staleReason: String?
    ) -> MonitorSnapshot {
        let platforms = PlatformID.allCases.map { platform in
            buildPlatformActivity(
                platform: platform,
                concurrency: concurrency,
                availability: availability
            )
        }

        return MonitorSnapshot(
            instanceID: instanceID,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(max(refreshInterval * 2, 15))),
            platforms: platforms,
            server: buildServerHealth(overview: dashboard?.overview),
            authState: authState,
            staleReason: staleReason,
            diagnostics: diagnostics
        )
    }

    private static func buildPlatformActivity(
        platform: PlatformID,
        concurrency: ConcurrencyResponseDTO?,
        availability: AvailabilityResponseDTO?
    ) -> PlatformActivity {
        let platformConcurrency = concurrency?.platform[platform.rawValue]
        let platformAvailability = availability?.platform[platform.rawValue]
        let availabilityAccounts = availability?.account.reduce(into: [Int64: AccountAvailabilityDTO]()) { partial, item in
            partial[item.value.accountID] = item.value
        } ?? [:]

        let rawAccounts: [AccountConcurrencyDTO]
        if let accountMap = concurrency?.account {
            rawAccounts = Array(accountMap.values)
        } else {
            rawAccounts = []
        }
        let matchingAccounts = rawAccounts.filter { account in
            account.platform == platform.rawValue && (account.currentInUse > 0 || account.waitingInQueue > 0)
        }
        let accounts = matchingAccounts
            .map { account in
                buildActiveAccount(
                    account: account,
                    platform: platform,
                    availability: availabilityAccounts[account.accountID]
                )
            }
            .sorted(by: sortActiveAccounts)

        let fallbackCurrent = accounts.reduce(0) { partial, account in partial + account.currentInUse }
        let fallbackCapacity = accounts.reduce(0) { partial, account in partial + account.maxCapacity }
        let fallbackQueue = accounts.reduce(0) { partial, account in partial + account.waitingInQueue }
        let currentInUse = platformConcurrency?.currentInUse ?? fallbackCurrent
        let maxCapacity = platformConcurrency?.maxCapacity ?? fallbackCapacity
        let waitingInQueue = platformConcurrency?.waitingInQueue ?? fallbackQueue
        let loadPercent = platformConcurrency?.loadPercentage ?? 0
        let availableCount = platformAvailability?.availableCount ?? 0
        let totalAccounts = platformAvailability?.totalAccounts ?? 0
        let rateLimitedCount = platformAvailability?.rateLimitCount ?? 0
        let errorCount = platformAvailability?.errorCount ?? 0

        return PlatformActivity(
            platform: platform,
            currentInUse: currentInUse,
            maxCapacity: maxCapacity,
            waitingInQueue: waitingInQueue,
            loadPercent: loadPercent,
            activeAccounts: accounts,
            availableCount: availableCount,
            totalAccounts: totalAccounts,
            rateLimitedCount: rateLimitedCount,
            errorCount: errorCount
        )
    }

    private static func buildActiveAccount(
        account: AccountConcurrencyDTO,
        platform: PlatformID,
        availability: AccountAvailabilityDTO?
    ) -> ActiveAccount {
        let accountName = account.accountName?.nilIfBlank ?? availability?.accountName ?? "#\(account.accountID)"
        let groupName = account.groupName?.nilIfBlank ?? availability?.groupName?.nilIfBlank ?? "default"

        return ActiveAccount(
            accountID: account.accountID,
            accountName: accountName,
            platform: platform,
            groupName: groupName,
            currentInUse: account.currentInUse,
            maxCapacity: account.maxCapacity,
            waitingInQueue: account.waitingInQueue,
            loadPercent: account.loadPercentage,
            status: availability?.status ?? "active",
            isRateLimited: availability?.isRateLimited ?? false,
            hasError: availability?.hasError ?? false
        )
    }

    private static func sortActiveAccounts(_ lhs: ActiveAccount, _ rhs: ActiveAccount) -> Bool {
        if lhs.currentInUse != rhs.currentInUse {
            return lhs.currentInUse > rhs.currentInUse
        }
        if lhs.waitingInQueue != rhs.waitingInQueue {
            return lhs.waitingInQueue > rhs.waitingInQueue
        }
        return lhs.accountName.localizedStandardCompare(rhs.accountName) == .orderedAscending
    }

    private static func buildServerHealth(overview: DashboardOverviewDTO?) -> ServerHealth {
        let system = overview?.systemMetrics
        let jobStatus: ServiceStatus = {
            guard let jobs = overview?.jobHeartbeats, !jobs.isEmpty else { return .unknown }
            return jobs.contains { ($0.lastError ?? "").isEmpty == false } ? .warning : .ok
        }()

        return ServerHealth(
            healthScore: overview?.healthScore ?? 0,
            requestCount: overview?.requestCountTotal ?? 0,
            tokenConsumed: overview?.tokenConsumed ?? 0,
            qps: overview?.qps ?? RateSummary(current: 0, peak: 0, avg: 0),
            tps: overview?.tps ?? RateSummary(current: 0, peak: 0, avg: 0),
            slaPercent: overview?.sla ?? 0,
            errorRate: overview?.errorRate ?? 0,
            upstreamErrorRate: overview?.upstreamErrorRate ?? 0,
            durationP99: overview?.duration?.p99,
            ttftP99: overview?.ttft?.p99,
            cpuPercent: system?.cpuUsagePercent,
            memoryPercent: system?.memoryUsagePercent,
            memoryUsedMB: system?.memoryUsedMB,
            memoryTotalMB: system?.memoryTotalMB,
            dbStatus: status(for: system?.dbOK),
            redisStatus: status(for: system?.redisOK),
            goroutines: system?.goroutineCount,
            queueDepth: system?.concurrencyQueueDepth,
            jobStatus: jobStatus
        )
    }

    private static func status(for ok: Bool?) -> ServiceStatus {
        guard let ok else { return .unknown }
        return ok ? .ok : .error
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
