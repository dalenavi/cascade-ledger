//
//  SettlementDetector.swift
//  cascade-ledger
//
//  Institution-specific logic for detecting settlement rows
//

import Foundation

/// Protocol for detecting settlement rows in CSV data
protocol SettlementDetector {
    /// Check if a row is a settlement row
    func isSettlementRow(_ row: [String: Any]) -> Bool

    /// Group rows into transactions
    func groupRows(_ rows: [[String: Any]]) -> [[[String: Any]]]
}

// MARK: - Fidelity Settlement Detector

/// Fidelity pattern: Asset row followed by settlement row(s)
struct FidelitySettlementDetector: SettlementDetector {

    func isSettlementRow(_ row: [String: Any]) -> Bool {
        // Settlement row pattern:
        // 1. No transaction type/action (empty or missing)
        // 2. No asset/symbol (empty or missing)
        // 3. Quantity is 0 or missing
        // 4. Description is often "No Description" or empty

        let action = row["action"] as? String ?? row["transactionType"] as? String ?? ""
        let symbol = row["symbol"] as? String ?? row["assetId"] as? String ?? ""
        let quantity = row["quantity"] as? Decimal ?? 0

        // Settlement has empty action, empty symbol, and zero quantity
        let isSettlement = action.trimmingCharacters(in: .whitespaces).isEmpty &&
                          symbol.trimmingCharacters(in: .whitespaces).isEmpty &&
                          quantity == 0

        return isSettlement
    }

    func groupRows(_ rows: [[String: Any]]) -> [[[String: Any]]] {
        var groups: [[[String: Any]]] = []
        var currentGroup: [[String: Any]] = []

        for (index, row) in rows.enumerated() {
            if !isSettlementRow(row) {
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
}

// MARK: - Coinbase Settlement Detector

/// Coinbase pattern: One row per transaction (no settlements)
struct CoinbaseSettlementDetector: SettlementDetector {

    func isSettlementRow(_ row: [String: Any]) -> Bool {
        // Coinbase has no settlement rows
        return false
    }

    func groupRows(_ rows: [[String: Any]]) -> [[[String: Any]]] {
        // Each row is its own transaction
        return rows.map { [$0] }
    }
}

// MARK: - Generic Settlement Detector

/// Fallback detector that treats each row as a separate transaction
struct GenericSettlementDetector: SettlementDetector {

    func isSettlementRow(_ row: [String: Any]) -> Bool {
        false
    }

    func groupRows(_ rows: [[String: Any]]) -> [[[String: Any]]] {
        // Each row is its own transaction
        return rows.map { [$0] }
    }
}

// MARK: - Settlement Detector Factory

/// Creates appropriate settlement detector for an institution
struct SettlementDetectorFactory {

    static func create(for institution: InstitutionDetector.Institution) -> SettlementDetector {
        switch institution {
        case .fidelity:
            return FidelitySettlementDetector()
        case .coinbase:
            return CoinbaseSettlementDetector()
        case .schwab, .unknown:
            return GenericSettlementDetector()
        }
    }
}
