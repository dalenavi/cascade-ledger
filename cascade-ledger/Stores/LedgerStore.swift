//
//  LedgerStore.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import Combine

@MainActor
class LedgerStore: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Append-Only Operations

    // Add ledger entry (append-only)
    func appendTransaction(_ entry: Transaction) throws {
        // Check for duplicates
        if let duplicate = try findDuplicate(entry) {
            entry.isDuplicate = true
            entry.duplicateOf = duplicate.id
        }

        modelContext.insert(entry)
        try modelContext.save()
    }

    // Batch append ledger entries
    func appendLedgerEntries(_ entries: [Transaction]) async throws {
        for entry in entries {
            if let duplicate = try findDuplicate(entry) {
                entry.isDuplicate = true
                entry.duplicateOf = duplicate.id
            }
            modelContext.insert(entry)
        }
        try modelContext.save()
    }

    // MARK: - Query Operations

    // Get ledger entries for account
    func getLedgerEntriesForAccount(_ account: Account, limit: Int? = nil) async throws -> [Transaction] {
        let accountId = account.id
        var descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { entry in
                entry.account?.id == accountId
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        if let limit = limit {
            descriptor.fetchLimit = limit
        }

        return try modelContext.fetch(descriptor)
    }

    // Get ledger entries by date range
    func getLedgerEntriesByDateRange(account: Account, from startDate: Date, to endDate: Date) async throws -> [Transaction] {
        let accountId = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { entry in
                entry.account?.id == accountId &&
                entry.date >= startDate &&
                entry.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // Get ledger entries for import batch
    func getLedgerEntriesForImport(_ importBatch: ImportBatch) async throws -> [Transaction] {
        let importBatchId = importBatch.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { entry in
                entry.importBatch?.id == importBatchId
            },
            sortBy: [SortDescriptor(\.date)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Duplicate Detection

    // Find duplicate by transaction hash
    func findDuplicate(_ entry: Transaction) throws -> Transaction? {
        let transactionHash = entry.transactionHash
        let entryId = entry.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { ledger in
                ledger.transactionHash == transactionHash &&
                ledger.id != entryId &&
                !ledger.isDuplicate
            }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    // Find potential duplicates using fuzzy matching
    func findPotentialDuplicates(_ entry: Transaction, tolerance: TimeInterval = 86400) async throws -> [Transaction] {
        guard let account = entry.account else { return [] }

        let accountId = account.id
        let entryId = entry.id
        let startDate = entry.date.addingTimeInterval(-tolerance)
        let endDate = entry.date.addingTimeInterval(tolerance)

        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { ledger in
                ledger.account?.id == accountId &&
                ledger.id != entryId &&
                ledger.date >= startDate &&
                ledger.date <= endDate &&
                !ledger.isDuplicate
            }
        )

        let candidates = try modelContext.fetch(descriptor)

        // Filter by amount similarity (within 1 cent)
        let amountTolerance = Decimal(0.01)
        return candidates.filter { candidate in
            abs(candidate.amount - entry.amount) <= amountTolerance
        }
    }

    // MARK: - Statistics

    // Get account balance
    func getAccountBalance(_ account: Account) async throws -> Decimal {
        let entries = try await getLedgerEntriesForAccount(account)
        return entries.reduce(Decimal.zero) { total, entry in
            switch entry.transactionType {
            case .credit, .deposit, .dividend, .interest:
                return total + entry.amount
            case .debit, .withdrawal, .fee, .tax:
                return total - entry.amount
            case .buy:
                return total - entry.amount
            case .sell:
                return total + entry.amount
            case .transfer:
                // Transfers need special handling based on source/destination
                return total
            }
        }
    }

    // Get transaction count
    func getTransactionCount(_ account: Account) async throws -> Int {
        let accountId = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { entry in
                entry.account?.id == accountId && !entry.isDuplicate
            }
        )
        let results = try modelContext.fetch(descriptor)
        return results.count
    }

    // MARK: - Reconciliation

    // Mark entry as reconciled
    func markAsReconciled(_ entry: Transaction) throws {
        entry.isReconciled = true
        entry.updatedAt = Date()
        try modelContext.save()
    }

    // Batch reconcile entries
    func batchReconcile(_ entries: [Transaction]) throws {
        for entry in entries {
            entry.isReconciled = true
            entry.updatedAt = Date()
        }
        try modelContext.save()
    }

    // MARK: - Export

    // Export ledger entries to CSV
    func exportToCSV(_ entries: [Transaction]) -> String {
        var csv = "Date,Amount,Description,Type,Category,Account,Reconciled\n"

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        for entry in entries {
            let date = dateFormatter.string(from: entry.date)
            let amount = String(describing: entry.amount)
            let description = entry.transactionDescription.replacingOccurrences(of: ",", with: ";")
            let type = entry.transactionType.rawValue
            let category = entry.category ?? ""
            let accountName = entry.account?.name ?? ""
            let reconciled = entry.isReconciled ? "Yes" : "No"

            csv += "\(date),\(amount),\"\(description)\",\(type),\(category),\(accountName),\(reconciled)\n"
        }

        return csv
    }
}