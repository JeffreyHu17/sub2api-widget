import Foundation

enum Sub2APIError: LocalizedError, Sendable {
    case invalidResponse
    case apiError(String)
    case unauthorized
    case sessionExpired(reason: String?)
    case missingToken
    case insecureBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Sub2API"
        case .apiError(let message): message
        case .unauthorized: "Session expired. Please log in again."
        case .sessionExpired(let reason): reason ?? "Session expired. Please log in again."
        case .missingToken: "Missing access token"
        case .insecureBaseURL: "Refusing to send credentials to an insecure or invalid Base URL"
        }
    }
}

/// One monitoring source's result. Failure is carried, not thrown, so a single bad
/// endpoint degrades the snapshot to `partial` instead of discarding everything.
struct SourceOutcome<Value: Sendable>: Sendable {
    var value: Value?
    var failure: String?

    /// Non-nil only when this source failed because the session is unauthorized.
    var fatalError: Sub2APIError? {
        guard failure == Sub2APIError.unauthorized.localizedDescription else { return nil }
        return .unauthorized
    }
}

enum SourceSummary {
    static func combine(_ failures: [String?]) -> String? {
        let messages = failures.compactMap { $0 }
        guard !messages.isEmpty else { return nil }
        return messages.joined(separator: "；")
    }
}

