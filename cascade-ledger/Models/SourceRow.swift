//
//  SourceRow.swift
//  cascade-ledger
//
//  Persistent representation of every CSV row with full provenance
//

import Foundation
import SwiftData

/// Represents a single row from an imported CSV file
/// Stores both raw CSV data and standardized mapped representation
@Model
final class SourceRow {
    var id: UUID
    var rowNumber: Int           // 1-based index within the source file
    var globalRowNumber: Int     // Unique identifier across all imports

    // Provenance
    @Relationship
    var sourceFile: RawFile

    // Data storage (JSON-encoded)
    var rawDataJSON: Data        // Original CSV [String: String]
    var mappedDataJSON: Data     // Standardized MappedRowData

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \JournalEntry.sourceRows)
    var journalEntries: [JournalEntry]

    // Metadata
    var createdAt: Date

    init(
        rowNumber: Int,
        globalRowNumber: Int,
        sourceFile: RawFile,
        rawData: [String: String],
        mappedData: MappedRowData
    ) {
        self.id = UUID()
        self.rowNumber = rowNumber
        self.globalRowNumber = globalRowNumber
        self.sourceFile = sourceFile
        self.createdAt = Date()

        // Encode raw data
        if let encoded = try? JSONEncoder().encode(rawData) {
            self.rawDataJSON = encoded
        } else {
            self.rawDataJSON = Data()
        }

        // Encode mapped data
        if let encoded = try? JSONEncoder().encode(mappedData) {
            self.mappedDataJSON = encoded
        } else {
            self.mappedDataJSON = Data()
        }

        self.journalEntries = []
    }
}

// MARK: - Computed Properties

extension SourceRow {
    /// Decoded raw CSV data
    var rawData: [String: String] {
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: rawDataJSON) else {
            return [:]
        }
        return decoded
    }

    /// Decoded standardized mapped data
    var mappedData: MappedRowData {
        guard let decoded = try? JSONDecoder().decode(MappedRowData.self, from: mappedDataJSON) else {
            return MappedRowData(date: Date(), action: "")
        }
        return decoded
    }

    /// Update raw data (re-encodes to JSON)
    func updateRawData(_ data: [String: String]) {
        if let encoded = try? JSONEncoder().encode(data) {
            self.rawDataJSON = encoded
        }
    }

    /// Update mapped data (re-encodes to JSON)
    func updateMappedData(_ data: MappedRowData) {
        if let encoded = try? JSONEncoder().encode(data) {
            self.mappedDataJSON = encoded
        }
    }
}

/// Standardized view of CSV row data, regardless of source format
struct MappedRowData: Codable {
    // Core fields (always present)
    var date: Date
    var action: String

    // Transaction details (optional)
    var symbol: String?
    var quantity: Decimal?
    var amount: Decimal?
    var price: Decimal?
    var description: String?

    // Settlement details
    var settlementDate: Date?
    var balance: Decimal?        // Standardized balance field

    // Fees & charges
    var commission: Decimal?
    var fees: Decimal?
    var accruedInterest: Decimal?

    // Metadata
    var transactionType: String?

    init(
        date: Date,
        action: String,
        symbol: String? = nil,
        quantity: Decimal? = nil,
        amount: Decimal? = nil,
        price: Decimal? = nil,
        description: String? = nil,
        settlementDate: Date? = nil,
        balance: Decimal? = nil,
        commission: Decimal? = nil,
        fees: Decimal? = nil,
        accruedInterest: Decimal? = nil,
        transactionType: String? = nil
    ) {
        self.date = date
        self.action = action
        self.symbol = symbol
        self.quantity = quantity
        self.amount = amount
        self.price = price
        self.description = description
        self.settlementDate = settlementDate
        self.balance = balance
        self.commission = commission
        self.fees = fees
        self.accruedInterest = accruedInterest
        self.transactionType = transactionType
    }
}

