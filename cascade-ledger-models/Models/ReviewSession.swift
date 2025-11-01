//
//  ReviewSession.swift
//  cascade-ledger
//
//  Transaction review and refinement tracking
//

import Foundation
import SwiftData

/// Tracks a review operation on transactions
@Model
final class ReviewSession {
    var id: UUID
    var createdAt: Date

    // Scope
    @Relationship
    var categorizationSession: CategorizationSession?
    var startDate: Date
    var endDate: Date
    var rowsInScopeData: Data?  // JSON-encoded [Int]

    // Computed property for rows in scope
    var rowsInScope: [Int] {
        get {
            guard let data = rowsInScopeData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return array
        }
        set {
            rowsInScopeData = try? JSONEncoder().encode(newValue)
        }
    }

    // Results
    var transactionsCreated: Int
    var transactionsUpdated: Int
    var transactionsDeleted: Int
    var uncoveredRowsFound: Int

    // AI generation metadata
    var aiModel: String
    var aiPromptVersion: String
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double

    // Status
    var isComplete: Bool
    var errorMessage: String?

    @Relationship(deleteRule: .cascade, inverse: \TransactionDelta.reviewSession)
    var deltas: [TransactionDelta]

    init(
        categorizationSession: CategorizationSession,
        startDate: Date,
        endDate: Date,
        rowsInScope: [Int],
        aiModel: String = "claude-haiku-4-5",
        promptVersion: String = "review-v1"
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.categorizationSession = categorizationSession
        self.startDate = startDate
        self.endDate = endDate
        self.transactionsCreated = 0
        self.transactionsUpdated = 0
        self.transactionsDeleted = 0
        self.uncoveredRowsFound = rowsInScope.count
        self.aiModel = aiModel
        self.aiPromptVersion = promptVersion
        self.inputTokens = 0
        self.outputTokens = 0
        self.durationSeconds = 0
        self.isComplete = false
        self.deltas = []
        // Set rows via computed property after all stored properties initialized
        self.rowsInScopeData = try? JSONEncoder().encode(rowsInScope)
    }
}

/// Review mode determines what the AI should focus on
enum ReviewMode: String, Codable {
    case gapFilling       // Focus on creating transactions for uncovered rows
    case qualityCheck     // Verify existing transactions are correct
    case fullReview       // Both gap filling and quality check
    case targeted         // Review specific issues
}
