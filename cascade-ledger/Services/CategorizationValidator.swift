//
//  CategorizationValidator.swift
//  cascade-ledger
//
//  Validates AI categorization for accounting integrity
//

import Foundation
import SwiftData

@MainActor
struct CategorizationValidator {

    // MARK: - Main Validation

    static func validate(
        session: CategorizationSession,
        sourceRows: [[String: String]],
        csvHeaders: [String]
    ) -> ValidationReport {
        let rowCoverage = validateRowCoverage(
            sourceRowCount: sourceRows.count,
            transactions: session.transactions
        )

        let transactionBalance = validateTransactionBalance(
            transactions: session.transactions
        )

        let runningBalance = validateRunningBalance(
            transactions: session.transactions.sorted { $0.date < $1.date },
            sourceRows: sourceRows,
            headers: csvHeaders
        )

        let assetPositions = validateAssetPositions(
            transactions: session.transactions.sorted { $0.date < $1.date }
        )

        let settlementPairing = validateSettlementPairing(
            transactions: session.transactions,
            sourceRows: sourceRows
        )

        return ValidationReport(
            rowCoverage: rowCoverage,
            transactionBalance: transactionBalance,
            runningBalance: runningBalance,
            assetPositions: assetPositions,
            settlementPairing: settlementPairing
        )
    }

    // MARK: - Row Coverage Validation

    static func validateRowCoverage(
        sourceRowCount: Int,
        transactions: [Transaction]
    ) -> RowCoverageReport {
        var usedRows: [Int] = []
        var duplicateRows: [Int] = []
        var seenRows: Set<Int> = []

        for transaction in transactions {
            for rowNum in transaction.sourceRowNumbers {
                if seenRows.contains(rowNum) {
                    duplicateRows.append(rowNum)
                } else {
                    seenRows.insert(rowNum)
                    usedRows.append(rowNum)
                }
            }
        }

        let allSourceRows = Set(1...sourceRowCount)  // 1-based
        let missingRows = allSourceRows.subtracting(seenRows).sorted()

        return RowCoverageReport(
            totalSourceRows: sourceRowCount,
            coveredRows: usedRows.count,
            missingRows: missingRows,
            duplicateRows: duplicateRows,
            isPerfect: missingRows.isEmpty && duplicateRows.isEmpty
        )
    }

    // MARK: - Transaction Balance Validation

    static func validateTransactionBalance(
        transactions: [Transaction]
    ) -> TransactionBalanceReport {
        var unbalancedTransactions: [(Transaction, Decimal)] = []

        for transaction in transactions {
            let diff = abs(transaction.totalDebits - transaction.totalCredits)
            if diff >= 0.01 {  // Tolerance: $0.01
                unbalancedTransactions.append((transaction, diff))
            }
        }

        return TransactionBalanceReport(
            totalTransactions: transactions.count,
            balancedCount: transactions.count - unbalancedTransactions.count,
            unbalancedTransactions: unbalancedTransactions,
            isPerfect: unbalancedTransactions.isEmpty
        )
    }

    // MARK: - Running Balance Validation

    static func validateRunningBalance(
        transactions: [Transaction],
        sourceRows: [[String: String]],
        headers: [String]
    ) -> RunningBalanceReport {
        guard let cashBalanceIndex = headers.firstIndex(of: "Cash Balance ($)") else {
            return RunningBalanceReport(
                available: false,
                discrepancies: [],
                maxDiscrepancy: 0,
                isPerfect: true  // N/A
            )
        }

        var discrepancies: [(rowNum: Int, expected: Decimal, calculated: Decimal, diff: Decimal)] = []
        var runningCalculated: Decimal = 0

        // Build map of row number to transaction
        var rowToTransaction: [Int: Transaction] = [:]
        for transaction in transactions {
            for rowNum in transaction.sourceRowNumbers {
                rowToTransaction[rowNum] = transaction
            }
        }

        for (index, row) in sourceRows.enumerated() {
            let rowNum = index + 1  // 1-based

            // Get expected balance from CSV
            guard let balanceStr = row["Cash Balance ($)"],
                  let expected = Decimal(string: balanceStr.replacingOccurrences(of: ",", with: "")) else {
                continue
            }

            // If this row has a transaction, update running balance
            if let transaction = rowToTransaction[rowNum] {
                runningCalculated += transaction.netCashImpact
            }

            // Compare
            let diff = abs(expected - runningCalculated)
            if diff >= 0.01 {  // $0.01 tolerance
                discrepancies.append((rowNum, expected, runningCalculated, diff))
            }
        }

        let maxDiff = discrepancies.map { $0.diff }.max() ?? 0

        return RunningBalanceReport(
            available: true,
            discrepancies: discrepancies.prefix(10).map { $0 },  // Limit to first 10
            maxDiscrepancy: maxDiff,
            isPerfect: discrepancies.isEmpty
        )
    }

    // MARK: - Asset Position Validation

