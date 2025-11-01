//
//  ReconciliationSession.swift
//  cascade-ledger
//
//  Tracks a reconciliation run
//

import Foundation
import SwiftData

/// Tracks a balance reconciliation run
@Model
final class ReconciliationSession {
    var id: UUID
    var createdAt: Date

    // Analysis
    var checkpointsBuilt: Int
    var discrepanciesFound: Int
    var discrepanciesResolved: Int

    // Investigations run
    @Relationship(deleteRule: .cascade, inverse: \Investigation.reconciliationSession)
    var investigations: [Investigation]
    var fixesApplied: Int

    // Results
    var initialMaxDiscrepancy: Decimal
    var finalMaxDiscrepancy: Decimal
    var isFullyReconciled: Bool

    // Status
    var isComplete: Bool
    var iterations: Int
    var errorMessage: String?

    // Relationships
    @Relationship
    var categorizationSession: CategorizationSession?

    @Relationship(deleteRule: .cascade)
    var checkpoints: [BalanceCheckpoint]

    @Relationship(deleteRule: .cascade)
    var discrepancies: [Discrepancy]

    init(
        categorizationSession: CategorizationSession
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.categorizationSession = categorizationSession
        self.checkpointsBuilt = 0
        self.discrepanciesFound = 0
        self.discrepanciesResolved = 0
        self.investigations = []
        self.fixesApplied = 0
        self.initialMaxDiscrepancy = 0
        self.finalMaxDiscrepancy = 0
        self.isFullyReconciled = false
        self.isComplete = false
        self.iterations = 0
        self.checkpoints = []
        self.discrepancies = []
    }
}
