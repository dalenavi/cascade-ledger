//
//  ReconciliationService.swift
//  cascade-ledger
//
//  Balance reconciliation between CSV and calculated balances
//

import Foundation
import SwiftData

/// Service for balance reconciliation
class ReconciliationService {
    private let balanceCalculator = BalanceCalculationService()
    private let clauseAPIService: ClaudeAPIService

    init(claudeAPIService: ClaudeAPIService) {
        self.clauseAPIService = claudeAPIService
    }

    // MARK: - Phase 1: Build Checkpoints

    /// Build balance checkpoints from CSV rows
    func buildBalanceCheckpoints(
        session: CategorizationSession,
        csvRows: [[String: String]],
        modelContext: ModelContext
    ) -> [BalanceCheckpoint] {
        var checkpoints: [BalanceCheckpoint] = []

        // Get all transactions sorted by date
        let transactions = session.transactions.sorted { $0.date < $1.date }

        // Process each CSV row
        for (index, row) in csvRows.enumerated() {
            let rowNumber = index + 1

            // Check if row has balance field
            guard let balanceField = row["Balance"],
                  !balanceField.isEmpty,
                  let csvBalance = parseBalance(balanceField) else {
                continue
            }

            // Get date for this row
            guard let dateStr = row["Run Date"],
                  let date = parseDate(dateStr) else {
                continue
            }

            // Calculate balance at this date
            let calculatedBalance = balanceCalculator.calculateCashBalance(
                upToDate: date,
                transactions: transactions
            )

            // Create checkpoint
            let checkpoint = BalanceCheckpoint(
                date: date,
                rowNumber: rowNumber,
                csvBalance: csvBalance,
                csvBalanceField: balanceField,
                calculatedBalance: calculatedBalance,
                categorizationSession: session
            )

            modelContext.insert(checkpoint)
            checkpoints.append(checkpoint)
        }

        return checkpoints
    }

    // MARK: - Phase 2: Detect Discrepancies

    /// Find all discrepancies in checkpoints and transactions
    func findDiscrepancies(
        checkpoints: [BalanceCheckpoint],
        session: CategorizationSession,
        modelContext: ModelContext
    ) -> [Discrepancy] {
        var discrepancies: [Discrepancy] = []

        // 1. Balance mismatches
        for checkpoint in checkpoints where checkpoint.hasDiscrepancy {
            let discrepancy = Discrepancy(
                type: .balanceMismatch,
                severity: checkpoint.severity,
                startDate: checkpoint.date,
                endDate: checkpoint.date,
                affectedRowNumbers: [checkpoint.rowNumber],
                summary: "Balance mismatch at row \(checkpoint.rowNumber)",
                evidence: "CSV balance: \(checkpoint.csvBalance), Calculated: \(checkpoint.calculatedBalance), Discrepancy: \(checkpoint.discrepancyAmount)",
                expectedValue: checkpoint.csvBalance,
                actualValue: checkpoint.calculatedBalance,
                delta: checkpoint.discrepancyAmount,
                categorizationSession: session,
                relatedCheckpoint: checkpoint
            )

            modelContext.insert(discrepancy)
            discrepancies.append(discrepancy)
        }

        // 2. Unbalanced transactions
        for transaction in session.transactions where !transaction.isBalanced {
            let discrepancy = Discrepancy(
                type: .unbalancedTxn,
                severity: .critical,
                startDate: transaction.date,
                endDate: transaction.date,
                affectedRowNumbers: transaction.sourceRowNumbers,
                summary: "Unbalanced transaction: debits ≠ credits",
                evidence: "Debits: \(transaction.totalDebits), Credits: \(transaction.totalCredits)",
                expectedValue: transaction.totalCredits,
                actualValue: transaction.totalDebits,
                delta: transaction.totalDebits - transaction.totalCredits,
                categorizationSession: session
            )

            modelContext.insert(discrepancy)
            discrepancies.append(discrepancy)
        }

        // 3. Negative starting balance pattern
        if let firstCheckpoint = checkpoints.first,
           firstCheckpoint.calculatedBalance < 0 {
            let discrepancy = Discrepancy(
                type: .missingTransaction,
                severity: .critical,
                startDate: firstCheckpoint.date,
                endDate: firstCheckpoint.date,
                affectedRowNumbers: [firstCheckpoint.rowNumber],
                summary: "Negative starting balance indicates missing opening balance or funding transaction",
                evidence: "First calculated balance: \(firstCheckpoint.calculatedBalance), Expected: \(firstCheckpoint.csvBalance)",
                expectedValue: firstCheckpoint.csvBalance,
                actualValue: firstCheckpoint.calculatedBalance,
                delta: firstCheckpoint.discrepancyAmount,
                categorizationSession: session,
                relatedCheckpoint: firstCheckpoint
            )

            modelContext.insert(discrepancy)
            discrepancies.append(discrepancy)
        }

        return discrepancies
    }

