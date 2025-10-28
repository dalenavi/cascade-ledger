//
//  TransactionBuilder.swift
//  cascade-ledger
//
//  Builds double-entry transactions from CSV row groups
//

import Foundation
import SwiftData

/// Builds proper double-entry transactions from grouped CSV rows
@MainActor
class TransactionBuilder {

    // MARK: - Row Grouping (DEPRECATED - Use SettlementDetector instead)

    /// Group related CSV rows into transaction groups
    /// @deprecated Use SettlementDetectorFactory.create(for:).groupRows() instead
    /// Fidelity pattern: Asset row followed by settlement row(s)
    static func groupRows(_ rows: [[String: Any]]) -> [[[String: Any]]] {
        var groups: [[[String: Any]]] = []
        var currentGroup: [[String: Any]] = []

        for (index, row) in rows.enumerated() {
            // Try to get transaction type from various possible field names (after transformation)
            let transactionType = row["transactionType"] as? String
                ?? row["type"] as? String
                ?? row["metadata.action"] as? String
                ?? ""

            // Try to get asset from various possible field names
            let assetId = row["assetId"] as? String
                ?? row["symbol"] as? String
                ?? row["metadata.symbol"] as? String
                ?? ""

            // Get quantity (this field name usually stays the same)
            let quantity = row["quantity"] as? Decimal ?? 0

            // Also check the description to see if it's a settlement row
            let description = row["description"] as? String
                ?? row["transactionDescription"] as? String
                ?? ""

            // Settlement row pattern:
            // 1. No transaction type/action
            // 2. No asset/symbol
            // 3. Quantity is 0
            // 4. Description is often "No Description" or empty
            let isSettlement = transactionType.isEmpty &&
                              assetId.isEmpty &&
                              quantity == 0

            // Debug output for first few rows
            if index < 5 || index == rows.count - 1 {
                print("Row \(index): type='\(transactionType)' asset='\(assetId)' qty=\(quantity) desc='\(description.prefix(30))' -> settlement=\(isSettlement)")
            }

            if !isSettlement {
                // Primary transaction row - start new group
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                }
                currentGroup = [row]
            } else {
                // Settlement row - add to current group
                if currentGroup.isEmpty {
                    // Orphaned settlement row (shouldn't happen)
                    print("⚠️ Orphaned settlement row at index \(index)")
                    // Start a new group with this orphaned row
                    groups.append([row])
                } else {
                    currentGroup.append(row)
                }
            }
        }

