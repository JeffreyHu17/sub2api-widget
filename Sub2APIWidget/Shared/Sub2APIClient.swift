import Foundation

enum Sub2APIError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case unauthorized
    case missingToken
    case insecureBaseURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Sub2API"
        case .apiError(let message): message
        case .unauthorized: "Session expired. Please log in again."
        case .missingToken: "Missing access token"
        case .insecureBaseURL: "Refusing to send credentials to an insecure or invalid Base URL"
        }
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

    func fetchSnapshot(tokens: AuthTokenBundle, config: WidgetDisplayConfig) async throws -> MonitorSnapshot {
        var currentTokens = tokens
        do {
            return try await fetchSnapshotOnce(tokens: currentTokens, config: config)
        } catch Sub2APIError.unauthorized {
            guard let refresh = tokens.refreshToken else {
                throw Sub2APIError.unauthorized
            }
            currentTokens = try await refreshToken(refresh)
            try KeychainStore.saveTokens(currentTokens, for: instance)
            return try await fetchSnapshotOnce(tokens: currentTokens, config: config)
        }
    }

    private func fetchSnapshotOnce(tokens: AuthTokenBundle, config: WidgetDisplayConfig) async throws -> MonitorSnapshot {
        let fetchAt = Date()
        async let concurrencyRequest: ConcurrencyResponseDTO = get(
            path: "/api/v1/admin/ops/concurrency",
            query: monitorQuery(config: config, includeTimeRange: false),
            accessToken: tokens.accessToken
        )
        async let availabilityRequest: AvailabilityResponseDTO = get(
            path: "/api/v1/admin/ops/account-availability",
            query: monitorQuery(config: config, includeTimeRange: false),
            accessToken: tokens.accessToken
        )
        async let dashboardRequest: DashboardSnapshotDTO = get(
            path: "/api/v1/admin/ops/dashboard/snapshot-v2",
            query: monitorQuery(config: config, includeTimeRange: true),
            accessToken: tokens.accessToken
        )
        async let accountsRequest: AccountsPageDTO? = fetchAccounts(accessToken: tokens.accessToken)

        let (concurrency, availability, dashboard, accounts) = try await (
            concurrencyRequest,
            availabilityRequest,
            dashboardRequest,
            accountsRequest
        )

        let diagnostics = RefreshDiagnostics(
            lastFetchAt: fetchAt,
            nextFetchAt: nil,
            lastSnapshotWriteAt: nil,
            lastWidgetReloadRequestAt: nil,
            lastWidgetRenderAt: nil,
            lastError: nil
        )

        return SnapshotBuilder.build(
            instanceID: instance.id,
            concurrency: concurrency,
            availability: availability,
            dashboard: dashboard,
            accounts: accounts,
            authState: AuthState(isAuthenticated: true, userEmail: tokens.userEmail, tokenExpiresAt: tokens.expiresAt),
            refreshInterval: config.refreshIntervalSec,
            diagnostics: diagnostics,
            staleReason: nil
        )
    }

    func healthCheck() async throws -> Bool {
        let url = instance.baseURL.appendingPathComponent("health")
        let (_, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw Sub2APIError.invalidResponse
        }
        return (200..<300).contains(http.statusCode)
    }

    private func fetchAccounts(accessToken: String) async -> AccountsPageDTO? {
        let cacheKey = "\(instance.id):\(instance.baseURL.normalizedOrigin ?? instance.baseURL.absoluteString)"
        if let cached = await AccountListCache.shared.value(for: cacheKey, maxAge: 30) {
            return cached
        }

        do {
            let page: AccountsPageDTO = try await get(
                path: "/api/v1/admin/accounts",
                query: [
                    URLQueryItem(name: "page", value: "1"),
                    URLQueryItem(name: "page_size", value: "1000"),
                    URLQueryItem(name: "include_scheduler_score", value: "0")
                ],
                accessToken: accessToken
            )
            await AccountListCache.shared.store(page, for: cacheKey)
            return page
        } catch {
            return nil
        }
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
            throw Sub2APIError.apiError(errorEnvelope?.message ?? "HTTP \(http.statusCode)")
        }

        let envelope = try JSONDecoder.sub2api.decode(APIEnvelope<T>.self, from: data)
        if let code = envelope.code, code != 0 {
            throw Sub2APIError.apiError(envelope.message ?? "Sub2API error \(code)")
        }
        guard let payload = envelope.data else {
            throw Sub2APIError.apiError(envelope.message ?? "Sub2API response did not include data")
        }
        return payload
    }
}

private struct APIErrorEnvelope: Decodable {
    var code: Int?
    var message: String?
}

private actor AccountListCache {
    static let shared = AccountListCache()

    private struct Entry: Sendable {
        var storedAt: Date
        var page: AccountsPageDTO
    }

    private var entries: [String: Entry] = [:]

    func value(for key: String, maxAge: TimeInterval) -> AccountsPageDTO? {
        guard let entry = entries[key], Date().timeIntervalSince(entry.storedAt) <= maxAge else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.page
    }

    func store(_ page: AccountsPageDTO, for key: String) {
        entries[key] = Entry(storedAt: Date(), page: page)
    }
}
