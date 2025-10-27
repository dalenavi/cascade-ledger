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
        let allEntriesDescriptor = FetchDescriptor<LedgerEntry>()
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
                        let ledgerEntry = try createLedgerEntry(
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
                            parseRun.ledgerEntries.append(ledgerEntry)
                            parseRun.successfulRows += 1
                        }
                    } else {
                        // Record validation failure
                        let error = ParseError(
                            rowNumber: globalRowIndex,
                            errorType: .validationFailed,
                            message: "Validation failed",
                            field: nil,
                            value: nil
                        )
                        parseRun.errors.append(error)
                        parseRun.failedRows += 1
                    }

                    // Create lineage mapping
                    let lineage = LineageMapping(
                        sourceRowNumber: globalRowIndex,
                        sourceFields: rowDict,
                        outputEntryId: isValid ? parseRun.ledgerEntries.last?.id : nil,
                        transformsApplied: parsePlanVersion.definition.transforms.map { $0.name },
                        validationResults: validationResults
                    )
                    parseRun.lineageMappings.append(lineage)

                } catch {
                    // Record transform error
                    let parseError = ParseError(
                        rowNumber: globalRowIndex,
                        errorType: .transformFailed,
                        message: error.localizedDescription,
                        field: nil,
                        value: nil
                    )
                    parseRun.errors.append(parseError)
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
        print("Ledger entries created: \(parseRun.ledgerEntries.count)")

        try modelContext.save()

        return parseRun
    }

    // MARK: - Helper Methods

    // Check if transaction already exists (excluding current import batch)
    private func checkForDuplicate(_ entry: LedgerEntry, currentBatchId: UUID) throws -> Bool {
        let hash = entry.transactionHash
        let batchId = currentBatchId
        let descriptor = FetchDescriptor<LedgerEntry>(
            predicate: #Predicate<LedgerEntry> { existing in
                existing.transactionHash == hash &&
                existing.importBatch?.id != batchId  // Exclude current batch
            }
        )

        let results = try modelContext.fetch(descriptor)

        if !results.isEmpty {
            let existing = results.first!
            print("  🔍 DUPLICATE FOUND (from previous import):")
            print("     Hash: \(hash.prefix(16))...")
            print("     New: \(entry.date.formatted(date: .abbreviated, time: .omitted)) \(entry.transactionDescription.prefix(40)) \(entry.amount)")
            print("     Existing: \(existing.date.formatted(date: .abbreviated, time: .omitted)) \(existing.transactionDescription.prefix(40)) \(existing.amount)")
            print("     Existing from batch: \(existing.importBatch?.batchName ?? existing.importBatch?.rawFile?.fileName ?? "Unknown")")
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
    private func createLedgerEntry(
        from data: [String: Any],
        account: Account,
        importBatch: ImportBatch,
        parseRun: ParseRun,
        rowNumber: Int
    ) throws -> LedgerEntry {
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

        // Create ledger entry
        let ledgerEntry = LedgerEntry(
            date: date,
            amount: amount,
            description: description,
            account: account,
            transactionType: transactionType
        )

        // Set additional fields
        ledgerEntry.importBatch = importBatch
        ledgerEntry.parseRun = parseRun
        ledgerEntry.sourceRowNumber = rowNumber
        ledgerEntry.rawTransactionType = rawType // Preserve original CSV value

        // Optional fields
        ledgerEntry.category = data["category"] as? String
        ledgerEntry.subcategory = data["subcategory"] as? String
        ledgerEntry.normalizedDescription = data["normalizedDescription"] as? String
        ledgerEntry.assetId = data["assetId"] as? String

        // Quantity fields (for investments)
        if let quantityValue = data["quantity"] {
            if let decimalQty = quantityValue as? Decimal {
                ledgerEntry.quantity = decimalQty
                print("✓ Quantity (Decimal): \(decimalQty)")
            } else if let doubleQty = quantityValue as? Double {
                ledgerEntry.quantity = Decimal(doubleQty)
                print("✓ Quantity (Double→Decimal): \(doubleQty)")
            } else if let intQty = quantityValue as? Int {
                ledgerEntry.quantity = Decimal(intQty)
                print("✓ Quantity (Int→Decimal): \(intQty)")
            } else {
                print("⚠️ Quantity value type not recognized: \(type(of: quantityValue))")
            }
        } else {
            print("⚠️ No quantity field in data. Available fields: \(data.keys.joined(separator: ", "))")
        }

        ledgerEntry.quantityUnit = data["quantityUnit"] as? String
            ?? inferQuantityUnit(assetId: data["assetId"] as? String)

        print("Transaction: \(ledgerEntry.transactionDescription.prefix(50)) | Asset: \(ledgerEntry.assetId ?? "nil") | Qty: \(ledgerEntry.quantity?.description ?? "nil") \(ledgerEntry.quantityUnit ?? "")")

        // Metadata - handle both direct metadata.* keys and unmapped fields
        for (key, value) in data {
            if key.hasPrefix("metadata.") {
                // Explicitly mapped metadata field
                let metadataKey = String(key.dropFirst("metadata.".count))
                ledgerEntry.metadata[metadataKey] = String(describing: value)
            } else if !["date", "amount", "description", "transactionDescription", "transactionType", "type", "action", "category", "subcategory", "assetId", "normalizedDescription"].contains(key) {
                // Unmapped field - add to metadata (excluding type-related fields we already captured)
                ledgerEntry.metadata[key] = String(describing: value)
            }
        }

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
            return amount < 0 ? .debit : .credit
        }

        return .credit
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