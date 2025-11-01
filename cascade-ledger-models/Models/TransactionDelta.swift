//
//  TransactionDelta.swift
//  cascade-ledger
//
//  Describes changes to transactions (create/update/delete)
//

import Foundation
import SwiftData

/// A single change to be applied to transactions
@Model
final class TransactionDelta {
    enum Action: String, Codable {
        case create   // New transaction for uncovered rows
        case update   // Fix existing transaction
        case delete   // Remove invalid transaction
        case exclude  // Mark rows as non-transactional (disclaimers, metadata, etc.)
    }

    var id: UUID
    var actionRaw: String  // Stored as String, use computed property
    var reason: String  // AI explanation for this change

    // For update/delete - reference to original
    var originalTransactionId: UUID?
    var originalSourceRowsData: Data?  // JSON-encoded [Int]

    // Computed property for original source rows
    var originalSourceRows: [Int]? {
        get {
            guard let data = originalSourceRowsData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            originalSourceRowsData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    // For create/update - new transaction data
    var newTransactionData: Data?  // JSON-encoded transaction

    // For exclude - rows to mark as non-transactional
    var excludedRowsData: Data?  // JSON-encoded [Int]

    // Computed property for excluded rows
    var excludedRows: [Int]? {
        get {
            guard let data = excludedRowsData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            excludedRowsData = newValue.flatMap { try? JSONEncoder().encode($0) }
        }
    }

    // Status
    var appliedAt: Date?

    @Relationship
    var reviewSession: ReviewSession?

    // Computed property for action
    var action: Action {
        get { Action(rawValue: actionRaw) ?? .create }
        set { actionRaw = newValue.rawValue }
    }

    init(
        action: Action,
        reason: String,
        originalTransactionId: UUID? = nil,
        originalSourceRows: [Int]? = nil,
        newTransactionData: Data? = nil
    ) {
        self.id = UUID()
        self.actionRaw = action.rawValue
        self.reason = reason
        self.originalTransactionId = originalTransactionId
        self.originalSourceRows = originalSourceRows
        self.newTransactionData = newTransactionData
    }
}

/// Codable structure for new transaction data in deltas
struct DeltaTransactionData: Codable {
    var sourceRows: [Int]
    var date: String  // yyyy-MM-dd format
    var description: String
    var transactionType: String
    var journalEntries: [DeltaJournalEntry]
}

struct DeltaJournalEntry: Codable {
    var type: String  // "debit" or "credit"
    var accountType: String
    var accountName: String
    var amount: Decimal
    var quantity: Decimal?
    var quantityUnit: String?
    var assetSymbol: String?

    // Source provenance (optional for backward compatibility)
    var sourceRows: [Int]?     // Which source rows this entry came from
    var csvAmount: Decimal?    // Expected amount from CSV for validation
}