        // Don't forget the last group
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        print("Grouped \(rows.count) rows into \(groups.count) transactions")
        return groups
    }

    // MARK: - Transaction Creation

    /// Create a double-entry transaction from grouped rows
    static func createTransaction(
        from rowGroup: [[String: Any]],
        account: Account,
        importSession: ImportSession?,
        assetRegistry: AssetRegistry = AssetRegistry.shared
    ) throws -> Transaction {
        guard let primaryRow = rowGroup.first(where: { row in
            // Check for transaction type in various fields
            let type = row["transactionType"] as? String
                ?? row["type"] as? String
                ?? row["metadata.action"] as? String
                ?? ""
            return !type.isEmpty
        }) else {
            throw TransactionBuilderError.noPrimaryRow
        }

        // Extract core fields
        guard let date = primaryRow["date"] as? Date else {
            throw TransactionBuilderError.missingDate
        }

        // Get transaction type/action from various possible fields
        let action = primaryRow["metadata.action"] as? String
            ?? primaryRow["transactionType"] as? String
            ?? primaryRow["type"] as? String
            ?? ""

        // Get asset symbol from various possible fields
        let symbol = primaryRow["assetId"] as? String
            ?? primaryRow["metadata.symbol"] as? String
            ?? primaryRow["symbol"] as? String
            ?? ""

        let description = primaryRow["description"] as? String
            ?? primaryRow["transactionDescription"] as? String
            ?? primaryRow["metadata.description"] as? String
            ?? action

        // Determine transaction type
        let transactionType = determineTransactionType(action: action)

        // Create transaction
        let transaction = Transaction(
            date: date,
            description: description,
            type: transactionType,
            account: account
        )

        transaction.importSession = importSession
        transaction.sourceRowNumbers = rowGroup.compactMap { $0["rowNumber"] as? Int }

        // Build journal entries based on transaction pattern
        try buildJournalEntries(
            for: transaction,
            primaryRow: primaryRow,
            settlementRows: rowGroup.filter { row in
                let type = row["transactionType"] as? String
                    ?? row["type"] as? String
                    ?? row["metadata.action"] as? String
                    ?? ""
                return type.isEmpty
            },
            assetRegistry: assetRegistry
        )

        // Validate the transaction
        try transaction.validate()

        return transaction
    }

    // MARK: - Journal Entry Building

    private static func buildJournalEntries(
        for transaction: Transaction,
        primaryRow: [String: Any],
        settlementRows: [[String: Any]],
        assetRegistry: AssetRegistry
    ) throws {
        // Get action from metadata or transformed fields
        let action = primaryRow["metadata.action"] as? String
            ?? primaryRow["transactionType"] as? String
            ?? primaryRow["type"] as? String
            ?? ""

        // Get symbol from various possible fields
        let symbol = primaryRow["assetId"] as? String
            ?? primaryRow["metadata.symbol"] as? String
            ?? primaryRow["symbol"] as? String
            ?? ""

        // Get quantity and amount
        let quantity = primaryRow["quantity"] as? Decimal
        let amount = primaryRow["amount"] as? Decimal ?? 0

        // Convert amount to positive for journal entries
        let absAmount = abs(amount)

        let actionUpper = action.uppercased()

        // Log the action for debugging
        print("Processing action: '\(action)' -> '\(actionUpper)'")

        if actionUpper.contains("YOU BOUGHT") || actionUpper.contains("BOUGHT") {
            try buildBuyTransaction(
                transaction: transaction,
                symbol: symbol,
                quantity: quantity,
                amount: absAmount,
                assetRegistry: assetRegistry
            )
        } else if actionUpper.contains("YOU SOLD") || actionUpper.contains("SOLD") {
            try buildSellTransaction(
                transaction: transaction,
                symbol: symbol,
                quantity: abs(quantity ?? 0),  // Quantity might be negative
                amount: absAmount,
                assetRegistry: assetRegistry
            )
        } else if actionUpper.contains("DIVIDEND") {
            try buildDividendTransaction(
                transaction: transaction,
                symbol: symbol,
                quantity: quantity,
                amount: absAmount,
                isReinvested: quantity != nil && quantity != 0,
                assetRegistry: assetRegistry
            )
        } else if actionUpper.contains("TRANSFERRED TO") || actionUpper.contains("TRANSFERRED FROM") {
            try buildTransferTransaction(
                transaction: transaction,
                amount: amount,  // Keep sign for transfers
                isOutgoing: actionUpper.contains("TO"),
                assetRegistry: assetRegistry
            )
        } else if actionUpper.contains("INTEREST") {
            try buildInterestTransaction(
                transaction: transaction,
                amount: absAmount,
                assetRegistry: assetRegistry
            )
        } else if actionUpper.contains("FEE") || actionUpper.contains("COMMISSION") {
            try buildFeeTransaction(
                transaction: transaction,
                amount: absAmount,
                assetRegistry: assetRegistry
            )
        } else {
            // Generic transaction
            print("Unknown action type: '\(action)' - creating generic transaction")
            if quantity != nil && quantity != 0 && !symbol.isEmpty {
                // Has asset component
                try buildGenericAssetTransaction(
                    transaction: transaction,
                    symbol: symbol,
                    quantity: quantity!,
                    amount: amount,
                    assetRegistry: assetRegistry
                )
            } else {
                // Pure cash transaction
                try buildGenericCashTransaction(
                    transaction: transaction,
                    amount: amount,
                    assetRegistry: assetRegistry
                )
            }
        }
    }

    // MARK: - Specific Transaction Patterns

    private static func buildBuyTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal?,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        guard let qty = quantity, qty > 0 else {
            throw TransactionBuilderError.invalidQuantity
        }

        // Resolve asset through registry
        let asset = assetRegistry.findOrCreate(symbol: symbol)

        // Debit: Asset increases
        let debitEntry = JournalEntry(
            accountType: .asset,
            accountName: symbol,
            debitAmount: amount,
            creditAmount: nil,
            quantity: qty,
            quantityUnit: inferQuantityUnit(symbol: symbol),
            transaction: transaction
        )
        debitEntry.asset = asset
        transaction.journalEntries.append(debitEntry)

        // Credit: Cash decreases
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")
        let creditEntry = JournalEntry(
            accountType: .cash,
            accountName: "USD",
            debitAmount: nil,
            creditAmount: amount,
            transaction: transaction
        )
        creditEntry.asset = usdAsset
        transaction.journalEntries.append(creditEntry)
    }

    private static func buildSellTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        guard quantity > 0 else {
            throw TransactionBuilderError.invalidQuantity
        }

        // Resolve asset through registry
        let asset = assetRegistry.findOrCreate(symbol: symbol)

        // Credit: Asset decreases
        let creditEntry = JournalEntry(
            accountType: .asset,
            accountName: symbol,
            debitAmount: nil,
            creditAmount: amount,
            quantity: quantity,
            quantityUnit: inferQuantityUnit(symbol: symbol),
            transaction: transaction
        )
        creditEntry.asset = asset
        transaction.journalEntries.append(creditEntry)

        // Debit: Cash increases
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")
        let debitEntry = JournalEntry(
            accountType: .cash,
            accountName: "USD",
            debitAmount: amount,
            creditAmount: nil,
            transaction: transaction
        )
        debitEntry.asset = usdAsset
        transaction.journalEntries.append(debitEntry)
    }

    private static func buildDividendTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal?,
        amount: Decimal,
        isReinvested: Bool,
        assetRegistry: AssetRegistry
    ) throws {
        if isReinvested && quantity != nil {
            // Reinvested dividend
            let asset = assetRegistry.findOrCreate(symbol: symbol)

            // 1. Debit: Asset increases
            let debitEntry = JournalEntry(
                accountType: .asset,
                accountName: symbol,
                debitAmount: amount,
                creditAmount: nil,
                quantity: quantity,
                quantityUnit: inferQuantityUnit(symbol: symbol),
                transaction: transaction
            )
            debitEntry.asset = asset
            transaction.journalEntries.append(debitEntry)

            // 2. Credit: Dividend income
            let creditEntry = JournalEntry(
                accountType: .income,
                accountName: "Dividend Income",
                debitAmount: nil,
                creditAmount: amount,
                transaction: transaction
            )
            transaction.journalEntries.append(creditEntry)

        } else {
            // Cash dividend
            let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

            // 1. Debit: Cash increases
            let debitEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: amount,
                creditAmount: nil,
                transaction: transaction
            )
            debitEntry.asset = usdAsset
            transaction.journalEntries.append(debitEntry)

            // 2. Credit: Dividend income
            let creditEntry = JournalEntry(
                accountType: .income,
                accountName: "Dividend Income",
                debitAmount: nil,
                creditAmount: amount,
                transaction: transaction
            )
            transaction.journalEntries.append(creditEntry)
        }
    }

    private static func buildTransferTransaction(
        transaction: Transaction,
        amount: Decimal,
        isOutgoing: Bool,
        assetRegistry: AssetRegistry
    ) throws {
        let absAmount = abs(amount)
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

        if isOutgoing {
            // Money leaving account
            let creditEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: nil,
                creditAmount: absAmount,
                transaction: transaction
            )
            creditEntry.asset = usdAsset
            transaction.journalEntries.append(creditEntry)

            let debitEntry = JournalEntry(
                accountType: .equity,
                accountName: "Owner Withdrawals",
                debitAmount: absAmount,
                creditAmount: nil,
                transaction: transaction
            )
            transaction.journalEntries.append(debitEntry)
        } else {
            // Money entering account
            let debitEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: absAmount,
                creditAmount: nil,
                transaction: transaction
            )
            debitEntry.asset = usdAsset
            transaction.journalEntries.append(debitEntry)

            let creditEntry = JournalEntry(
                accountType: .equity,
                accountName: "Owner Contributions",
                debitAmount: nil,
                creditAmount: absAmount,
                transaction: transaction
            )
            transaction.journalEntries.append(creditEntry)
        }
    }

    private static func buildInterestTransaction(
        transaction: Transaction,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

        // Debit: Cash increases
        let debitEntry = JournalEntry(
            accountType: .cash,
            accountName: "USD",
            debitAmount: amount,
            creditAmount: nil,
            transaction: transaction
        )
        debitEntry.asset = usdAsset
        transaction.journalEntries.append(debitEntry)

        // Credit: Interest income
        let creditEntry = JournalEntry(
            accountType: .income,
            accountName: "Interest Income",
            debitAmount: nil,
            creditAmount: amount,
            transaction: transaction
        )
        transaction.journalEntries.append(creditEntry)
    }

    private static func buildFeeTransaction(
        transaction: Transaction,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

        // Debit: Expense increases
        let debitEntry = JournalEntry(
            accountType: .expense,
            accountName: "Fees & Commissions",
            debitAmount: amount,
            creditAmount: nil,
            transaction: transaction
        )
        transaction.journalEntries.append(debitEntry)

        // Credit: Cash decreases
        let creditEntry = JournalEntry(
            accountType: .cash,
            accountName: "USD",
            debitAmount: nil,
            creditAmount: amount,
            transaction: transaction
        )
        creditEntry.asset = usdAsset
        transaction.journalEntries.append(creditEntry)
    }

    private static func buildGenericAssetTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        let absAmount = abs(amount)
        let absQuantity = abs(quantity)
        let asset = assetRegistry.findOrCreate(symbol: symbol)
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

        if amount < 0 {
            // Buying asset
            let debitEntry = JournalEntry(
                accountType: .asset,
                accountName: symbol,
                debitAmount: absAmount,
                creditAmount: nil,
                quantity: absQuantity,
                quantityUnit: inferQuantityUnit(symbol: symbol),
                transaction: transaction
            )
            debitEntry.asset = asset
            transaction.journalEntries.append(debitEntry)

            let creditEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: nil,
                creditAmount: absAmount,
                transaction: transaction
            )
            creditEntry.asset = usdAsset
            transaction.journalEntries.append(creditEntry)
        } else {
            // Selling asset
            let creditEntry = JournalEntry(
                accountType: .asset,
                accountName: symbol,
                debitAmount: nil,
                creditAmount: absAmount,
                quantity: absQuantity,
                quantityUnit: inferQuantityUnit(symbol: symbol),
                transaction: transaction
            )
            creditEntry.asset = asset
            transaction.journalEntries.append(creditEntry)

            let debitEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: absAmount,
                creditAmount: nil,
                transaction: transaction
            )
            debitEntry.asset = usdAsset
            transaction.journalEntries.append(debitEntry)
        }
    }

    private static func buildGenericCashTransaction(
        transaction: Transaction,
        amount: Decimal,
        assetRegistry: AssetRegistry
    ) throws {
        let absAmount = abs(amount)
        let usdAsset = assetRegistry.findOrCreate(symbol: "USD")

        if amount > 0 {
            // Cash inflow
            let debitEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: absAmount,
                creditAmount: nil,
                transaction: transaction
            )
            debitEntry.asset = usdAsset
            transaction.journalEntries.append(debitEntry)

            let creditEntry = JournalEntry(
                accountType: .income,
                accountName: "Other Income",
                debitAmount: nil,
                creditAmount: absAmount,
                transaction: transaction
            )
            transaction.journalEntries.append(creditEntry)
        } else {
            // Cash outflow
            let debitEntry = JournalEntry(
                accountType: .expense,
                accountName: "Other Expenses",
                debitAmount: absAmount,
                creditAmount: nil,
                transaction: transaction
            )
            transaction.journalEntries.append(debitEntry)

            let creditEntry = JournalEntry(
                accountType: .cash,
                accountName: "USD",
                debitAmount: nil,
                creditAmount: absAmount,
                transaction: transaction
            )
            creditEntry.asset = usdAsset
            transaction.journalEntries.append(creditEntry)
        }
    }

    // MARK: - Helper Methods

    private static func determineTransactionType(action: String) -> TransactionType {
        switch action.uppercased() {
        case "YOU BOUGHT", "BOUGHT":
            return .buy
        case "YOU SOLD", "SOLD":
            return .sell
        case "DIVIDEND":
            return .dividend
        case "INTEREST":
            return .interest
        case "FEE", "COMMISSION":
            return .fee
        case "TRANSFERRED TO", "TRANSFERRED FROM":
            return .transfer
        case "DEPOSIT":
            return .deposit
        case "WITHDRAWAL":
            return .withdrawal
        default:
            return .other
        }
    }

    private static func inferQuantityUnit(symbol: String) -> String {
        // Direct crypto symbols
        if ["BTC", "ETH", "SOL", "ADA"].contains(symbol.uppercased()) {
            return symbol.uppercased()
        }

        // Everything else is shares (including crypto ETFs like FBTC, GBTC)
        return "shares"
    }
}

enum TransactionBuilderError: LocalizedError {
    case noPrimaryRow
    case missingDate
    case invalidQuantity
    case invalidAmount

    var errorDescription: String? {
        switch self {
        case .noPrimaryRow:
            return "No primary transaction row found in group"
        case .missingDate:
            return "Transaction date is missing"
        case .invalidQuantity:
            return "Invalid quantity for asset transaction"
        case .invalidAmount:
            return "Invalid amount for transaction"
        }
    }
}