//
//  Investigation.swift
//  cascade-ledger
//
//  AI's research and analysis of a discrepancy
//

import Foundation
import SwiftData

/// AI's investigation of a discrepancy
@Model
final class Investigation {
    var id: UUID
    var createdAt: Date

    // AI's analysis
    var hypothesis: String
    var evidenceAnalysis: String
    var uncertaintiesData: Data?  // JSON-encoded [String]
    var needsMoreData: Bool

    // Proposed solutions (JSON-encoded array)
    var proposedFixesData: Data?  // JSON-encoded [ProposedFix]

    // Metadata
    var aiModel: String
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double

    // Status
    var wasApplied: Bool
    var appliedFixIndex: Int?
    var appliedAt: Date?

    // Relationships
    @Relationship
    var discrepancy: Discrepancy?

    @Relationship
    var reconciliationSession: ReconciliationSession?

    // Computed properties
    var uncertainties: [String] {
        get {
            guard let data = uncertaintiesData,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            uncertaintiesData = try? JSONEncoder().encode(newValue)
        }
    }

    var proposedFixes: [ProposedFix] {
        get {
            guard let data = proposedFixesData,
                  let array = try? JSONDecoder().decode([ProposedFix].self, from: data) else {
                return []
            }
            return array
        }
        set {
            proposedFixesData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        hypothesis: String,
        evidenceAnalysis: String,
        uncertainties: [String] = [],
        needsMoreData: Bool = false,
        proposedFixes: [ProposedFix] = [],
        aiModel: String,
        inputTokens: Int,
        outputTokens: Int,
        durationSeconds: Double,
        discrepancy: Discrepancy
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.hypothesis = hypothesis
        self.evidenceAnalysis = evidenceAnalysis
        self.needsMoreData = needsMoreData
        self.aiModel = aiModel
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.durationSeconds = durationSeconds
        self.wasApplied = false
        self.discrepancy = discrepancy
        // Set via computed properties
        self.uncertainties = uncertainties
        self.proposedFixes = proposedFixes
    }
}
