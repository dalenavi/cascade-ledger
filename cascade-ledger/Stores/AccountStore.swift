//
//  AccountStore.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import Combine

@MainActor
class AccountStore: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupDefaultInstitutions()
    }

    // MARK: - Institution Management

    private func setupDefaultInstitutions() {
        // Check if institutions exist
        let descriptor = FetchDescriptor<Institution>()
        if let existingInstitutions = try? modelContext.fetch(descriptor),
           !existingInstitutions.isEmpty {
            return
        }

        // Create default institutions
        let defaultInstitutions = [
            ("fidelity", "Fidelity Investments"),
            ("vanguard", "Vanguard"),
            ("schwab", "Charles Schwab"),
            ("chase", "Chase Bank"),
            ("bofa", "Bank of America"),
            ("wells_fargo", "Wells Fargo"),
            ("citi", "Citibank"),
            ("amex", "American Express"),
            ("td_ameritrade", "TD Ameritrade"),
            ("etrade", "E*TRADE"),
            ("robinhood", "Robinhood"),
            ("coinbase", "Coinbase"),
            ("binance", "Binance"),
            ("kraken", "Kraken")
        ]

        for (id, name) in defaultInstitutions {
            let institution = Institution(id: id, displayName: name)
            modelContext.insert(institution)
        }

        try? modelContext.save()
    }

    func getAllInstitutions() async throws -> [Institution] {
        let descriptor = FetchDescriptor<Institution>(
            sortBy: [SortDescriptor(\.displayName)]
        )
        return try modelContext.fetch(descriptor)
    }

    func getInstitution(byId id: String) async throws -> Institution? {
        let descriptor = FetchDescriptor<Institution>(
            predicate: #Predicate { $0.id == id }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    func createCustomInstitution(id: String, displayName: String) throws -> Institution {
        let institution = Institution(id: id, displayName: displayName)
        modelContext.insert(institution)
        try modelContext.save()
        return institution
    }

    // MARK: - Account Management

    func createAccount(name: String, institutionId: String? = nil) async throws -> Account {
        var institution: Institution? = nil

        if let institutionId = institutionId {
            institution = try await getInstitution(byId: institutionId)
        }

        let account = Account(name: name, institution: institution)
        modelContext.insert(account)
        try modelContext.save()

        return account
    }

    func getAllAccounts() async throws -> [Account] {
        let descriptor = FetchDescriptor<Account>(
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func getAccount(byId id: UUID) async throws -> Account? {
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    func getAccountsForInstitution(_ institution: Institution) async throws -> [Account] {
        let institutionId = institution.id
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { account in
                account.institution?.id == institutionId
            },
            sortBy: [SortDescriptor(\.name)]
        )
        return try modelContext.fetch(descriptor)
    }

    func updateAccount(_ account: Account, name: String? = nil, institution: Institution? = nil) throws {
        if let name = name {
            account.name = name
        }
        if let institution = institution {
            account.institution = institution
        }
        account.updatedAt = Date()
        try modelContext.save()
    }

    func setDefaultParsePlan(for account: Account, parsePlan: ParsePlan) throws {
        account.defaultParsePlanID = parsePlan.id
        account.updatedAt = Date()
        try modelContext.save()
    }

    func deleteAccount(_ account: Account) throws {
        // Check if account has imports
        guard account.importBatches.isEmpty else {
            throw AccountError.hasImports
        }

        modelContext.delete(account)
        try modelContext.save()
    }

    // MARK: - Institution Detection

    func detectInstitutionFromCSV(_ rawFile: RawFile) async -> Institution? {
        guard let content = String(data: rawFile.content, encoding: .utf8) else {
            return nil
        }

        let lowercaseContent = content.lowercased()

        // Check for institution patterns
        let institutionPatterns: [(String, String)] = [
            ("fidelity", "fidelity"),
            ("vanguard", "vanguard"),
            ("charles schwab", "schwab"),
            ("schwab", "schwab"),
            ("chase", "chase"),
            ("bank of america", "bofa"),
            ("wells fargo", "wells_fargo"),
            ("citibank", "citi"),
            ("american express", "amex"),
            ("td ameritrade", "td_ameritrade"),
            ("e*trade", "etrade"),
            ("etrade", "etrade"),
            ("robinhood", "robinhood"),
            ("coinbase", "coinbase"),
            ("binance", "binance"),
            ("kraken", "kraken")
        ]

        for (pattern, institutionId) in institutionPatterns {
            if lowercaseContent.contains(pattern) {
                return try? await getInstitution(byId: institutionId)
            }
        }

        return nil
    }
}

enum AccountError: LocalizedError {
    case hasImports
    case institutionNotFound
    case duplicateName

    var errorDescription: String? {
        switch self {
        case .hasImports:
            return "Cannot delete account that has import history"
        case .institutionNotFound:
            return "Institution not found"
        case .duplicateName:
            return "An account with this name already exists"
        }
    }
}