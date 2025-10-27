//
//  CategorizationService.swift
//  cascade-ledger
//
//  Service for AI-driven transaction categorization
//

import Foundation
import SwiftData
import Combine

@MainActor
class CategorizationService: ObservableObject {
    private let modelContext: ModelContext
    private let claudeAPI = ClaudeAPIService.shared

    @Published var isProcessing = false
    @Published var progress: Double = 0.0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Prompt Management

    func getGlobalPrompt() -> CategorizationPrompt {
        let descriptor = FetchDescriptor<CategorizationPrompt>(
            predicate: #Predicate<CategorizationPrompt> { prompt in
                prompt.account == nil
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Create default global prompt
        let defaultPrompt = """
        You are categorizing financial transactions. Apply these rules:

        TRANSACTION TYPES (based on what the transaction IS):
        - dividend → Income: Dividend
        - interest → Income: Interest
        - buy → Investments: Stock Purchase
        - sell → Investments: Stock Sale
        - deposit (salary patterns) → Income: Salary
        - withdrawal → varies by description
        - transfer → varies by description
        - fee → Fees & Charges
        - tax → Taxes

        COMMON PATTERNS:
        - "DIVIDEND" → Income: Dividend, tags: [Investment Income]
        - "INTEREST" → Income: Interest
        - "PAYROLL", "SALARY", "DIRECT DEP" → Income: Salary, tags: [Direct Deposit]
        - "CASH APP", "VENMO", "ZELLE" → Transfers, tags: [service name]

        For ambiguous transactions, use medium confidence (0.5-0.7).
        Only use high confidence (>0.9) for clear patterns.
        """

        let prompt = CategorizationPrompt(promptText: defaultPrompt, account: nil)
        modelContext.insert(prompt)
        try? modelContext.save()
        return prompt
    }

    func getAccountPrompt(_ account: Account) -> CategorizationPrompt? {
        let accountId = account.id
        let descriptor = FetchDescriptor<CategorizationPrompt>(
            predicate: #Predicate<CategorizationPrompt> { prompt in
                prompt.account?.id == accountId
            }
        )

        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }

        // Create default account prompt
        let defaultText = """
        Account-specific patterns will be learned here as you correct categorizations.
        """

