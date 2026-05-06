import Foundation

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
}
