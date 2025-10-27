//
//  KeychainService.swift
//  cascade-ledger
//
//  Secure API key storage using macOS Keychain
//

import Foundation
import Security

class KeychainService {
    static let shared = KeychainService()

    private let service = "com.cascade-ledger.api-keys"
    private let claudeAPIKeyAccount = "anthropic-claude-api-key"

    private init() {}

    // MARK: - API Key Management

    func saveClaudeAPIKey(_ key: String) throws {
        let data = key.data(using: .utf8)!

        // Delete existing key first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAPIKeyAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Simple approach: Use kSecAttrAccessible without access control
        // This should allow app access without prompts in sandbox
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAPIKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: false
        ]

        // Add new key
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unableToSave(status: status)
        }
    }

    func getClaudeAPIKey() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAPIKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.unableToRetrieve(status: status)
        }

        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }

        return key
    }

    func deleteClaudeAPIKey() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: claudeAPIKeyAccount
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unableToDelete(status: status)
        }
    }

    func hasClaudeAPIKey() -> Bool {
        return (try? getClaudeAPIKey()) != nil
    }
}

enum KeychainError: LocalizedError {
    case unableToSave(status: OSStatus)
    case unableToRetrieve(status: OSStatus)
    case unableToDelete(status: OSStatus)
    case invalidData
    case accessControlFailed(error: Error)

    var errorDescription: String? {
        switch self {
        case .unableToSave(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .unableToRetrieve(let status):
            return "Failed to retrieve from Keychain (status: \(status))"
        case .unableToDelete(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .invalidData:
            return "Invalid data in Keychain"
        case .accessControlFailed(let error):
            return "Failed to create access control: \(error.localizedDescription)"
        }
    }
}
