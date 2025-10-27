//
//  Transaction.swift
//  cascade-ledger
//
//  Double-entry bookkeeping transaction container
//

import Foundation
import SwiftData

/// Represents a complete financial transaction with multiple journal entries (legs)
/// Following double-entry bookkeeping principles where debits must equal credits
@Model
final class Transaction {
    var id: UUID

    // Core transaction fields
    var date: Date
    var transactionDescription: String
    var transactionType: TransactionType

    // Optional fields
    var referenceNumber: String?      // Check number, confirmation code, etc.
    var settlementDate: Date?
    var notes: String?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \JournalEntry.transaction)
    var journalEntries: [JournalEntry]

    @Relationship
    var account: Account?              // The brokerage/bank account

    @Relationship
    var importBatch: ImportBatch?

    // Source tracking
    var sourceRowNumbers: [Int]       // CSV rows that created this transaction
    var sourceHash: String?           // Hash for deduplication

    // Audit fields
    var createdAt: Date
    var updatedAt: Date

    // Computed properties
    var totalDebits: Decimal {
        journalEntries.compactMap(\.debitAmount).reduce(0, +)
    }

    var totalCredits: Decimal {
        journalEntries.compactMap(\.creditAmount).reduce(0, +)
    }

    /// Check if transaction is balanced (fundamental accounting rule)
    var isBalanced: Bool {
        let difference = abs(totalDebits - totalCredits)
        return difference < 0.01  // Allow for minor rounding differences
    }

    /// Net cash impact (sum of all USD/cash journal entries)
    var netCashImpact: Decimal {
        journalEntries
            .filter { $0.accountType == .cash }
            .reduce(0) { sum, entry in
                let debit = entry.debitAmount ?? 0
                let credit = entry.creditAmount ?? 0
                return sum + debit - credit
            }
    }

    /// Get the primary asset involved (if any)
    var primaryAsset: String? {
        journalEntries
            .first(where: { $0.accountType == .asset })?
            .accountName
    }

    /// Get total quantity change for an asset
    func quantityChange(for assetId: String) -> Decimal {
        journalEntries
            .filter { $0.accountType == .asset && $0.accountName == assetId }
            .reduce(0) { sum, entry in
                if entry.debitAmount != nil {
                    // Debit increases asset
                    return sum + (entry.quantity ?? 0)
                } else if entry.creditAmount != nil {
                    // Credit decreases asset
                    return sum - (entry.quantity ?? 0)
                }
                return sum
            }
    }

    init(
        date: Date,
        description: String,
        type: TransactionType,
        account: Account
    ) {
        self.id = UUID()
        self.date = date
        self.transactionDescription = description
        self.transactionType = type
        self.account = account
        self.journalEntries = []
        self.sourceRowNumbers = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Add a debit journal entry
    func addDebit(
        accountType: AccountType,
        accountName: String,
        amount: Decimal,
        quantity: Decimal? = nil,
        quantityUnit: String? = nil
    ) {
        let entry = JournalEntry(
            accountType: accountType,
            accountName: accountName,
            debitAmount: amount,
            creditAmount: nil,
            quantity: quantity,
            quantityUnit: quantityUnit,
            transaction: self
        )
        journalEntries.append(entry)
    }

    /// Add a credit journal entry
    func addCredit(
        accountType: AccountType,
        accountName: String,
        amount: Decimal,
        quantity: Decimal? = nil,
        quantityUnit: String? = nil
    ) {
        let entry = JournalEntry(
            accountType: accountType,
            accountName: accountName,
            debitAmount: nil,
            creditAmount: amount,
            quantity: quantity,
            quantityUnit: quantityUnit,
            transaction: self
        )
        journalEntries.append(entry)
    }

    /// Validate the transaction follows accounting rules
    func validate() throws {
        guard isBalanced else {
            throw TransactionError.unbalanced(
                debits: totalDebits,
                credits: totalCredits
            )
        }

        guard !journalEntries.isEmpty else {
            throw TransactionError.noJournalEntries
        }

        guard journalEntries.count >= 2 else {
            throw TransactionError.insufficientJournalEntries
        }
    }
}

enum TransactionError: LocalizedError {
    case unbalanced(debits: Decimal, credits: Decimal)
    case noJournalEntries
    case insufficientJournalEntries

    var errorDescription: String? {
        switch self {
        case .unbalanced(let debits, let credits):
            return "Transaction is not balanced: Debits = \(debits), Credits = \(credits)"
        case .noJournalEntries:
            return "Transaction has no journal entries"
        case .insufficientJournalEntries:
            return "Transaction must have at least 2 journal entries"
        }
    }
}