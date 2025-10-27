//
//  CoinGeckoService.swift
//  cascade-ledger
//
//  Fetch cryptocurrency prices from CoinGecko
//

import Foundation

class CoinGeckoService {
    func fetchHistoricalPrices(
        symbol: String,  // BTC, ETH, FBTC
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)] {
        let coinId = mapSymbolToCoinId(symbol)

        let url = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart/range"

        var components = URLComponents(string: url)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "from", value: "\(Int(from.timeIntervalSince1970))"),
            URLQueryItem(name: "to", value: "\(Int(to.timeIntervalSince1970))")
        ]

        guard let requestURL = components.url else {
            throw PriceAPIError.invalidURL
        }

        print("Fetching \(symbol) from CoinGecko...")

        let (data, response) = try await URLSession.shared.data(from: requestURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PriceAPIError.apiError("CoinGecko returned error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        guard let pricesArray = json["prices"] as? [[Any]] else {
            throw PriceAPIError.noData
        }

        var prices: [(Date, Decimal)] = []
        for item in pricesArray {
            guard let timestamp = item[0] as? TimeInterval,
                  let priceValue = item[1] as? Double else {
                continue
            }

            let date = Date(timeIntervalSince1970: timestamp / 1000)  // CoinGecko uses milliseconds
            prices.append((date, Decimal(priceValue)))
        }

        print("✓ Fetched \(prices.count) days for \(symbol)")
        return prices
    }

    func fetchLatestPrice(symbol: String) async throws -> Decimal {
        let coinId = mapSymbolToCoinId(symbol)
        let url = "https://api.coingecko.com/api/v3/simple/price"

        var components = URLComponents(string: url)!
        components.queryItems = [
            URLQueryItem(name: "ids", value: coinId),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]

        guard let requestURL = components.url else {
            throw PriceAPIError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: requestURL)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        guard let coinData = json[coinId] as? [String: Any],
              let priceValue = coinData["usd"] as? Double else {
            throw PriceAPIError.noData
        }

        return Decimal(priceValue)
    }

    private func mapSymbolToCoinId(_ symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC":
            return "bitcoin"
        case "ETH":
            return "ethereum"
        case "SOL":
            return "solana"
        case "ADA":
            return "cardano"
        // Currency pairs (for exchange rates)
        case "USD-BTC":
            return "bitcoin"  // Will invert the price
        case "USD-ETH":
            return "ethereum"
        default:
            return symbol.lowercased()
        }
    }

    // Fetch exchange rate (inverted crypto price)
    func fetchExchangeRate(
        pair: String,  // "USD-BTC", "USD-AUD"
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)] {
        // For USD-BTC, fetch BTC price and invert
        if pair == "USD-BTC" {
            let btcPrices = try await fetchHistoricalPrices(symbol: "BTC", from: from, to: to)
            return btcPrices.map { (date, price) in
                (date, 1 / price)  // USD-BTC rate = 1 / BTC-USD price
            }
        }

        // For fiat currencies, would need different API (future)
        throw PriceAPIError.unsupportedAsset
    }
}
