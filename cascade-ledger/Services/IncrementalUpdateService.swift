//
//  IncrementalUpdateService.swift
//  cascade-ledger
//
//  Handles incremental updates when new CSV data is added
//

import Foundation
import SwiftData
import CryptoKit

class IncrementalUpdateService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Row Hash Computation

    /// Compute hash for a CSV row (for deduplication)
    func computeRowHash(_ row: [String: String], headers: [String]) -> String {
        // Create deterministic string from row data
        let sortedHeaders = headers.sorted()
        let values = sortedHeaders.map { row[$0] ?? "" }
        let rowString = values.joined(separator: "|")

        // Compute SHA256 hash
        let data = Data(rowString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Incremental Update

    /// Add new CSV data to an existing session
    func appendNewData(
        newCSVRows: [[String: String]],
        headers: [String],
        to session: CategorizationSession
    ) async throws -> IncrementalUpdateResult {

        print("📊 Starting incremental update for session v\(session.versionNumber)")
        print("   Current coverage: \(session.transactionCount) transactions, \(session.totalSourceRows) source rows")

        // Compute hashes for new rows
        let newRowsWithHashes = newCSVRows.map { row -> (row: [String: String], hash: String) in
            let hash = computeRowHash(row, headers: headers)
            return (row, hash)
        }

        // Get existing hashes
        let existingHashes = Set(session.sourceRowHashes)

        // Filter to truly new rows (not in existing session)
        let newRows = newRowsWithHashes.filter { !existingHashes.contains($0.hash) }

        print("   New CSV file: \(newCSVRows.count) rows")
        print("   Already processed: \(newCSVRows.count - newRows.count) rows")
        print("   New rows to process: \(newRows.count) rows")

        if newRows.isEmpty {
            print("   ✅ No new rows to process")
            return IncrementalUpdateResult(
                newRowsFound: 0,
                transactionsCreated: 0,
                reviewSession: nil
            )
        }

        // Assign new global row numbers
        let nextRowNumber = session.totalSourceRows + 1
        var enrichedRows: [[String: String]] = []

        for (index, (row, hash)) in newRows.enumerated() {
            var enrichedRow = row
            enrichedRow["_globalRowNumber"] = "\(nextRowNumber + index)"
            // Note: _sourceFile and _fileRowNumber should already be in the row
            enrichedRows.append(enrichedRow)
        }

        print("   Assigned row numbers: #\(nextRowNumber) to #\(nextRowNumber + newRows.count - 1)")

        // Get date range for new rows
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"
        let newRowDates = enrichedRows.compactMap { row -> Date? in
            guard let dateStr = row["Run Date"] else { return nil }
            return dateFormatter.date(from: dateStr)
        }

        guard let startDate = newRowDates.min(),
              let endDate = newRowDates.max() else {
            throw IncrementalUpdateError.invalidDateRange
        }

        print("   New data date range: \(formatDate(startDate)) → \(formatDate(endDate))")

        // Expand context to include recent existing transactions
        let contextStart = Calendar.current.date(byAdding: .day, value: -7, to: startDate) ?? startDate
        let recentExistingRows = await getRecentRows(before: endDate, daysBack: 7, session: session)

        print("   Including \(recentExistingRows.count) recent rows for context")

        // Combine recent context + new rows for AI
        let combinedRows = recentExistingRows + enrichedRows

        // Use review service to categorize new rows
        let reviewService = TransactionReviewService(modelContext: modelContext)

        let reviewSession = try await reviewService.reviewDateRange(
            session: session,
            csvRows: combinedRows,
            startDate: contextStart,
            endDate: endDate,
            mode: .gapFilling
        )

        print("\n📊 Review complete:")
        print("   Deltas generated: \(reviewSession.deltas.count)")

        // Apply deltas
        if !reviewSession.deltas.isEmpty {
            try reviewService.applyDeltas(from: reviewSession, to: session)

            // Update session metadata
            let newHashes = newRows.map { $0.hash }
            session.sourceRowHashes.append(contentsOf: newHashes)
            session.totalSourceRows += newRows.count

            try modelContext.save()

            print("\n✅ Incremental update complete:")
            print("   New rows added: \(newRows.count)")
            print("   Transactions created: \(reviewSession.transactionsCreated)")
            print("   Total coverage: \(session.buildCoverageIndex().count)/\(session.totalSourceRows) rows")
        }

        return IncrementalUpdateResult(
            newRowsFound: newRows.count,
            transactionsCreated: reviewSession.transactionsCreated,
            reviewSession: reviewSession
        )
    }

    // MARK: - Private Helpers

    private func getRecentRows(
        before date: Date,
        daysBack: Int,
        session: CategorizationSession
    ) async -> [[String: String]] {
        // TODO: This would need to fetch the original CSV data
        // For now, return empty - the AI can work without context
        // In a full implementation, we'd store the raw CSV data or reconstruct from import batches
        return []
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Results

struct IncrementalUpdateResult {
    let newRowsFound: Int
    let transactionsCreated: Int
    let reviewSession: ReviewSession?
}

enum IncrementalUpdateError: LocalizedError {
    case invalidDateRange
    case noNewRows
    case sessionNotComplete

    var errorDescription: String? {
        switch self {
        case .invalidDateRange:
            return "Could not determine date range from new rows"
        case .noNewRows:
            return "No new rows found in CSV file"
        case .sessionNotComplete:
            return "Cannot append to incomplete session - finish or resume first"
        }
    }
}
