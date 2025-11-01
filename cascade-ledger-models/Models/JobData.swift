//
//  JobData.swift
//  cascade-ledger
//
//  Job-specific parameter and result types
//

import Foundation

// MARK: - Categorization Job

/// Parameters for categorization job
struct CategorizationJobParameters: Codable {
    var accountId: UUID
    var sessionId: UUID
    var csvRows: [[String: String]]
    var headers: [String]
    var startFromRow: Int  // For resumability
}

/// Results from categorization job
struct CategorizationJobResult: Codable {
    var sessionId: UUID
    var transactionsCreated: Int
    var rowsProcessed: Int
    var balanceAccuracy: Decimal?
    var warnings: [String]

    // API usage
    var totalInputTokens: Int
    var totalOutputTokens: Int
    var totalAPITime: Double
}

// MARK: - Future Job Types

/// Parameters for CSV import job (future)
struct ImportJobParameters: Codable {
    var accountId: UUID
    var filePath: String
    var fileType: String
}

/// Results from import job (future)
struct ImportJobResult: Codable {
    var rowsImported: Int
    var fileSize: Int
    var duration: Double
}
