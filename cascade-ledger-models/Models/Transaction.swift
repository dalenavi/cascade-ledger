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

    // User categorization overrides
    var userTransactionType: TransactionType?
    var userCategory: String?
    var tagsData: Data?  // JSON-encoded array of tags

    // Computed property for tags
    var tags: [String] {
        get {
            guard let data = tagsData,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            tagsData = try? JSONEncoder().encode(newValue)
        }
    }

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \JournalEntry.transaction)
    var journalEntries: [JournalEntry]

    @Relationship
    var account: Account?              // The brokerage/bank account

    @Relationship
    var importSession: ImportSession?

    @Relationship
    var categorizationSession: CategorizationSession?

    @Relationship(deleteRule: .nullify, inverse: \CategorizationAttempt.transaction)
    var categorizationAttempts: [CategorizationAttempt]

    // Source tracking
    var sourceRowNumbersData: Data?   // JSON-encoded array of row numbers
    var sourceHash: String?           // Hash for deduplication

    // Computed property for sourceRowNumbers
    var sourceRowNumbers: [Int] {
        get {
            guard let data = sourceRowNumbersData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return array
        }
        set {
            sourceRowNumbersData = try? JSONEncoder().encode(newValue)
        }
    }

    // Duplicate tracking
    var isDuplicate: Bool
    var duplicateOf: UUID?

    // Reconciliation
    var isReconciled: Bool

    // Balance tracking (from CSV and calculated)
    var csvBalance: Decimal?              // Balance from CSV row (if available)
    var calculatedBalance: Decimal?       // Running balance calculated from journal entries
    var balanceDiscrepancy: Decimal?      // Difference between CSV and calculated

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

    /// Check if balance discrepancy exists (significant difference)
    var hasBalanceDiscrepancy: Bool {
        guard let discrepancy = balanceDiscrepancy else { return false }
        return abs(discrepancy) > 0.01
    }

    /// Net cash impact (sum of cash entries using account's balance instrument)
    var netCashImpact: Decimal {
        // Get the balance instrument from the account (defaults to "Cash USD")
        let balanceInstrument = account?.balanceInstrument ?? "Cash USD"

        return journalEntries
            .filter { entry in
                // Include cash type entries
                if entry.accountType == .cash {
                    return true
                }
                // Include entries matching the account's balance instrument
                // (e.g., SPAXX for Fidelity, VMMXX for Vanguard)
                if entry.accountName.uppercased() == balanceInstrument.uppercased() {
                    return true
                }
                return false
            }
            .reduce(0) { sum, entry in
                let debit = entry.debitAmount ?? 0
                let credit = entry.creditAmount ?? 0
                return sum + debit - credit
            }
    }

    /// Get the primary asset involved (if any)
    var primaryAsset: Asset? {
        journalEntries
            .first(where: { $0.accountType == .asset })?
            .asset
    }

    /// Compatibility: Amount field for UI
    var amount: Decimal {
        abs(netCashImpact)
    }

    /// Compatibility: Effective category considering user overrides
    var effectiveCategory: String {
        userCategory ?? transactionType.rawValue
    }

    /// Compatibility: Check if has tentative categorization
    var hasTentativeCategorization: Bool {
        false  // Stub for now
    }

    /// Compatibility: Check if has quantity data
    var hasQuantityData: Bool {
        journalEntries.contains { $0.quantity != nil }
    }

    /// Compatibility: Effective transaction type considering user overrides
    var effectiveTransactionType: TransactionType {
        userTransactionType ?? transactionType
    }

    /// Compatibility: Asset ID for old views
    var assetId: String? {
        primaryAsset?.symbol
    }

    /// Compatibility: Quantity for old views
    var quantity: Decimal? {
        guard let asset = primaryAsset else { return nil }
        let quantities = journalEntries
            .filter { $0.asset?.id == asset.id }
            .compactMap { $0.quantity }
        return quantities.isEmpty ? nil : quantities.reduce(0, +)
    }

    /// Compatibility: Quantity unit for old views
    var quantityUnit: String? {
        journalEntries.first(where: { $0.quantityUnit != nil })?.quantityUnit
    }

    /// Compatibility: Category field
    var category: String? {
        userCategory
    }

    /// Compatibility: Raw transaction type from CSV
    var rawTransactionType: String? {
        nil  // Stub for now
    }

    /// Compatibility: Subcategory field
    var subcategory: String? {
        nil  // Stub for now
    }

    /// Compatibility: Metadata dictionary
    var metadata: [String: String] {
        [:]  // Stub for now
    }

    /// Compatibility: Legacy importBatch field (maps to importSession)
    var importBatch: ImportBatch? {
        get { nil }  // Legacy field not used in new model
        set { }
    }

    /// Compatibility: Legacy transactionHash (maps to sourceHash)
    var transactionHash: String? {
        get { sourceHash }
        set { sourceHash = newValue }
    }

    /// Compatibility: Legacy parseRun field (deprecated)
    var parseRun: ParseRun? {
        get { nil }
        set { }
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
        // Initialize Data fields directly (computed properties need fully initialized self)
        self.sourceRowNumbersData = try? JSONEncoder().encode([Int]())
        self.tagsData = try? JSONEncoder().encode([String]())
        self.categorizationAttempts = []
        self.isDuplicate = false
        self.isReconciled = false
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

enum TransactionType: String, Codable, CaseIterable {
    case buy = "buy"
    case sell = "sell"
    case transfer = "transfer"
    case dividend = "dividend"
    case interest = "interest"
    case fee = "fee"
    case tax = "tax"
    case deposit = "deposit"
    case withdrawal = "withdrawal"
    case other = "other"
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