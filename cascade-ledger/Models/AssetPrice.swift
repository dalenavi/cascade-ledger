//
//  AssetPrice.swift
//  cascade-ledger
//
//  Price data for assets over time
//

import Foundation
import SwiftData

@Model
final class AssetPrice {
    var id: UUID
    var assetId: String        // SPY, FBTC, BTC, etc.
    var date: Date             // Price date (day granularity)
    var price: Decimal         // Price per unit in USD
    var source: PriceSource    // Where this price came from
    var createdAt: Date

    init(assetId: String, date: Date, price: Decimal, source: PriceSource) {
        self.id = UUID()
        self.assetId = assetId
        self.date = Calendar.current.startOfDay(for: date)  // Normalize to day
        self.price = price
        self.source = source
        self.createdAt = Date()
    }
}

enum PriceSource: String, Codable {
    case transaction    // Extracted from buy/sell transactions
    case csvImport      // Imported from price data CSV
    case api            // Fetched from API (future)
    case manual         // User-entered
}
