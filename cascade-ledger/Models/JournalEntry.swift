//
//  JournalEntry.swift
//  cascade-ledger
//
//  Individual journal entry (leg) of a double-entry transaction
//

import Foundation
import SwiftData
import SwiftUI

/// Represents one leg of a double-entry bookkeeping transaction
/// Each transaction has 2+ journal entries where sum(debits) = sum(credits)
@Model
final class JournalEntry {
    var id: UUID

    // Account information
    var accountType: AccountType       // Asset, Cash, Income, etc.
    var accountName: String            // "SPY", "USD", "Dividend Income"

    // Amounts (one should be nil)
    var debitAmount: Decimal?         // Increases assets, expenses; decreases liabilities, equity, income
    var creditAmount: Decimal?        // Opposite of debit

    // Quantity tracking (for asset accounts)
    var quantity: Decimal?            // Number of shares, units, etc.
    var quantityUnit: String?         // "shares", "BTC", etc.

    // Price information (computed or stored)
    var pricePerUnit: Decimal?        // Price at time of transaction

    // Relationships
    @Relationship
    var transaction: Transaction?

    @Relationship
    var asset: Asset?  // Link to Asset master record for asset entries

    // Source tracking
    var sourceRowNumber: Int?         // Which CSV row created this entry
    var sourceData: String?           // Raw CSV data for audit

    // Metadata
    var metadata: [String: String]

    // Computed properties
    var amount: Decimal {
        debitAmount ?? creditAmount ?? 0
    }

    var isDebit: Bool {
        debitAmount != nil
    }

    var isCredit: Bool {
        creditAmount != nil
    }

    /// Net effect on the account (considering accounting rules)
    var netEffect: Decimal {
        switch accountType {
        case .asset, .expense:
            // Debits increase, credits decrease
            return (debitAmount ?? 0) - (creditAmount ?? 0)
        case .liability, .equity, .income:
            // Credits increase, debits decrease
            return (creditAmount ?? 0) - (debitAmount ?? 0)
        case .cash:
            // Cash is an asset: debits increase, credits decrease
            return (debitAmount ?? 0) - (creditAmount ?? 0)
        }
    }

    /// Net quantity change for asset accounts
    var netQuantityChange: Decimal {
        guard accountType == .asset, let qty = quantity else { return 0 }

        if debitAmount != nil {
            return qty  // Debit increases assets
        } else if creditAmount != nil {
            return -qty  // Credit decreases assets
        }
        return 0
    }

    init(
        accountType: AccountType,
        accountName: String,
        debitAmount: Decimal? = nil,
        creditAmount: Decimal? = nil,
        quantity: Decimal? = nil,
        quantityUnit: String? = nil,
        transaction: Transaction? = nil
    ) {
        self.id = UUID()
        self.accountType = accountType
        self.accountName = accountName
        self.debitAmount = debitAmount
        self.creditAmount = creditAmount
        self.quantity = quantity
        self.quantityUnit = quantityUnit
        self.transaction = transaction
        self.metadata = [:]

        // Calculate price if we have both amount and quantity
        let amt = debitAmount ?? creditAmount ?? 0
        if amt != 0, let qty = quantity, qty != 0 {
            self.pricePerUnit = abs(amt / qty)
        }
    }

    /// Validate the journal entry
    func validate() throws {
        // Exactly one of debit or credit should be set
        if (debitAmount != nil && creditAmount != nil) ||
           (debitAmount == nil && creditAmount == nil) {
            throw JournalEntryError.invalidAmounts
        }

        // Asset entries should have quantity
        if accountType == .asset && quantity == nil {
            throw JournalEntryError.missingQuantity
        }

        // Amount should be positive
        if let debit = debitAmount, debit < 0 {
            throw JournalEntryError.negativeAmount
        }
        if let credit = creditAmount, credit < 0 {
            throw JournalEntryError.negativeAmount
        }
    }
}

/// Account types following standard accounting categories
enum AccountType: String, Codable, CaseIterable {
    case asset = "asset"           // Stocks, bonds, crypto, other investments
    case cash = "cash"            // USD and other currencies
    case liability = "liability"   // Margin debt, loans
    case equity = "equity"        // Owner's equity
    case income = "income"        // Dividends, interest, gains
    case expense = "expense"      // Fees, commissions, losses
}

enum JournalEntryError: LocalizedError {
    case invalidAmounts
    case missingQuantity
    case negativeAmount

    var errorDescription: String? {
        switch self {
        case .invalidAmounts:
            return "Journal entry must have exactly one of debit or credit amount"
        case .missingQuantity:
            return "Asset journal entries must have a quantity"
        case .negativeAmount:
            return "Journal entry amounts must be positive"
        }
    }
}

// MARK: - Helper Extensions

extension AccountType {
    /// Human-readable description
    var displayName: String {
        switch self {
        case .asset: return "Asset"
        case .cash: return "Cash"
        case .liability: return "Liability"
        case .equity: return "Equity"
        case .income: return "Income"
        case .expense: return "Expense"
        }
    }

    /// Icon for UI display
    var systemImage: String {
        switch self {
        case .asset: return "chart.line.uptrend.xyaxis"
        case .cash: return "dollarsign.circle"
        case .liability: return "creditcard"
        case .equity: return "person.fill"
        case .income: return "arrow.down.circle"
        case .expense: return "arrow.up.circle"
        }
    }

    /// Color for UI display
    var color: Color {
        switch self {
        case .asset: return .blue
        case .cash: return .green
        case .liability: return .red
        case .equity: return .purple
        case .income: return .teal
        case .expense: return .orange
        }
    }
}