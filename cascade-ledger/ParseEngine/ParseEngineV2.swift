//
//  ParseEngineV2.swift
//  cascade-ledger
//
//  Parse engine with double-entry bookkeeping support
//

import Foundation
import SwiftData
import Combine

/// Parse engine that creates proper double-entry transactions
@MainActor
class ParseEngineV2: ObservableObject {
    private let csvParser: CSVParser
    private let transformExecutor: TransformExecutor
    private let modelContext: ModelContext

    @Published var isProcessing = false
    @Published var progress: Double = 0.0
    @Published var currentStatus = ""

    /// Toggle between double-entry and single-entry mode
    var useDoubleEntry: Bool = true

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.csvParser = CSVParser()
        self.transformExecutor = TransformExecutor()
    }

    // MARK: - Import with Double-Entry

    /// Import CSV data creating double-entry transactions
    func importWithDoubleEntry(
        importBatch: ImportBatch,
        parsePlanVersion: ParsePlanVersion,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> (transactions: [Transaction], parseRun: ParseRun) {
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

        guard let account = importBatch.account else {
            throw ParseEngineV2Error.missingAccount
        }

        // Parse CSV
        currentStatus = "Parsing CSV..."
        let rawFile = importBatch.rawFile!
        let csvContent = String(data: rawFile.content, encoding: .utf8) ?? ""
        let parser = CSVParser(dialect: parsePlanVersion.definition.dialect)
        let csvData = try parser.parse(csvContent)

        parseRun.totalRows = csvData.rowCount

        print("=== Double-Entry Import Starting ===")
        print("Total rows: \(csvData.rowCount)")
        print("Account: \(account.name)")

        // Transform all rows first
        currentStatus = "Transforming data..."
        var transformedRows: [[String: Any]] = []
        var skippedRows = 0

        for (index, row) in csvData.rows.enumerated() {
            let rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))

            do {
                let transformed = try transformExecutor.transformRow(
                    rowDict,
                    schema: parsePlanVersion.definition.schema,
                    transforms: parsePlanVersion.definition.transforms
                )

                // Validate that we have the required fields
                if transformed["date"] != nil {
                    // Add row number for tracking
                    var enrichedRow = transformed
                    enrichedRow["rowNumber"] = index

                    // Store original action from CSV in metadata
                    if let action = rowDict["Action"] {
                        enrichedRow["metadata.action"] = action
                    }
                    if let symbol = rowDict["Symbol"] {
                        enrichedRow["metadata.symbol"] = symbol
                    }

                    transformedRows.append(enrichedRow)
                } else {
                    print("Skipping row \(index): No valid date after transformation")
                    skippedRows += 1
                }

            } catch {
                print("Transform error at row \(index): \(error)")
                parseRun.errors.append(ParseError(
                    rowNumber: index,
                    errorType: .transformFailed,
                    message: error.localizedDescription,
                    field: nil,
                    value: nil
                ))
                parseRun.failedRows += 1
                skippedRows += 1
            }

            let progressValue = Double(index) / Double(csvData.rowCount) * 0.5
            progress = progressValue
            onProgress?(progressValue)
        }

        print("Transformed \(transformedRows.count) valid rows, skipped \(skippedRows) invalid rows")

        // Group rows into transactions
        currentStatus = "Grouping transactions..."
        let rowGroups = TransactionBuilder.groupRows(transformedRows)
        print("Created \(rowGroups.count) transaction groups from \(transformedRows.count) rows")

        // Create transactions
        currentStatus = "Creating transactions..."
        var transactions: [Transaction] = []
        var createdTransactions = 0
        var failedTransactions = 0

        for (groupIndex, rowGroup) in rowGroups.enumerated() {
            do {
                let transaction = try TransactionBuilder.createTransaction(
                    from: rowGroup,
                    account: account,
                    importBatch: importBatch
                )

                // Check for duplicate
                let isDuplicate = try checkForDuplicateTransaction(transaction)

                if isDuplicate {
                    print("⊘ Skipping duplicate transaction: \(transaction.transactionDescription)")
                    parseRun.failedRows += rowGroup.count
                } else {
                    modelContext.insert(transaction)

                    // Also insert journal entries
                    for entry in transaction.journalEntries {
                        modelContext.insert(entry)
                    }

                    transactions.append(transaction)
                    createdTransactions += 1
                    parseRun.successfulRows += rowGroup.count
                }

            } catch {
                print("Failed to create transaction from group \(groupIndex): \(error)")
                failedTransactions += 1
                parseRun.failedRows += rowGroup.count

                parseRun.errors.append(ParseError(
                    rowNumber: rowGroup.first?["rowNumber"] as? Int ?? 0,
                    errorType: .transformFailed,
                    message: "Transaction creation failed: \(error.localizedDescription)",
                    field: nil,
                    value: nil
                ))
            }

            let progressValue = 0.5 + (Double(groupIndex) / Double(rowGroups.count) * 0.5)
            progress = progressValue
            onProgress?(progressValue)
        }

        // Update import batch status
        importBatch.totalRows = parseRun.totalRows
        importBatch.successfulRows = parseRun.successfulRows
        importBatch.failedRows = parseRun.failedRows

        if parseRun.failedRows == 0 {
            importBatch.status = .success
        } else if parseRun.successfulRows > 0 {
            importBatch.status = .partialSuccess
        } else {
            importBatch.status = .failed
        }

        importBatch.completedAt = Date()
        parseRun.completedAt = Date()

        // Calculate and display USD balance
        let usdBalance = calculateUSDBalance(from: transactions)

        print("=== Import Complete ===")
        print("✓ Transactions created: \(createdTransactions)")
        print("✗ Transactions failed: \(failedTransactions)")
        print("✓ Rows processed: \(parseRun.successfulRows)")
        print("✗ Rows failed: \(parseRun.failedRows)")
        print("💵 USD Balance: \(usdBalance)")
        print("========================")

        try modelContext.save()

        return (transactions, parseRun)
    }

    // MARK: - Backward Compatibility

    /// Import using legacy single-entry mode (delegates to original ParseEngine)
    func importWithSingleEntry(
        importBatch: ImportBatch,
        parsePlanVersion: ParsePlanVersion,
        onProgress: ((Double) -> Void)? = nil
    ) async throws -> ParseRun {
        // Use original ParseEngine for backward compatibility
        let legacyEngine = ParseEngine(modelContext: modelContext)
        return try await legacyEngine.executeImport(
            importBatch: importBatch,
            parsePlanVersion: parsePlanVersion,
            onProgress: onProgress
        )
    }

    // MARK: - Helper Methods

    /// Check if a similar transaction already exists
    private func checkForDuplicateTransaction(_ transaction: Transaction) throws -> Bool {
        let date = transaction.date
        let amount = transaction.netCashImpact
        let description = transaction.transactionDescription

        // Create a simple hash for comparison
        let hashString = "\(date)|\(amount)|\(description)"
        let hash = hashString.data(using: .utf8)!.base64EncodedString().prefix(16)

        // Check for existing transaction with similar characteristics
        let batchId = transaction.importBatch?.id
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { existing in
                existing.date == date &&
                existing.transactionDescription == description &&
                existing.importBatch?.id != batchId
            }
        )

        let results = try modelContext.fetch(descriptor)
        return !results.isEmpty
    }

    /// Calculate total USD balance from transactions
    private func calculateUSDBalance(from transactions: [Transaction]) -> Decimal {
        return transactions.reduce(0) { sum, transaction in
            sum + transaction.netCashImpact
        }
    }

    // MARK: - Migration Support

    /// Migrate existing LedgerEntry data to Transaction/JournalEntry model
    func migrateExistingData() async throws -> (migrated: Int, failed: Int) {
        currentStatus = "Migrating existing data..."
        isProcessing = true
        defer {
            isProcessing = false
            currentStatus = "Migration complete"
        }

        // Fetch all existing ledger entries
        let descriptor = FetchDescriptor<LedgerEntry>(
            sortBy: [SortDescriptor(\.date), SortDescriptor(\.sourceRowNumber)]
        )
        let ledgerEntries = try modelContext.fetch(descriptor)

        print("=== Migration Starting ===")
        print("Found \(ledgerEntries.count) ledger entries to migrate")

        // Group by import batch and approximate transaction
        var entriesByBatch: [UUID: [LedgerEntry]] = [:]
        for entry in ledgerEntries {
            let batchId = entry.importBatch?.id ?? UUID()
            entriesByBatch[batchId, default: []].append(entry)
        }

        var migratedCount = 0
        var failedCount = 0

        for (batchId, batchEntries) in entriesByBatch {
            print("Processing batch \(batchId) with \(batchEntries.count) entries")

            // Group entries into potential transactions
            let groups = groupLedgerEntriesIntoTransactions(batchEntries)

            for group in groups {
                do {
                    let transaction = try createTransactionFromLedgerEntries(group)
                    modelContext.insert(transaction)

                    for entry in transaction.journalEntries {
                        modelContext.insert(entry)
                    }

                    migratedCount += 1
                } catch {
                    print("Failed to migrate group: \(error)")
                    failedCount += 1
                }
            }
        }

        try modelContext.save()

        print("=== Migration Complete ===")
        print("✓ Migrated: \(migratedCount) transactions")
        print("✗ Failed: \(failedCount)")

        return (migratedCount, failedCount)
    }

    /// Group ledger entries that likely belong to the same transaction
    private func groupLedgerEntriesIntoTransactions(_ entries: [LedgerEntry]) -> [[LedgerEntry]] {
        var groups: [[LedgerEntry]] = []
        var currentGroup: [LedgerEntry] = []
        var lastDate: Date?

        for entry in entries.sorted(by: { $0.date < $1.date || ($0.date == $1.date && ($0.sourceRowNumber ?? 0) < ($1.sourceRowNumber ?? 0)) }) {
            // Start new group if date changes or significant time gap
            if let last = lastDate, entry.date != last {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [entry]
            } else {
                currentGroup.append(entry)
            }
            lastDate = entry.date
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    /// Create a transaction from grouped ledger entries
    private func createTransactionFromLedgerEntries(_ entries: [LedgerEntry]) throws -> Transaction {
        guard let first = entries.first,
              let account = first.account else {
            throw ParseEngineV2Error.invalidData
        }

        let transaction = Transaction(
            date: first.date,
            description: first.transactionDescription,
            type: first.effectiveTransactionType,
            account: account
        )

        // Simple conversion: each entry becomes appropriate journal entries
        for entry in entries {
            if let assetId = entry.assetId, let quantity = entry.quantity {
                // Asset transaction
                if entry.amount < 0 {
                    // Buy
                    transaction.addDebit(
                        accountType: .asset,
                        accountName: assetId,
                        amount: abs(entry.amount),
                        quantity: abs(quantity),
                        quantityUnit: entry.quantityUnit
                    )
                    transaction.addCredit(
                        accountType: .cash,
                        accountName: "USD",
                        amount: abs(entry.amount)
                    )
                } else {
                    // Sell
                    transaction.addCredit(
                        accountType: .asset,
                        accountName: assetId,
                        amount: abs(entry.amount),
                        quantity: abs(quantity),
                        quantityUnit: entry.quantityUnit
                    )
                    transaction.addDebit(
                        accountType: .cash,
                        accountName: "USD",
                        amount: abs(entry.amount)
                    )
                }
            } else {
                // Cash transaction
                if entry.amount > 0 {
                    transaction.addDebit(
                        accountType: .cash,
                        accountName: "USD",
                        amount: entry.amount
                    )
                    transaction.addCredit(
                        accountType: .income,
                        accountName: "Other Income",
                        amount: entry.amount
                    )
                } else {
                    transaction.addDebit(
                        accountType: .expense,
                        accountName: "Other Expenses",
                        amount: abs(entry.amount)
                    )
                    transaction.addCredit(
                        accountType: .cash,
                        accountName: "USD",
                        amount: abs(entry.amount)
                    )
                }
            }
        }

        // Force balance if needed (may need adjustment for complex cases)
        if !transaction.isBalanced {
            let difference = transaction.totalDebits - transaction.totalCredits
            if abs(difference) < 1 {
                // Small rounding difference - add adjustment entry
                if difference > 0 {
                    transaction.addCredit(
                        accountType: .equity,
                        accountName: "Rounding Adjustment",
                        amount: difference
                    )
                } else {
                    transaction.addDebit(
                        accountType: .equity,
                        accountName: "Rounding Adjustment",
                        amount: abs(difference)
                    )
                }
            }
        }

        return transaction
    }
}

// MARK: - Error Types

enum ParseEngineV2Error: LocalizedError {
    case missingAccount
    case invalidData
    case missingRequiredField(String)

    var errorDescription: String? {
        switch self {
        case .missingAccount:
            return "Import batch must have an associated account"
        case .invalidData:
            return "Invalid data for creating transaction"
        case .missingRequiredField(let field):
            return "Missing required field: \(field)"
        }
    }
}