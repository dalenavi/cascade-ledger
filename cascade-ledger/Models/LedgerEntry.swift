//
//  LedgerEntry.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class LedgerEntry {
    var id: UUID
    var transactionHash: String // SHA256 for deduplication

    // Core transaction fields
    var date: Date
    var amount: Decimal
    var transactionDescription: String
    var normalizedDescription: String?

    // Quantity tracking (for investments)
    var quantity: Decimal?           // Number of units (100 shares, 0.5 BTC)
    var quantityUnit: String?        // "shares", "BTC", "ETH", etc.

    // Computed
    var pricePerUnit: Decimal? {
        guard let qty = quantity, qty != 0 else { return nil }
        return abs(amount) / abs(qty)
    }

    // Account and asset information
    @Relationship
    var account: Account?
    var assetId: String?

    // Transaction classification
    var transactionType: TransactionType      // Current type (can be edited)
    var rawTransactionType: String?           // Original type from CSV (preserved)
    var userTransactionType: TransactionType? // User override

    // Computed effective type
    var effectiveTransactionType: TransactionType {
        userTransactionType ?? transactionType
    }

    // Category and tags
    var category: String?
    var subcategory: String?
    var tags: [String]

    // Import tracking
    @Relationship
    var importBatch: ImportBatch?

    @Relationship
    var parseRun: ParseRun?

    // Lineage information
    var sourceRowNumber: Int?
    var sourceData: Data? // Original row data

    // Metadata
    var metadata: [String: String]
    var isReconciled: Bool
    var isDuplicate: Bool
    var duplicateOf: UUID?

    // User annotations
    var notes: String?
    var userCategory: String? // User-assigned category (overrides auto category)

    // Categorization attempts
    @Relationship(deleteRule: .cascade, inverse: \CategorizationAttempt.transaction)
    var categorizationAttempts: [CategorizationAttempt]

    // Computed
    var hasTentativeCategorization: Bool {
        categorizationAttempts.contains { $0.status == .tentative }
    }

    var effectiveCategory: String {
        userCategory ?? category ?? "Uncategorized"
    }

    var hasQuantityData: Bool {
        quantity != nil && quantity != 0
    }

    var createdAt: Date
    var updatedAt: Date

    init(date: Date, amount: Decimal, description: String, account: Account, transactionType: TransactionType) {
        self.id = UUID()
        self.date = date
        self.amount = amount
        self.transactionDescription = description
        self.account = account
        self.transactionType = transactionType
        self.assetId = nil
        self.normalizedDescription = nil
        self.category = nil
        self.subcategory = nil
        self.tags = []
        self.importBatch = nil
        self.parseRun = nil
        self.sourceRowNumber = nil
        self.sourceData = nil
        self.metadata = [:]
        self.isReconciled = false
        self.isDuplicate = false
        self.duplicateOf = nil
        self.categorizationAttempts = []
        self.createdAt = Date()
        self.updatedAt = Date()

        // Calculate transaction hash (set it after all other properties)
        self.transactionHash = Self.calculateHash(
            date: date,
            accountId: account.id,
            assetId: nil,
            type: transactionType.rawValue,
            amount: amount,
            description: description
        )
    }

    static func calculateHash(date: Date, accountId: UUID, assetId: String?, type: String, amount: Decimal, description: String) -> String {
        let dateString = ISO8601DateFormatter().string(from: date)
        let amountString = String(describing: amount)
        let hashInput = "\(dateString)|\(accountId.uuidString)|\(assetId ?? "")|\(type)|\(amountString)|\(description)"

        let hash = SHA256.hash(data: Data(hashInput.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

enum TransactionType: String, Codable, CaseIterable {
    case debit = "debit"
    case credit = "credit"
    case buy = "buy"
    case sell = "sell"
    case transfer = "transfer"
    case dividend = "dividend"
    case interest = "interest"
    case fee = "fee"
    case tax = "tax"
    case deposit = "deposit"
    case withdrawal = "withdrawal"
}

@Model
final class ParseRun {
    var id: UUID
    var startedAt: Date
    var completedAt: Date?

    @Relationship
    var importBatch: ImportBatch?

    @Relationship
    var parsePlanVersion: ParsePlanVersion?

    @Relationship(deleteRule: .cascade, inverse: \LedgerEntry.parseRun)
    var ledgerEntries: [LedgerEntry]

    // Lineage tracking
    var lineageMappings: [LineageMapping]

    // Statistics
    var totalRows: Int
    var processedRows: Int
    var successfulRows: Int
    var failedRows: Int
    var errors: [ParseError]

    init(importBatch: ImportBatch, parsePlanVersion: ParsePlanVersion) {
        self.id = UUID()
        self.startedAt = Date()
        self.importBatch = importBatch
        self.parsePlanVersion = parsePlanVersion
        self.ledgerEntries = []
        self.lineageMappings = []
        self.totalRows = 0
        self.processedRows = 0
        self.successfulRows = 0
        self.failedRows = 0
        self.errors = []
    }
}

// Lineage mapping from source to output
struct LineageMapping: Codable {
    var sourceRowNumber: Int
    var sourceFields: [String: String] // field name to value
    var outputEntryId: UUID?
    var transformsApplied: [String]
    var validationResults: [ValidationResult]
}

struct ParseError: Codable {
    var rowNumber: Int
    var errorType: ParseErrorType
    var message: String
    var field: String?
    var value: String?
}

enum ParseErrorType: String, Codable, CaseIterable {
    case invalidFormat = "invalid_format"
    case missingRequired = "missing_required"
    case validationFailed = "validation_failed"
    case transformFailed = "transform_failed"
    case typeMismatch = "type_mismatch"
}

struct ValidationResult: Codable {
    var ruleName: String
    var passed: Bool
    var message: String?
    var severity: ValidationSeverity
}