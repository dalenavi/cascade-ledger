//
//  ParseRun.swift
//  cascade-ledger
//
//  Stub model for backward compatibility during rewrite
//

import Foundation
import SwiftData

@Model
final class ParseRun {
    var id: UUID
    var startedAt: Date
    var completedAt: Date?

    @Relationship
    var importBatch: ImportBatch?

    var totalRows: Int
    var successfulRows: Int
    var failedRows: Int

    init(importBatch: ImportBatch) {
        self.id = UUID()
        self.startedAt = Date()
        self.importBatch = importBatch
        self.totalRows = 0
        self.successfulRows = 0
        self.failedRows = 0
    }
}
