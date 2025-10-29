//
//  BalanceCalculationService.swift
//  cascade-ledger
//
//  Calculate account balances from journal entries
//

import Foundation
import SwiftData

/// Calculate account balances from journal entries
class BalanceCalculationService {

    /// Calculate balance for a specific account up to a given date
    func calculateBalanceAtDate(
        accountName: String,
        accountType: AccountType,
        upToDate: Date,
        transactions: [Transaction]
    ) -> Decimal {
        // Filter transactions up to the date
        let relevantTransactions = transactions.filter { $0.date <= upToDate }

        // Sum net effects from journal entries for this account
        var balance: Decimal = 0

        for transaction in relevantTransactions {
            for entry in transaction.journalEntries {
                if entry.accountName == accountName && entry.accountType == accountType {
                    balance += entry.netEffect
                }
            }
        }

        return balance
    }

    /// Calculate running balance for all transactions (chronologically ordered)
    func calculateBalanceProgression(
        accountName: String,
        accountType: AccountType,
        transactions: [Transaction]
    ) -> [(date: Date, balance: Decimal, transaction: Transaction)] {
        // Sort transactions by date
        let sortedTransactions = transactions.sorted { $0.date < $1.date }

        var runningBalance: Decimal = 0
        var progression: [(Date, Decimal, Transaction)] = []

        for transaction in sortedTransactions {
            // Calculate net effect of this transaction on the account
            var transactionEffect: Decimal = 0

            for entry in transaction.journalEntries {
                if entry.accountName == accountName && entry.accountType == accountType {
                    transactionEffect += entry.netEffect
                }
            }

            runningBalance += transactionEffect
            progression.append((transaction.date, runningBalance, transaction))
        }

        return progression
    }

    /// Calculate cash balance (USD) at a given date
    func calculateCashBalance(
        upToDate: Date,
        transactions: [Transaction],
        currency: String = "USD"
    ) -> Decimal {
        return calculateBalanceAtDate(
            accountName: "Cash \(currency)",
            accountType: .cash,
            upToDate: upToDate,
            transactions: transactions
        )
    }

    /// Calculate cash balance progression over time
    func calculateCashBalanceProgression(
        transactions: [Transaction],
        currency: String = "USD"
    ) -> [(date: Date, balance: Decimal, transaction: Transaction)] {
        return calculateBalanceProgression(
            accountName: "Cash \(currency)",
            accountType: .cash,
            transactions: transactions
        )
    }
}
