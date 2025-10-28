//
//  Position.swift
//  cascade-ledger
//
//  Materialized holdings per account-asset combination
//

import Foundation
import SwiftData

@Model
final class Position {
    var id: UUID
    var quantity: Decimal
    var lastTransactionDate: Date
    var lastCalculated: Date

    // Relationships
    @Relationship
    var account: Account?

    @Relationship
    var asset: Asset?

    // Future: Cost basis tracking (stubbed)
    // var lots: [Lot] = []

    // Cached calculations
    var averageCost: Decimal?
    var totalCost: Decimal?

    init(account: Account, asset: Asset) {
        self.id = UUID()
        self.account = account
        self.asset = asset
        self.quantity = 0
        self.lastTransactionDate = Date()
        self.lastCalculated = Date()
    }

    /// Recalculate position from transaction history
    func recalculate(from transactions: [Transaction]) {
        guard let asset = self.asset else { return }

        var calculatedQuantity: Decimal = 0
        var latestDate = Date.distantPast

        for transaction in transactions {
            // Sum up quantity changes from journal entries for this asset
            for entry in transaction.journalEntries {
                if entry.asset?.id == asset.id {
                    calculatedQuantity += entry.netQuantityChange
                    if transaction.date > latestDate {
                        latestDate = transaction.date
                    }
                }
            }
        }

        self.quantity = calculatedQuantity
        self.lastTransactionDate = latestDate
        self.lastCalculated = Date()
    }
}

// Future: Cost basis lot tracking
// struct Lot: Codable {
//     let id: UUID
//     let purchaseDate: Date
//     let quantity: Decimal
//     let costPerUnit: Decimal
//     var remainingQuantity: Decimal
// }
