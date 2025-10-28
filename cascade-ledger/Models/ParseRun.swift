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

    @Relationship
    var parsePlanVersion: ParsePlanVersion?

    var totalRows: Int
    var successfulRows: Int
    var failedRows: Int
    var processedRows: Int

    // Legacy collections for compatibility - removed because SwiftData can't handle these properly
    // @Relationship var ledgerEntries: [Transaction] - causes store identification errors
    // Note: errors and lineageMappings removed - can't store non-PersistentModel types
    // Will be replaced in Phase 3 with proper error tracking

    init(importBatch: ImportBatch, parsePlanVersion: ParsePlanVersion? = nil) {
        self.id = UUID()
        self.startedAt = Date()
        self.importBatch = importBatch
        self.parsePlanVersion = parsePlanVersion
        self.totalRows = 0
        self.successfulRows = 0
        self.failedRows = 0
        self.processedRows = 0
    }
}
