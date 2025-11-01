//
//  ProposedFix.swift
//  cascade-ledger
//
//  A specific correction with confidence and impact
//

import Foundation

/// A specific correction with confidence and impact
struct ProposedFix: Codable {
    var description: String
    var confidence: Double  // 0.0-1.0
    var reasoning: String

    // Changes to apply (stored as JSON-encoded deltas)
    var deltas: [DeltaTransactionData]

    // Impact prediction
    var impact: ImpactAnalysis

    // Evidence
    var supportingEvidence: [String]
    var assumptions: [String]
}

struct ImpactAnalysis: Codable {
    var balanceChange: Decimal
    var transactionsModified: Int
    var transactionsCreated: Int
    var transactionsDeleted: Int
    var checkpointsResolved: Int
    var newDiscrepanciesRisk: String?
}
