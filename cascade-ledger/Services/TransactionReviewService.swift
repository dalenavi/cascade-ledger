//
//  TransactionReviewService.swift
//  cascade-ledger
//
//  Service for reviewing and refining transactions
//

import Foundation
import SwiftData

class TransactionReviewService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Gap Analysis

    /// Find all gaps in a categorization session
    func findGaps(in session: CategorizationSession) -> GapAnalysis {
        let uncoveredRows = session.findUncoveredRows()
        let unbalancedTransactions = session.findUnbalancedTransactions()

        // TODO: Implement orphaned transaction detection
        let orphanedTransactions: [Transaction] = []

        return GapAnalysis(
            uncoveredRows: uncoveredRows,
            orphanedTransactions: orphanedTransactions,
            unbalancedTransactions: unbalancedTransactions
        )
    }

    /// Fill gaps in an existing session by reviewing uncovered rows
    /// This is useful when initial categorization left some rows unprocessed
    func fillGaps(
        in session: CategorizationSession,
        csvRows: [[String: String]]
    ) async throws -> ReviewSession {

        print("\n🔍 Analyzing gaps in session v\(session.versionNumber)")

        let gaps = findGaps(in: session)

        guard !gaps.uncoveredRows.isEmpty else {
            print("   ✅ No gaps found - session has 100% coverage")
            throw ReviewError.noRowsToReview
        }

        print("   Found \(gaps.uncoveredRows.count) uncovered rows")
        print("   Found \(gaps.unbalancedTransactions.count) unbalanced transactions")

        // Review uncovered rows
        let reviewSession = try await reviewUncoveredRows(
            session: session,
            csvRows: csvRows,
            uncoveredRowNumbers: gaps.uncoveredRows
        )

        // Auto-apply deltas
        if !reviewSession.deltas.isEmpty {
            try applyDeltas(from: reviewSession, to: session)

            let finalCoverage = session.buildCoverageIndex().count
            print("\n✅ Gap filling complete:")
            print("   Coverage: \(finalCoverage)/\(session.totalSourceRows) rows (\(String(format: "%.1f", Double(finalCoverage) * 100.0 / Double(session.totalSourceRows)))%)")
        }

        return reviewSession
    }

    // MARK: - Review Operations

    /// Review a specific date range
    func reviewDateRange(
        session: CategorizationSession,
        csvRows: [[String: String]],
        startDate: Date,
        endDate: Date,
        mode: ReviewMode = .gapFilling
    ) async throws -> ReviewSession {

        print("📋 Starting review for \(formatDateRange(startDate, endDate))")

        // Convert to CSVRowData for easier handling
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        let allRowsData = csvRows.map { CSVRowData(data: $0, dateFormatter: dateFormatter) }

        // Filter rows by date
        let rowsInRange = allRowsData.filter { row in
            row.date >= startDate && row.date <= endDate
        }

        print("   Found \(rowsInRange.count) CSV rows in range")

        // Get existing transactions in range
        let existingTransactions = session.transactions.filter { txn in
            txn.date >= startDate && txn.date <= endDate
        }

        print("   Found \(existingTransactions.count) existing transactions in range")

        // Build coverage index for this range
        let coverageIndex = buildRangeCoverageIndex(
            rows: rowsInRange,
            transactions: existingTransactions
        )

        let uncovered = rowsInRange.filter { row in
            !(coverageIndex[row.globalRowNumber]?.isCovered ?? false)
        }

        print("   Uncovered rows in range: \(uncovered.count)")

        // Build review prompt
        let prompt = buildReviewPrompt(
            rows: rowsInRange,
            existingTransactions: existingTransactions,
            uncoveredRows: uncovered,
            mode: mode
        )

        // Call AI
        let startTime = Date()
        let response = try await callClaudeAPI(prompt: prompt)
        let duration = Date().timeIntervalSince(startTime)

        // Parse deltas
        let deltas = try parseDeltas(from: response)

        // Create review session
        let reviewSession = ReviewSession(
            categorizationSession: session,
            startDate: startDate,
            endDate: endDate,
            rowsInScope: rowsInRange.map { $0.globalRowNumber }
        )

        reviewSession.inputTokens = response.usage.inputTokens
        reviewSession.outputTokens = response.usage.outputTokens
        reviewSession.durationSeconds = duration

        // Add deltas
        for delta in deltas {
            delta.reviewSession = reviewSession
            modelContext.insert(delta)
        }

        reviewSession.isComplete = true

        modelContext.insert(reviewSession)
        session.reviewSessions.append(reviewSession)

        return reviewSession
    }

    /// Review specific uncovered rows with context expansion
    func reviewUncoveredRows(
        session: CategorizationSession,
        csvRows: [[String: String]],
        uncoveredRowNumbers: [Int]
    ) async throws -> ReviewSession {

        print("🔍 Reviewing \(uncoveredRowNumbers.count) uncovered rows")

        // Convert to CSVRowData
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        let allRowsData = csvRows.map { CSVRowData(data: $0, dateFormatter: dateFormatter) }

        // Get the uncovered rows
        let uncoveredRows = allRowsData.filter { row in
            uncoveredRowNumbers.contains(row.globalRowNumber)
        }

        guard let firstRow = uncoveredRows.first,
              let lastRow = uncoveredRows.last else {
            throw ReviewError.noRowsToReview
        }

        // Expand context to include nearby rows for better understanding
        let expandedRows = expandContext(uncoveredRows, in: allRowsData, contextDays: 2)

        print("   Expanded to \(expandedRows.count) rows for context")

        // Convert back to dictionary format for reviewDateRange
        let expandedDicts = expandedRows.map { $0.data }

        // Use date range review with gap-filling mode
        return try await reviewDateRange(
            session: session,
            csvRows: expandedDicts,
            startDate: firstRow.date,
            endDate: lastRow.date,
            mode: .gapFilling
        )
    }

    // MARK: - Delta Application

    /// Apply deltas from a review session
    func applyDeltas(
        from reviewSession: ReviewSession,
        to session: CategorizationSession
    ) throws {

        print("📝 Applying \(reviewSession.deltas.count) deltas")

        for delta in reviewSession.deltas {
            switch delta.action {
            case .create:
                try applyCreate(delta, to: session)
            case .update:
                try applyUpdate(delta, to: session)
            case .delete:
                try applyDelete(delta, to: session)
            case .exclude:
                try applyExclude(delta, to: session)
            }

            delta.appliedAt = Date()
        }

        // Update session statistics
        session.updateStatistics()

        // Update review session counts
        reviewSession.transactionsCreated = reviewSession.deltas.filter { $0.action == .create }.count
        reviewSession.transactionsUpdated = reviewSession.deltas.filter { $0.action == .update }.count
        reviewSession.transactionsDeleted = reviewSession.deltas.filter { $0.action == .delete }.count

        // Count excluded rows
        let excludedCount = reviewSession.deltas
            .filter { $0.action == .exclude }
            .compactMap { $0.excludedRows?.count }
            .reduce(0, +)

        try modelContext.save()

        print("✅ Applied deltas:")
        print("   Created: \(reviewSession.transactionsCreated)")
        print("   Updated: \(reviewSession.transactionsUpdated)")
        print("   Deleted: \(reviewSession.transactionsDeleted)")
        if excludedCount > 0 {
            print("   Excluded: \(excludedCount) rows")
        }
    }

    // MARK: - Private Helpers

    private func buildRangeCoverageIndex(
        rows: [CSVRowData],
        transactions: [Transaction]
    ) -> [Int: RowCoverage] {
        var index: [Int: RowCoverage] = [:]

        // Initialize all rows as uncovered
        for row in rows {
            index[row.globalRowNumber] = RowCoverage(
                rowNumber: row.globalRowNumber,
                transactionIds: []
            )
        }

        // Mark covered rows
        for transaction in transactions {
            for rowNum in transaction.sourceRowNumbers {
                if index[rowNum] != nil {
                    index[rowNum]?.transactionIds.append(transaction.id)
                }
            }
        }

        return index
    }

    private func expandContext(
        _ rows: [CSVRowData],
        in allRows: [CSVRowData],
        contextDays: Int = 2
    ) -> [CSVRowData] {

        guard let firstDate = rows.first?.date,
              let lastDate = rows.last?.date else {
            return rows
        }

        let calendar = Calendar.current
        let expandedStart = calendar.date(byAdding: .day, value: -contextDays, to: firstDate) ?? firstDate
        let expandedEnd = calendar.date(byAdding: .day, value: contextDays, to: lastDate) ?? lastDate

        return allRows.filter { row in
            row.date >= expandedStart && row.date <= expandedEnd
        }.sorted { $0.date < $1.date }
    }

    private func formatDateRange(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
    }

    // MARK: - Prompt Building

    private func buildReviewPrompt(
        rows: [CSVRowData],
        existingTransactions: [Transaction],
        uncoveredRows: [CSVRowData],
        mode: ReviewMode
    ) -> String {

        // Build coverage index
        var coverageIndex: [Int: [UUID]] = [:]
        for transaction in existingTransactions {
            for rowNum in transaction.sourceRowNumbers {
                if coverageIndex[rowNum] == nil {
                    coverageIndex[rowNum] = []
                }
                coverageIndex[rowNum]?.append(transaction.id)
            }
        }

        let coveredRowNumbers = Set(coverageIndex.keys)
        let uncoveredRowNumbers = Set(uncoveredRows.map { $0.globalRowNumber })

        // Format CSV rows
        let csvString = formatRowsAsCSV(rows)

        // Format existing transactions
        let existingTxnsString = formatExistingTransactions(existingTransactions, coverageIndex: coverageIndex)

        // Detect year range
        let yearRange = detectYearRange(from: rows)

        let taskDescription = describeTask(for: mode, uncoveredCount: uncoveredRows.count)

        return """
        TRANSACTION REVIEW MODE

        You are reviewing financial transaction categorizations for accuracy and completeness.

        === CSV DATA ===
        \(rows.count) rows spanning \(formatDateRange(rows.first?.date ?? Date(), rows.last?.date ?? Date()))

        ```csv
        \(csvString)
        ```

        === EXISTING TRANSACTIONS ===
        \(existingTransactions.count) transactions already created:

        \(existingTxnsString)

        === ROW COVERAGE ANALYSIS ===
        Total rows in scope: \(rows.count)
        Covered rows: \(coveredRowNumbers.count) - Row numbers: \(coveredRowNumbers.sorted().map { "#\($0)" }.joined(separator: ", "))
        UNCOVERED rows: \(uncoveredRowNumbers.count) - Row numbers: \(uncoveredRowNumbers.sorted().map { "#\($0)" }.joined(separator: ", "))

        === YOUR TASK ===
        \(taskDescription)

        === YEAR CONTEXT ===
        - These transactions span the year(s): \(yearRange)
        - When you see dates in MM/dd/yyyy format, the year is already specified
        - Return dates in yyyy-MM-dd format, using the EXACT year from the CSV

        === RESPONSE FORMAT ===
        Return a JSON object with deltas (changes to apply):

        ```json
        {
          "deltas": [
            {
              "action": "create",
              "reason": "Rows #123, #124 are uncovered and form a buy transaction for SPY",
              "transaction": {
                "sourceRows": [123, 124],
                "date": "2024-05-15",
                "description": "Buy SPY",
                "transactionType": "buy",
                "journalEntries": [
                  {
                    "type": "debit",
                    "accountType": "asset",
                    "accountName": "SPY",
                    "amount": 5000.00,
                    "quantity": 10,
                    "quantityUnit": "shares",
                    "assetSymbol": "SPY"
                  },
                  {
                    "type": "credit",
                    "accountType": "cash",
                    "accountName": "Cash USD",
                    "amount": 5000.00
                  }
                ]
              }
            },
            {
              "action": "exclude",
              "reason": "Rows #457-465 contain legal disclaimers and file metadata, not transaction data",
              "excludedRows": [457, 458, 459, 460, 461, 462, 463, 464, 465]
            }
          ],
          "summary": "Created 1 transaction and excluded 9 non-transactional rows"
        }
        ```

        IMPORTANT - Exclusion Action:
        - Use "action": "exclude" for rows that are NOT financial transactions
        - Common exclusions: legal disclaimers, copyright notices, file metadata, headers, blank rows
        - Provide "excludedRows" array with the row numbers to exclude
        - Provide clear "reason" explaining why these are non-transactional
        - Excluded rows will not count against coverage percentage
        ```

        CRITICAL RULES:
        - Every row must be covered by exactly one transaction
        - All transactions must balance (total debits = total credits)
        - Use _globalRowNumber for sourceRows arrays
        - Preserve Fidelity settlement patterns (dual-row structure)
        - Use exact asset symbols from CSV (FBTC, FXAIX, SPY, etc.)
        """
    }

    private func describeTask(for mode: ReviewMode, uncoveredCount: Int) -> String {
        switch mode {
        case .gapFilling:
            return """
            Focus on UNCOVERED rows (\(uncoveredCount) rows need coverage):
            1. Identify which uncovered rows form transactions
            2. Create new transactions to cover them using "action": "create"
            3. Do NOT modify existing correct transactions
            4. Every delta must have a clear "reason" explaining why the change is needed
            """
        case .qualityCheck:
            return """
            Focus on EXISTING transactions:
            1. Verify each transaction is correctly structured
            2. Check that source rows are appropriate
            3. Suggest updates for incorrect transactions using "action": "update"
            4. Suggest deletions for invalid transactions using "action": "delete"
            5. Every delta must have a clear "reason"
            """
        case .fullReview:
            return """
            Comprehensive review:
            1. Verify all existing transactions are correct
            2. Create transactions for \(uncoveredCount) uncovered rows
            3. Update incorrect transactions
            4. Delete invalid transactions
            5. Every delta must have a clear "reason"
            """
        case .targeted:
            return """
            Address specific issues flagged in the coverage analysis.
            Focus on unbalanced transactions and uncovered rows.
            Every delta must have a clear "reason".
            """
        }
    }

    private func formatRowsAsCSV(_ rows: [CSVRowData]) -> String {
        guard let firstRow = rows.first else { return "" }

        // Get headers from first row
        let headers = Array(firstRow.data.keys.sorted()) + ["_globalRowNumber", "_sourceFile", "_fileRowNumber"]

        var csvLines: [String] = []
        csvLines.append(headers.joined(separator: ","))

        for row in rows {
            let values = headers.map { header in
                var value: String
                if header == "_globalRowNumber" {
                    value = "\(row.globalRowNumber)"
                } else if header == "_sourceFile" {
                    value = row.sourceFileName
                } else if header == "_fileRowNumber" {
                    value = "\(row.fileRowNumber)"
                } else {
                    value = row.data[header] ?? ""
                }

                // Quote if contains comma or quote
                if value.contains(",") || value.contains("\"") {
                    return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return value
            }
            csvLines.append(values.joined(separator: ","))
        }

        return csvLines.joined(separator: "\n")
    }

    private func formatExistingTransactions(
        _ transactions: [Transaction],
        coverageIndex: [Int: [UUID]]
    ) -> String {
        if transactions.isEmpty {
            return "No existing transactions in this range."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium

        var lines: [String] = []
        for (index, txn) in transactions.enumerated() {
            let rowList = txn.sourceRowNumbers.map { "#\($0)" }.joined(separator: ", ")
            lines.append("""
            Transaction #\(index + 1) [ID: \(txn.id.uuidString.prefix(8))]:
              Date: \(formatter.string(from: txn.date))
              Description: \(txn.transactionDescription)
              Type: \(txn.transactionType.rawValue)
              Source Rows: \(rowList)
              Journal Entries: \(txn.journalEntries.count) (\(txn.isBalanced ? "BALANCED ✓" : "UNBALANCED ✗"))
            """)
        }

        return lines.joined(separator: "\n\n")
    }

    private func detectYearRange(from rows: [CSVRowData]) -> String {
        guard let oldestDate = rows.first?.date,
              let newestDate = rows.last?.date else {
            return "2024-2025"
        }

        let calendar = Calendar.current
        let oldestYear = calendar.component(.year, from: oldestDate)
        let newestYear = calendar.component(.year, from: newestDate)

        if oldestYear == newestYear {
            return "\(oldestYear)"
        } else {
            return "\(oldestYear)-\(newestYear)"
        }
    }

    // MARK: - API Communication

    private func callClaudeAPI(prompt: String) async throws -> ClaudeAPIResponse {
        let apiService = ClaudeAPIService.shared

        let systemPrompt = buildSystemPrompt()

        let response = try await apiService.sendMessage(
            messages: [ClaudeMessage(role: "user", content: prompt)],
            system: systemPrompt,
            maxTokens: 4096,
            temperature: 0,
            stream: false
        )

        // Extract text from response
        let text = response.content.compactMap { $0.text }.joined()

        return ClaudeAPIResponse(
            content: text,
            usage: ClaudeAPIResponse.UsageInfo(
                inputTokens: response.usage.inputTokens,
                outputTokens: response.usage.outputTokens
            )
        )
    }

    private func buildSystemPrompt() -> String {
        return """
        You are a financial transaction categorization specialist. Your task is to review CSV
        transaction data and existing transactions, then produce deltas (changes) to ensure accuracy and completeness.

        CRITICAL ACCOUNTING RULES:
        - Every transaction MUST balance: total debits = total credits
        - Use exact symbols from CSV (FBTC != BTC, they are different assets)
        - Each transaction needs 2+ journal entry legs

        FIDELITY SETTLEMENT PATTERN:
        Fidelity uses dual-row structure:
        - Row N: Primary transaction (Action, Symbol, Quantity, Amount)
        - Row N+1: Settlement row (Action="", Symbol="", Quantity=0, Amount matches)
        - These TWO rows form ONE transaction
        - sourceRows should include both: [N, N+1]

        ACCOUNT TYPES:
        - asset: Stocks, ETFs, Mutual Funds (SPY, FXAIX, NVDA, VOO, FBTC, SCHD, GLD, VXUS, QQQ, SPAXX)
        - cash: USD currency ("Cash USD")
        - income: Dividend Income, Interest Income
        - expense: Fees, Commissions, Cash Withdrawals, Payments
        - equity: Owner Contributions (deposits), Owner Withdrawals (withdrawals)

        TRANSACTION TYPES:
        - buy: Purchase of securities (Debit Asset, Credit Cash)
        - sell: Sale of securities (Debit Cash, Credit Asset)
        - dividend: Dividend received (Debit Cash/Asset, Credit Income)
        - deposit/transfer_in: Money in (Debit Cash, Credit Equity)
        - withdrawal/transfer_out: Money out (Debit Equity, Credit Cash)
        - fee: Fees charged (Debit Expense, Credit Cash)
        """
    }

    // MARK: - Delta Parsing

    private func parseDeltas(from response: ClaudeAPIResponse) throws -> [TransactionDelta] {
        print("📝 Parsing deltas from response (\(response.content.count) chars)")

        // Extract JSON from markdown code blocks if present
        let jsonString = extractJSON(from: response.content)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw ReviewError.invalidDelta("Failed to parse JSON from response")
        }

        guard let deltasArray = json["deltas"] as? [[String: Any]] else {
            throw ReviewError.invalidDelta("No 'deltas' array in response")
        }

        print("✓ Found \(deltasArray.count) deltas in response")

        var deltas: [TransactionDelta] = []

        for (index, deltaDict) in deltasArray.enumerated() {
            guard let actionString = deltaDict["action"] as? String,
                  let action = TransactionDelta.Action(rawValue: actionString),
                  let reason = deltaDict["reason"] as? String else {
                print("⚠️ Delta #\(index): Missing action or reason")
                continue
            }

            // Parse original transaction reference (for update/delete)
            let originalId = (deltaDict["originalTransactionId"] as? String).flatMap { UUID(uuidString: $0) }
            let originalRows = deltaDict["originalSourceRows"] as? [Int]

            // Parse new transaction data (for create/update)
            var newTransactionData: Data?
            if let transactionDict = deltaDict["transaction"] as? [String: Any] {
                newTransactionData = try? JSONSerialization.data(withJSONObject: transactionDict)
            }

            // Parse excluded rows (for exclude action)
            let excludedRows = deltaDict["excludedRows"] as? [Int]

            let delta = TransactionDelta(
                action: action,
                reason: reason,
                originalTransactionId: originalId,
                originalSourceRows: originalRows,
                newTransactionData: newTransactionData
            )

            // Set excluded rows if present
            if let rows = excludedRows {
                delta.excludedRows = rows
            }

            deltas.append(delta)
            print("  ✓ Delta #\(index): \(action.rawValue) - \(reason.prefix(80))...")
        }

        return deltas
    }

    private func extractJSON(from response: String) -> String {
        // Try to extract JSON from markdown code blocks
        if let match = response.range(of: "```json\\s*\\n(.+?)\\n```", options: .regularExpression) {
            let jsonBlock = String(response[match])
            let lines = jsonBlock.components(separatedBy: "\n")
            let jsonLines = lines.dropFirst().dropLast()  // Remove ```json and ```
            return jsonLines.joined(separator: "\n")
        }

        // Try to find raw JSON object
        if let start = response.range(of: "{")?.lowerBound,
           let end = response.range(of: "}", options: .backwards)?.upperBound {
            return String(response[start..<end])
        }

        return response
    }

    // MARK: - Delta Application

    private func applyCreate(_ delta: TransactionDelta, to session: CategorizationSession) throws {
        guard let txnData = delta.newTransactionData else {
            throw ReviewError.invalidDelta("Create delta missing transaction data")
        }

        // Decode transaction data
        guard let txnDict = try? JSONSerialization.jsonObject(with: txnData) as? [String: Any],
              let sourceRows = txnDict["sourceRows"] as? [Int],
              let dateString = txnDict["date"] as? String,
              let description = txnDict["description"] as? String,
              let typeString = txnDict["transactionType"] as? String,
              let entriesArray = txnDict["journalEntries"] as? [[String: Any]] else {
            throw ReviewError.invalidDelta("Invalid transaction data structure")
        }

        // Parse date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = dateFormatter.date(from: dateString) else {
            throw ReviewError.invalidDelta("Invalid date format: \(dateString)")
        }

        // Map transaction type
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

        // Create transaction
        guard let account = session.account else {
            throw ReviewError.applyFailed("Session has no account")
        }

        let transaction = Transaction(
            date: date,
            description: description,
            type: type,
            account: account
        )

        transaction.sourceRowNumbers = sourceRows
        transaction.categorizationSession = session

        // Parse journal entries
        for entryDict in entriesArray {
            guard let typeStr = entryDict["type"] as? String,
                  let accountTypeStr = entryDict["accountType"] as? String,
                  let accountName = entryDict["accountName"] as? String else {
                continue
            }

            let accountType = AccountType(rawValue: accountTypeStr) ?? .asset

            // Parse amount (can be Int, Double, or Decimal in JSON)
            var amount: Decimal = 0
            if let amountDouble = entryDict["amount"] as? Double {
                amount = Decimal(amountDouble)
            } else if let amountInt = entryDict["amount"] as? Int {
                amount = Decimal(amountInt)
            } else if let amountString = entryDict["amount"] as? String,
                      let amountDecimal = Decimal(string: amountString) {
                amount = amountDecimal
            }

            // Parse quantity if present
            var quantity: Decimal?
            if let qtyDouble = entryDict["quantity"] as? Double {
                quantity = Decimal(qtyDouble)
            } else if let qtyInt = entryDict["quantity"] as? Int {
                quantity = Decimal(qtyInt)
            }

            let quantityUnit = entryDict["quantityUnit"] as? String

            // Create entry with debit or credit based on type
            let entry = JournalEntry(
                accountType: accountType,
                accountName: accountName,
                debitAmount: typeStr == "debit" ? amount : nil,
                creditAmount: typeStr == "credit" ? amount : nil,
                quantity: quantity,
                quantityUnit: quantityUnit,
                transaction: transaction
            )

            modelContext.insert(entry)
        }

        modelContext.insert(transaction)
        session.transactions.append(transaction)

        print("  ✅ Created transaction: \(description) covering rows \(sourceRows.map { "#\($0)" }.joined(separator: ", "))")
    }

    private func applyUpdate(_ delta: TransactionDelta, to session: CategorizationSession) throws {
        guard let originalId = delta.originalTransactionId else {
            throw ReviewError.invalidDelta("Update delta missing originalTransactionId")
        }

        guard let transaction = session.transactions.first(where: { $0.id == originalId }) else {
            throw ReviewError.transactionNotFound(originalId)
        }

        // For now, we'll implement update by delete + create
        // This is simpler and safer than in-place modification
        print("  ⚠️ Update via delete+create for transaction \(transaction.transactionDescription)")

        // Delete old transaction
        modelContext.delete(transaction)
        session.transactions.removeAll { $0.id == originalId }

        // Create new transaction
        try applyCreate(delta, to: session)
    }

    private func applyDelete(_ delta: TransactionDelta, to session: CategorizationSession) throws {
        guard let originalId = delta.originalTransactionId else {
            throw ReviewError.invalidDelta("Delete delta missing originalTransactionId")
        }

        guard let transaction = session.transactions.first(where: { $0.id == originalId }) else {
            throw ReviewError.transactionNotFound(originalId)
        }

        print("  🗑️ Deleting transaction: \(transaction.transactionDescription) (rows \(transaction.sourceRowNumbers.map { "#\($0)" }.joined(separator: ", ")))")

        modelContext.delete(transaction)
        session.transactions.removeAll { $0.id == originalId }
    }

    private func applyExclude(_ delta: TransactionDelta, to session: CategorizationSession) throws {
        guard let rowsToExclude = delta.excludedRows, !rowsToExclude.isEmpty else {
            throw ReviewError.invalidDelta("Exclude delta missing excludedRows array")
        }

        print("  🚫 Excluding \(rowsToExclude.count) rows: \(rowsToExclude.map { "#\($0)" }.joined(separator: ", "))")
        print("     Reason: \(delta.reason)")

        // Add to session's excluded rows (avoiding duplicates)
        var currentExcluded = Set(session.excludedRowNumbers)
        currentExcluded.formUnion(rowsToExclude)
        session.excludedRowNumbers = Array(currentExcluded).sorted()

        print("     Total excluded rows now: \(session.excludedRowNumbers.count)")
    }
}

// MARK: - Errors

enum ReviewError: LocalizedError {
    case noRowsToReview
    case invalidDelta(String)
    case transactionNotFound(UUID)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .noRowsToReview:
            return "No rows to review"
        case .invalidDelta(let reason):
            return "Invalid delta: \(reason)"
        case .transactionNotFound(let id):
            return "Transaction not found: \(id)"
        case .applyFailed(let reason):
            return "Failed to apply delta: \(reason)"
        }
    }
}

// MARK: - Internal Response Structure

struct ClaudeAPIResponse {
    let content: String
    let usage: UsageInfo

    struct UsageInfo {
        let inputTokens: Int
        let outputTokens: Int
    }
}
