//
//  DirectCategorizationService.swift
//  cascade-ledger
//
//  AI direct categorization - sends all CSV rows to Claude for categorization
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class DirectCategorizationService: ObservableObject {
    @Published var status: Status = .idle
    @Published var progress: Double = 0.0
    @Published var currentStep: String = ""
    @Published var currentChunk: Int = 0
    @Published var totalChunks: Int = 0

    private let claudeAPI = ClaudeAPIService.shared
    private let modelContext: ModelContext
    private var isPausedFlag = false

    enum Status: Equatable {
        case idle
        case analyzing
        case processing(chunk: Int, of: Int)
        case waitingForRateLimit(secondsRemaining: Int)
        case paused
        case completed
        case failed(String)
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func pause() {
        isPausedFlag = true
        status = .paused
    }

    func resume() {
        isPausedFlag = false
    }

    // MARK: - Main Workflow (Chunked)

    func categorizeRows(
        csvRows: [[String: String]],
        headers: [String],
        account: Account,
        existingSession: CategorizationSession? = nil
    ) async throws -> CategorizationSession {
        // Reset pause flag
        isPausedFlag = false

        status = .analyzing
        progress = 0.0
        currentStep = "Preparing CSV data for AI..."

        // MUST use existing session (created by UI)
        guard let session = existingSession else {
            fatalError("DirectCategorizationService requires an existing session to be passed in")
        }

        // Log resume vs fresh start
        if session.processedRowsCount > 0 {
            print("📋 Resuming session v\(session.versionNumber) from array index \(session.processedRowsCount)")
            print("   Already have \(session.transactionCount) transactions")
            print("   Already covered \(session.buildCoverageIndex().count) rows")
            currentStep = "Resuming from array index \(session.processedRowsCount)..."
            session.isPaused = false
        } else {
            print("📋 Starting fresh session v\(session.versionNumber)")
        }

        // Configure AssetRegistry
        AssetRegistry.shared.configure(modelContext: modelContext)

        // CRITICAL: Preserve original CSV file order - it's already chronological!
        // Fidelity CSV is in REVERSE chronological order (newest first)
        // Sort DESCENDING by row number to get oldest-to-newest for processing
        let sortedRows = csvRows.sorted { (row1, row2) in
            let rowNum1 = Int(row1["_globalRowNumber"] ?? "0") ?? 0
            let rowNum2 = Int(row2["_globalRowNumber"] ?? "0") ?? 0
            return rowNum1 > rowNum2  // Reverse file order: higher row = older = process first
        }

        print("📋 Processing \(sortedRows.count) rows in CHRONOLOGICAL ORDER (oldest first)")
        print("   CSV file is reversed to get oldest→newest sequence")
        if let firstRow = sortedRows.first {
            let rowNum = firstRow["_globalRowNumber"] ?? "?"
            let date = firstRow["Run Date"] ?? "?"
            print("   Starting with: #\(rowNum) (oldest date: \(date))")
        }
        if let lastRow = sortedRows.last {
            let rowNum = lastRow["_globalRowNumber"] ?? "?"
            let date = lastRow["Run Date"] ?? "?"
            print("   Ending with: #\(rowNum) (newest date: \(date))")
        }

        // Process with windowed approach
        let transactionsPerChunk = 10
        let windowSize = 30  // Reduced from 100 to lower token usage

        let alreadyProcessedTransactions = session.transactionCount

        print("📋 Resume state: \(alreadyProcessedTransactions) transactions, \(session.batches.count) existing batches")

        var processedTransactionCount = alreadyProcessedTransactions
        // Always continue from where we left off (for fresh starts, processedRowsCount = 0)
        var currentArrayIndex = session.processedRowsCount

        // Track which global row numbers have been covered
        var coveredGlobalRows = Set(session.transactions.flatMap { $0.sourceRowNumbers })

        print("📍 Starting position:")
        print("   currentArrayIndex: \(currentArrayIndex)")
        print("   sortedRows.count: \(sortedRows.count)")
        print("   coveredGlobalRows.count: \(coveredGlobalRows.count)")
        print("   Remaining rows to process: \(sortedRows.count - currentArrayIndex)")
        print("📍 Coverage at start: \(coveredGlobalRows.count) rows covered")
        if !coveredGlobalRows.isEmpty {
            print("   Already covered: \(Array(coveredGlobalRows.sorted().prefix(10)).map { "#\($0)" }.joined(separator: ", "))\(coveredGlobalRows.count > 10 ? "..." : "")")
        }

        var currentChunk = 0

        // Process until all rows are covered (dynamic batching)
        while currentArrayIndex < sortedRows.count && coveredGlobalRows.count < sortedRows.count {
            // Check for pause
            if isPausedFlag {
                session.isPaused = true
                try modelContext.save()
                status = .paused
                currentStep = "Paused, \(session.transactionCount) transactions so far"
                return session
            }

            currentChunk += 1

            // Update totalChunks estimate for display (will grow as needed)
            totalChunks = max(currentChunk, totalChunks)
            status = .processing(chunk: currentChunk, of: totalChunks)
            progress = Double(currentArrayIndex) / Double(sortedRows.count)

            // WINDOWING: Always send next 30 rows from current position (lookahead)
            // Don't filter - AI needs context to see upcoming rows
            let windowEnd = min(currentArrayIndex + windowSize, sortedRows.count)
            let window = Array(sortedRows[currentArrayIndex..<windowEnd])

            // Get actual row numbers for logging
            let windowGlobalRows = window.compactMap { row -> Int? in
                guard let str = row["_globalRowNumber"] else { return nil }
                return Int(str)
            }
            let windowDates = window.compactMap { $0["Run Date"] }

            currentStep = "Processing window of \(window.count) rows"
            print("🔄 Batch \(currentChunk)/\(totalChunks):")
            print("   Window: rows \(currentArrayIndex + 1)-\(windowEnd) of \(sortedRows.count)")
            print("   Global row IDs: \(windowGlobalRows.prefix(10).map { "#\($0)" }.joined(separator: ", "))\(windowGlobalRows.count > 10 ? "..." : "")")
            print("   Date range: \(windowDates.first ?? "?") → \(windowDates.last ?? "?")")
            print("   Covered so far: \(coveredGlobalRows.count)/\(sortedRows.count) rows")

            // Build prompt with windowed context
            let prompt = buildWindowedPrompt(
                window: window,
                windowStartRow: currentArrayIndex + 1,  // 1-based for display
                totalRows: sortedRows.count,
                headers: headers,
                account: account,
                alreadyProcessedTransactions: processedTransactionCount,
                requestedCount: transactionsPerChunk
            )

            let startTime = Date()

            // Call API with auto-retry on rate limit
            let response: ClaudeResponse
            var retryCount = 0
            let maxRetries = 5

            while true {
                do {
                    response = try await claudeAPI.sendMessage(
                        messages: [ClaudeMessage(role: "user", content: prompt)],
                        system: buildSystemPrompt(),
                        maxTokens: 4096,  // Enough for ~10 transactions
                        temperature: 0.0
                    )
                    break  // Success!

                } catch let error as ClaudeAPIError {
                    if case .httpError(let statusCode, _, _) = error, statusCode == 429 {
                        // Rate limit - auto-retry after waiting
                        retryCount += 1
                        if retryCount > maxRetries {
                            print("  ❌ Max retries reached for rate limit")
                            throw error
                        }

                        let waitTime: Int = 120  // 2 minutes
                        print("  ⏱️ Rate limit hit, waiting \(waitTime)s before retry \(retryCount)/\(maxRetries)...")

                        // Wait with live countdown
                        for second in 0..<waitTime {
                            if isPausedFlag {
                                throw error  // User paused during wait
                            }

                            let remaining = waitTime - second
                            status = .waitingForRateLimit(secondsRemaining: remaining)
                            currentStep = "Rate limit exceeded - retrying in \(remaining)s..."

                            try await Task.sleep(for: .seconds(1))
                        }

                        print("  ♻️ Retrying after rate limit wait...")
                        status = .processing(chunk: currentChunk, of: totalChunks)
                        continue  // Retry
                    } else if case .httpError(let statusCode, let body, _) = error, statusCode == 400 {
                        // Check for credit balance error
                        if body.contains("credit balance is too low") {
                            print("  ❌ Credit balance too low - pausing job")
                            session.isPaused = true
                            session.errorMessage = "Your Anthropic API credit balance is too low. Please add credits at https://console.anthropic.com/settings/plans and then resume this job."
                            try modelContext.save()
                            status = .failed("Credit balance too low. Please add credits and resume.")
                            return session
                        }
                        // Other 400 error - pause with error details
                        print("  ❌ API error - pausing job")
                        session.isPaused = true
                        session.errorMessage = "API Error: \(body)"
                        try modelContext.save()
                        status = .failed(body)
                        return session
                    } else {
                        // Other error - pause with details
                        let errorDetails = error.localizedDescription
                        print("  ❌ API error - pausing job: \(errorDetails)")
                        session.isPaused = true
                        session.errorMessage = errorDetails
                        try modelContext.save()
                        status = .failed(errorDetails)
                        return session
                    }
                } catch {
                    // General error - pause with details
                    let errorDetails = error.localizedDescription
                    print("  ❌ Error - pausing job: \(errorDetails)")
                    session.isPaused = true
                    session.errorMessage = errorDetails
                    try modelContext.save()
                    status = .failed(errorDetails)
                    return session
                }
            }

            let duration = Date().timeIntervalSince(startTime)

            // Track metadata
            session.inputTokens += response.usage.inputTokens
            session.outputTokens += response.usage.outputTokens
            session.durationSeconds += duration
            session.aiModel = response.model

            // Check if truncated
            if response.stopReason == "max_tokens" {
                session.wasResponseTruncated = true
                print("  ⚠️ Chunk \(currentChunk): Response truncated (hit max_tokens)")
            }

            let textContent = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()

            // Parse chunk transactions (passing sortedRows, not csvRows which is the full unsorted set)
            let chunkTransactions = try parseTransactionsFromResponse(textContent, session: session, account: account, csvRows: sortedRows, allowIncomplete: true)

            print("  ✅ Chunk \(currentChunk): Created \(chunkTransactions.count) transactions (\(response.usage.inputTokens) in, \(response.usage.outputTokens) out, \(String(format: "%.1f", duration))s)")

            // Track which rows were consumed (global row numbers)
            let sourceRowsUsed = chunkTransactions.flatMap { $0.sourceRowNumbers }.sorted()
            let minRowInBatch = sourceRowsUsed.first ?? 0
            let maxRowInBatch = sourceRowsUsed.last ?? 0

            print("  📊 AI returned \(chunkTransactions.count) transactions:")
            for (txIdx, txn) in chunkTransactions.enumerated() {
                let rows = txn.sourceRowNumbers.sorted()
                print("     Txn #\(txIdx): uses rows \(rows.map { "#\($0)" }.joined(separator: ", ")) - \(txn.transactionDescription.prefix(40))")
            }
            print("     All rows used: \(sourceRowsUsed.map { "#\($0)" }.joined(separator: ", "))")

            // Check for duplicates
            let alreadyCovered = sourceRowsUsed.filter { coveredGlobalRows.contains($0) }
            if !alreadyCovered.isEmpty {
                print("  ⚠️ DUPLICATE ROWS! AI reused already-covered rows: \(alreadyCovered.map { "#\($0)" }.joined(separator: ", "))")
            }

            // Filter out transactions that only use already-covered rows
            let newTransactions = chunkTransactions.filter { transaction in
                // Keep transaction if it uses ANY new (uncovered) rows
                transaction.sourceRowNumbers.contains { rowNum in
                    !coveredGlobalRows.contains(rowNum)
                }
            }

            if newTransactions.count < chunkTransactions.count {
                let skipped = chunkTransactions.count - newTransactions.count
                print("  🚮 Skipping \(skipped) duplicate transactions (already covered rows)")
            }

            // Check for out-of-window rows
            let outOfWindow = sourceRowsUsed.filter { !windowGlobalRows.contains($0) }
            if !outOfWindow.isEmpty {
                print("  ⚠️ OUT OF WINDOW! AI used rows not in window: \(outOfWindow.map { "#\($0)" }.joined(separator: ", "))")
            }

            // Add to covered set
            let beforeCount = coveredGlobalRows.count
            coveredGlobalRows.formUnion(sourceRowsUsed)
            let afterCount = coveredGlobalRows.count
            let newlyCovered = afterCount - beforeCount

            print("  ✅ Coverage: \(beforeCount) → \(afterCount) rows (\(newlyCovered) new)")
            print("  📝 Transactions: \(newTransactions.count) new (filtered from \(chunkTransactions.count) total)")

            // WINDOWING: Advance by number of rows consumed from START of window
            // Find the highest array index that was consumed
            var rowsConsumedFromWindow = 0
            for (arrayOffset, row) in window.enumerated() {
                guard let globalRowStr = row["_globalRowNumber"],
                      let globalRow = Int(globalRowStr) else { continue }

                if sourceRowsUsed.contains(globalRow) {
                    // This row was consumed - mark as furthest consumed position
                    rowsConsumedFromWindow = max(rowsConsumedFromWindow, arrayOffset + 1)
                }
            }

            print("     AI consumed \(rowsConsumedFromWindow) rows from window (leaving \(window.count - rowsConsumedFromWindow) for lookahead)")
            print("     Advancing array index by \(rowsConsumedFromWindow) positions (from \(currentArrayIndex) → \(currentArrayIndex + rowsConsumedFromWindow))")

            // Only create batch and update if we have new transactions
            if !newTransactions.isEmpty {
                // Create batch record
                let batch = CategorizationBatch(
                    batchNumber: currentChunk,
                    startRow: minRowInBatch,
                    endRow: maxRowInBatch,
                    windowSize: window.count,
                    session: session
                )
                batch.addTransactions(
                    newTransactions,  // Only add non-duplicate transactions
                    tokens: (response.usage.inputTokens, response.usage.outputTokens),
                    duration: duration,
                    response: textContent.data(using: String.Encoding.utf8),
                    request: prompt.data(using: String.Encoding.utf8)
                )

                print("  📦 Creating batch #\(currentChunk): global rows #\(minRowInBatch)-#\(maxRowInBatch)")
                modelContext.insert(batch)

                // Add new transactions to session
                session.transactions.append(contentsOf: newTransactions)
                processedTransactionCount += newTransactions.count
                session.updateStatistics()

                // Calculate balances continuously after adding transactions
                print("  💰 Updating running balances after batch...")
                let balanceSample = session.transactions.last?.calculatedBalance
                calculateRunningBalances(for: session)
                print("     Latest transaction balance: \(balanceSample?.description ?? "nil") → \(session.transactions.last?.calculatedBalance?.description ?? "nil")")
            } else {
                print("  ⏭️  Skipping batch #\(currentChunk) - all transactions are duplicates")
            }

            // Update state - CRITICAL: Use array index, not global row number!
            // Always advance the window, even if all transactions were duplicates
            currentArrayIndex += rowsConsumedFromWindow
            session.processedRowsCount = currentArrayIndex  // Array position for resume

            print("  📍 Advanced to array index \(currentArrayIndex), covered \(coveredGlobalRows.count) global rows total")

            // Save incrementally
            try modelContext.save()

            print("  ✅ Batch #\(currentChunk) saved")
            print("  📍 State after batch:")
            print("     Current array index: \(currentArrayIndex)/\(sortedRows.count)")
            print("     Total covered: \(coveredGlobalRows.count)/\(sortedRows.count) global rows")
            print("     Session has: \(session.transactionCount) transactions total")
            print("")

            // Check if all rows are covered
            if coveredGlobalRows.count >= sortedRows.count {
                print("✅ All rows covered - terminating early")
                break
            }

            // If we didn't make progress, stop
            if rowsConsumedFromWindow == 0 {
                print("⚠️ No progress made (advanced 0 positions), stopping to prevent infinite loop")
                break
            }
        }

        print("═══════════════════════════════════════")
        print("Final coverage: \(coveredGlobalRows.count)/\(sortedRows.count) rows")
        print("Missing rows: \(sortedRows.count - coveredGlobalRows.count)")
        print("═══════════════════════════════════════")

        // Gap filling - process any uncovered rows
        if coveredGlobalRows.count < sortedRows.count {
            print("\n🔍 Detecting gaps in coverage...")

            let uncoveredRowNumbers = session.findUncoveredRows()
            print("   Found \(uncoveredRowNumbers.count) uncovered rows: \(uncoveredRowNumbers.prefix(20).map { "#\($0)" }.joined(separator: ", "))\(uncoveredRowNumbers.count > 20 ? "..." : "")")

            if !uncoveredRowNumbers.isEmpty {
                print("\n🔄 Starting gap-filling review...")

                // Create review service
                let reviewService = TransactionReviewService(modelContext: modelContext)

                do {
                    // Review uncovered rows
                    let reviewSession = try await reviewService.reviewUncoveredRows(
                        session: session,
                        csvRows: csvRows,
                        uncoveredRowNumbers: uncoveredRowNumbers
                    )

                    print("\n📊 Review complete:")
                    print("   Deltas generated: \(reviewSession.deltas.count)")

                    // Apply deltas
                    if !reviewSession.deltas.isEmpty {
                        try reviewService.applyDeltas(from: reviewSession, to: session)

                        print("\n✅ Gap filling complete:")
                        print("   Created: \(reviewSession.transactionsCreated) transactions")
                        print("   Updated: \(reviewSession.transactionsUpdated) transactions")
                        print("   Deleted: \(reviewSession.transactionsDeleted) transactions")

                        // Recompute coverage
                        let finalCoverage = session.buildCoverageIndex().count
                        print("   Final coverage: \(finalCoverage)/\(sortedRows.count) rows")
                    } else {
                        print("   ⚠️ No deltas generated - AI couldn't create transactions for uncovered rows")
                    }
                } catch {
                    print("   ⚠️ Gap filling failed: \(error.localizedDescription)")
                    print("   Continuing with partial coverage...")
                }
            }
        }

        // Final balance calculation (already done per batch, but do one more for completeness)
        print("💰 Final balance calculation...")
        calculateRunningBalances(for: session)

        // Mark complete
        session.isComplete = true
        session.processedRowsCount = csvRows.count
        try modelContext.save()

        status = .completed
        progress = 1.0
        currentStep = "✓ Created \(session.transactionCount) transactions"

        return session
    }

    // MARK: - Balance Calculation

    /// Public method to recalculate balances for an existing session
    func recalculateBalances(
        for session: CategorizationSession,
        csvRows: [[String: String]]
    ) {
        print("\n🔄 Recalculating balances for session v\(session.versionNumber)...")

        // First, extract CSV balances for all transactions
        extractCSVBalances(for: session, csvRows: csvRows)

        // Then calculate running balances
        calculateRunningBalances(for: session)

        print("✅ Balance recalculation complete\n")
    }

    private func extractCSVBalances(for session: CategorizationSession, csvRows: [[String: String]]) {
        print("📊 Extracting CSV balances from source rows...")
        print("   Total CSV rows available: \(csvRows.count)")
        print("   Total transactions: \(session.transactions.count)")

        var extracted = 0
        var rowsWithBalance = 0
        var rowsWithoutBalance = 0

        // Check what headers exist
        if let firstRow = csvRows.first {
            print("   CSV Headers: \(firstRow.keys.joined(separator: ", "))")
            let balanceField = firstRow["Cash Balance ($)"] ?? firstRow["Balance"] ?? firstRow["Cash Balance"]
            if let balanceField = balanceField {
                print("   ✓ Balance field exists (sample: '\(balanceField)')")
            } else {
                print("   ❌ Balance field NOT found in CSV headers")
            }
        }

        for (index, transaction) in session.transactions.enumerated() {
            // Find the last source row (usually the settlement row with balance)
            guard let lastRowNum = transaction.sourceRowNumbers.max(),
                  lastRowNum > 0 else {
                if index < 3 {
                    print("   Txn #\(index): No valid source rows (rows: \(transaction.sourceRowNumbers))")
                }
                continue
            }

            // Find CSV row by global row number (not array index!)
            guard let csvRow = csvRows.first(where: { row in
                guard let globalRowStr = row["_globalRowNumber"],
                      let globalRow = Int(globalRowStr) else {
                    return false
                }
                return globalRow == lastRowNum
            }) else {
                if index < 3 {
                    print("   Txn #\(index): Could not find CSV row #\(lastRowNum)")
                }
                continue
            }

            // Extract balance field (try multiple possible names)
            let balanceStr = csvRow["Cash Balance ($)"] ?? csvRow["Balance"] ?? csvRow["Cash Balance"]

            if let balanceStr = balanceStr, !balanceStr.isEmpty {
                rowsWithBalance += 1

                // Parse balance (remove $ and commas)
                let cleaned = balanceStr
                    .replacingOccurrences(of: "$", with: "")
                    .replacingOccurrences(of: ",", with: "")
                    .trimmingCharacters(in: .whitespaces)

                if let csvBalance = Decimal(string: cleaned) {
                    transaction.csvBalance = csvBalance
                    extracted += 1

                    if index < 3 {
                        print("   Txn #\(index) (\(transaction.transactionDescription)): CSV Balance = $\(csvBalance)")
                    }
                } else {
                    if index < 3 {
                        print("   Txn #\(index): Failed to parse balance '\(balanceStr)' → '\(cleaned)'")
                    }
                }
            } else {
                rowsWithoutBalance += 1
                if index < 3 {
                    print("   Txn #\(index) (row \(lastRowNum)): No balance field (Balance = '\(csvRow["Balance"] ?? "nil")')")
                }
            }
        }

        print("✓ Extracted CSV balance for \(extracted)/\(session.transactions.count) transactions")
        print("   CSV rows with Balance field: \(rowsWithBalance)")
        print("   CSV rows without Balance field: \(rowsWithoutBalance)")
    }

    private func calculateRunningBalances(for session: CategorizationSession) {
        // Sort transactions chronologically (oldest first)
        // Fidelity CSV is reverse chronological, so higher row numbers = older
        let sortedTransactions = session.transactions.sorted { t1, t2 in
            let minRow1 = t1.sourceRowNumbers.min() ?? 0
            let minRow2 = t2.sourceRowNumbers.min() ?? 0
            return minRow1 > minRow2  // Higher row = older = process first
        }

        print("💰 Calculating running balances for \(sortedTransactions.count) transactions in CHRONOLOGICAL ORDER (oldest first)...")

        var runningBalance: Decimal = 0
        var transactionsWithCSVBalance = 0
        var transactionsWithDiscrepancies = 0

        for (index, transaction) in sortedTransactions.enumerated() {
            // Calculate net cash impact
            let cashImpact = transaction.netCashImpact

            // Update running balance
            runningBalance += cashImpact

            // Store calculated balance
            transaction.calculatedBalance = runningBalance

            // Calculate discrepancy if CSV balance exists
            if let csvBalance = transaction.csvBalance {
                transactionsWithCSVBalance += 1
                transaction.balanceDiscrepancy = csvBalance - runningBalance

                if abs(transaction.balanceDiscrepancy ?? 0) > 0.01 {
                    transactionsWithDiscrepancies += 1
                }
            }

            // Debug first few and last few
            if index < 3 || index >= sortedTransactions.count - 3 {
                print("  Txn #\(index): \(transaction.transactionDescription)")
                print("    Cash impact: \(cashImpact)")
                print("    Running balance: \(runningBalance)")
                print("    CSV balance: \(transaction.csvBalance?.description ?? "none")")
                if let discrepancy = transaction.balanceDiscrepancy {
                    print("    Discrepancy: \(discrepancy)")
                }
            }
        }

        print("✓ Calculated running balances:")
        print("  Total transactions: \(sortedTransactions.count)")
        print("  With CSV balance: \(transactionsWithCSVBalance)")
        print("  With discrepancies: \(transactionsWithDiscrepancies)")
        print("  Final balance: \(runningBalance)")
    }

    // MARK: - Prompt Building

    private func buildSystemPrompt() -> String {
        return """
        You are a financial transaction categorization specialist. Your task is to analyze CSV
        transaction data and produce double-entry accounting Transaction objects with JournalEntry legs.

        CRITICAL ACCOUNTING RULES:
        - Every transaction MUST balance: total debits = total credits
        - Use exact symbols from CSV (FBTC != BTC, they are different assets)
        - Each transaction needs 2+ journal entry legs

        FIDELITY SETTLEMENT PATTERN:
        Fidelity uses dual-row structure:
        - Row N: Primary transaction (Action=YOU BOUGHT, Symbol=SPY, Quantity=4)
        - Row N+1: Settlement row (Action="", Symbol="", Quantity=0)

        Settlement rows should be GROUPED with primary row, not separate transactions.

        JOURNAL ENTRY TYPES:

        Buy:
          DR: Asset {symbol}  {amount}  ({quantity} shares)
          CR: Cash USD        {amount}

        Sell:
          DR: Cash USD        {amount}
          CR: Asset {symbol}  {amount}  ({quantity} shares)

        Dividend (Cash):
          DR: Cash USD        {amount}
          CR: Income "Dividend Income"  {amount}

        Dividend (Reinvested):
          DR: Asset {symbol}  {amount}  ({quantity} shares)
          CR: Income "Dividend Income"  {amount}

        Transfer In:
          DR: Cash USD        {amount}
          CR: Equity "Owner Contributions"  {amount}

        Transfer Out:
          DR: Equity "Owner Withdrawals"  {amount}
          CR: Cash USD        {amount}

        Fee:
          DR: Expense "Fees"  {amount}
          CR: Cash USD        {amount}

        OUTPUT FORMAT:
        Return JSON with this structure:

        ```json
        {
          "transactions": [
            {
              "sourceRows": [0, 1],
              "date": "2024-12-31",
              "description": "SPAXX Reinvestment",
              "transactionType": "dividend",
              "journalEntries": [
                {
                  "type": "debit",
                  "accountType": "asset",
                  "accountName": "SPAXX",
                  "amount": 283.06,
                  "quantity": 283.06,
                  "quantityUnit": "shares",
                  "assetSymbol": "SPAXX",
                  "sourceRows": [0],
                  "csvAmount": 283.06
                },
                {
                  "type": "credit",
                  "accountType": "income",
                  "accountName": "Dividend Income",
                  "amount": 283.06,
                  "sourceRows": [0],
                  "csvAmount": 283.06
                }
              ]
            }
          ]
        }
        ```

        CRITICAL: Each journal entry MUST specify:
        - sourceRows: Array of global row numbers this entry came from
        - csvAmount: The expected amount from the CSV for validation

        This enables full data lineage and amount validation.

        Analyze all rows and group/categorize them correctly.
        """
    }

    private func buildWindowedPrompt(
        window: [[String: String]],
        windowStartRow: Int,
        totalRows: Int,
        headers: [String],
        account: Account,
        alreadyProcessedTransactions: Int,
        requestedCount: Int
    ) -> String {
        // Convert window to CSV format (much more compact than JSON)
        var csvLines: [String] = []

        // Add headers including metadata columns
        let allHeaders = headers + ["_globalRowNumber", "_sourceFile", "_fileRowNumber"]
        csvLines.append(allHeaders.joined(separator: ","))

        // Add data rows
        for row in window {
            let values = allHeaders.map { header in
                let value = row[header] ?? ""
                // Quote if contains comma or quote
                if value.contains(",") || value.contains("\"") {
                    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return value
            }
            csvLines.append(values.joined(separator: ","))
        }

        let csvString = csvLines.joined(separator: "\n")
        let isFirstBatch = alreadyProcessedTransactions == 0

        // Detect year range from window dates
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        let windowDates = window.compactMap { row -> Date? in
            guard let dateStr = row["Run Date"] else { return nil }
            return dateFormatter.date(from: dateStr)
        }
        let yearRange: String
        if let oldestDate = windowDates.min(), let newestDate = windowDates.max() {
            let calendar = Calendar.current
            let oldestYear = calendar.component(.year, from: oldestDate)
            let newestYear = calendar.component(.year, from: newestDate)
            if oldestYear == newestYear {
                yearRange = "\(oldestYear)"
            } else {
                yearRange = "\(oldestYear)-\(newestYear)"
            }
        } else {
            yearRange = "2024-2025"
        }

        return """
        I'm showing you a WINDOW of \(window.count) rows from Fidelity CSV data.

        These rows are sorted OLDEST to NEWEST (chronological order).
        This is a sliding window - you can see the next \(window.count) rows ahead.
        Process rows sequentially from top to bottom.

        \(isFirstBatch ? "Generate the FIRST \(requestedCount) transactions from the start of this window." : "You already generated \(alreadyProcessedTransactions) transactions. Generate the NEXT \(requestedCount) transactions from the start of this window.")

        WINDOWING INSTRUCTIONS:
        - You're seeing a \(window.count)-row lookahead window
        - Generate up to \(requestedCount) transactions from the TOP of this window
        - You don't need to use ALL rows in the window - leave some as lookahead
        - Use "_globalRowNumber" for sourceRows arrays
        - Process rows IN ORDER (top to bottom, oldest to newest)

        Account: \(account.name)
        Institution: Fidelity Investments

        \(account.categorizationContext != nil ? """
        CATEGORIZATION CONTEXT FOR THIS ACCOUNT:
        \(account.categorizationContext!)

        IMPORTANT: Follow these account-specific patterns when categorizing.
        """ : "")

        YEAR CONTEXT:
        - These transactions span the year(s): \(yearRange)
        - When you see dates in MM/dd/yyyy format, the year is already specified
        - Return dates in yyyy-MM-dd format, using the EXACT year from the CSV
        - Example: CSV "01/02/2025" should become "2025-01-02" (not 2024-01-02)

        IMPORTANT INSTRUCTIONS:
        1. Use the "_globalRowNumber" field in each row for sourceRows arrays
           - Each row has "_globalRowNumber" showing its position in the combined dataset
           - Each row also has "_sourceFile" and "_fileRowNumber" for provenance
           - When you return sourceRows: [42, 43], use the _globalRowNumber values
           - This preserves exact provenance: which file + which line

        2. Group settlement rows with primary rows
           - Settlement pattern: Action="", Symbol="", Quantity=0
           - Use _globalRowNumber to reference rows in sourceRows arrays

        2. Create BALANCED journal entries
           - Debits MUST equal credits
           - Every transaction needs 2+ journal entry legs

        3. Use EXACT symbols from CSV
           - FBTC != BTC (different assets!)
           - SPAXX, FXAIX, NVDA, SPY, GLD, VOO, VXUS, SCHD, etc. - use as-is

        4. Account types:
           - asset: Stocks, ETFs, funds (FXAIX, SPY, NVDA, VOO, FBTC, SCHD, GLD, VXUS)
           - cash: USD currency
           - income: Dividend Income, Interest Income
           - expense: Fees, Commissions, Cash Withdrawals, Payments
           - equity: Owner Contributions, Owner Withdrawals

        5. Windowing approach:
           - Generate up to \(requestedCount) transactions from the TOP of the window
           - Process rows in order (oldest to newest)
           - You can leave rows unconsumed at the end of the window (lookahead buffer)
           - Use "_globalRowNumber" values for sourceRows arrays
           - Don't jump ahead - process sequentially from the start

        CSV Data (\(window.count)-row window, oldest to newest):
        ```csv
        \(csvString)
        ```

        Return JSON with up to \(requestedCount) transactions.
        Use "_globalRowNumber" for sourceRows arrays (preserves source file provenance).
        Process from the TOP of this window sequentially.
        """
    }

    // MARK: - Response Parsing

    func parseTransactionsFromResponse(
        _ response: String,
        session: CategorizationSession,
        account: Account,
        csvRows: [[String: String]] = [],
        allowIncomplete: Bool = false
    ) throws -> [Transaction] {
        print("📝 Parsing AI response (\(response.count) chars)")

        // Extract JSON from response
        var jsonMatch = try extractJSON(from: response)

        if jsonMatch == nil && allowIncomplete {
            // Try to fix incomplete JSON (truncated response)
            print("  ⚠️ No complete JSON block found, attempting to repair truncated response...")
            jsonMatch = try repairTruncatedJSON(from: response)
        }

        guard let jsonString = jsonMatch else {
            print("❌ No JSON found in response (even after repair attempt)")
            throw CategorizationError.invalidResponse
        }

        print("✓ Extracted JSON (\(jsonString.count) chars)")

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            print("❌ Failed to parse JSON object")
            throw CategorizationError.invalidResponse
        }

        guard let transactionsArray = json["transactions"] as? [[String: Any]] else {
            print("❌ No 'transactions' array in JSON")
            throw CategorizationError.invalidResponse
        }

        print("✓ Found \(transactionsArray.count) transactions in response")

        var transactions: [Transaction] = []

        for (index, txnDict) in transactionsArray.enumerated() {
            guard let sourceRows = txnDict["sourceRows"] as? [Int],
                  let dateString = txnDict["date"] as? String,
                  let description = txnDict["description"] as? String,
                  let typeString = txnDict["transactionType"] as? String,
                  let entriesArray = txnDict["journalEntries"] as? [[String: Any]] else {
                print("❌ Transaction #\(index): Missing required field")
                continue
            }

            // Map AI transaction types to our enum
            let type: TransactionType
            switch typeString {
            case "buy": type = .buy
            case "sell": type = .sell
            case "dividend": type = .dividend
            case "transfer_in", "deposit": type = .deposit
            case "transfer_out", "withdrawal": type = .withdrawal
            case "fee": type = .fee
            case "interest": type = .interest
            case "tax": type = .tax
            default: type = .other
            }

            // Parse date - handle multiple formats
            let date: Date
            let iso8601Formatter = ISO8601DateFormatter()
            if let isoDate = iso8601Formatter.date(from: dateString) {
                date = isoDate
            } else {
                // Try common date formats
                let dateFormatter = DateFormatter()
                dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)

                // Try yyyy-MM-dd
                dateFormatter.dateFormat = "yyyy-MM-dd"
                if let parsedDate = dateFormatter.date(from: dateString) {
                    date = parsedDate
                } else {
                    // Try MM/dd/yyyy (what AI returned in batch 4)
                    dateFormatter.dateFormat = "MM/dd/yyyy"
                    guard let parsedDate = dateFormatter.date(from: dateString) else {
                        print("❌ Transaction #\(index): Invalid date '\(dateString)'")
                        continue
                    }
                    date = parsedDate
                }
            }

            // Create transaction
            let transaction = Transaction(
                date: date,
                description: description,
                type: type,
                account: account
            )

            transaction.sourceRowNumbers = sourceRows
            transaction.categorizationSession = session

            // Extract balance from CSV rows if available
            if !csvRows.isEmpty {
                // Find the chronologically last source row (not just max row number!)
                // The csvRows array is sorted chronologically, so we need the last occurrence
                let rowPositions = sourceRows.compactMap { rowNum -> (rowNumber: Int, arrayIndex: Int)? in
                    // Find the position of this row in the sorted CSV array
                    if let arrayIndex = csvRows.firstIndex(where: { row in
                        guard let globalRowStr = row["_globalRowNumber"],
                              let globalRow = Int(globalRowStr) else { return false }
                        return globalRow == rowNum
                    }) {
                        return (rowNum, arrayIndex)
                    }
                    return nil
                }

                // Get chronologically last row (highest array index)
                let chronologicallyLastRow = rowPositions.max(by: { $0.arrayIndex < $1.arrayIndex })
                let lastRowNum = chronologicallyLastRow?.rowNumber

                if let lastRowNum = lastRowNum, lastRowNum > 0 {
                    if index < 3 {
                        print("  🔍 Transaction #\(index): Looking for CSV balance in row #\(lastRowNum) (chronologically last)")
                        print("     Source rows: \(sourceRows.sorted()) -> chronologically last: #\(lastRowNum)")
                        print("     Row positions in sorted array: \(rowPositions.map { "row #\($0.rowNumber) at index \($0.arrayIndex)" }.joined(separator: ", "))")
                        print("     CSV rows available: \(csvRows.count)")
                        print("     First CSV row has _globalRowNumber: \(csvRows.first?["_globalRowNumber"] ?? "nil")")
                    }

                    // Find CSV row by global row number (not array index!)
                    if let csvRow = csvRows.first(where: { row in
                        guard let globalRowStr = row["_globalRowNumber"],
                              let globalRow = Int(globalRowStr) else {
                            return false
                        }
                        return globalRow == lastRowNum
                    }) {
                        if index < 3 {
                            print("     Found CSV row #\(lastRowNum)")
                            print("     CSV row has \(csvRow.keys.count) fields: \(csvRow.keys.sorted().joined(separator: ", "))")
                            print("     Balance field value: '\(csvRow["Balance"] ?? "nil")'")

                            // Check if balance is under a different name
                            for (key, value) in csvRow where !value.isEmpty && (key.lowercased().contains("balance") || value.contains("$")) {
                                print("     Possible balance field: \(key) = '\(value)'")
                            }
                        }

                        // Extract balance field (try multiple possible names)
                        let balanceStr = csvRow["Cash Balance ($)"] ?? csvRow["Balance"] ?? csvRow["Cash Balance"]

                        if let balanceStr = balanceStr, !balanceStr.isEmpty {
                            // Parse balance (remove $ and commas)
                            let cleaned = balanceStr
                                .replacingOccurrences(of: "$", with: "")
                                .replacingOccurrences(of: ",", with: "")
                                .trimmingCharacters(in: .whitespaces)

                            if let csvBalance = Decimal(string: cleaned) {
                                transaction.csvBalance = csvBalance
                                print("  ✓ Transaction #\(index): CSV Balance extracted = $\(csvBalance) (from row #\(lastRowNum))")
                            } else if index < 3 {
                                print("     Failed to parse '\(cleaned)' as Decimal")
                            }
                        } else if index < 3 {
                            print("     Balance field is empty or nil")
                        }
                    } else if index < 3 {
                        print("     ❌ Could not find CSV row #\(lastRowNum) in csvRows")
                    }
                } else if index < 3 {
                    print("  ⚠️ Transaction #\(index): No valid source rows (sourceRows: \(sourceRows))")
                }
            } else if index < 3 {
                print("  ⚠️ Transaction #\(index): csvRows is empty!")
            }

            print("  ✓ Transaction #\(index): \(description) with \(entriesArray.count) entries")

            // Parse journal entries
            for (entryIndex, entryDict) in entriesArray.enumerated() {
                guard let typeStr = entryDict["type"] as? String,
                      let accountTypeStr = entryDict["accountType"] as? String,
                      let accountName = entryDict["accountName"] as? String,
                      let amount = entryDict["amount"] as? Double else {
                    print("    ❌ Entry #\(entryIndex): Missing field (type/accountType/accountName/amount)")
                    continue
                }

                let decimalAmount = Decimal(amount)
                let quantity = (entryDict["quantity"] as? Double).map { Decimal($0) }
                let quantityUnit = entryDict["quantityUnit"] as? String
                let assetSymbol = entryDict["assetSymbol"] as? String

                // Extract source provenance (new)
                let entrySourceRows = (entryDict["sourceRows"] as? [Int]) ?? sourceRows
                let entryCsvAmount = (entryDict["csvAmount"] as? Double).map { Decimal($0) }

                // Create entry
                let entry = JournalEntry(
                    accountType: AccountType(rawValue: accountTypeStr) ?? .expense,
                    accountName: accountName,
                    debitAmount: typeStr == "debit" ? decimalAmount : nil,
                    creditAmount: typeStr == "credit" ? decimalAmount : nil,
                    quantity: quantity,
                    quantityUnit: quantityUnit,
                    transaction: transaction
                )

                // Set CSV amount for validation
                entry.csvAmount = entryCsvAmount
                entry.calculateAmountDiscrepancy()

                // Link to SourceRows
                let sourceRowService = SourceRowService(modelContext: modelContext)
                let linkedSourceRows = sourceRowService.getSourceRows(globalRowNumbers: entrySourceRows)
                entry.sourceRows = linkedSourceRows

                // Link to asset if specified
                if let symbol = assetSymbol {
                    entry.asset = AssetRegistry.shared.findOrCreate(symbol: symbol)
                }

                transaction.journalEntries.append(entry)
            }

            // Validate amount discrepancies and detect over-grouping
            if transaction.journalEntries.count >= 2 {
                var hasDiscrepancies = false
                for entry in transaction.journalEntries {
                    if entry.hasAmountDiscrepancy {
                        hasDiscrepancies = true
                        print("  ⚠️ AMOUNT MISMATCH: Entry \(entry.accountName) has discrepancy of \(entry.amountDiscrepancy!)")
                        print("     Expected (CSV): \(entry.csvAmount!) | Actual: \(entry.amount)")
                        print("     This may indicate over-grouping or incorrect row linkage")
                    }
                }

                if hasDiscrepancies {
                    print("  🚨 Transaction #\(index) has amount validation errors - may be over-grouped!")
                }

                transactions.append(transaction)
                print("  ✅ Transaction #\(index) parsed successfully (\(transaction.journalEntries.count) entries)")
            } else {
                print("  ⚠️ Transaction #\(index) skipped: only \(transaction.journalEntries.count) journal entries")
            }
        }

        print("✅ Successfully parsed \(transactions.count) transactions from AI response")
        return transactions
    }

    private func extractJSON(from text: String) throws -> String? {
        // Look for JSON code block
        let pattern = "```json\\s*(.+?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }

        let jsonRange = match.range(at: 1)
        return (text as NSString).substring(with: jsonRange)
    }

    private func repairTruncatedJSON(from text: String) throws -> String? {
        // Find start of JSON (```json or just {)
        guard let startRange = text.range(of: "```json") else {
            return nil
        }

        var jsonString = String(text[startRange.upperBound...])
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove any trailing ``` if present
        if jsonString.hasSuffix("```") {
            jsonString = String(jsonString.dropLast(3))
        }

        // Try to close unclosed structures
        var openBraces = 0
        var openBrackets = 0
        var inString = false
        var escaped = false

        for char in jsonString {
            if escaped {
                escaped = false
                continue
            }

            if char == "\\" {
                escaped = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            if !inString {
                if char == "{" { openBraces += 1 }
                if char == "}" { openBraces -= 1 }
                if char == "[" { openBrackets += 1 }
                if char == "]" { openBrackets -= 1 }
            }
        }

        // Close unclosed structures
        for _ in 0..<openBrackets {
            jsonString += "]"
        }
        for _ in 0..<openBraces {
            jsonString += "}"
        }

        print("  🔧 Repaired JSON: added \(openBrackets) ] and \(openBraces) }")

        return jsonString
    }
}

enum CategorizationError: LocalizedError, Equatable {
    case invalidResponse
    case parsingFailed
    case networkTimeout
    case rateLimit(limit: String, suggestion: String)
    case apiError(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "AI response did not contain valid transaction JSON"
        case .parsingFailed:
            return "Failed to parse AI categorization"
        case .networkTimeout:
            return "Request timed out connecting to Anthropic API"
        case .rateLimit(let limit, _):
            return "Rate limit exceeded: \(limit)"
        case .apiError(let details):
            return "API Error: \(details)"
        case .unknown(let details):
            return "Error: \(details)"
        }
    }

    var userFriendlyMessage: String {
        switch self {
        case .networkTimeout:
            return "The request timed out. This usually happens with slow internet or if the API is busy."
        case .rateLimit(let limit, let suggestion):
            return "You've hit your API rate limit (\(limit)). \(suggestion)"
        case .apiError(let details):
            if details.contains("rate_limit") {
                return "API rate limit exceeded. Please wait a moment before trying again."
            }
            return "The Anthropic API returned an error. Check your API key and try again."
        case .invalidResponse:
            return "The AI returned a response that couldn't be parsed. The categorization format may have changed."
        case .parsingFailed:
            return "Failed to parse the AI's categorization into transaction objects."
        case .unknown:
            return "An unexpected error occurred during categorization."
        }
    }

    var technicalDetails: String {
        switch self {
        case .networkTimeout:
            return "Network request to api.anthropic.com timed out after 180 seconds. Check internet connection or try again."
        case .rateLimit(let limit, let suggestion):
            return "Rate limit: \(limit)\n\nThe current approach sends ~84k tokens per request. With a 50k/min limit, this means one request per ~1.7 minutes.\n\n\(suggestion)\n\nConsider: Wait 2 minutes and retry, or contact Anthropic for higher limits."
        case .apiError(let details):
            return details
        case .invalidResponse:
            return "Expected JSON with 'transactions' array but got different structure. Check console for raw response."
        case .parsingFailed:
            return "JSON parsing succeeded but transaction objects couldn't be constructed. Check field types match expected format."
        case .unknown(let details):
            return details
        }
    }

    static func == (lhs: CategorizationError, rhs: CategorizationError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse): return true
        case (.parsingFailed, .parsingFailed): return true
        case (.networkTimeout, .networkTimeout): return true
        case (.rateLimit(let a, let b), .rateLimit(let c, let d)): return a == c && b == d
        case (.apiError(let a), .apiError(let b)): return a == b
        case (.unknown(let a), .unknown(let b)): return a == b
        default: return false
        }
    }
}

// String extension for SHA256
extension String {
    func sha256() -> String {
        guard let data = self.data(using: .utf8) else { return "" }
        let hash = data.withUnsafeBytes { bytes in
            var hash = [UInt8](repeating: 0, count: 32)
            // Simple hash for now
            for (i, byte) in bytes.enumerated() {
                hash[i % 32] ^= byte
            }
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