        let prompt = CategorizationPrompt(promptText: defaultText, account: account)
        modelContext.insert(prompt)
        try? modelContext.save()
        return prompt
    }

    // MARK: - Categorization

    func categorizeTransactions(
        _ transactions: [LedgerEntry],
        account: Account
    ) async throws -> [CategorizationAttempt] {
        isProcessing = true
        progress = 0.0

        // Sort chronologically for better context
        let sortedTransactions = transactions.sorted { $0.date < $1.date }

        let globalPrompt = getGlobalPrompt()
        let accountPrompt = getAccountPrompt(account)

        let systemPrompt = buildCategorizationSystemPrompt(
            globalPrompt: globalPrompt,
            accountPrompt: accountPrompt,
            account: account
        )

        var attempts: [CategorizationAttempt] = []

        // Process in batches of 10 for efficiency
        let batchSize = 10
        let batches = sortedTransactions.chunked(into: batchSize)

        for (batchIndex, batch) in batches.enumerated() {
            print("Processing categorization batch \(batchIndex + 1)/\(batches.count)")

            let userMessage = buildBatchCategorizationRequest(batch)

            // Call Claude once for the batch
            let messages = [ClaudeMessage(role: "user", content: userMessage)]

            let response = try await claudeAPI.sendMessage(
                messages: messages,
                system: systemPrompt,
                maxTokens: 2000, // More tokens for batch
                temperature: 0.3
            )

            guard let responseText = response.content.first?.text else {
                continue
            }

            // Parse batch response
            let batchAttempts = parseBatchCategorizationResponse(responseText, transactions: batch)

            for attempt in batchAttempts {
                modelContext.insert(attempt)

                // Auto-apply if high confidence
                if attempt.status == .applied {
                    attempt.apply()
                    globalPrompt.recordSuccess()
                }

                attempts.append(attempt)
            }

            progress = Double((batchIndex + 1) * batchSize) / Double(sortedTransactions.count)
        }

        try modelContext.save()

        isProcessing = false
        return attempts
    }

    // MARK: - Prompt Building

    private func buildCategorizationSystemPrompt(
        globalPrompt: CategorizationPrompt,
        accountPrompt: CategorizationPrompt?,
        account: Account
    ) -> String {
        var prompt = """
        You are categorizing transactions for financial ledger analysis.

        ACCOUNT CONTEXT:
        - Account: \(account.name)
        - Institution: \(account.institution?.displayName ?? "None")

        GLOBAL RULES:
        \(globalPrompt.promptText)
        """

        if let accountPrompt = accountPrompt, !accountPrompt.promptText.isEmpty {
            prompt += """


            ACCOUNT-SPECIFIC RULES:
            \(accountPrompt.promptText)
            """
        }

        prompt += """


        RESPONSE FORMAT:
        You will receive multiple transactions in a batch.
        Respond with a JSON array, one object per transaction:
        [
          {
            "index": 0,
            "type": "transfer",
            "category": "Housing: Rent",
            "tags": ["Rent Payment"],
            "confidence": 0.85,
            "reasoning": "Monthly recurring transfer to landlord"
          },
          {
            "index": 1,
            "type": "dividend",
            "category": "Income: Dividend",
            "tags": ["Investment Income"],
            "confidence": 0.95,
            "reasoning": "Stock dividend payment"
          }
        ]

        Confidence levels:
        - 0.9-1.0: Very certain (will auto-apply)
        - 0.5-0.9: Likely correct (user will review)
        - 0.0-0.5: Uncertain (flag for manual review)

        Process transactions in chronological order for better context.
        """

        return prompt
    }

    private func buildBatchCategorizationRequest(_ transactions: [LedgerEntry]) -> String {
        var request = """
        Categorize these \(transactions.count) transactions in chronological order.

        For each, provide categorization in this JSON array format:
        [
          {
            "index": 0,
            "type": "transfer",
            "category": "Housing: Rent",
            "tags": ["Rent Payment"],
            "confidence": 0.85,
            "reasoning": "Brief explanation"
          }
        ]

        Transactions:
        """

        for (index, transaction) in transactions.enumerated() {
            request += """


            [\(index)] Date: \(transaction.date.formatted(date: .abbreviated, time: .omitted))
                Amount: \(transaction.amount)
                Description: \(transaction.transactionDescription)
                Type: \(transaction.transactionType.rawValue)
            """

            if let rawType = transaction.rawTransactionType {
                request += "\n    CSV Type: \(rawType)"
            }
        }

        return request
    }

    private func parseBatchCategorizationResponse(
        _ response: String,
        transactions: [LedgerEntry]
    ) -> [CategorizationAttempt] {
        // Extract JSON array from response
        guard let jsonStart = response.range(of: "["),
              let jsonEnd = response.range(of: "]", options: .backwards),
              jsonStart.lowerBound < jsonEnd.upperBound else {
            print("No JSON array found in response")
            return []
        }

        let jsonString = String(response[jsonStart.lowerBound...jsonEnd.upperBound])
        guard let jsonData = jsonString.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            print("Failed to parse JSON array")
            return []
        }

        var attempts: [CategorizationAttempt] = []

        for json in jsonArray {
            guard let index = json["index"] as? Int,
                  index < transactions.count else {
                continue
            }

            let transaction = transactions[index]
            let typeString = json["type"] as? String
            let type = typeString.flatMap { TransactionType(rawValue: $0) }
            let category = json["category"] as? String
            let tags = json["tags"] as? [String] ?? []
            let confidence = json["confidence"] as? Double ?? 0.5
            let reasoning = json["reasoning"] as? String

            let attempt = CategorizationAttempt(
                transaction: transaction,
                proposedType: type,
                proposedCategory: category,
                proposedTags: tags,
                confidence: confidence,
                reasoning: reasoning
            )

            attempts.append(attempt)
        }

        return attempts
    }

    // MARK: - Learning

    func learnFromCorrection(
        _ attempt: CategorizationAttempt,
        account: Account
    ) async throws {
        guard attempt.status == .corrected else { return }

        // Determine if this should update account or global prompt
        let isAccountSpecific = shouldUpdateAccountPrompt(attempt)

        let targetPrompt = isAccountSpecific
            ? getAccountPrompt(account)
            : getGlobalPrompt()

        guard let prompt = isAccountSpecific ? targetPrompt : targetPrompt as CategorizationPrompt? else {
            return
        }

        // Generate pattern from correction
        let pattern = await generatePatternFromCorrection(attempt)

        // Update prompt
        prompt.learn(from: attempt, newPattern: pattern)
        try modelContext.save()
    }

    private func shouldUpdateAccountPrompt(_ attempt: CategorizationAttempt) -> Bool {
        // If correction involves specific payees or patterns, it's account-specific
        // For now, simple heuristic: if description has specific names, it's account-specific
        guard let transaction = attempt.transaction else { return false }

        let description = transaction.transactionDescription.lowercased()

        // Check for specific payee names, account numbers, etc.
        let hasSpecificPayee = description.contains(where: { $0.isUppercase })
        return hasSpecificPayee
    }

    private func generatePatternFromCorrection(_ attempt: CategorizationAttempt) async -> String {
        guard let transaction = attempt.transaction else { return "" }

        let description = transaction.transactionDescription

        var pattern = "- "

        // Add matching condition
        if description.count < 30 {
            pattern += "Description contains \"\(description)\""
        } else {
            // Extract key words
            let words = description.components(separatedBy: .whitespaces)
                .filter { $0.count > 3 }
                .prefix(3)
            pattern += "Description contains \(words.joined(separator: " + "))"
        }

        // Add result
        if let actualCategory = attempt.actualCategory {
            pattern += " → \(actualCategory)"
        }

        if !attempt.actualTags.isEmpty {
            pattern += ", tags: [\(attempt.actualTags.joined(separator: ", "))]"
        }

        pattern += "\n  (Learned from correction on \(Date().formatted(date: .abbreviated, time: .omitted)))"

        return pattern
    }
}
