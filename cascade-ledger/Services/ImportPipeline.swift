//
//  ImportPipeline.swift
//  cascade-ledger
//
//  Protocol and types for the import pipeline
//

import Foundation
import SwiftData

/// Main pipeline protocol
protocol ImportPipeline {
    /// Execute the full import pipeline
    func execute(
        session: ImportSession,
        fileData: Data,
        modelContext: ModelContext
    ) async throws -> ImportResult
}

/// Result of an import operation
struct ImportResult {
    let totalRows: Int
    let successfulRows: Int
    let failedRows: Int
    let transactions: [Transaction]
    let errors: [ImportError]

    var isSuccess: Bool {
        failedRows == 0
    }
}

/// Import error with context
struct ImportError: Error {
    let row: Int
    let message: String
    let context: [String: String]
}

/// Stage 1: Detect institution from file content
/// NOTE: See InstitutionDetector.swift for actual implementation

/// Stage 2: Parse CSV into raw rows
protocol ImportCSVParser {
    func parse(fileData: Data) throws -> ParsedCSV
}

struct ParsedCSV {
    let headers: [String]
    let rows: [[String: String]]  // Each row as dict of column -> value
}

/// Stage 3: Detect settlement patterns
/// NOTE: See SettlementDetector.swift for actual protocol and implementations

/// Stage 4: Transform CSV rows into transactions
/// NOTE: See TransactionBuilder.swift for actual implementation

/// Default implementation of the import pipeline
/// NOTE: This is a placeholder. Phase 3 will implement proper pipeline using new architecture
class DefaultImportPipeline: ImportPipeline {

    func execute(
        session: ImportSession,
        fileData: Data,
        modelContext: ModelContext
    ) async throws -> ImportResult {
        // TODO: Implement proper pipeline with:
        // 1. InstitutionDetector
        // 2. SettlementDetector
        // 3. TransactionBuilder with AssetRegistry
        // 4. PositionCalculator updates

        throw ImportPipelineError.unsupportedInstitution
    }
}

enum ImportPipelineError: LocalizedError {
    case missingAccount
    case invalidCSV
    case unsupportedInstitution

    var errorDescription: String? {
        switch self {
        case .missingAccount:
            return "Import session missing account"
        case .invalidCSV:
            return "Invalid CSV format"
        case .unsupportedInstitution:
            return "Institution not supported"
        }
    }
}