    // MARK: - Phase 3: Investigate (AI)

    /// Investigate a discrepancy using AI
    func investigate(
        discrepancy: Discrepancy,
        session: CategorizationSession,
        csvRows: [[String: String]],
        modelContext: ModelContext,
        thoroughness: InvestigationThoroughness = .balanced
    ) async throws -> Investigation {
        let startTime = Date()

        // Build context window
        let contextDays = thoroughness.contextDays
        let contextWindow = buildContextWindow(
            discrepancy: discrepancy,
            session: session,
            csvRows: csvRows,
            contextDays: contextDays
        )

        // Build investigation prompt
        let prompt = buildInvestigationPrompt(
            discrepancy: discrepancy,
            contextWindow: contextWindow,
            session: session
        )

        // Call Claude API
        let response = try await clauseAPIService.sendMessage(
            messages: [ClaudeMessage(role: "user", content: prompt)],
            maxTokens: 4096
        )

        let duration = Date().timeIntervalSince(startTime)

        // Parse response
        let contentText = response.content.compactMap { $0.text }.joined()
        let investigationData = try parseInvestigationResponse(contentText)

        // Create Investigation object
        let investigation = Investigation(
            hypothesis: investigationData.hypothesis,
            evidenceAnalysis: investigationData.evidenceAnalysis,
            uncertainties: investigationData.uncertainties,
            needsMoreData: investigationData.needsMoreData,
            proposedFixes: investigationData.proposedFixes,
            aiModel: response.model,
            inputTokens: response.usage.inputTokens,
            outputTokens: response.usage.outputTokens,
            durationSeconds: duration,
            discrepancy: discrepancy
        )

        modelContext.insert(investigation)

        return investigation
    }

    // MARK: - Phase 4: Apply Fixes

    /// Apply a proposed fix
    func applyFix(
        _ fix: ProposedFix,
        investigation: Investigation,
        session: CategorizationSession,
        reviewSession: ReviewSession,
        reviewService: TransactionReviewService,
        modelContext: ModelContext
    ) throws {
        // Convert ProposedFix deltas to TransactionDeltas
        for deltaData in fix.deltas {
            let delta = try createTransactionDelta(from: deltaData, reason: fix.reasoning)
            delta.reviewSession = reviewSession
            modelContext.insert(delta)
            reviewSession.deltas.append(delta)
        }

        // Apply deltas using review service
        try reviewService.applyDeltas(from: reviewSession, to: session)

        // Mark investigation as applied
        investigation.wasApplied = true
        investigation.appliedAt = Date()

        // Mark discrepancy as resolved
        if let discrepancy = investigation.discrepancy {
            discrepancy.isResolved = true
            discrepancy.resolvedAt = Date()
        }
    }

    // MARK: - Phase 5: Full Reconciliation

