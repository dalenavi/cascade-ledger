//
//  ImportSession.swift
//  cascade-ledger
//
//  Tracks imports as discrete sessions with full lifecycle management
//  Replaces ImportBatch with proper session semantics
//

import Foundation
import SwiftData
import CryptoKit

@Model
final class ImportSession {
    var id: UUID
    var fileName: String
    var fileHash: String  // SHA256 for deduplication
    var dataStartDate: Date  // Earliest transaction in file
    var dataEndDate: Date    // Latest transaction in file
    var status: ImportStatus

    // Import metadata
    var importedAt: Date
    var completedAt: Date?
    var importMode: ImportMode

    // Statistics
    var totalRows: Int
    var successfulRows: Int
    var failedRows: Int

    // Relationships
    @Relationship
    var account: Account?

    @Relationship
    var parsePlanVersion: ParsePlanVersion?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.importSession)
    var transactions: [Transaction]

    // Errors and warnings
    var errorsData: Data?  // JSON-encoded array of error strings

    var errors: [String] {
        get {
            guard let data = errorsData,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            errorsData = try? JSONEncoder().encode(newValue)
        }
    }

    init(
        fileName: String,
        fileData: Data,
        account: Account,
        parsePlanVersion: ParsePlanVersion
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.fileHash = Self.calculateHash(fileData)
        self.dataStartDate = Date()  // Will be updated during import
        self.dataEndDate = Date()    // Will be updated during import
        self.status = .pending
        self.importedAt = Date()
        self.importMode = .append
        self.totalRows = 0
        self.successfulRows = 0
        self.failedRows = 0
        self.account = account
        self.parsePlanVersion = parsePlanVersion
        self.transactions = []
        self.errors = []
    }

    /// Calculate SHA256 hash for file deduplication
    static func calculateHash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Rollback this import session
    func rollback(modelContext: ModelContext) {
        // Delete all transactions
        for transaction in transactions {
            modelContext.delete(transaction)
        }
        transactions.removeAll()

        // Mark as rolled back
        status = .rolledBack
        completedAt = Date()

        // Note: PositionCalculator will handle recalculation
    }
}

enum ImportStatus: String, Codable {
    case pending = "pending"
    case inProgress = "in_progress"
    case processing = "processing"
    case success = "success"
    case partialSuccess = "partial_success"
    case failed = "failed"
    case rolledBack = "rolled_back"
}

enum ImportMode: String, Codable {
    case append = "append"      // Add new transactions only
    case replace = "replace"    // Delete existing in date range, then add
    case merge = "merge"        // Smart merge, updating existing
}
