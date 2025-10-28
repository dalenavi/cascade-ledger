//
//  CategorizationJobManager.swift
//  cascade-ledger
//
//  Singleton service for background AI categorization jobs
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class CategorizationJobManager: ObservableObject {
    static let shared = CategorizationJobManager()

    @Published var currentJob: CategorizationJob?
    @Published var status: JobStatus = .idle
    @Published var progress: Double = 0.0
    @Published var currentStep: String = ""

    private var modelContext: ModelContext?
    private var isPaused = false
    private var nextAvailableTime: Date?  // When quota is available again

    enum JobStatus {
        case idle
        case running
        case waitingForQuota(availableAt: Date)
        case paused
        case completed
        case failed(Error)
    }

    struct CategorizationJob {
        let session: CategorizationSession
        let csvRows: [[String: String]]
        let headers: [String]
        let account: Account
    }

    private init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Job Control

    func startCategorization(
        session: CategorizationSession,
        csvRows: [[String: String]],
        headers: [String],
        account: Account
    ) {
        let job = CategorizationJob(
            session: session,
            csvRows: csvRows,
            headers: headers,
            account: account
        )

        currentJob = job
        status = .running

        Task {
            await runCategorizationJob(job)
        }
    }

    func pause() {
        isPaused = true
        status = .paused
    }

    func resume() {
        guard let job = currentJob else { return }
        isPaused = false
        status = .running

        Task {
            await runCategorizationJob(job)
        }
    }

    // MARK: - Job Execution

    private func runCategorizationJob(_ job: CategorizationJob) async {
        guard let modelContext = modelContext else { return }

        // Get uncovered rows only
        let coveredRows = Set(job.session.transactions.flatMap { $0.sourceRowNumbers })
        let uncoveredRows = job.csvRows.filter { row in
            guard let rowNumStr = row["_globalRowNumber"],
                  let rowNum = Int(rowNumStr) else { return true }
            return !coveredRows.contains(rowNum)
        }

        print("📊 Coverage check: \(job.csvRows.count) total rows, \(coveredRows.count) covered, \(uncoveredRows.count) uncovered")

        // Sort uncovered rows chronologically
        let sortedUncovered = uncoveredRows.sorted { r1, r2 in
            let date1 = r1["Run Date"] ?? ""
            let date2 = r2["Run Date"] ?? ""
            return date1 < date2
        }

        // Process uncovered rows
        let windowSize = 30
        let transactionsPerBatch = 10
        var currentIndex = 0

        while currentIndex < sortedUncovered.count && !isPaused {
            // Check quota availability
            if let available = nextAvailableTime, available > Date() {
                let waitTime = available.timeIntervalSinceNow
                status = .waitingForQuota(availableAt: available)
                print("⏱️ Waiting \(Int(waitTime))s for quota...")

                try? await Task.sleep(for: .seconds(waitTime))
            }

            // Extract window
            let windowEnd = min(currentIndex + windowSize, sortedUncovered.count)
            let window = Array(sortedUncovered[currentIndex..<windowEnd])

            // Process batch
            do {
                try await processBatch(
                    window: window,
                    job: job,
                    batchNumber: (job.session.batches.count + 1)
                )

                // Move window forward based on rows consumed
                let coveredAfterBatch = Set(job.session.transactions.flatMap { $0.sourceRowNumbers })
                let newlyCovered = coveredAfterBatch.subtracting(coveredRows)
                currentIndex += newlyCovered.count

            } catch let error as ClaudeAPIError {
                if case .httpError(let code, _, _) = error, code == 429 {
                    // Rate limit - schedule retry
                    nextAvailableTime = Date().addingTimeInterval(120)  // 2 minutes
                    print("⏱️ Rate limit - next available at \(nextAvailableTime!)")
                    // Loop will wait and retry
                } else {
                    status = .failed(error)
                    print("❌ Job failed: \(error)")
                    return
                }
            } catch {
                status = .failed(error)
                print("❌ Job failed: \(error)")
                return
            }
        }

        status = isPaused ? .paused : .completed
        print("✅ Categorization job complete")
    }

    private func processBatch(
        window: [[String: String]],
        job: CategorizationJob,
        batchNumber: Int
    ) async throws {
        guard let modelContext = modelContext else { return }

        // Configure AssetRegistry
        AssetRegistry.shared.configure(modelContext: modelContext)

        // Build CSV format prompt
        let prompt = buildPrompt(window: window, job: job)

        currentStep = "Processing batch \(batchNumber)..."
        print("🔄 Batch \(batchNumber): \(window.count) rows")

        // Call API
        let startTime = Date()
        let claudeAPI = ClaudeAPIService.shared
        let response = try await claudeAPI.sendMessage(
            messages: [ClaudeMessage(role: "user", content: prompt)],
            system: buildSystemPrompt(),
            maxTokens: 4096,
            temperature: 0.0
        )
        let duration = Date().timeIntervalSince(startTime)

        let textContent = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()

        // Parse transactions (using DirectCategorizationService parser)
        let service = DirectCategorizationService(modelContext: modelContext)
        let transactions = try service.parseTransactionsFromResponse(
            textContent,
            session: job.session,
            account: job.account,
            allowIncomplete: true
        )

        // Create batch record
        let sourceRows = transactions.flatMap { $0.sourceRowNumbers }.sorted()
        let batch = CategorizationBatch(
            batchNumber: batchNumber,
            startRow: sourceRows.first ?? 0,
            endRow: sourceRows.last ?? 0,
            windowSize: window.count,
            session: job.session
        )

        batch.addTransactions(
            transactions,
            tokens: (response.usage.inputTokens, response.usage.outputTokens),
            duration: duration,
            response: textContent.data(using: .utf8),
            request: prompt.data(using: .utf8)
        )

        modelContext.insert(batch)
        job.session.transactions.append(contentsOf: transactions)
        job.session.updateStatistics()

        try modelContext.save()

        print("  ✅ Batch \(batchNumber): \(transactions.count) txns, \(response.usage.inputTokens) input tokens")
    }

    private func buildSystemPrompt() -> String {
        return """
        You are a financial transaction categorization specialist.

        CRITICAL: Return JSON with "transactions" array.
        Each transaction must have balanced journal entries (debits = credits).
        Use exact symbols from CSV.
        Group settlement rows with primary rows.
        """
    }

    private func buildPrompt(window: [[String: String]], job: CategorizationJob) -> String {
        // Build CSV format
        var csvLines: [String] = []
        let allHeaders = job.headers + ["_globalRowNumber"]
        csvLines.append(allHeaders.joined(separator: ","))

        for row in window {
            let values = allHeaders.map { row[$0] ?? "" }
            csvLines.append(values.joined(separator: ","))
        }

        return """
        Categorize these \(window.count) Fidelity CSV rows.
        Generate 10 transactions from the earliest rows.

        CSV Data:
        ```csv
        \(csvLines.joined(separator: "\n"))
        ```

        Return JSON with transactions. Use "_globalRowNumber" for sourceRows arrays.
        """
    }
}
