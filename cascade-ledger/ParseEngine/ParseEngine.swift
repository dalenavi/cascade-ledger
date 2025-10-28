//
//  ParseEngine.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import Combine

// Main parse engine that coordinates parsing, transformation, and validation
@MainActor
class ParseEngine: ObservableObject {
    private let csvParser: CSVParser
    private let transformExecutor: TransformExecutor
    private let modelContext: ModelContext

    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentStatus = ""

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.csvParser = CSVParser()
        self.transformExecutor = TransformExecutor()
    }

    // MARK: - Preview Operations

    // Parse and preview CSV with parse plan - processes ALL rows
    func previewParse(rawFile: RawFile, parsePlan: ParsePlan) async throws -> ParsePreview {
        let definition = parsePlan.workingCopy ?? ParsePlanDefinition()

        // Parse entire CSV
        let csvContent = String(data: rawFile.content, encoding: .utf8) ?? ""
        let parser = CSVParser(dialect: definition.dialect)
        let csvData = try parser.parse(csvContent)

        print("Preview parsing \(csvData.rowCount) rows")

        // Transform rows
        var transformedRows: [TransformedRow] = []
        var errors: [ParseError] = []

        for (index, row) in csvData.rows.enumerated() {
            let rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))

            do {
                let transformed = try transformExecutor.transformRow(
                    rowDict,
                    schema: definition.schema,
                    transforms: definition.transforms
                )

                // Validate
                let validationResults = try validateRow(transformed, rules: definition.validations)

                transformedRows.append(TransformedRow(
                    rowNumber: index,
                    originalData: rowDict,
                    transformedData: transformed,
                    validationResults: validationResults,
                    isValid: validationResults.allSatisfy { $0.passed }
                ))
            } catch {
                errors.append(ParseError(
                    rowNumber: index,
                    errorType: .transformFailed,
                    message: error.localizedDescription,
                    field: nil,
                    value: nil
                ))
            }
        }

        return ParsePreview(
            totalRows: csvData.rowCount,
            sampledRows: transformedRows.count,
            transformedRows: transformedRows,
            errors: errors,
            headers: csvData.headers,
            successRate: Double(transformedRows.filter { $0.isValid }.count) / Double(transformedRows.count)
        )
    }

    // MARK: - Full Import Operations

    // Execute full import with parse plan version
    func executeImport(
        importBatch: ImportBatch,
        parsePlanVersion: ParsePlanVersion,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ParseRun {
        guard let rawFile = importBatch.rawFile else {
            throw ParseEngineError.missingRawFile
        }

        isProcessing = true
        progress = 0.0
        currentStatus = "Starting import..."

        defer {
            isProcessing = false
            progress = 1.0
            currentStatus = "Import complete"
        }

        // Create parse run
        let parseRun = ParseRun(importBatch: importBatch, parsePlanVersion: parsePlanVersion)
        modelContext.insert(parseRun)

        // Parse CSV
        currentStatus = "Parsing CSV..."
        let csvContent = String(data: rawFile.content, encoding: .utf8) ?? ""
        let parser = CSVParser(dialect: parsePlanVersion.definition.dialect)
        let csvData = try parser.parse(csvContent)

        parseRun.totalRows = csvData.rowCount
        var duplicateCount = 0

        // Check existing ledger entry count before import
        let allEntriesDescriptor = FetchDescriptor<Transaction>()
        let existingEntryCount = (try? modelContext.fetch(allEntriesDescriptor).count) ?? 0

        print("=== Full Import Starting ===")
        print("Total rows to process: \(csvData.rowCount)")
        print("Existing ledger entries in database: \(existingEntryCount)")
        print("Account: \(importBatch.account?.name ?? "Unknown")")
        print("Headers: \(csvData.headers.joined(separator: ", "))")

        // Process in chunks for better performance
        let chunkSize = 100
        let chunks = csvData.rows.chunked(into: chunkSize)
        print("Processing in \(chunks.count) chunks of \(chunkSize) rows")

        for (chunkIndex, chunk) in chunks.enumerated() {
            currentStatus = "Processing chunk \(chunkIndex + 1) of \(chunks.count)..."

            for (rowIndex, row) in chunk.enumerated() {
                let globalRowIndex = chunkIndex * chunkSize + rowIndex
                let rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))

                do {
                    // Transform row
                    let transformed = try transformExecutor.transformRow(
                        rowDict,
                        schema: parsePlanVersion.definition.schema,
                        transforms: parsePlanVersion.definition.transforms
                    )

                    // Validate
                    let validationResults = try validateRow(
                        transformed,
                        rules: parsePlanVersion.definition.validations
                    )

                    let isValid = validationResults.allSatisfy { $0.passed }

                    if isValid {
                        // Create ledger entry
                        let ledgerEntry = try createTransaction(
                            from: transformed,
                            account: importBatch.account!,
                            importBatch: importBatch,
                            parseRun: parseRun,
                            rowNumber: globalRowIndex
                        )

                        // Check for duplicate before inserting (exclude current batch)
                        let isDuplicate = try checkForDuplicate(ledgerEntry, currentBatchId: importBatch.id)

                        if isDuplicate {
                            print("⊘ Skipping duplicate: \(ledgerEntry.transactionDescription.prefix(50)) on \(ledgerEntry.date)")
                            duplicateCount += 1
                            // Don't count as failed, just skipped
                        } else {
                            modelContext.insert(ledgerEntry)
                            // parseRun.ledgerEntries removed - can't store arrays in SwiftData
                            parseRun.successfulRows += 1
                        }
                    } else {
                        // Record validation failure (legacy error tracking removed)
                        parseRun.failedRows += 1
                    }

                    // Legacy lineage mapping removed - will be replaced in Phase 3

                } catch {
                    // Record transform error (legacy error tracking removed)
                    parseRun.failedRows += 1
                }

                parseRun.processedRows += 1

                // Update progress
                let progressValue = Double(parseRun.processedRows) / Double(parseRun.totalRows)
                progress = progressValue
                onProgress?(progressValue)
            }

            // Save periodically
            try modelContext.save()
        }

        // Update import batch status
        importBatch.totalRows = parseRun.totalRows
        importBatch.successfulRows = parseRun.successfulRows
        importBatch.failedRows = parseRun.failedRows
        importBatch.duplicateRows = duplicateCount

        if parseRun.failedRows == 0 && duplicateCount == 0 {
            importBatch.status = .success
        } else if parseRun.successfulRows > 0 {
            importBatch.status = .partialSuccess
        } else {
            importBatch.status = .failed
        }

        importBatch.completedAt = Date()
        parseRun.completedAt = Date()

        print("=== Import Complete ===")
        print("Total rows: \(parseRun.totalRows)")
        print("✓ Successful: \(parseRun.successfulRows)")
        print("⊘ Duplicates skipped: \(duplicateCount)")
        print("✗ Failed: \(parseRun.failedRows)")
        print("Ledger entries created: \(parseRun.successfulRows)")

        try modelContext.save()

        return parseRun
    }

    // MARK: - Helper Methods

    // Check if transaction already exists (excluding current import batch)
    private func checkForDuplicate(_ entry: Transaction, currentBatchId: UUID) throws -> Bool {
        guard let hash = entry.sourceHash else {
            return false // No hash, can't check for duplicates
        }

        // Simplified predicate to avoid macro issues
        let descriptor = FetchDescriptor<Transaction>()
        let allTransactions = try modelContext.fetch(descriptor)

        let results = allTransactions.filter { existing in
            existing.sourceHash == hash &&
            existing.importSession?.id != currentBatchId  // Exclude current batch
        }

        if !results.isEmpty {
            let existing = results.first!
            print("  🔍 DUPLICATE FOUND (from previous import):")
            print("     Hash: \(hash.prefix(16))...")
            print("     New: \(entry.date.formatted(date: .abbreviated, time: .omitted)) \(entry.transactionDescription.prefix(40)) \(entry.amount)")
            print("     Existing: \(existing.date.formatted(date: .abbreviated, time: .omitted)) \(existing.transactionDescription.prefix(40)) \(existing.amount)")
        }

        return !results.isEmpty
    }

    // Validate row against rules
    private func validateRow(_ row: [String: Any], rules: [ValidationRule]) throws -> [ValidationResult] {
        var results: [ValidationResult] = []

        for rule in rules {
            let passed = try evaluateValidationRule(rule, row: row)
            results.append(ValidationResult(
                ruleName: rule.name,
                passed: passed,
                message: passed ? nil : rule.errorMessage,
                severity: rule.severity
            ))
        }

        return results
    }

    // Evaluate validation rule
    private func evaluateValidationRule(_ rule: ValidationRule, row: [String: Any]) throws -> Bool {
        switch rule.type {
        case .required:
            let fieldName = rule.expression
            return row[fieldName] != nil

        case .format:
            // Implement format validation
            return true

        case .range:
            // Implement range validation
            return true

        case .uniqueness:
            // Would require checking against existing entries
            return true

        case .consistency:
            // Implement consistency checks
            return true

        case .custom:
            // Execute custom validation expression
            return true
        }
    }

    // Create ledger entry from transformed data
    private func createTransaction(
        from data: [String: Any],
        account: Account,
        importBatch: ImportBatch,
        parseRun: ParseRun,
        rowNumber: Int
    ) throws -> Transaction {
        // Extract required fields
        guard let date = data["date"] as? Date else {
            throw ParseEngineError.missingRequiredField("date")
        }

        let amount: Decimal
        if let decimalAmount = data["amount"] as? Decimal {
            amount = decimalAmount
        } else if let doubleAmount = data["amount"] as? Double {
            amount = Decimal(doubleAmount)
        } else {
            throw ParseEngineError.missingRequiredField("amount")
        }

        let description = data["description"] as? String ?? data["transactionDescription"] as? String ?? ""

        // Determine transaction type
        let transactionType = determineTransactionType(from: data)

        // Capture raw transaction type from CSV if present
        let rawType = data["transactionType"] as? String
            ?? data["type"] as? String
            ?? data["action"] as? String

        // LEGACY: Create transaction with old single-entry pattern
        // TODO: Phase 3 will refactor this to use proper double-entry TransactionBuilder
        let ledgerEntry = Transaction(
            date: date,
            description: description,
            type: transactionType,
            account: account
        )

        // Set fields compatible with new model
        ledgerEntry.importSession = nil  // Will be set by caller
        ledgerEntry.sourceRowNumbers = [rowNumber]
        ledgerEntry.userCategory = data["category"] as? String

        // Generate source hash for deduplication
        let hashString = "\(date.timeIntervalSince1970)|\(description)|\(amount)|\(account.id.uuidString)"
        ledgerEntry.sourceHash = hashString

        // LEGACY: Old fields that don't exist in new model - skipped
        // - parseRun (deprecated)
        // - rawTransactionType (stub property)
        // - normalizedDescription (not in new model)
        // - quantity/quantityUnit (now in JournalEntry, not Transaction)
        // - metadata (stub property)

        print("Transaction: \(ledgerEntry.transactionDescription.prefix(50)) | Type: \(transactionType)")

        return ledgerEntry
    }

    // Determine transaction type from data
    private func determineTransactionType(from data: [String: Any]) -> TransactionType {
        if let typeString = data["transactionType"] as? String,
           let type = TransactionType(rawValue: typeString) {
            return type
        }

        // Try to infer from other fields
        if let action = data["action"] as? String {
            switch action.lowercased() {
            case "buy": return .buy
            case "sell": return .sell
            case "deposit": return .deposit
            case "withdrawal": return .withdrawal
            case "transfer": return .transfer
            case "dividend": return .dividend
            case "interest": return .interest
            case "fee": return .fee
            case "tax": return .tax
            default: break
            }
        }

        // Default based on amount
        if let amount = data["amount"] as? Double {
            return amount < 0 ? .withdrawal : .deposit
        }

        return .other
    }

    // Infer quantity unit from asset ID
    private func inferQuantityUnit(assetId: String?) -> String? {
        guard let assetId = assetId else { return nil }

        // Direct crypto tickers (actual coins)
        if assetId == "BTC" {
            return "BTC"
        }
        if assetId == "ETH" {
            return "ETH"
        }
        if assetId == "SOL" {
            return "SOL"
        }

        // Everything else (including FBTC, GBTC which are funds) are shares
        return "shares"
    }
}

