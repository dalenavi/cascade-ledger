//
//  TransactionBuilder.swift
//  cascade-ledger
//
//  Builds double-entry transactions from CSV row groups
//

import Foundation
import SwiftData

/// Builds proper double-entry transactions from grouped CSV rows
class TransactionBuilder {

    // MARK: - Row Grouping

    /// Group related CSV rows into transaction groups
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
        importBatch: ImportBatch?
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

        transaction.importBatch = importBatch
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
            }
        )

        // Validate the transaction
        try transaction.validate()

        return transaction
    }

    // MARK: - Journal Entry Building

    private static func buildJournalEntries(
        for transaction: Transaction,
        primaryRow: [String: Any],
        settlementRows: [[String: Any]]
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
                amount: absAmount
            )
        } else if actionUpper.contains("YOU SOLD") || actionUpper.contains("SOLD") {
            try buildSellTransaction(
                transaction: transaction,
                symbol: symbol,
                quantity: abs(quantity ?? 0),  // Quantity might be negative
                amount: absAmount
            )
        } else if actionUpper.contains("DIVIDEND") {
            try buildDividendTransaction(
                transaction: transaction,
                symbol: symbol,
                quantity: quantity,
                amount: absAmount,
                isReinvested: quantity != nil && quantity != 0
            )
        } else if actionUpper.contains("TRANSFERRED TO") || actionUpper.contains("TRANSFERRED FROM") {
            try buildTransferTransaction(
                transaction: transaction,
                amount: amount,  // Keep sign for transfers
                isOutgoing: actionUpper.contains("TO")
            )
        } else if actionUpper.contains("INTEREST") {
            try buildInterestTransaction(
                transaction: transaction,
                amount: absAmount
            )
        } else if actionUpper.contains("FEE") || actionUpper.contains("COMMISSION") {
            try buildFeeTransaction(
                transaction: transaction,
                amount: absAmount
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
                    amount: amount
                )
            } else {
                // Pure cash transaction
                try buildGenericCashTransaction(
                    transaction: transaction,
                    amount: amount
                )
            }
        }
    }

    // MARK: - Specific Transaction Patterns

    private static func buildBuyTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal?,
        amount: Decimal
    ) throws {
        guard let qty = quantity, qty > 0 else {
            throw TransactionBuilderError.invalidQuantity
        }

        // Debit: Asset increases
        transaction.addDebit(
            accountType: .asset,
            accountName: symbol,
            amount: amount,
            quantity: qty,
            quantityUnit: inferQuantityUnit(symbol: symbol)
        )

        // Credit: Cash decreases
        transaction.addCredit(
            accountType: .cash,
            accountName: "USD",
            amount: amount
        )
    }

    private static func buildSellTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal,
        amount: Decimal
    ) throws {
        guard quantity > 0 else {
            throw TransactionBuilderError.invalidQuantity
        }

        // Credit: Asset decreases
        transaction.addCredit(
            accountType: .asset,
            accountName: symbol,
            amount: amount,
            quantity: quantity,
            quantityUnit: inferQuantityUnit(symbol: symbol)
        )

        // Debit: Cash increases
        transaction.addDebit(
            accountType: .cash,
            accountName: "USD",
            amount: amount
        )
    }

    private static func buildDividendTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal?,
        amount: Decimal,
        isReinvested: Bool
    ) throws {
        if isReinvested && quantity != nil {
            // Reinvested dividend - 4 entries

            // 1. Debit: Asset increases
            transaction.addDebit(
                accountType: .asset,
                accountName: symbol,
                amount: amount,
                quantity: quantity,
                quantityUnit: inferQuantityUnit(symbol: symbol)
            )

            // 2. Credit: Dividend income
            transaction.addCredit(
                accountType: .income,
                accountName: "Dividend Income",
                amount: amount
            )

            // Note: The cash entries net to zero for reinvested dividends
            // Some brokers show them, some don't. We'll omit for simplicity.

        } else {
            // Cash dividend - 2 entries

            // 1. Debit: Cash increases
            transaction.addDebit(
                accountType: .cash,
                accountName: "USD",
                amount: amount
            )

            // 2. Credit: Dividend income
            transaction.addCredit(
                accountType: .income,
                accountName: "Dividend Income",
                amount: amount
            )
        }
    }

    private static func buildTransferTransaction(
        transaction: Transaction,
        amount: Decimal,
        isOutgoing: Bool
    ) throws {
        let absAmount = abs(amount)

        if isOutgoing {
            // Money leaving account
            transaction.addCredit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )

            transaction.addDebit(
                accountType: .equity,
                accountName: "Owner Withdrawals",
                amount: absAmount
            )
        } else {
            // Money entering account
            transaction.addDebit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )

            transaction.addCredit(
                accountType: .equity,
                accountName: "Owner Contributions",
                amount: absAmount
            )
        }
    }

    private static func buildInterestTransaction(
        transaction: Transaction,
        amount: Decimal
    ) throws {
        // Debit: Cash increases
        transaction.addDebit(
            accountType: .cash,
            accountName: "USD",
            amount: amount
        )

        // Credit: Interest income
        transaction.addCredit(
            accountType: .income,
            accountName: "Interest Income",
            amount: amount
        )
    }

    private static func buildFeeTransaction(
        transaction: Transaction,
        amount: Decimal
    ) throws {
        // Debit: Expense increases
        transaction.addDebit(
            accountType: .expense,
            accountName: "Fees & Commissions",
            amount: amount
        )

        // Credit: Cash decreases
        transaction.addCredit(
            accountType: .cash,
            accountName: "USD",
            amount: amount
        )
    }

    private static func buildGenericAssetTransaction(
        transaction: Transaction,
        symbol: String,
        quantity: Decimal,
        amount: Decimal
    ) throws {
        let absAmount = abs(amount)
        let absQuantity = abs(quantity)

        if amount < 0 {
            // Buying asset
            transaction.addDebit(
                accountType: .asset,
                accountName: symbol,
                amount: absAmount,
                quantity: absQuantity,
                quantityUnit: inferQuantityUnit(symbol: symbol)
            )

            transaction.addCredit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )
        } else {
            // Selling asset
            transaction.addCredit(
                accountType: .asset,
                accountName: symbol,
                amount: absAmount,
                quantity: absQuantity,
                quantityUnit: inferQuantityUnit(symbol: symbol)
            )

            transaction.addDebit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )
        }
    }

    private static func buildGenericCashTransaction(
        transaction: Transaction,
        amount: Decimal
    ) throws {
        let absAmount = abs(amount)

        if amount > 0 {
            // Cash inflow
            transaction.addDebit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )

            transaction.addCredit(
                accountType: .income,
                accountName: "Other Income",
                amount: absAmount
            )
        } else {
            // Cash outflow
            transaction.addDebit(
                accountType: .expense,
                accountName: "Other Expenses",
                amount: absAmount
            )

            transaction.addCredit(
                accountType: .cash,
                accountName: "USD",
                amount: absAmount
            )
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
            return .credit
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