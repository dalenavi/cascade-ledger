//
//  CategorizationBatch.swift
//  cascade-ledger
//
//  Individual batch of AI-generated transactions (fragment of a session)
//

import Foundation
import SwiftData

@Model
final class CategorizationBatch {
    var id: UUID
    var batchNumber: Int
    var createdAt: Date

    // What this batch covers
    var startRow: Int  // 1-based
    var endRow: Int    // 1-based (inclusive)
    var windowSize: Int  // How many rows AI saw

    // Results
    @Relationship(deleteRule: .cascade)
    var transactions: [Transaction]

    var transactionCount: Int

    // Metadata
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double
    var aiResponseData: Data?
    var aiRequestData: Data?  // Store the actual prompt sent

    // Parent session
    @Relationship
    var session: CategorizationSession?

    init(
        batchNumber: Int,
        startRow: Int,
        endRow: Int,
        windowSize: Int,
        session: CategorizationSession
    ) {
        self.id = UUID()
        self.batchNumber = batchNumber
        self.createdAt = Date()
        self.startRow = startRow
        self.endRow = endRow
        self.windowSize = windowSize
        self.session = session
        self.transactions = []
        self.transactionCount = 0
        self.inputTokens = 0
        self.outputTokens = 0
        self.durationSeconds = 0
    }

    func addTransactions(_ txns: [Transaction], tokens: (input: Int, output: Int), duration: Double, response: Data?, request: Data?) {
        self.transactions = txns
        self.transactionCount = txns.count
        self.inputTokens = tokens.input
        self.outputTokens = tokens.output
        self.durationSeconds = duration
        self.aiResponseData = response
        self.aiRequestData = request
    }
}