// Parse preview result
struct ParsePreview {
    let totalRows: Int
    let sampledRows: Int
    let transformedRows: [TransformedRow]
    let errors: [ParseError]
    let headers: [String]
    let successRate: Double
}

struct ParseError {
    let rowNumber: Int
    let errorType: ParseErrorType
    let message: String
    let field: String?
    let value: String?
}

enum ParseErrorType {
    case transformFailed
    case validationFailed
    case missingField
    case invalidFormat
}

struct ValidationResult {
    let ruleName: String
    let passed: Bool
    let message: String?
    let severity: ValidationSeverity

    init(ruleName: String, passed: Bool, message: String?, severity: ValidationSeverity = .error) {
        self.ruleName = ruleName
        self.passed = passed
        self.message = message
        self.severity = severity
    }
}

struct TransformedRow: Identifiable {
    let id = UUID()
    let rowNumber: Int
    let originalData: [String: String]
    let transformedData: [String: Any]
    let validationResults: [ValidationResult]
    let isValid: Bool
}

enum ParseEngineError: LocalizedError {
    case missingRawFile
    case missingParsePlan
    case missingRequiredField(String)
    case invalidData
    case transformFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingRawFile:
            return "Raw file not found"
        case .missingParsePlan:
            return "Parse plan not found"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        case .invalidData:
            return "Invalid data format"
        case .transformFailed(let message):
            return "Transform failed: \(message)"
        }
    }
}

// Array chunking extension
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}