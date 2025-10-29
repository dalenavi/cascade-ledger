//
//  SourceRowService.swift
//  cascade-ledger
//
//  Service for creating and managing SourceRow entities from CSV imports
//

import Foundation
import SwiftData

class SourceRowService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Create SourceRow objects from parsed CSV data
    /// Returns the created SourceRows for use in categorization
    func createSourceRows(
        from csvRows: [[String: String]],
        headers: [String],
        sourceFile: RawFile,
        account: Account
    ) throws -> [SourceRow] {
        print("📝 Creating SourceRows for \(csvRows.count) rows")

        // Auto-detect field mapping if not configured
        if account.csvFieldMapping == nil {
            let detected = CSVFieldMapping.detect(from: headers)
            account.csvFieldMapping = detected
            print("  ✓ Auto-detected field mapping:")
            print("    Balance field: \(detected.balanceField)")
            print("    Amount field: \(detected.amountField)")
            print("    Date field: \(detected.dateField)")
        }

        // Auto-detect balance instrument
        // Check if SPAXX appears in the CSV (indicates Fidelity account)
        let hasSPAXX = csvRows.contains { row in
            row.values.contains { $0.uppercased().contains("SPAXX") }
        }

        let currentInstrument = account.balanceInstrument ?? "Cash USD"
        let detectedInstrument = hasSPAXX ? "SPAXX" : "Cash USD"

        if currentInstrument != detectedInstrument {
            print("  🔄 Updating balance instrument: \(currentInstrument) → \(detectedInstrument)")
            account.balanceInstrument = detectedInstrument
        } else {
            print("  ✓ Balance instrument: \(detectedInstrument)")
        }

        guard let fieldMapping = account.csvFieldMapping else {
            throw SourceRowError.missingFieldMapping
        }

        var sourceRows: [SourceRow] = []

        for (index, row) in csvRows.enumerated() {
            let rowNumber = index + 1  // 1-based
            let globalRowNumber = Int(row["_globalRowNumber"] ?? "\(rowNumber)") ?? rowNumber

            // Map CSV row to standardized format
            guard let mappedData = mapCSVRow(row, using: fieldMapping) else {
                print("  ⚠️ Skipping row #\(globalRowNumber) - failed to map")
                continue
            }

            // Create SourceRow
            let sourceRow = SourceRow(
                rowNumber: rowNumber,
                globalRowNumber: globalRowNumber,
                sourceFile: sourceFile,
                rawData: row,
                mappedData: mappedData
            )

            modelContext.insert(sourceRow)
            sourceRows.append(sourceRow)

            // Log balance extraction
            if let balance = mappedData.balance {
                print("  ✓ Row #\(globalRowNumber): balance = \(balance)")
            }
        }

        // Batch save
        if sourceRows.count > 0 {
            try modelContext.save()
            print("📝 Created \(sourceRows.count) SourceRows")
        }

        return sourceRows
    }

    /// Map a CSV row to standardized MappedRowData
    private func mapCSVRow(_ row: [String: String], using mapping: CSVFieldMapping) -> MappedRowData? {
        // Parse date (required)
        guard let dateStr = row[mapping.dateField],
              let date = parseDate(dateStr) else {
            return nil
        }

        // Get action (required, but can be empty string)
        let action = row[mapping.actionField] ?? ""

        // Parse optional fields
        let symbol = row[mapping.symbolField ?? "Symbol"]
        let quantity = parseDecimal(row[mapping.quantityField ?? "Quantity"])
        let amount = parseDecimal(row[mapping.amountField])
        let price = parseDecimal(row[mapping.priceField ?? "Price"])
        let balance = parseDecimal(row[mapping.balanceField])

        let description = row[mapping.descriptionField ?? "Description"]
        let transactionType = row[mapping.typeField ?? "Type"]

        // Parse settlement date
        var settlementDate: Date? = nil
        if let field = mapping.settlementDateField,
           let dateStr = row[field] {
            settlementDate = parseDate(dateStr)
        }

        // Parse fees
        let commission = parseDecimal(row[mapping.commissionField ?? "Commission"])
        let fees = parseDecimal(row[mapping.feesField ?? "Fees"])
        let accruedInterest = parseDecimal(row[mapping.accruedInterestField ?? "Accrued Interest"])

        return MappedRowData(
            date: date,
            action: action,
            symbol: symbol,
            quantity: quantity,
            amount: amount,
            price: price,
            description: description,
            settlementDate: settlementDate,
            balance: balance,
            commission: commission,
            fees: fees,
            accruedInterest: accruedInterest,
            transactionType: transactionType
        )
    }

    /// Parse date with multiple format support
    private func parseDate(_ dateStr: String) -> Date? {
        let formats = [
            "MM/dd/yyyy",
            "yyyy-MM-dd",
            "M/d/yyyy",
            "dd/MM/yyyy"
        ]

        let dateFormatter = DateFormatter()
        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateStr) {
                return date
            }
        }

        return nil
    }

    /// Parse decimal amount (handles $, commas, etc.)
    private func parseDecimal(_ value: String?) -> Decimal? {
        guard let value = value else { return nil }

        // Clean string: remove $, commas, spaces
        var cleaned = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces)

        // Handle empty or non-numeric
        if cleaned.isEmpty || cleaned == "-" || cleaned == "--" {
            return nil
        }

        // Handle parentheses for negative (accounting format)
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            cleaned = "-" + cleaned.dropFirst().dropLast()
        }

        return Decimal(string: cleaned)
    }

    /// Get SourceRow by global row number
    func getSourceRow(globalRowNumber: Int) -> SourceRow? {
        let descriptor = FetchDescriptor<SourceRow>(
            predicate: #Predicate { $0.globalRowNumber == globalRowNumber }
        )

        do {
            let results = try modelContext.fetch(descriptor)
            return results.first
        } catch {
            print("⚠️ Error fetching SourceRow #\(globalRowNumber): \(error)")
            return nil
        }
    }

    /// Get multiple SourceRows by global row numbers
    func getSourceRows(globalRowNumbers: [Int]) -> [SourceRow] {
        let numberSet = Set(globalRowNumbers)
        let descriptor = FetchDescriptor<SourceRow>(
            predicate: #Predicate { row in
                numberSet.contains(row.globalRowNumber)
            }
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            print("⚠️ Error fetching SourceRows: \(error)")
            return []
        }
    }
}

enum SourceRowError: LocalizedError {
    case missingFieldMapping
    case invalidRowData

    var errorDescription: String? {
        switch self {
        case .missingFieldMapping:
            return "CSV field mapping is not configured for this account"
        case .invalidRowData:
            return "CSV row data is invalid or missing required fields"
        }
    }
}
