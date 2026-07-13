import Foundation

extension URL {
    var normalizedOrigin: String? {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              !host.isEmpty
        else {
            return nil
        }

        let defaultPort = scheme == "https" ? 443 : (scheme == "http" ? 80 : nil)
        let port = components.port ?? defaultPort
        guard let port else { return nil }
        return "\(scheme)://\(host):\(port)"
    }

    var isAllowedSub2APIBaseURL: Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            return false
        }

        if scheme == "https" { return true }
        return scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)
    }

    func hasSameOrigin(as other: URL) -> Bool {
        normalizedOrigin != nil && normalizedOrigin == other.normalizedOrigin
    }
}

extension InstanceConfig {
    func dashboardURL(platform: PlatformID?, timeRange: TimeRange = .fiveMinutes) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = dashboardPath
        var items = [URLQueryItem(name: "tr", value: timeRange.rawValue)]
        if let platform {
            items.append(URLQueryItem(name: "platform", value: platform.rawValue))
        }
        components?.queryItems = items
        return components?.url ?? baseURL
    }

    var loginURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/login"
        return components?.url ?? baseURL
    }

    var accountsURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = "/admin/accounts"
        components?.query = nil
        return components?.url ?? baseURL
    }
}
