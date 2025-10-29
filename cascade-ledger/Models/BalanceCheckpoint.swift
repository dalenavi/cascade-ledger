//
//  BalanceCheckpoint.swift
//  cascade-ledger
//
//  Balance comparison at a specific point in time
//

import Foundation
import SwiftData

/// Compare CSV balance to calculated balance at specific points in time
@Model
final class BalanceCheckpoint {
    var id: UUID
    var date: Date
    var rowNumber: Int

    // Ground truth from CSV
    var csvBalance: Decimal
    var csvBalanceField: String  // Original CSV value

    // Our calculation from journal entries
    var calculatedBalance: Decimal

    // Analysis
    var discrepancyAmount: Decimal  // csvBalance - calculatedBalance
    var severityRaw: String  // Stored as String, use computed property

    // Context
    @Relationship
    var categorizationSession: CategorizationSession?

    @Relationship
    var reconciliationSession: ReconciliationSession?

    // Computed properties
    var hasDiscrepancy: Bool {
        abs(discrepancyAmount) > 0.01
    }

    var severity: DiscrepancySeverity {
        get { DiscrepancySeverity(rawValue: severityRaw) ?? .low }
        set { severityRaw = newValue.rawValue }
    }

    init(
        date: Date,
        rowNumber: Int,
        csvBalance: Decimal,
        csvBalanceField: String,
        calculatedBalance: Decimal,
        categorizationSession: CategorizationSession
    ) {
        self.id = UUID()
        self.date = date
        self.rowNumber = rowNumber
        self.csvBalance = csvBalance
        self.csvBalanceField = csvBalanceField
        self.calculatedBalance = calculatedBalance
        self.discrepancyAmount = csvBalance - calculatedBalance

        // Calculate severity
        let absDiscrepancy = abs(csvBalance - calculatedBalance)
        if absDiscrepancy > 1000 {
            self.severityRaw = DiscrepancySeverity.critical.rawValue
        } else if absDiscrepancy > 100 {
            self.severityRaw = DiscrepancySeverity.high.rawValue
        } else if absDiscrepancy > 10 {
            self.severityRaw = DiscrepancySeverity.medium.rawValue
        } else {
            self.severityRaw = DiscrepancySeverity.low.rawValue
        }

        self.categorizationSession = categorizationSession
    }
}

enum DiscrepancySeverity: String, Codable {
    case critical   // >$1000 or breaks accounting
    case high       // $100-1000
    case medium     // $10-100
    case low        // $0.01-10
}
