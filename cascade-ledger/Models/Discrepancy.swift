//
//  Discrepancy.swift
//  cascade-ledger
//
//  Represents a problem that needs investigation
//

import Foundation
import SwiftData

/// A balance or transaction problem that needs investigation
@Model
final class Discrepancy {
    var id: UUID
    var typeRaw: String  // Stored as String, use computed property
    var severityRaw: String  // Stored as String, use computed property

    // Location
    var startDate: Date
    var endDate: Date
    var affectedRowNumbersData: Data?  // JSON-encoded [Int]

    // Problem description
    var summary: String
    var evidence: String
    var expectedValue: Decimal?
    var actualValue: Decimal?
    var delta: Decimal?

    // Resolution
    var isResolved: Bool
    var resolvedAt: Date?

    // Relationships
    @Relationship
    var categorizationSession: CategorizationSession?

    @Relationship
    var relatedCheckpoint: BalanceCheckpoint?

    @Relationship(deleteRule: .cascade, inverse: \Investigation.discrepancy)
    var investigations: [Investigation]

    // Computed properties
    var type: DiscrepancyType {
        get { DiscrepancyType(rawValue: typeRaw) ?? .balanceMismatch }
        set { typeRaw = newValue.rawValue }
    }

    var severity: DiscrepancySeverity {
        get { DiscrepancySeverity(rawValue: severityRaw) ?? .low }
        set { severityRaw = newValue.rawValue }
    }

    var affectedRowNumbers: [Int] {
        get {
            guard let data = affectedRowNumbersData,
                  let array = try? JSONDecoder().decode([Int].self, from: data) else {
                return []
            }
            return array
        }
        set {
            affectedRowNumbersData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        type: DiscrepancyType,
        severity: DiscrepancySeverity,
        startDate: Date,
        endDate: Date,
        affectedRowNumbers: [Int],
        summary: String,
        evidence: String,
        expectedValue: Decimal? = nil,
        actualValue: Decimal? = nil,
        delta: Decimal? = nil,
        categorizationSession: CategorizationSession,
        relatedCheckpoint: BalanceCheckpoint? = nil
    ) {
        self.id = UUID()
        self.typeRaw = type.rawValue
        self.severityRaw = severity.rawValue
        self.startDate = startDate
        self.endDate = endDate
        self.summary = summary
        self.evidence = evidence
        self.expectedValue = expectedValue
        self.actualValue = actualValue
        self.delta = delta
        self.isResolved = false
        self.categorizationSession = categorizationSession
        self.relatedCheckpoint = relatedCheckpoint
        self.investigations = []
        // Set via computed property
        self.affectedRowNumbers = affectedRowNumbers
    }
}

enum DiscrepancyType: String, Codable {
    case balanceMismatch      // Calculated ≠ CSV
    case unbalancedTxn        // DR ≠ CR
    case missingTransaction   // Pattern suggests missing data
    case incorrectAmount      // Amount doesn't match CSV
}
