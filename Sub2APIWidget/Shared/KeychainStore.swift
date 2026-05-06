import Foundation
import Security

struct AuthTokenBundle: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var userEmail: String?
}

enum KeychainStore {
    private static let legacyServices = [
        "xyz.rorii.Sub2APIWidget"
    ]

    static func saveTokens(_ tokens: AuthTokenBundle, instanceID: String) throws {
        let data = try JSONEncoder.sub2api.encode(tokens)
        let account = accountName(instanceID: instanceID)
        SecItemDelete(baseQuery(account: account, service: AppConstants.bundleID) as CFDictionary)

        var query = baseQuery(account: account, service: AppConstants.bundleID)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandled(status)
        }
    }

    static func loadTokens(instanceID: String) throws -> AuthTokenBundle? {
        let account = accountName(instanceID: instanceID)
        if let tokens = try loadTokens(account: account, service: AppConstants.bundleID) {
            return tokens
        }
        for legacyService in legacyServices {
            if let tokens = try loadTokens(account: account, service: legacyService) {
                try? saveTokens(tokens, instanceID: instanceID)
                return tokens
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

    private static func baseQuery(account: String, service: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
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
