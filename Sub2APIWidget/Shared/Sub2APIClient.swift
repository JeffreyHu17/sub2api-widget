import Foundation

enum Sub2APIError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case unauthorized
    case missingToken

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from Sub2API"
        case .apiError(let message): message
        case .unauthorized: "Session expired. Please log in again."
        case .missingToken: "Missing access token"
        }
    }
}

final class Sub2APIClient {
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
            refreshToken: response.refreshToken,
            expiresAt: response.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) },
            userEmail: response.user?.email
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
            try KeychainStore.saveTokens(currentTokens, instanceID: instance.id)
            return try await fetchSnapshotOnce(tokens: currentTokens, config: config)
        }
    }

    private func fetchSnapshotOnce(tokens: AuthTokenBundle, config: WidgetDisplayConfig) async throws -> MonitorSnapshot {
        let fetchAt = Date()
        let concurrency: ConcurrencyResponseDTO = try await get(
            path: "/api/v1/admin/ops/concurrency",
            query: monitorQuery(config: config, includeTimeRange: false),
            accessToken: tokens.accessToken
        )
        let availability: AvailabilityResponseDTO = try await get(
            path: "/api/v1/admin/ops/account-availability",
            query: monitorQuery(config: config, includeTimeRange: false),
            accessToken: tokens.accessToken
        )
        let dashboard: DashboardSnapshotDTO = try await get(
            path: "/api/v1/admin/ops/dashboard/snapshot-v2",
            query: monitorQuery(config: config, includeTimeRange: true),
            accessToken: tokens.accessToken
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
            throw Sub2APIError.apiError("HTTP \(http.statusCode)")
        }

        let envelope = try JSONDecoder.sub2api.decode(APIEnvelope<T>.self, from: data)
        if let code = envelope.code, code != 0 {
            throw Sub2APIError.apiError(envelope.message ?? "Sub2API error \(code)")
        }
        return envelope.data
    }
}