    static func validateAssetPositions(
        transactions: [Transaction]
    ) -> AssetPositionReport {
        var positions: [String: Decimal] = [:]  // symbol → quantity
        var negativePositions: [(symbol: String, quantity: Decimal, atTransaction: UUID)] = []

        for transaction in transactions {
            for entry in transaction.journalEntries {
                guard entry.accountType == .asset,
                      let quantity = entry.quantity,
                      let symbol = entry.asset?.symbol ?? entry.accountName as String? else {
                    continue
                }

                let currentQty = positions[symbol] ?? 0
                let change = entry.isDebit ? quantity : -quantity
                let newQty = currentQty + change

                positions[symbol] = newQty

                // Check for negative position
                if newQty < 0 {
                    negativePositions.append((symbol, newQty, transaction.id))
                }
            }
        }

        return AssetPositionReport(
            assetCount: positions.count,
            finalPositions: positions,
            negativePositions: negativePositions,
            isPerfect: negativePositions.isEmpty
        )
    }

    // MARK: - Settlement Pairing Validation

    static func validateSettlementPairing(
        transactions: [Transaction],
        sourceRows: [[String: String]]
    ) -> SettlementReport {
        var settlementRows: Set<Int> = []
        var primaryRows: Set<Int> = []

        // Identify settlement vs primary rows
        for (index, row) in sourceRows.enumerated() {
            let rowNum = index + 1  // 1-based
            let action = row["Action"] ?? ""
            let symbol = row["Symbol"] ?? ""
            let quantityStr = row["Quantity"] ?? "0"
            let quantity = Decimal(string: quantityStr) ?? 0

            if action.trimmingCharacters(in: .whitespaces).isEmpty &&
               symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
               quantity == 0 {
                settlementRows.insert(rowNum)
            } else {
                primaryRows.insert(rowNum)
            }
        }

        // Check pairing
        var unpairedSettlements: [Int] = []
        var properlyPaired = 0

        for transaction in transactions {
            let txnRows = Set(transaction.sourceRowNumbers)
            let hasSettlement = !txnRows.intersection(settlementRows).isEmpty
            let hasPrimary = !txnRows.intersection(primaryRows).isEmpty

            if hasSettlement && hasPrimary {
                properlyPaired += 1
            } else if hasSettlement && !hasPrimary {
                unpairedSettlements.append(contentsOf: txnRows.intersection(settlementRows))
            }
        }

        return SettlementReport(
            totalSettlementRows: settlementRows.count,
            properlyPaired: properlyPaired,
            unpairedSettlements: unpairedSettlements,
            isPerfect: unpairedSettlements.isEmpty
        )
    }
}

// MARK: - Report Types

struct ValidationReport {
    let rowCoverage: RowCoverageReport
    let transactionBalance: TransactionBalanceReport
    let runningBalance: RunningBalanceReport
    let assetPositions: AssetPositionReport
    let settlementPairing: SettlementReport

    var overallStatus: ValidationStatus {
        if !rowCoverage.isPerfect || !transactionBalance.isPerfect {
            return .critical
        }
        if !runningBalance.isPerfect || !assetPositions.isPerfect || !settlementPairing.isPerfect {
            return .warning
        }
        return .pass
    }

    var criticalIssues: [String] {
        var issues: [String] = []

        if !rowCoverage.isPerfect {
            if !rowCoverage.missingRows.isEmpty {
                issues.append("\(rowCoverage.missingRows.count) rows not categorized")
            }
            if !rowCoverage.duplicateRows.isEmpty {
                issues.append("\(rowCoverage.duplicateRows.count) rows used multiple times")
            }
        }

        if !transactionBalance.isPerfect {
            issues.append("\(transactionBalance.unbalancedTransactions.count) unbalanced transactions")
        }

        return issues
    }

    var warnings: [String] {
        var warns: [String] = []

        if runningBalance.available && !runningBalance.isPerfect {
            warns.append("Cash balance discrepancies (max: $\(String(format: "%.2f", runningBalance.maxDiscrepancy as NSDecimalNumber)))")
        }

        if !assetPositions.isPerfect {
            warns.append("\(assetPositions.negativePositions.count) negative asset positions")
        }

        if !settlementPairing.isPerfect {
            warns.append("\(settlementPairing.unpairedSettlements.count) unpaired settlement rows")
        }

        return warns
    }
}

enum ValidationStatus {
    case pass
    case warning
    case critical
}

struct RowCoverageReport {
    let totalSourceRows: Int
    let coveredRows: Int
    let missingRows: [Int]
    let duplicateRows: [Int]
    let isPerfect: Bool
}

struct TransactionBalanceReport {
    let totalTransactions: Int
    let balancedCount: Int
    let unbalancedTransactions: [(Transaction, Decimal)]
    let isPerfect: Bool
}

struct RunningBalanceReport {
    let available: Bool  // CSV has Cash Balance column
    let discrepancies: [(rowNum: Int, expected: Decimal, calculated: Decimal, diff: Decimal)]
    let maxDiscrepancy: Decimal
    let isPerfect: Bool
}

struct AssetPositionReport {
    let assetCount: Int
    let finalPositions: [String: Decimal]
    let negativePositions: [(symbol: String, quantity: Decimal, atTransaction: UUID)]
    let isPerfect: Bool
}

struct SettlementReport {
    let totalSettlementRows: Int
    let properlyPaired: Int
    let unpairedSettlements: [Int]
    let isPerfect: Bool
}
