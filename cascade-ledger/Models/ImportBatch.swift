//
//  ImportBatch.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData

@Model
final class ImportBatch {
    var id: UUID
    var timestamp: Date

    // User-defined metadata
    var batchName: String?
    var dateRangeStart: Date?
    var dateRangeEnd: Date?

    @Relationship
    var account: Account?

    @Relationship
    var rawFile: RawFile?

    @Relationship
    var parsePlanVersion: ParsePlanVersion?

    var status: ImportStatus
    var totalRows: Int
    var successfulRows: Int
    var failedRows: Int
    var duplicateRows: Int = 0  // Default value for migration

    @Relationship(deleteRule: .cascade, inverse: \Transaction.importSession)
    var transactions: [Transaction]

    var createdAt: Date
    var completedAt: Date?

    init(account: Account, rawFile: RawFile) {
        self.id = UUID()
        self.timestamp = Date()
        self.account = account
        self.rawFile = rawFile
        self.status = .pending
        self.totalRows = 0
        self.successfulRows = 0
        self.failedRows = 0
        self.duplicateRows = 0
        self.transactions = []
        self.createdAt = Date()
    }
}

@Model
final class RawFile {
    var id: UUID
    var fileName: String
    var fileSize: Int64
    var sha256Hash: String // For deduplication
    var content: Data // Raw file content
    var mimeType: String
    var isArchived: Bool = false // Archive instead of delete

    @Relationship(deleteRule: .nullify)
    var importBatches: [ImportBatch]

    @Relationship(deleteRule: .cascade, inverse: \SourceRow.sourceFile)
    var sourceRows: [SourceRow]

    var uploadedAt: Date

    init(fileName: String, content: Data, mimeType: String = "text/csv") {
        self.id = UUID()
        self.fileName = fileName
        self.content = content
        self.fileSize = Int64(content.count)
        self.sha256Hash = content.sha256Hash()
        self.mimeType = mimeType
        self.isArchived = false
        self.importBatches = []
        self.sourceRows = []
        self.uploadedAt = Date()
    }
}

// Extension for SHA256 hash calculation
import CryptoKit

extension Data {
    func sha256Hash() -> String {
        let hash = SHA256.hash(data: self)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}