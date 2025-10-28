//
//  PositionCalculator.swift
//  cascade-ledger
//
//  Actor-based service for calculating and updating positions
//

import Foundation
import SwiftData

actor PositionCalculator {
    private var modelContext: ModelContext?

    init() {}

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Recalculate all positions for an account
    func recalculateAllPositions(for account: Account) async throws {
        guard let modelContext = modelContext else {
            throw PositionCalculatorError.notConfigured
        }

        // Fetch all transactions for this account
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\Transaction.date)]
        )

        let allTransactions = try modelContext.fetch(descriptor)
        let transactions = allTransactions.filter { $0.account?.id == account.id }

        // Group transactions by asset
        var transactionsByAsset: [UUID: [Transaction]] = [:]

        for transaction in transactions {
            for entry in transaction.journalEntries {
                if let assetId = entry.asset?.id {
                    if transactionsByAsset[assetId] == nil {
                        transactionsByAsset[assetId] = []
                    }
                    if !transactionsByAsset[assetId]!.contains(where: { $0.id == transaction.id }) {
                        transactionsByAsset[assetId]!.append(transaction)
                    }
                }
            }
        }

        // Recalculate each position
        for (assetId, assetTransactions) in transactionsByAsset {
            try await recalculatePosition(
                accountId: account.id,
                assetId: assetId,
                transactions: assetTransactions
            )
        }

        // Clean up zero positions
        try await cleanupZeroPositions(for: account)
    }

    /// Recalculate a single position
    private func recalculatePosition(
        accountId: UUID,
        assetId: UUID,
        transactions: [Transaction]
    ) async throws {
        guard let modelContext = modelContext else {
            throw PositionCalculatorError.notConfigured
        }

        // Find or create position
        let positionDescriptor = FetchDescriptor<Position>()

        let allPositions = try modelContext.fetch(positionDescriptor)
        let existing = allPositions.first { position in
            position.account?.id == accountId && position.asset?.id == assetId
        }

        let position: Position
        if let existing = existing {
            position = existing
        } else {
            // Create new position
            let accountDescriptor = FetchDescriptor<Account>(
                predicate: #Predicate<Account> { account in
                    account.id == accountId
                }
            )
            let account = try modelContext.fetch(accountDescriptor).first

            let assetDescriptor = FetchDescriptor<Asset>(
                predicate: #Predicate<Asset> { asset in
                    asset.id == assetId
                }
            )
            let asset = try modelContext.fetch(assetDescriptor).first

            guard let account = account, let asset = asset else {
                throw PositionCalculatorError.missingEntity
            }

            position = Position(account: account, asset: asset)
            modelContext.insert(position)
        }

        // Recalculate
        position.recalculate(from: transactions)
    }

    /// Remove positions with zero quantity
    private func cleanupZeroPositions(for account: Account) async throws {
        guard let modelContext = modelContext else {
            throw PositionCalculatorError.notConfigured
        }

        let descriptor = FetchDescriptor<Position>()

        let allPositions = try modelContext.fetch(descriptor)
        let zeroPositions = allPositions.filter { position in
            position.account?.id == account.id && position.quantity == 0
        }

        for position in zeroPositions {
            modelContext.delete(position)
        }
    }

    /// Recalculate positions affected by an import session
    func recalculatePositions(for importSession: ImportSession) async throws {
        guard let account = importSession.account else {
            throw PositionCalculatorError.missingEntity
        }

        try await recalculateAllPositions(for: account)
    }

    /// Recalculate positions affected by a rollback
    func handleRollback(for importSession: ImportSession) async throws {
        guard let account = importSession.account else {
            throw PositionCalculatorError.missingEntity
        }

        try await recalculateAllPositions(for: account)
    }
}

enum PositionCalculatorError: LocalizedError {
    case notConfigured
    case missingEntity

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "PositionCalculator not configured with ModelContext"
        case .missingEntity:
            return "Required entity (Account or Asset) not found"
        }
    }
}