actor Sub2APIClient {
    private let instance: InstanceConfig
    private let session: URLSession

    init(instance: InstanceConfig, session: URLSession = .shared) {
        self.instance = instance
        self.session = session
    }

    func refreshToken(_ refreshToken: String) async throws -> AuthTokenBundle {
        struct Request: Encodable {
            var refresh_token: String
        }

        let response: AuthResponseDTO = try await post(
            path: "/api/v1/auth/refresh",
            body: Request(refresh_token: refreshToken),
            accessToken: nil
        )

        return AuthTokenBundle(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            userEmail: response.user?.email,
            origin: instance.baseURL.normalizedOrigin
        )
    }

    func validateAdminSession(accessToken: String) async throws {
        let _: ConcurrencyResponseDTO = try await get(
            path: "/api/v1/admin/ops/concurrency",
            query: [URLQueryItem(name: "timezone", value: TimeZone.current.identifier)],
            accessToken: accessToken
        )
    }

    func fetchSnapshot(tokens: AuthTokenBundle, config: WidgetDisplayConfig) async throws -> MonitorSnapshot {
        var currentTokens = tokens
        do {
            return try await fetchSnapshotOnce(tokens: currentTokens, config: config)
        } catch Sub2APIError.unauthorized {
            guard let refresh = tokens.refreshToken else {
                throw Sub2APIError.unauthorized
            }
            do {
                currentTokens = try await refreshToken(refresh)
            } catch let error as Sub2APIError {
                // A failed refresh means the session is genuinely dead. Flag it so the
                // poller stops instead of hammering the API, but keep the distinction
                // from a transient network fault.
                throw Sub2APIError.sessionExpired(reason: error.errorDescription ?? "登录已失效")
            }
            try KeychainStore.saveTokens(currentTokens, for: instance)
            return try await fetchSnapshotOnce(tokens: currentTokens, config: config)
        }
    }

    private func fetchSnapshotOnce(tokens: AuthTokenBundle, config: WidgetDisplayConfig) async throws -> MonitorSnapshot {
        let fetchAt = Date()

        // Fetch the sources concurrently, but settle them independently: a single
        // failing endpoint must degrade to `partial` instead of voiding the whole
        // snapshot. Only a 401 is fatal, because it invalidates every source at once.
        async let concurrencyOutcome: SourceOutcome<ConcurrencyResponseDTO> =
            fetchSource(path: "/api/v1/admin/ops/concurrency", query: monitorQuery(config: config, includeTimeRange: false), accessToken: tokens.accessToken)
        async let availabilityOutcome: SourceOutcome<AvailabilityResponseDTO> =
            fetchSource(path: "/api/v1/admin/ops/account-availability", query: monitorQuery(config: config, includeTimeRange: false), accessToken: tokens.accessToken)
        async let dashboardOutcome: SourceOutcome<DashboardSnapshotDTO> =
            fetchSource(path: "/api/v1/admin/ops/dashboard/snapshot-v2", query: monitorQuery(config: config, includeTimeRange: true), accessToken: tokens.accessToken)
        async let accountsOutcome: SourceOutcome<AccountsPageDTO> =
            fetchSource(path: "/api/v1/admin/accounts", query: accountsPageQuery, accessToken: tokens.accessToken)

        let (concurrency, availability, dashboard, accounts) = await (
            concurrencyOutcome, availabilityOutcome, dashboardOutcome, accountsOutcome
        )

        // A 401 on any source means the whole session is dead; anything else is partial.
        if let fatal = [concurrency.fatalError, availability.fatalError, dashboard.fatalError, accounts.fatalError]
            .compactMap({ $0 })
            .first {
            throw fatal
        }

        let accountUsages = if let items = accounts.value?.items {
            await fetchAccountUsages(
                accounts: items,
                config: config,
                accessToken: tokens.accessToken
            )
        } else {
            [Int64: AccountUsageDTO]()
        }

        let diagnostics = RefreshDiagnostics(
            lastFetchAt: fetchAt,
            nextFetchAt: nil,
            lastSnapshotWriteAt: nil,
            lastWidgetReloadRequestAt: nil,
            lastWidgetRenderAt: nil,
            lastError: SourceSummary.combine([
                concurrency.failure, availability.failure, dashboard.failure, accounts.failure
            ])
        )

        return SnapshotBuilder.build(
            instanceID: instance.id,
            concurrency: concurrency.value,
            availability: availability.value,
            dashboard: dashboard.value,
            accounts: accounts.value,
            usages: accountUsages,
            authState: AuthState(isAuthenticated: true, userEmail: tokens.userEmail, tokenExpiresAt: tokens.expiresAt),
            refreshInterval: config.refreshIntervalSec,
            diagnostics: diagnostics,
            staleReason: nil
        )
    }

    private var accountsPageQuery: [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: "1000"),
            URLQueryItem(name: "include_scheduler_score", value: "0")
        ]
    }

    /// Runs one source request, converting failure into a value rather than a throw.
    private func fetchSource<T: Decodable>(path: String, query: [URLQueryItem], accessToken: String) async -> SourceOutcome<T> {
        do {
            return SourceOutcome(value: try await get(path: path, query: query, accessToken: accessToken), failure: nil)
        } catch {
            return SourceOutcome(value: nil, failure: SafeMessage.sanitize(error))
        }
    }

    func healthCheck() async throws -> Bool {
        guard instance.baseURL.isAllowedSub2APIBaseURL else {
            throw Sub2APIError.insecureBaseURL
        }
        var request = URLRequest(url: instance.baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 20
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Sub2APIError.invalidResponse
        }
        return (200..<300).contains(http.statusCode)
    }

    private func monitorQuery(config: WidgetDisplayConfig, includeTimeRange: Bool) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if let platform = config.platformFilter {
            items.append(URLQueryItem(name: "platform", value: platform.rawValue))
        }
        if includeTimeRange {
            items.append(URLQueryItem(name: "time_range", value: config.timeRange.rawValue))
            items.append(URLQueryItem(name: "mode", value: "auto"))
        }
        items.append(URLQueryItem(name: "timezone", value: TimeZone.current.identifier))
        return items
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem], accessToken: String) async throws -> T {
        guard instance.baseURL.isAllowedSub2APIBaseURL else {
            throw Sub2APIError.insecureBaseURL
        }
        var components = URLComponents(url: instance.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = query.isEmpty ? nil : query
        guard let url = components?.url else {
            throw Sub2APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Locale.preferredLanguages.first ?? "zh-CN", forHTTPHeaderField: "Accept-Language")
        return try await perform(request: request)
    }

    private func post<T: Decodable, Body: Encodable>(path: String, body: Body, accessToken: String?) async throws -> T {
        guard instance.baseURL.isAllowedSub2APIBaseURL else {
            throw Sub2APIError.insecureBaseURL
        }
        let url = instance.baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request: request)
    }

    private func perform<T: Decodable>(request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Sub2APIError.invalidResponse
        }
        if http.statusCode == 401 {
            throw Sub2APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorEnvelope = try? JSONDecoder.sub2api.decode(APIErrorEnvelope.self, from: data)
            // Scrubbed at the source: this message is surfaced on the desktop
            // widget, and servers can echo request context into it.
            let message = SafeMessage.sanitize(errorEnvelope?.message ?? "HTTP \(http.statusCode)")
            throw Sub2APIError.apiError(message)
        }

        let envelope = try JSONDecoder.sub2api.decode(APIEnvelope<T>.self, from: data)
        if let code = envelope.code, code != 0 {
            throw Sub2APIError.apiError(SafeMessage.sanitize(envelope.message ?? "Sub2API error \(code)"))
        }
        guard let payload = envelope.data else {
            throw Sub2APIError.apiError(SafeMessage.sanitize(envelope.message ?? "Sub2API response did not include data"))
        }
        return payload
    }

    private func fetchAccountUsages(
        accounts: [AccountListItemDTO],
        config: WidgetDisplayConfig,
        accessToken: String
    ) async -> [Int64: AccountUsageDTO] {
        let manuallySelectedIDs = Set(config.selectedAccountIDs)
        let candidates = Self.usageCandidates(accounts: accounts, manuallySelectedIDs: manuallySelectedIDs)
        guard !candidates.isEmpty else { return [:] }

        var result: [Int64: AccountUsageDTO] = [:]
        var missing: [AccountListItemDTO] = []
        let origin = instance.baseURL.normalizedOrigin ?? instance.baseURL.absoluteString

        for account in candidates {
            let key = "\(origin):\(account.id)"
            switch await AccountUsageCache.shared.lookup(key: key, successMaxAge: 300, failureMaxAge: 60) {
            case .hit(let cached):
                if let cached {
                    result[account.id] = cached
                }
            case .miss:
                missing.append(account)
            }
        }

        guard !missing.isEmpty else { return result }

        let batchSize = min(max(8, manuallySelectedIDs.count), 16)
        let batch = Array(missing.prefix(batchSize))
        await withTaskGroup(of: UsageFetchResult.self) { group in
            for account in batch {
                group.addTask { [self] in
                    do {
                        let usage = try await fetchAccountUsage(account: account, accessToken: accessToken)
                        return UsageFetchResult(accountID: account.id, usage: usage)
                    } catch {
                        return UsageFetchResult(accountID: account.id, usage: nil)
                    }
                }
            }

            for await item in group {
                let key = "\(origin):\(item.accountID)"
                await AccountUsageCache.shared.store(item.usage, for: key)
                if let usage = item.usage {
                    result[item.accountID] = usage
                }
            }
        }
        return result
    }

    private func fetchAccountUsage(
        account: AccountListItemDTO,
        accessToken: String
    ) async throws -> AccountUsageDTO {
        if account.platform == "anthropic" && ["oauth", "setup-token"].contains(account.type) {
            let passive: AccountUsageDTO = try await get(
                path: "/api/v1/admin/accounts/\(account.id)/usage",
                query: [URLQueryItem(name: "source", value: "passive")],
                accessToken: accessToken
            )
            if passive.hasAnthropicQuotaData {
                return passive
            }
        }

        return try await get(
            path: "/api/v1/admin/accounts/\(account.id)/usage",
            query: [],
            accessToken: accessToken
        )
    }

    private nonisolated static func supportsUsage(_ account: AccountListItemDTO) -> Bool {
        switch account.platform {
        case "anthropic":
            return ["oauth", "setup-token"].contains(account.type)
        case "gemini":
            return true
        case "antigravity", "grok", "openai":
            return account.type == "oauth"
        default:
            return false
        }
    }

    nonisolated static func usageCandidates(
        accounts: [AccountListItemDTO],
        manuallySelectedIDs: Set<Int64>
    ) -> [AccountListItemDTO] {
        accounts
            .filter {
                supportsUsage($0)
                    && ($0.schedulable || manuallySelectedIDs.contains($0.id))
            }
            .sorted {
                let lhsSelected = manuallySelectedIDs.contains($0.id)
                let rhsSelected = manuallySelectedIDs.contains($1.id)
                if lhsSelected != rhsSelected { return lhsSelected }
                if $0.schedulable != $1.schedulable { return $0.schedulable }
                return $0.id < $1.id
            }
    }
}

private struct APIErrorEnvelope: Decodable {
    var code: Int?
    var message: String?
}

private struct UsageFetchResult: Sendable {
    var accountID: Int64
    var usage: AccountUsageDTO?
}

private enum AccountUsageCacheLookup: Sendable {
    case hit(AccountUsageDTO?)
    case miss
}

private actor AccountUsageCache {
    static let shared = AccountUsageCache()

    private struct Entry: Sendable {
        var storedAt: Date
        var usage: AccountUsageDTO?
    }

    private var entries: [String: Entry] = [:]

    func lookup(
        key: String,
        successMaxAge: TimeInterval,
        failureMaxAge: TimeInterval
    ) -> AccountUsageCacheLookup {
        guard let entry = entries[key] else { return .miss }
        let maxAge = entry.usage == nil ? failureMaxAge : successMaxAge
        guard Date().timeIntervalSince(entry.storedAt) <= maxAge else {
            entries.removeValue(forKey: key)
            return .miss
        }
        return .hit(entry.usage)
    }

    func store(_ usage: AccountUsageDTO?, for key: String) {
        entries[key] = Entry(storedAt: Date(), usage: usage)
    }
}
