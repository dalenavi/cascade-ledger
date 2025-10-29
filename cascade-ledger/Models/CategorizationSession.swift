//
//  CategorizationSession.swift
//  cascade-ledger
//
//  AI-generated direct categorization of CSV rows to transactions
//

import Foundation
import SwiftData

/// Direct AI categorization session - maps specific CSV rows to Transaction objects
@Model
final class CategorizationSession {
    var id: UUID
    var sessionName: String
    var createdAt: Date

    // Versioning
    var versionNumber: Int                    // 1, 2, 3...
    var sessionMode: SessionMode              // full, incremental (future), override (future)
    var baseVersionNumber: Int?               // null for full, parent version for incremental

    // Source data fingerprint
    var sourceRowHashesData: Data?  // JSON-encoded array of hashes
    var totalSourceRows: Int

    // Row exclusions (non-transactional rows like disclaimers)
    var excludedRowNumbersData: Data?  // JSON-encoded array of row numbers

    // Computed property for excluded row numbers
    var excludedRowNumbers: [Int] {
        get {
            guard let data = excludedRowNumbersData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return array
        }
        set {
            excludedRowNumbersData = try? JSONEncoder().encode(newValue)
        }
    }

    // Chunking/Progress state
    var processedRowsCount: Int              // How many rows processed so far
    var isComplete: Bool                     // All chunks processed
    var isPaused: Bool                       // Paused by user
    var errorMessage: String?                // Error that caused pause (if any)

    // Computed property for sourceRowHashes
    var sourceRowHashes: [String] {
        get {
            guard let data = sourceRowHashesData,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            sourceRowHashesData = try? JSONEncoder().encode(newValue)
        }
    }

    // AI generation metadata (immutable artifact metadata)
    var aiModel: String  // e.g. "claude-haiku-4-5"
    var aiPromptVersion: String
    var aiResponseData: Data?  // Full JSON response from AI
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double
    var wasResponseTruncated: Bool  // true if hit max_tokens

    // Relationships
    @Relationship
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.categorizationSession)
    var transactions: [Transaction]

    @Relationship(deleteRule: .cascade, inverse: \CategorizationBatch.session)
    var batches: [CategorizationBatch]

    @Relationship(deleteRule: .cascade, inverse: \ReviewSession.categorizationSession)
    var reviewSessions: [ReviewSession]

    @Relationship(deleteRule: .cascade, inverse: \ReconciliationSession.categorizationSession)
    var reconciliationSessions: [ReconciliationSession]

    // Statistics
    var transactionCount: Int
    var balancedCount: Int
    var unbalancedCount: Int

    // Validation
    var isValid: Bool {
        unbalancedCount == 0
    }

    init(
        sessionName: String,
        sourceRowHashes: [String],
        account: Account,
        versionNumber: Int = 1,
        baseVersion: Int? = nil,
        mode: SessionMode = .full,
        aiModel: String = "claude-haiku-4-5",
        promptVersion: String = "v1"
    ) {
        self.id = UUID()
        self.sessionName = sessionName
        self.createdAt = Date()
        self.versionNumber = versionNumber
        self.sessionMode = mode
        self.baseVersionNumber = baseVersion
        self.totalSourceRows = sourceRowHashes.count
        self.account = account
        self.aiModel = aiModel
        self.aiPromptVersion = promptVersion
        self.transactions = []
        self.batches = []
        self.reviewSessions = []
        self.reconciliationSessions = []
        self.transactionCount = 0
        self.balancedCount = 0
        self.unbalancedCount = 0
        self.processedRowsCount = 0
        self.isComplete = false
        self.isPaused = false
        self.inputTokens = 0
        self.outputTokens = 0
        self.durationSeconds = 0
        self.wasResponseTruncated = false
        // Set hashes via computed property
        self.sourceRowHashes = sourceRowHashes
    }

    var progressPercentage: Double {
        guard totalSourceRows > 0 else { return 0 }
        return Double(processedRowsCount) / Double(totalSourceRows)
    }

    /// Update statistics after transactions are generated
    func updateStatistics() {
        transactionCount = transactions.count
        balancedCount = transactions.filter { $0.isBalanced }.count
        unbalancedCount = transactions.filter { !$0.isBalanced }.count
    }

    /// Build coverage index mapping row numbers to transactions
    func buildCoverageIndex() -> [Int: RowCoverage] {
        var index: [Int: RowCoverage] = [:]

        for transaction in transactions {
            for rowNum in transaction.sourceRowNumbers {
                if index[rowNum] == nil {
                    index[rowNum] = RowCoverage(rowNumber: rowNum, transactionIds: [])
                }
                index[rowNum]?.transactionIds.append(transaction.id)
            }
        }

        return index
    }

    /// Find row numbers that are not covered by any transaction and not excluded
    func findUncoveredRows() -> [Int] {
        let index = buildCoverageIndex()
        let allRowNumbers = Set(1...totalSourceRows)
        let coveredRowNumbers = Set(index.keys)
        let excludedRowNumbers = Set(self.excludedRowNumbers)

        // Uncovered = all rows - covered rows - excluded rows
        return Array(allRowNumbers.subtracting(coveredRowNumbers).subtracting(excludedRowNumbers)).sorted()
    }

    /// Get coverage percentage (excluding non-transactional rows)
    var coveragePercentage: Double {
        guard totalSourceRows > 0 else { return 0 }
        let transactionalRows = totalSourceRows - excludedRowNumbers.count
        guard transactionalRows > 0 else { return 1.0 }  // All excluded = 100% coverage
        let coveredCount = buildCoverageIndex().count
        return Double(coveredCount) / Double(transactionalRows)
    }

    /// Get effective total rows (excluding non-transactional rows)
    var effectiveSourceRows: Int {
        totalSourceRows - excludedRowNumbers.count
    }

    /// Find transactions that are unbalanced
    func findUnbalancedTransactions() -> [Transaction] {
        transactions.filter { !$0.isBalanced }
    }
}

enum SessionMode: String, Codable {
    case full = "full"                    // Complete categorization of all rows
    case incremental = "incremental"      // Future: Delta from base version (new rows)
    case override = "override"            // Future: Selective re-categorization of specific rows
}

/// Row coverage information
struct RowCoverage {
    var rowNumber: Int
    var transactionIds: [UUID]
    var isCovered: Bool { !transactionIds.isEmpty }
}

/// Gap analysis results
struct GapAnalysis {
    var uncoveredRows: [Int]
    var orphanedTransactions: [Transaction]  // Transactions with no valid source rows
    var unbalancedTransactions: [Transaction]
}
