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

        if session.isPaused {
            session.isPaused = false
            print("📋 Resuming paused session v\(session.versionNumber)")
            currentStep = "Resuming from row \(session.processedRowsCount + 1)..."
        } else {
            print("📋 Starting session v\(session.versionNumber)")
        }

        // Configure AssetRegistry
        AssetRegistry.shared.configure(modelContext: modelContext)

        // Sort chronologically by ACTUAL date (parse MM/dd/yyyy format)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"

        let sortedRows = csvRows.sorted { (row1, row2) in
            let dateStr1 = row1["Run Date"] ?? ""
            let dateStr2 = row2["Run Date"] ?? ""
            let date1 = dateFormatter.date(from: dateStr1) ?? Date.distantPast
            let date2 = dateFormatter.date(from: dateStr2) ?? Date.distantPast
            return date1 > date2  // LATEST first (reverse chronological)
        }

        print("📋 Processing \(sortedRows.count) rows in REVERSE chronological order (latest first)")
        print("   Preserving original row numbers for provenance")
        if let firstRow = sortedRows.first {
            let rowNum = firstRow["_globalRowNumber"] ?? "?"
            let date = firstRow["Run Date"] ?? "?"
            print("   First row to process: #\(rowNum) (latest date: \(date))")
        }
        if let lastRow = sortedRows.last {
            let rowNum = lastRow["_globalRowNumber"] ?? "?"
            let date = lastRow["Run Date"] ?? "?"
            print("   Last row to process: #\(rowNum) (earliest date: \(date))")
        }

        // Process with windowed approach
        let transactionsPerChunk = 10
        let windowSize = 30  // Reduced from 100 to lower token usage

        let startRowIndex = session.processedRowsCount
        let alreadyProcessedTransactions = session.transactionCount

        print("📋 Resume state: \(alreadyProcessedTransactions) transactions, \(session.batches.count) existing batches")

        // Estimate total transactions needed (~50% of rows become transactions with settlement grouping)
        let estimatedTotalTransactions = (csvRows.count / 2)
        let remainingTransactions = estimatedTotalTransactions - alreadyProcessedTransactions
        totalChunks = max(1, (remainingTransactions + transactionsPerChunk - 1) / transactionsPerChunk)

        var processedTransactionCount = alreadyProcessedTransactions
        var currentArrayIndex = 0  // Index into sortedRows array

        // Track which global row numbers have been covered
        var coveredGlobalRows = Set(session.transactions.flatMap { $0.sourceRowNumbers })
        print("📍 Coverage at start: \(coveredGlobalRows.count) rows covered")
        if !coveredGlobalRows.isEmpty {
            print("   Already covered: \(Array(coveredGlobalRows.sorted().prefix(10)).map { "#\($0)" }.joined(separator: ", "))\(coveredGlobalRows.count > 10 ? "..." : "")")
        }

        for chunkIndex in 0..<totalChunks {
            // Check for pause
            if isPausedFlag {
                session.isPaused = true
                try modelContext.save()
                status = .paused
                currentStep = "Paused, \(session.transactionCount) transactions so far"
                return session
            }

            // Skip already-covered rows
            while currentArrayIndex < sortedRows.count {
                if let globalRowStr = sortedRows[currentArrayIndex]["_globalRowNumber"],
                   let globalRow = Int(globalRowStr),
                   coveredGlobalRows.contains(globalRow) {
                    print("  ⏭️ Skipping array index \(currentArrayIndex) (global row #\(globalRow) already covered)")
                    currentArrayIndex += 1
                } else {
                    break
                }
            }

            // Check if we're done
            if currentArrayIndex >= sortedRows.count {
                print("✅ All rows processed!")
                break
            }

            currentChunk = chunkIndex + 1
            status = .processing(chunk: currentChunk, of: totalChunks)
            progress = Double(currentArrayIndex) / Double(sortedRows.count)

            // Extract window, filtering out already-covered rows
            var window: [[String: String]] = []
            var windowArrayEnd = currentArrayIndex

            while window.count < windowSize && windowArrayEnd < sortedRows.count {
                let row = sortedRows[windowArrayEnd]
                if let globalRowStr = row["_globalRowNumber"],
                   let globalRow = Int(globalRowStr),
                   !coveredGlobalRows.contains(globalRow) {
                    window.append(row)
                }
                windowArrayEnd += 1
            }

            // Get actual row numbers for logging
            let windowGlobalRows = window.compactMap { row -> Int? in
                guard let str = row["_globalRowNumber"] else { return nil }
                return Int(str)
            }
            let minGlobal = windowGlobalRows.min() ?? 0
            let maxGlobal = windowGlobalRows.max() ?? 0
            let windowDates = window.compactMap { $0["Run Date"] }.prefix(3)

            currentStep = "Processing \(window.count) uncovered rows"
            print("🔄 Batch \(currentChunk)/\(totalChunks):")
            print("   Filtered window: \(window.count) UNCOVERED rows (scanned array \(currentArrayIndex)-\(windowArrayEnd-1))")
            print("   Global rows: \(windowGlobalRows.prefix(10).map { "#\($0)" }.joined(separator: ", "))\(windowGlobalRows.count > 10 ? "..." : "")")
            print("   Date range: \(windowDates.last ?? "latest") → \(windowDates.first ?? "earliest")")
            print("   Total covered so far: \(coveredGlobalRows.count)/\(sortedRows.count)")

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
                    if case .httpError(let statusCode, let body, _) = error, statusCode == 429 {
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
                    } else {
                        throw error  // Other error, propagate
                    }
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

            // Parse chunk transactions
            let chunkTransactions = try parseTransactionsFromResponse(textContent, session: session, account: account, allowIncomplete: true)

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

            // Since we filtered the window, just advance by the number of rows in window
            // that were actually used by the AI
            let rowsConsumedFromWindow = window.filter { row in
                guard let globalRowStr = row["_globalRowNumber"],
                      let globalRow = Int(globalRowStr) else { return false }
                return sourceRowsUsed.contains(globalRow)
            }.count

            print("     Advancing array index by \(rowsConsumedFromWindow) positions (from \(currentArrayIndex) → \(currentArrayIndex + rowsConsumedFromWindow))")

            // Create batch record
            let batch = CategorizationBatch(
                batchNumber: currentChunk,
                startRow: minRowInBatch,
                endRow: maxRowInBatch,
                windowSize: window.count,
                session: session
            )
            batch.addTransactions(
                chunkTransactions,
                tokens: (response.usage.inputTokens, response.usage.outputTokens),
                duration: duration,
                response: textContent.data(using: String.Encoding.utf8),
                request: prompt.data(using: String.Encoding.utf8)
            )

            print("  📦 Creating batch #\(currentChunk): global rows #\(minRowInBatch)-#\(maxRowInBatch)")
            modelContext.insert(batch)

            // Update state - CRITICAL: Use array index, not global row number!
            currentArrayIndex += rowsConsumedFromWindow
            session.processedRowsCount = currentArrayIndex  // Array position for resume
            session.transactions.append(contentsOf: chunkTransactions)
            processedTransactionCount += chunkTransactions.count
            session.updateStatistics()

            print("  📍 Advanced to array index \(currentArrayIndex), covered \(coveredGlobalRows.count) global rows total")

            // Save incrementally
            try modelContext.save()

            print("  ✅ Batch #\(currentChunk) saved")
            print("  📍 State after batch:")
            print("     Current array index: \(currentArrayIndex)/\(sortedRows.count)")
            print("     Total covered: \(coveredGlobalRows.count)/\(sortedRows.count) global rows")
            print("     Session has: \(session.transactionCount) transactions total")
            print("")

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

        // Mark complete
        session.isComplete = true
        session.processedRowsCount = csvRows.count
        try modelContext.save()

        status = .completed
        progress = 1.0
        currentStep = "✓ Created \(session.transactionCount) transactions"

        return session
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
                  "assetSymbol": "SPAXX"
                },
                {
                  "type": "credit",
                  "accountType": "income",
                  "accountName": "Dividend Income",
                  "amount": 283.06
                }
              ]
            }
          ]
        }
        ```

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

        // Get the actual global row number from first row in window
        let actualStartRow = window.first?["_globalRowNumber"] ?? "\(windowStartRow)"

        return """
        I'm showing you \(window.count) UNCOVERED rows from Fidelity CSV data.

        These rows are sorted LATEST to EARLIEST (most recent first).
        These are the ONLY uncovered rows - all other rows already have transactions.
        Process these \(window.count) rows sequentially from top to bottom.

        \(isFirstBatch ? "Generate the FIRST \(requestedCount) transactions from these rows." : "You already generated \(alreadyProcessedTransactions) transactions. Generate the NEXT \(requestedCount) transactions from the top of this list.")

        CRITICAL:
        - Use "_globalRowNumber" for sourceRows arrays
        - Process rows IN ORDER (top to bottom)
        - All rows shown are UNCOVERED - you won't see already-categorized rows

        Account: \(account.name)
        Institution: Fidelity Investments

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

        5. Important: Return ONLY the \(requestedCount) transactions requested
           - Process rows chronologically (earliest dates first)
           - Use "_globalRowNumber" values for sourceRows arrays
           - Stop after \(requestedCount) transactions even if more rows remain

        CSV Data (\(window.count) rows, chronologically sorted):
        ```csv
        \(csvString)
        ```

        Return JSON with up to \(requestedCount) transactions.
        Use "_globalRowNumber" for sourceRows arrays (preserves source file provenance).
        Continue from where you left off chronologically.
        """
    }

    // MARK: - Response Parsing

    func parseTransactionsFromResponse(
        _ response: String,
        session: CategorizationSession,
        account: Account,
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

                // Link to asset if specified
                if let symbol = assetSymbol {
                    entry.asset = AssetRegistry.shared.findOrCreate(symbol: symbol)
                }

                transaction.journalEntries.append(entry)
            }

            if transaction.journalEntries.count >= 2 {
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
