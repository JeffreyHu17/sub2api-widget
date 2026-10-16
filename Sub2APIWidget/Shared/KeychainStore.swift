import Foundation
import Security

struct AuthTokenBundle: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var userEmail: String?
    var origin: String? = nil
}

enum KeychainStore {
    private static let legacyServices = [
        "xyz.rorii.Sub2APIWidget"
    ]

    static func saveTokens(_ tokens: AuthTokenBundle, for instance: InstanceConfig) throws {
        var scopedTokens = tokens
        scopedTokens.origin = instance.baseURL.normalizedOrigin
        let data = try JSONEncoder.sub2api.encode(scopedTokens)
        let account = accountName(instanceID: instance.id)
        SecItemDelete(baseQuery(account: account, service: AppConstants.bundleID) as CFDictionary)

        var query = baseQuery(account: account, service: AppConstants.bundleID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func loadTokens(for instance: InstanceConfig) throws -> AuthTokenBundle? {
        let account = accountName(instanceID: instance.id)
        if let tokens = try loadTokens(account: account, service: AppConstants.bundleID) {
            guard tokens.origin == instance.baseURL.normalizedOrigin else {
                deleteTokens(instanceID: instance.id)
                return nil
            }
            return tokens
        }
        for legacyService in legacyServices {
            if try loadTokens(account: account, service: legacyService) != nil {
                deleteTokens(instanceID: instance.id)
                return nil
            }
        }
        return nil
    }

    static func deleteTokens(instanceID: String) {
        let account = accountName(instanceID: instanceID)
        SecItemDelete(baseQuery(account: account, service: AppConstants.bundleID) as CFDictionary)
        for legacyService in legacyServices {
            SecItemDelete(baseQuery(account: account, service: legacyService) as CFDictionary)
        }
    }

    private static func loadTokens(account: String, service: String) throws -> AuthTokenBundle? {
        var query = baseQuery(account: account, service: service)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandled(status)
        }
        return try JSONDecoder.sub2api.decode(AuthTokenBundle.self, from: data)
    }

    private static var accessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "Sub2APIAppIdentifierPrefix") as? String,
              !prefix.isEmpty,
              !prefix.contains("$(")
        else {
            return nil
        }
        return "\(prefix)top.jeffreyhjh.Sub2APIWidget.shared"
    }

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private static func accountName(instanceID: String) -> String {
        "sub2api-token-\(instanceID)"
    }
}

enum KeychainError: LocalizedError {
    case unhandled(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unhandled(let status): "Keychain error: \(status)"
        }
    }
}
