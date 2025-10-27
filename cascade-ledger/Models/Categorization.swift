//
//  Categorization.swift
//  cascade-ledger
//
//  Models for AI-driven categorization system
//

import Foundation
import SwiftData

@Model
final class CategorizationAttempt {
    var id: UUID
    var timestamp: Date

    @Relationship
    var transaction: LedgerEntry?

    // AI Proposal
    var proposedType: TransactionType?
    var proposedCategory: String?
    var proposedTags: [String]
    var confidence: Double // 0.0 to 1.0
    var reasoning: String? // Claude's explanation

    // Status
    var status: AttemptStatus

    // If corrected by user
    var actualType: TransactionType?
    var actualCategory: String?
    var actualTags: [String]
    var userFeedback: String? // User's explanation of correction

    init(
        transaction: LedgerEntry,
        proposedType: TransactionType? = nil,
        proposedCategory: String? = nil,
        proposedTags: [String] = [],
        confidence: Double,
        reasoning: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.transaction = transaction
        self.proposedType = proposedType
        self.proposedCategory = proposedCategory
        self.proposedTags = proposedTags
        self.confidence = confidence
        self.reasoning = reasoning
        self.actualTags = []

        // Auto-apply if high confidence
        if confidence >= 0.9 {
            self.status = .applied
        } else {
            self.status = .tentative
        }
    }

    // Apply the proposal to the transaction
    func apply() {
        guard let transaction = transaction else { return }

        if let proposedType = proposedType {
            transaction.userTransactionType = proposedType
        }
        if let proposedCategory = proposedCategory {
            transaction.userCategory = proposedCategory
        }
        if !proposedTags.isEmpty {
            transaction.tags = proposedTags
        }

        status = .applied
    }

    // Record user correction
    func correct(
        actualType: TransactionType?,
        actualCategory: String?,
        actualTags: [String],
        feedback: String? = nil
    ) {
        self.actualType = actualType
        self.actualCategory = actualCategory
        self.actualTags = actualTags
        self.userFeedback = feedback
        self.status = .corrected

        // Apply the correction to the transaction
        if let transaction = transaction {
            if let actualType = actualType {
                transaction.userTransactionType = actualType
            }
            if let actualCategory = actualCategory {
                transaction.userCategory = actualCategory
            }
            transaction.tags = actualTags
        }
    }

    // Reject the proposal
    func reject() {
        status = .rejected
    }
}

enum AttemptStatus: String, Codable {
    case tentative  // AI suggested, awaiting review
    case applied    // User accepted (or auto-applied)
    case rejected   // User declined
    case corrected  // User provided different answer
}

@Model
final class CategorizationPrompt {
    var id: UUID
    var promptText: String // Natural language categorization rules

    // Scope
    @Relationship
    var account: Account? // nil = global prompt

    // Versioning
    var version: Int
    var lastUpdated: Date

    // Statistics
    var successCount: Int     // Applied attempts using this prompt
    var correctionCount: Int  // Corrections made
    var totalAttempts: Int

    init(promptText: String, account: Account? = nil) {
        self.id = UUID()
        self.promptText = promptText
        self.account = account
        self.version = 1
        self.lastUpdated = Date()
        self.successCount = 0
        self.correctionCount = 0
        self.totalAttempts = 0
    }

    // Update prompt based on correction
    func learn(from attempt: CategorizationAttempt, newPattern: String) {
        // Append new pattern (keeping it concise)
        promptText += "\n\n" + newPattern

        version += 1
        lastUpdated = Date()
        correctionCount += 1
    }

    // Increment success count
    func recordSuccess() {
        successCount += 1
        totalAttempts += 1
    }

    // Get accuracy rate
    var accuracyRate: Double {
        guard totalAttempts > 0 else { return 0 }
        return Double(successCount) / Double(totalAttempts)
    }
}
