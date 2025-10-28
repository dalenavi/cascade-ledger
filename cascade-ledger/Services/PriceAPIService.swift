//
//  PriceAPIService.swift
//  cascade-ledger
//
//  Coordinate price fetching from multiple sources
//

import Foundation
import SwiftData

@MainActor
class PriceAPIService {
    private let modelContext: ModelContext
    private let yahooFinance = YahooFinanceService()
    private let coinGecko = CoinGeckoService()
    private let priceDataService: PriceDataService

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.priceDataService = PriceDataService(modelContext: modelContext)
    }

    // MARK: - Fetch Prices

    func fetchPricesForAsset(
        _ assetId: String,
        from: Date,
        to: Date
    ) async throws -> Int {
        let assetType = detectAssetType(assetId)

        let prices: [(Date, Decimal)]

        switch assetType {
        case .stock, .etf:
            prices = try await yahooFinance.fetchHistoricalPrices(
                symbol: assetId,
                from: from,
                to: to
            )

        case .crypto:
            prices = try await coinGecko.fetchHistoricalPrices(
                symbol: assetId,
                from: from,
                to: to
            )
        }

        // Store prices
        var importedCount = 0
        for (date, price) in prices {
            let assetPrice = AssetPrice(
                assetId: assetId,
                date: date,
                price: price,
                source: .api
            )

            // Check if exists
            let dayStart = Calendar.current.startOfDay(for: date)
            let descriptor = FetchDescriptor<AssetPrice>(
                predicate: #Predicate<AssetPrice> { existing in
                    existing.assetId == assetId && existing.date == dayStart
                }
            )

            let existing = try modelContext.fetch(descriptor)
            if existing.isEmpty {
                modelContext.insert(assetPrice)
                importedCount += 1
            }
        }

        try modelContext.save()
        print("Imported \(importedCount) new price points for \(assetId)")

        return importedCount
    }

    func fetchPricesForAllHoldings(account: Account) async throws -> [String: Int] {
        // Get unique assets from account's transactions
        let accountId = account.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { entry in
                entry.account?.id == accountId
            }
        )

        let entries = try modelContext.fetch(descriptor)
        let assets = Set(entries.compactMap { $0.assetId })
            .filter { !$0.isEmpty && $0.trimmingCharacters(in: .whitespaces).count > 0 }

        print("Fetching prices for \(assets.count) assets: \(assets.joined(separator: ", "))")

        var results: [String: Int] = [:]

        // Fetch last 2 years of data
        let to = Date()
        let from = Calendar.current.date(byAdding: .year, value: -2, to: to)!

        for asset in assets.sorted() {
            do {
                let count = try await fetchPricesForAsset(asset, from: from, to: to)
                results[asset] = count
            } catch {
                print("Failed to fetch \(asset): \(error)")
                results[asset] = 0
            }
        }

        return results
    }

    // MARK: - Asset Type Detection

    private func detectAssetType(_ assetId: String) -> AssetType {
        let upper = assetId.uppercased()

        // Only direct crypto coins (not funds)
        let directCrypto = ["BTC", "ETH", "SOL", "ADA"]
        if directCrypto.contains(upper) {
            return .crypto
        }

        // Everything else (including FBTC, GBTC, ETHE which are funds) is stock/ETF
        return .stock
    }
}

enum AssetType {
    case stock
    case etf
    case crypto

    var displayName: String {
        switch self {
        case .stock, .etf: return "Stock/ETF"
        case .crypto: return "Cryptocurrency"
        }
    }
}