    /// Run full reconciliation (iterative)
    func reconcile(
        session: CategorizationSession,
        csvRows: [[String: String]],
        reviewService: TransactionReviewService,
        modelContext: ModelContext,
        maxIterations: Int = 3
    ) async throws -> ReconciliationSession {
        let reconciliationSession = ReconciliationSession(categorizationSession: session)
        modelContext.insert(reconciliationSession)

        var iteration = 0

        while iteration < maxIterations {
            iteration += 1
            reconciliationSession.iterations = iteration

            // Build checkpoints
            let checkpoints = buildBalanceCheckpoints(
                session: session,
                csvRows: csvRows,
                modelContext: modelContext
            )
            reconciliationSession.checkpointsBuilt = checkpoints.count
            reconciliationSession.checkpoints.append(contentsOf: checkpoints)

            // Find discrepancies
            let discrepancies = findDiscrepancies(
                checkpoints: checkpoints,
                session: session,
                modelContext: modelContext
            )
            reconciliationSession.discrepanciesFound = discrepancies.count
            reconciliationSession.discrepancies.append(contentsOf: discrepancies)

            // Track initial max discrepancy
            if iteration == 1 {
                reconciliationSession.initialMaxDiscrepancy = checkpoints.map { abs($0.discrepancyAmount) }.max() ?? 0
            }

            // Stop if no discrepancies
            if discrepancies.isEmpty {
                reconciliationSession.isFullyReconciled = true
                break
            }

            // Investigate high-priority discrepancies
            var hasAppliedFixes = false

            for discrepancy in discrepancies.sorted(by: { $0.severity.rawValue < $1.severity.rawValue }) {
                // Skip if already resolved
                if discrepancy.isResolved { continue }

                // Investigate
                let investigation = try await investigate(
                    discrepancy: discrepancy,
                    session: session,
                    csvRows: csvRows,
                    modelContext: modelContext
                )
                reconciliationSession.investigations.append(investigation)

                // Apply high-confidence fixes (≥95%)
                if let bestFix = investigation.proposedFixes.first(where: { $0.confidence >= 0.95 }) {
                    // Create a review session for this fix
                    let reviewSession = ReviewSession(
                        categorizationSession: session,
                        startDate: discrepancy.startDate,
                        endDate: discrepancy.endDate,
                        rowsInScope: discrepancy.affectedRowNumbers,
                        aiModel: investigation.aiModel,
                        promptVersion: "reconciliation-v1"
                    )
                    modelContext.insert(reviewSession)

                    try applyFix(
                        bestFix,
                        investigation: investigation,
                        session: session,
                        reviewSession: reviewSession,
                        reviewService: reviewService,
                        modelContext: modelContext
                    )
                    reconciliationSession.fixesApplied += 1
                    hasAppliedFixes = true
                }
            }

            // Stop if no fixes were applied
            if !hasAppliedFixes {
                break
            }

            // Update statistics
            reconciliationSession.discrepanciesResolved = reconciliationSession.discrepancies.filter { $0.isResolved }.count
        }

        // Final status
        reconciliationSession.finalMaxDiscrepancy = reconciliationSession.checkpoints.map { abs($0.discrepancyAmount) }.max() ?? 0
        reconciliationSession.isComplete = true

        return reconciliationSession
    }

    // MARK: - Helper Methods

    private func parseBalance(_ balanceField: String) -> Decimal? {
        // Remove $ and commas
        let cleaned = balanceField
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)

