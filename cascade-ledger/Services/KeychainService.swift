//
//  KeychainService.swift
//  cascade-ledger
//
//  API key storage using UserDefaults
//  NOTE: Switched from Keychain due to persistent password prompt issues
//

import Foundation

class KeychainService {
    static let shared = KeychainService()

    private let userDefaults = UserDefaults.standard
    private let claudeAPIKeyKey = "com.cascade-ledger.claudeAPIKey"

    private init() {
        // Try to migrate from keychain if this is first run
        migrateFromKeychainIfNeeded()
    }

    // MARK: - API Key Management

    func saveClaudeAPIKey(_ key: String) throws {
        userDefaults.set(key, forKey: claudeAPIKeyKey)
        userDefaults.synchronize()
        print("✓ Saved Claude API key to UserDefaults")
    }

    func getClaudeAPIKey() throws -> String? {
        return userDefaults.string(forKey: claudeAPIKeyKey)
    }

    func deleteClaudeAPIKey() throws {
        userDefaults.removeObject(forKey: claudeAPIKeyKey)
        userDefaults.synchronize()
        print("✓ Deleted Claude API key from UserDefaults")
    }

    func hasClaudeAPIKey() -> Bool {
        return userDefaults.string(forKey: claudeAPIKeyKey) != nil
    }

    // MARK: - Migration

    private func migrateFromKeychainIfNeeded() {
        // Check if we already have a key in UserDefaults
        if userDefaults.string(forKey: claudeAPIKeyKey) != nil {
            return  // Already migrated
        }

        // Try to read from old keychain location
        let service = "com.cascade-ledger.api-keys"
        let account = "anthropic-claude-api-key"

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            // Found keychain key - migrate it
            userDefaults.set(key, forKey: claudeAPIKeyKey)
            userDefaults.synchronize()
            print("✓ Migrated API key from Keychain to UserDefaults")

            // Optionally delete from keychain
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }
    }
}

enum KeychainError: LocalizedError {
    case unableToSave
    case unableToRetrieve
    case unableToDelete
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unableToSave:
            return "Failed to save API key"
        case .unableToRetrieve:
            return "Failed to retrieve API key"
        case .unableToDelete:
            return "Failed to delete API key"
        case .invalidData:
            return "Invalid API key data"
        }
    }
}
