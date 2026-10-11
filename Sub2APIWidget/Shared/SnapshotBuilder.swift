import Foundation

enum SnapshotBuilder {
    static func build(
        instanceID: String,
        concurrency: ConcurrencyResponseDTO?,
        availability: AvailabilityResponseDTO?,
        dashboard: DashboardSnapshotDTO?,
        accounts: AccountsPageDTO?,
        authState: AuthState,
        refreshInterval: Int,
        diagnostics: RefreshDiagnostics,
        staleReason: String?
    ) -> MonitorSnapshot {
        let usableConcurrency = concurrency?.enabled == true ? concurrency : nil
        let usableAvailability = availability?.enabled == true ? availability : nil
        let hasDashboard = dashboard?.overview != nil
        let availableSourceCount = [usableConcurrency != nil, usableAvailability != nil, hasDashboard, accounts != nil]
            .filter { $0 }
            .count
        let dataState: SnapshotDataState = switch availableSourceCount {
        case 4: .available
        case 1...3: .partial
        default: .unavailable
        }
        let sourceReason = staleReason ?? missingSourceReason(
            concurrency: usableConcurrency,
            availability: usableAvailability,
            hasDashboard: hasDashboard,
            hasAccounts: accounts != nil
        )

        let platforms = PlatformID.allCases.map { platform in
            buildPlatformActivity(
                platform: platform,
                concurrency: usableConcurrency,
                availability: usableAvailability
            )
        }

        return MonitorSnapshot(
            instanceID: instanceID,
            generatedAt: Date(),
            expiresAt: Date().addingTimeInterval(TimeInterval(max(refreshInterval * 2, 15))),
            platforms: platforms,
            server: buildServerHealth(overview: dashboard?.overview),
            authState: authState,
            staleReason: sourceReason,
            diagnostics: diagnostics,
            dataState: dataState,
            accounts: buildAccounts(
                page: accounts,
                concurrency: usableConcurrency,
                availability: usableAvailability
            )
        )
    }

    private static func missingSourceReason(
        concurrency: ConcurrencyResponseDTO?,
        availability: AvailabilityResponseDTO?,
        hasDashboard: Bool,
        hasAccounts: Bool
    ) -> String? {
        var missing: [String] = []
        if concurrency == nil { missing.append("并发") }
        if availability == nil { missing.append("账号可用性") }
        if !hasDashboard { missing.append("服务器") }
        if !hasAccounts { missing.append("账号") }
        return missing.isEmpty ? nil : "部分监控数据不可用：\(missing.joined(separator: "、"))"
    }

    private static func buildAccounts(
        page: AccountsPageDTO?,
        concurrency: ConcurrencyResponseDTO?,
        availability: AvailabilityResponseDTO?
    ) -> [AccountMonitor] {
        let liveAccounts = concurrency.map { Array($0.account.values) } ?? []
        let availabilityAccounts = availability.map { Array($0.account.values) } ?? []
        // Must NOT use Dictionary(uniqueKeysWithValues:): the response dictionary is
        // keyed by a server-supplied string that can differ from account_id, so a
        // duplicate account_id traps the whole process with an unrecoverable
        // fatalError. Last write wins instead.
        let concurrencyByID = liveAccounts.reduce(into: [Int64: AccountConcurrencyDTO]()) {
            $0[$1.accountID] = $1
        }
        let availabilityByID = availabilityAccounts.reduce(into: [Int64: AccountAvailabilityDTO]()) {
            $0[$1.accountID] = $1
        }

        return (page?.items ?? []).map { account in
            let live = concurrencyByID[account.id]
            let accountAvailability = availabilityByID[account.id]
            return AccountMonitor(
                id: account.id,
                name: account.name,
                platform: account.platform,
                type: account.type,
                status: accountStatus(account: account, live: live, availability: accountAvailability),
                statusMessage: accountAvailability?.errorMessage?.nilIfBlank ?? account.errorMessage?.nilIfBlank,
                schedulable: account.schedulable,
                currentInUse: live?.currentInUse ?? account.currentConcurrency,
                maxConcurrency: live?.maxCapacity ?? account.concurrency,
                waitingInQueue: live?.waitingInQueue ?? 0,
                activeSessions: account.activeSessions,
                maxSessions: account.maxSessions,
                currentRPM: account.currentRPM,
                baseRPM: account.baseRPM,
                quotas: quotaWindows(account),
                lastUsedAt: account.lastUsedAt,
                recoveryAt: earliestDate([
                    account.rateLimitResetAt,
                    account.overloadUntil,
                    account.tempUnschedulableUntil
                ])
            )
        }
        .sorted(by: sortAccounts)
    }

    private static func accountStatus(
        account: AccountListItemDTO,
        live: AccountConcurrencyDTO?,
        availability: AccountAvailabilityDTO?
    ) -> AccountHealthStatus {
        if account.status != "active" || !account.schedulable { return .disabled }
        if availability?.hasError == true || account.errorMessage?.nilIfBlank != nil { return .error }
        if availability?.isRateLimited == true { return .rateLimited }
        if availability?.isOverloaded == true { return .overloaded }
        if availability?.isAvailable == false { return .unavailable }
        if (live?.currentInUse ?? account.currentConcurrency) > 0 || (live?.waitingInQueue ?? 0) > 0 {
            return .busy
        }
        return .healthy
    }

    private static func quotaWindows(_ account: AccountListItemDTO) -> [AccountQuotaWindow] {
        var windows: [AccountQuotaWindow] = []
        appendQuota(&windows, kind: "window", label: "窗口", used: account.currentWindowCost, limit: account.windowCostLimit, resetAt: nil)
        appendQuota(&windows, kind: "daily", label: "日额度", used: account.quotaDailyUsed, limit: account.quotaDailyLimit, resetAt: parseDate(account.quotaDailyResetAt))
        appendQuota(&windows, kind: "weekly", label: "周额度", used: account.quotaWeeklyUsed, limit: account.quotaWeeklyLimit, resetAt: parseDate(account.quotaWeeklyResetAt))
        appendQuota(&windows, kind: "total", label: "总额度", used: account.quotaUsed, limit: account.quotaLimit, resetAt: nil)
        return windows.sorted { $0.usedPercent > $1.usedPercent }
    }

    private static func appendQuota(
        _ windows: inout [AccountQuotaWindow],
        kind: String,
        label: String,
        used: Double?,
        limit: Double?,
        resetAt: Date?
    ) {
        guard let limit, limit > 0 else { return }
        windows.append(AccountQuotaWindow(kind: kind, label: label, used: used ?? 0, limit: limit, resetAt: resetAt))
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func earliestDate(_ dates: [Date?]) -> Date? {
        dates.compactMap { $0 }.min()
    }

    private static func sortAccounts(_ lhs: AccountMonitor, _ rhs: AccountMonitor) -> Bool {
        if lhs.currentInUse != rhs.currentInUse { return lhs.currentInUse > rhs.currentInUse }
        if lhs.waitingInQueue != rhs.waitingInQueue { return lhs.waitingInQueue > rhs.waitingInQueue }
        if lhs.status != rhs.status { return lhs.status.sortPriority > rhs.status.sortPriority }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
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
        let loadPercent = platformConcurrency?.loadPercentage
            ?? (maxCapacity > 0 ? Double(currentInUse) / Double(maxCapacity) * 100 : 0)
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
