//
//  Asset.swift
//  cascade-ledger
//
//  Master registry of all tradeable assets and currencies
//

import Foundation
import SwiftData

@Model
final class Asset {
    var id: UUID
    var symbol: String  // Canonical symbol like "SPY", "BTC"
    var name: String
    var assetClass: AssetClass
    var isCashEquivalent: Bool

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \Position.asset)
    var positions: [Position]

    @Relationship(deleteRule: .nullify, inverse: \JournalEntry.asset)
    var journalEntries: [JournalEntry]

    // Data source configuration
    var priceFeedType: String?  // Codable enum stored as string

    // Audit fields
    var createdAt: Date
    var updatedAt: Date

    init(symbol: String, name: String? = nil) {
        self.id = UUID()
        self.symbol = symbol.uppercased().trimmingCharacters(in: .whitespaces)
        self.name = name ?? symbol
        self.assetClass = AssetClass.infer(from: symbol)
        self.isCashEquivalent = false
        self.positions = []
        self.journalEntries = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

enum AssetClass: String, Codable, CaseIterable {
    case stock = "stock"
    case etf = "etf"
    case mutualFund = "mutual_fund"
    case crypto = "crypto"
    case cash = "cash"
    case commodity = "commodity"

    static func infer(from symbol: String) -> AssetClass {
        let upper = symbol.uppercased()

        // Cash equivalents
        if upper == "USD" || upper == "EUR" || upper == "GBP" { return .cash }
        if upper.hasSuffix("XX") { return .cash }  // SPAXX, VMFXX, etc.

        // Cryptocurrencies
        if ["BTC", "ETH", "SOL", "ADA", "DOT", "MATIC"].contains(upper) { return .crypto }

        // Mutual funds typically end in X
        if upper.hasSuffix("X") && upper.count == 5 { return .mutualFund }

        // Commodities
        if ["GLD", "SLV", "USO"].contains(upper) { return .commodity }

        // Default to stock (most common)
        return .stock
    }

    var displayName: String {
        switch self {
        case .stock: return "Stock"
        case .etf: return "ETF"
        case .mutualFund: return "Mutual Fund"
        case .crypto: return "Cryptocurrency"
        case .cash: return "Cash"
        case .commodity: return "Commodity"
        }
    }
}

enum PriceFeed: Codable {
    case yahoo(symbol: String)
    case coinGecko(id: String)
    case manual
    case none

    var typeString: String {
        switch self {
        case .yahoo: return "yahoo"
        case .coinGecko: return "coinGecko"
        case .manual: return "manual"
        case .none: return "none"
        }
    }
}
