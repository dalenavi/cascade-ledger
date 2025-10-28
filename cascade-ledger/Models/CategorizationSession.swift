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

    // Chunking/Progress state
    var processedRowsCount: Int              // How many rows processed so far
    var isComplete: Bool                     // All chunks processed
    var isPaused: Bool                       // Paused by user

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
}

enum SessionMode: String, Codable {
    case full = "full"                    // Complete categorization of all rows
    case incremental = "incremental"      // Future: Delta from base version (new rows)
    case override = "override"            // Future: Selective re-categorization of specific rows
}
