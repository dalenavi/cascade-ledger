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
protocol InstitutionDetector {
    func detect(fileData: Data, fileName: String) -> Institution?
}

/// Stage 2: Parse CSV into raw rows
protocol ImportCSVParser {
    func parse(fileData: Data) throws -> ParsedCSV
}

struct ParsedCSV {
    let headers: [String]
    let rows: [[String: String]]  // Each row as dict of column -> value
}

/// Stage 3: Detect settlement patterns
protocol SettlementDetector {
    func detectGroups(rows: [[String: String]]) -> [SettlementGroup]
}

struct SettlementGroup {
    let rows: [Int]  // Row indices that form a settlement
    let type: SettlementType
}

enum SettlementType: String {
    case buy
    case sell
    case dividend
    case transfer
    case fee
    case unknown
}

/// Stage 4: Transform CSV rows into transactions
protocol ImportTransactionBuilder {
    func build(
        groups: [SettlementGroup],
        rows: [[String: String]],
        account: Account,
        assetRegistry: AssetRegistry,
        modelContext: ModelContext
    ) async throws -> [Transaction]
}

/// Default implementation of the import pipeline
class DefaultImportPipeline: ImportPipeline {
    private let institutionDetector: InstitutionDetector
    private let csvParser: ImportCSVParser
    private let settlementDetector: SettlementDetector
    private let transactionBuilder: ImportTransactionBuilder

    init(
        institutionDetector: InstitutionDetector,
        csvParser: ImportCSVParser,
        settlementDetector: SettlementDetector,
        transactionBuilder: ImportTransactionBuilder
    ) {
        self.institutionDetector = institutionDetector
        self.csvParser = csvParser
        self.settlementDetector = settlementDetector
        self.transactionBuilder = transactionBuilder
    }

    func execute(
        session: ImportSession,
        fileData: Data,
        modelContext: ModelContext
    ) async throws -> ImportResult {
        // Stage 1: Detect institution (if not already known)
        // For now, skip - we'll use the ParsePlan's institution

        // Stage 2: Parse CSV
        let parsed = try csvParser.parse(fileData: fileData)

        // Stage 3: Detect settlement groups
        let groups = settlementDetector.detectGroups(rows: parsed.rows)

        // Stage 4: Build transactions
        guard let account = session.account else {
            throw ImportPipelineError.missingAccount
        }

        let transactions = try await transactionBuilder.build(
            groups: groups,
            rows: parsed.rows,
            account: account,
            assetRegistry: AssetRegistry.shared,
            modelContext: modelContext
        )

        // Update session
        session.totalRows = parsed.rows.count
        session.successfulRows = transactions.reduce(0) { $0 + $1.journalEntries.count }
        session.failedRows = parsed.rows.count - session.successfulRows
        session.transactions = transactions

        return ImportResult(
            totalRows: parsed.rows.count,
            successfulRows: session.successfulRows,
            failedRows: session.failedRows,
            transactions: transactions,
            errors: []
        )
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