        return Decimal(string: cleaned)
    }

    private func parseDate(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.date(from: dateStr)
    }

    private func buildContextWindow(
        discrepancy: Discrepancy,
        session: CategorizationSession,
        csvRows: [[String: String]],
        contextDays: Int
    ) -> ContextWindow {
        let startDate = Calendar.current.date(byAdding: .day, value: -contextDays, to: discrepancy.startDate) ?? discrepancy.startDate
        let endDate = Calendar.current.date(byAdding: .day, value: contextDays, to: discrepancy.endDate) ?? discrepancy.endDate

        // Filter CSV rows in range
        let contextRows = csvRows.filter { row in
            guard let dateStr = row["Run Date"],
                  let date = parseDate(dateStr) else {
                return false
            }
            return date >= startDate && date <= endDate
        }

        // Filter transactions in range
        let contextTransactions = session.transactions.filter { transaction in
            transaction.date >= startDate && transaction.date <= endDate
        }

        return ContextWindow(
            startDate: startDate,
            endDate: endDate,
            csvRows: contextRows,
            transactions: contextTransactions
        )
    }

    private func buildInvestigationPrompt(
        discrepancy: Discrepancy,
        contextWindow: ContextWindow,
        session: CategorizationSession
    ) -> String {
        // Build detailed investigation prompt based on design
        var prompt = """
        ACCOUNTANT MODE: Discrepancy Investigation

        You are a meticulous accountant investigating balance discrepancies in a financial ledger.

        === DISCREPANCY ===
        Type: \(discrepancy.type.rawValue)
        Date Range: \(formatDate(discrepancy.startDate)) to \(formatDate(discrepancy.endDate))
        Summary: \(discrepancy.summary)
        Evidence: \(discrepancy.evidence)
        """

        if let expected = discrepancy.expectedValue, let actual = discrepancy.actualValue {
            prompt += "\nExpected: $\(expected)"
            prompt += "\nActual: $\(actual)"
            prompt += "\nDiscrepancy: $\(discrepancy.delta ?? 0)"
        }

        prompt += "\n\nSeverity: \(discrepancy.severity.rawValue.uppercased())"

        // Add CSV context
        prompt += "\n\n=== CSV DATA (Context Window) ==="
        prompt += "\n```csv"
        // Add CSV rows (simplified)
        for row in contextWindow.csvRows.prefix(20) {
            prompt += "\n\(row["Run Date"] ?? ""),\(row["Action"] ?? ""),\(row["Symbol"] ?? ""),\(row["Quantity"] ?? ""),\(row["Amount"] ?? ""),\(row["Balance"] ?? "")"
        }
        prompt += "\n```"

        // Add existing transactions
        prompt += "\n\n=== EXISTING TRANSACTIONS ==="
        for (index, transaction) in contextWindow.transactions.prefix(10).enumerated() {
            prompt += "\n\nTransaction #\(index + 1) [ID: \(transaction.id)] (Rows #\(transaction.sourceRowNumbers.map(String.init).joined(separator: ", "))):"
            prompt += "\n  Date: \(formatDate(transaction.date))"
            prompt += "\n  Description: \"\(transaction.transactionDescription)\""
            prompt += "\n  Type: \(transaction.transactionType.rawValue)"
            prompt += "\n  Journal Entries: \(transaction.journalEntries.count) (\(transaction.isBalanced ? "BALANCED" : "UNBALANCED"))"

            for entry in transaction.journalEntries {
                let type = entry.isDebit ? "DR" : "CR"
                let amount = entry.amount
                prompt += "\n    \(type): \(entry.accountName) $\(amount)"
                if let qty = entry.quantity {
                    prompt += " (qty: \(qty))"
                }
            }
        }

        prompt += """


        === YOUR TASK ===
        Investigate this discrepancy and propose corrections.

        INVESTIGATION GUIDELINES:
        1. Form a hypothesis about what's wrong
        2. Analyze the evidence (CSV patterns, transaction structure)
        3. Propose 1-3 potential fixes
        4. Rate your confidence in each fix (0.0-1.0)
        5. Predict the impact of each fix
        6. Identify any uncertainties or assumptions

        IMPORTANT CONSTRAINTS:
        - Do NOT fudge numbers to force a match
        - Only propose fixes supported by CSV evidence
        - If uncertain, say so (confidence < 0.7)
        - Consider multiple possibilities
        - Explain your reasoning clearly

        RESPONSE FORMAT (JSON):
        {
          "hypothesis": "Your hypothesis about what's wrong",
          "evidenceAnalysis": "Detailed analysis of the evidence",
          "proposedFixes": [
            {
              "description": "Description of fix",
              "confidence": 0.90,
              "reasoning": "Why you think this is correct",
              "deltas": [
                {
                  "action": "create",
                  "reason": "Why this change is needed",
                  "transaction": {
                    "sourceRows": [],
                    "date": "2024-04-21",
                    "description": "Transaction description",
                    "transactionType": "deposit",
                    "journalEntries": [
                      {"type": "debit", "accountType": "cash", "accountName": "Cash USD", "amount": 1000.00},
                      {"type": "credit", "accountType": "equity", "accountName": "Opening Balance Equity", "amount": 1000.00}
                    ]
                  }
                }
              ],
              "impact": {
                "balanceChange": 1000.00,
                "transactionsCreated": 1,
                "transactionsModified": 0,
                "transactionsDeleted": 0,
                "checkpointsResolved": 1,
                "newDiscrepanciesRisk": "None"
              },
              "supportingEvidence": ["Evidence item 1", "Evidence item 2"],
              "assumptions": ["Assumption 1", "Assumption 2"]
            }
          ],
          "uncertainties": ["Uncertainty 1", "Uncertainty 2"],
          "needsMoreData": false
        }

        Respond with ONLY valid JSON matching this format.
        """

        return prompt
    }

    private func parseInvestigationResponse(_ content: String) throws -> InvestigationResponseData {
        // Extract JSON from response
        let jsonData: Data
        if let jsonStart = content.range(of: "{"),
           let jsonEnd = content.range(of: "}", options: .backwards) {
            let jsonString = String(content[jsonStart.lowerBound...jsonEnd.upperBound])
            jsonData = jsonString.data(using: .utf8)!
        } else {
            jsonData = content.data(using: .utf8)!
        }

        let decoder = JSONDecoder()
        return try decoder.decode(InvestigationResponseData.self, from: jsonData)
    }

    private func createTransactionDelta(from deltaData: DeltaTransactionData, reason: String) throws -> TransactionDelta {
        let encoder = JSONEncoder()
        let transactionData = try encoder.encode(deltaData)

        return TransactionDelta(
            action: .create,
            reason: reason,
            newTransactionData: transactionData
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Types

enum InvestigationThoroughness {
    case quick     // ±3 days
    case balanced  // ±7 days
    case thorough  // ±14 days

    var contextDays: Int {
        switch self {
        case .quick: return 3
        case .balanced: return 7
        case .thorough: return 14
        }
    }
}

struct ContextWindow {
    let startDate: Date
    let endDate: Date
    let csvRows: [[String: String]]
    let transactions: [Transaction]
}

struct InvestigationResponseData: Codable {
    let hypothesis: String
    let evidenceAnalysis: String
    let proposedFixes: [ProposedFix]
    let uncertainties: [String]
    let needsMoreData: Bool
}
