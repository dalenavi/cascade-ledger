//
//  YahooFinanceService.swift
//  cascade-ledger
//
//  Fetch stock/ETF prices from Yahoo Finance
//

import Foundation

class YahooFinanceService {
    func fetchHistoricalPrices(
        symbol: String,
        from: Date,
        to: Date
    ) async throws -> [(Date, Decimal)] {
        let url = "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)"

        var components = URLComponents(string: url)!
        components.queryItems = [
            URLQueryItem(name: "period1", value: "\(Int(from.timeIntervalSince1970))"),
            URLQueryItem(name: "period2", value: "\(Int(to.timeIntervalSince1970))"),
            URLQueryItem(name: "interval", value: "1d"),
            URLQueryItem(name: "events", value: "history")
        ]

        guard let requestURL = components.url else {
            throw PriceAPIError.invalidURL
        }

        print("Fetching \(symbol) from Yahoo Finance...")

        let (data, response) = try await URLSession.shared.data(from: requestURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw PriceAPIError.apiError("Yahoo Finance returned error")
        }

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let chart = json["chart"] as! [String: Any]

        guard let results = chart["result"] as? [[String: Any]],
              let result = results.first else {
            throw PriceAPIError.noData
        }

        let timestamps = result["timestamp"] as! [Int]
        let indicators = result["indicators"] as! [String: Any]
        let quotes = indicators["quote"] as! [[String: Any]]
        let quote = quotes.first!
        let closes = quote["close"] as! [Double?]

        var prices: [(Date, Decimal)] = []
        for (index, timestamp) in timestamps.enumerated() {
            guard let close = closes[index] else { continue }

            let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
            prices.append((date, Decimal(close)))
        }

        print("✓ Fetched \(prices.count) days for \(symbol)")
        return prices
    }

    func fetchLatestPrice(symbol: String) async throws -> Decimal {
        let to = Date()
        let from = Calendar.current.date(byAdding: .day, value: -7, to: to)!

        let prices = try await fetchHistoricalPrices(symbol: symbol, from: from, to: to)

        guard let latest = prices.last else {
            throw PriceAPIError.noData
        }

        return latest.1
    }
}

enum PriceAPIError: LocalizedError {
    case invalidURL
    case apiError(String)
    case noData
    case unsupportedAsset

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .apiError(let message):
            return "API error: \(message)"
        case .noData:
            return "No price data returned"
        case .unsupportedAsset:
            return "Asset type not supported"
        }
    }
}
