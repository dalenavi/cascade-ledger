//
//  PriceDataService.swift
//  cascade-ledger
//
//  Service for managing asset price data
//

import Foundation
import SwiftData

@MainActor
class PriceDataService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Price Import

    /// Import prices from CSV file
    /// Expected format: Date,Symbol,Close  OR  Date,SPY,VOO,QQQ,...
    func importPricesFromCSV(_ csvContent: String) async throws -> PriceImportResult {
        let parser = CSVParser()
        let csvData = try parser.parse(csvContent)

        print("=== Price Data Import ===")
        print("Headers: \(csvData.headers.joined(separator: ", "))")
        print("Rows: \(csvData.rowCount)")

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        // Detect format
        if csvData.headers.count == 3 &&
           csvData.headers.contains(where: { $0.lowercased().contains("symbol") }) {
            // Format 1: Date, Symbol, Close
            (imported, updated, skipped, errors) = try await importLongFormat(csvData)
        } else if csvData.headers.count > 1 {
            // Format 2: Date, SPY, VOO, QQQ, ...
            (imported, updated, skipped, errors) = try await importWideFormat(csvData)
        } else {
            throw PriceDataError.invalidFormat
        }

        print("Imported: \(imported), Updated: \(updated), Skipped: \(skipped)")
        print("============================")

        return PriceImportResult(
            imported: imported,
            updated: updated,
            skipped: skipped,
            errors: errors
        )
    }

    // Import format: Date, Symbol, Close
    private func importLongFormat(_ csvData: CSVData) async throws -> (Int, Int, Int, [String]) {
        let dateIndex = csvData.headers.firstIndex(where: { $0.lowercased().contains("date") }) ?? 0
        let symbolIndex = csvData.headers.firstIndex(where: { $0.lowercased().contains("symbol") }) ?? 1
        let priceIndex = csvData.headers.firstIndex(where: { $0.lowercased().contains("close") || $0.lowercased().contains("price") }) ?? 2

        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (index, row) in csvData.rows.enumerated() {
            guard dateIndex < row.count, symbolIndex < row.count, priceIndex < row.count else {
                errors.append("Row \(index): Missing columns")
                continue
            }

            guard let date = parseDate(row[dateIndex]),
                  let price = Decimal(string: row[priceIndex].replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) else {
                errors.append("Row \(index): Invalid date or price")
                skipped += 1
                continue
            }

            let symbol = row[symbolIndex].trimmingCharacters(in: .whitespaces)

            let result = try upsertPrice(assetId: symbol, date: date, price: price, source: .csvImport)
            if result == .imported { imported += 1 }
            else if result == .updated { updated += 1 }
        }

        try modelContext.save()
        return (imported, updated, skipped, errors)
    }

    // Import format: Date, SPY, VOO, QQQ, ...
    private func importWideFormat(_ csvData: CSVData) async throws -> (Int, Int, Int, [String]) {
        let dateIndex = 0
        var imported = 0
        var updated = 0
        var skipped = 0
        var errors: [String] = []

        for (rowIndex, row) in csvData.rows.enumerated() {
            guard let date = parseDate(row[dateIndex]) else {
                errors.append("Row \(rowIndex): Invalid date")
                skipped += 1
                continue
            }

            // Process each asset column (skip date column)
            for (colIndex, header) in csvData.headers.enumerated() where colIndex > 0 {
                guard colIndex < row.count else { continue }

                let priceString = row[colIndex].trimmingCharacters(in: .whitespaces)
                guard !priceString.isEmpty,
                      let price = Decimal(string: priceString.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) else {
                    continue // Empty cell, skip
                }

                let result = try upsertPrice(assetId: header, date: date, price: price, source: .csvImport)
                if result == .imported { imported += 1 }
                else if result == .updated { updated += 1 }
            }
        }

        try modelContext.save()
        return (imported, updated, skipped, errors)
    }

    // MARK: - Price Lookup

    /// Get price for asset on or before a specific date
    func getPrice(assetId: String, on date: Date) throws -> Decimal? {
        let dayStart = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<AssetPrice>(
            predicate: #Predicate<AssetPrice> { price in
                price.assetId == assetId && price.date <= dayStart
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )

        guard let latestPrice = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return latestPrice.price
    }

    /// Get all prices for an asset in date range
    func getPrices(assetId: String, from startDate: Date, to endDate: Date) throws -> [AssetPrice] {
        let start = Calendar.current.startOfDay(for: startDate)
        let end = Calendar.current.startOfDay(for: endDate)

        let descriptor = FetchDescriptor<AssetPrice>(
            predicate: #Predicate<AssetPrice> { price in
                price.assetId == assetId &&
                price.date >= start &&
                price.date <= end
            },
            sortBy: [SortDescriptor(\.date)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Price Management

    private func upsertPrice(assetId: String, date: Date, price: Decimal, source: PriceSource) throws -> UpsertResult {
        let dayStart = Calendar.current.startOfDay(for: date)

        // Check if price exists for this asset/date
        let descriptor = FetchDescriptor<AssetPrice>(
            predicate: #Predicate<AssetPrice> { existing in
                existing.assetId == assetId && existing.date == dayStart
            }
        )

        let existing = try modelContext.fetch(descriptor).first

        if let existing = existing {
            // Update if price changed
            if existing.price != price {
                existing.price = price
                existing.source = source
                return .updated
            }
            return .skipped
        } else {
            // Insert new price
            let assetPrice = AssetPrice(
                assetId: assetId,
                date: dayStart,
                price: price,
                source: source
            )
            modelContext.insert(assetPrice)
            return .imported
        }
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "dd/MM/yyyy",
            "yyyy/MM/dd"
        ]

        let formatter = DateFormatter()
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // Try ISO8601
        return ISO8601DateFormatter().date(from: dateString)
    }

    // MARK: - Statistics

    func getPriceCount(for assetId: String? = nil) throws -> Int {
        if let assetId = assetId {
            let descriptor = FetchDescriptor<AssetPrice>(
                predicate: #Predicate<AssetPrice> { price in
                    price.assetId == assetId
                }
            )
            return try modelContext.fetch(descriptor).count
        } else {
            let descriptor = FetchDescriptor<AssetPrice>()
            return try modelContext.fetch(descriptor).count
        }
    }

    func getAvailableAssets() throws -> [String] {
        let descriptor = FetchDescriptor<AssetPrice>()
        let prices = try modelContext.fetch(descriptor)
        return Array(Set(prices.map { $0.assetId })).sorted()
    }
}

enum UpsertResult {
    case imported
    case updated
    case skipped
}

struct PriceImportResult {
    let imported: Int
    let updated: Int
    let skipped: Int
    let errors: [String]
}

enum PriceDataError: LocalizedError {
    case invalidFormat
    case noPriceAvailable
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid price CSV format. Expected: Date,Symbol,Close or Date,SPY,VOO,..."
        case .noPriceAvailable:
            return "No price data available for this asset/date"
        case .invalidDate:
            return "Invalid date format"
        }
    }
}
