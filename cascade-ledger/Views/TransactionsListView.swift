//
//  TransactionsListView.swift
//  cascade-ledger
//
//  Dedicated transactions view with source row traceability
//

import SwiftUI
import SwiftData

struct TransactionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]

    // Get active account's transactions from active mapping
    private var activeTransactions: [Transaction] {
        guard let account = accounts.first,
              let activeMapping = account.activeMapping else {
            return []
        }

        // Sort by date DESC, then by source row number ASC
        return activeMapping.transactions.sorted { tx1, tx2 in
            if tx1.date != tx2.date {
                return tx1.date > tx2.date
            }
            // Same date - sort by source row number
            let rows1 = Set(tx1.journalEntries.flatMap { $0.sourceRows })
            let rows2 = Set(tx2.journalEntries.flatMap { $0.sourceRows })
            let minRow1 = rows1.map { $0.rowNumber }.min() ?? Int.max
            let minRow2 = rows2.map { $0.rowNumber }.min() ?? Int.max
            return minRow1 < minRow2
        }
    }

    @State private var selectedTransaction: Transaction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Transactions")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if let account = accounts.first,
                   let mapping = account.activeMapping {
                    Text("\(mapping.name) • \(activeTransactions.count) transactions")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            // Transaction list
            if activeTransactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create and activate a mapping to see transactions")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(activeTransactions, id: \.id) { transaction in
                            TransactionRowView(transaction: transaction)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedTransaction = transaction
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selectedTransaction) { transaction in
            TransactionDetailSheet(transaction: transaction)
        }
    }
}

struct TransactionRowView: View {
    let transaction: Transaction

    // Calculate cash impact
    private var cashImpact: Decimal {
        var impact: Decimal = 0
        for entry in transaction.journalEntries {
            if entry.accountName == "Cash" {
                if let debit = entry.debitAmount {
                    impact += debit
                }
                if let credit = entry.creditAmount {
                    impact -= credit
                }
            }
        }
        return impact
    }

    // Get non-cash asset impacts with quantity
    private var assetImpacts: [(String, Decimal?, String)] { // (asset, quantity, sign)
        transaction.journalEntries
            .filter { $0.accountName != "Cash" }
            .compactMap { entry in
                if let quantity = entry.quantity {
                    // Has quantity - show shares/units
                    let sign = entry.debitAmount != nil ? "+" : "−"
                    return (entry.accountName, quantity, sign)
                } else {
                    // No quantity - show USD amount
                    let amount = entry.debitAmount ?? entry.creditAmount ?? 0
                    let sign = entry.debitAmount != nil ? "+" : "−"
                    return (entry.accountName, amount, sign)
                }
            }
    }

    // Check balance discrepancy
    private var hasDiscrepancy: Bool {
        guard let reported = transaction.csvBalance else { return false }
        // Would need running balance here - for now just check if field exists
        return false // Simplified for now
    }

    // Get source row numbers
    private var sourceRowNumbers: [Int] {
        Set(transaction.journalEntries.flatMap { $0.sourceRows })
            .map { $0.rowNumber }
            .sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top line: Date and Balance
            HStack {
                Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                if let balance = transaction.csvBalance {
                    Text("Balance: \(formatCurrency(balance))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Image(systemName: transaction.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(transaction.isBalanced ? .green : .orange)
                    .imageScale(.small)
            }

            // Description
            Text(transaction.transactionDescription)
                .font(.body)
                .fontWeight(.medium)

            // Journal entries (minimal, inline)
            HStack(spacing: 16) {
                ForEach(transaction.journalEntries, id: \.id) { entry in
                    HStack(spacing: 4) {
                        Text(entry.accountName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if let debit = entry.debitAmount {
                            Text(formatCurrency(debit))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.blue)
                            Text("DR")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.blue.opacity(0.7))
                        } else if let credit = entry.creditAmount {
                            Text(formatCurrency(credit))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.green)
                            Text("CR")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.green.opacity(0.7))
                        }
                    }
                }
            }

            // Footer: Cash impact, assets, source rows
            HStack(spacing: 12) {
                // Cash impact
                HStack(spacing: 4) {
                    Text("Cash:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatCurrency(cashImpact, signed: true))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(cashImpact >= 0 ? .green : .red)
                }

                // Asset impacts
                if !assetImpacts.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    ForEach(assetImpacts, id: \.0) { asset, quantity, sign in
                        HStack(spacing: 2) {
                            Text(asset)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(sign)
                                .font(.caption2)
                                .foregroundStyle(sign == "+" ? .green : .red)
                            if let qty = quantity {
                                Text("\(qty as NSDecimalNumber)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                // Source rows
                Text("Row \(sourceRowNumbers.map(String.init).joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    private func formatCurrency(_ amount: Decimal, signed: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        if signed {
            formatter.positivePrefix = formatter.plusSign + formatter.currencySymbol
        }
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}

struct TransactionDetailSheet: View {
    let transaction: Transaction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(transaction.transactionDescription)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(transaction.date.formatted(date: .long, time: .omitted))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Balance reconciliation
                    if let reported = transaction.csvBalance {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Balance Reconciliation")
                                .font(.headline)

                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Reported")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(formatCurrency(reported))
                                        .font(.system(.body, design: .monospaced))
                                }

                                Spacer()

                                Image(systemName: transaction.isBalanced ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(transaction.isBalanced ? .green : .orange)
                            }
                            .padding()
                            .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                            .cornerRadius(8)
                        }
                    }

                    // Journal entries
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Journal Entries")
                            .font(.headline)

                        ForEach(transaction.journalEntries, id: \.id) { entry in
                            JournalEntryCard(entry: entry)
                        }
                    }

                    // Metadata
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Metadata")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 4) {
                            MetadataRow(label: "ID", value: transaction.id.uuidString)
                            MetadataRow(label: "Type", value: transaction.transactionType.rawValue)
                            if let mapping = transaction.mapping {
                                MetadataRow(label: "Mapping", value: mapping.name)
                            }
                            if let account = transaction.account {
                                MetadataRow(label: "Account", value: account.name)
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Transaction Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}

struct JournalEntryCard: View {
    let entry: JournalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Entry header
            HStack {
                Text(entry.accountName)
                    .font(.body)
                    .fontWeight(.medium)

                Spacer()

                if let debit = entry.debitAmount {
                    HStack(spacing: 4) {
                        Text(formatCurrency(debit))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.blue)
                        Text("DR")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue.opacity(0.7))
                    }
                } else if let credit = entry.creditAmount {
                    HStack(spacing: 4) {
                        Text(formatCurrency(credit))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)
                        Text("CR")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
            }

            // Source rows
            if !entry.sourceRows.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(entry.sourceRows.sorted(by: { $0.rowNumber < $1.rowNumber }), id: \.id) { row in
                        SourceRowView(sourceRow: row)
                    }
                }
            }
        }
        .padding()
        .background(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
        .cornerRadius(8)
    }

    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }
}

struct SourceRowView: View {
    let sourceRow: SourceRow

    private var csvData: [String: String] {
        (try? JSONDecoder().decode([String: String].self, from: sourceRow.rawDataJSON)) ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Row \(sourceRow.rowNumber)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.blue.opacity(0.1))
                    .foregroundStyle(.blue)
                    .cornerRadius(4)

                if let action = csvData["Action"] {
                    Text(action)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // Key CSV fields
            HStack(spacing: 16) {
                if let amount = csvData["Amount ($)"] {
                    KeyValue(key: "Amount", value: amount)
                }
                if let balance = csvData["Cash Balance ($)"] {
                    KeyValue(key: "Balance", value: balance)
                }
                if let date = csvData["Run Date"] {
                    KeyValue(key: "Date", value: date)
                }
            }
            .font(.caption2)
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(4)
    }
}

struct KeyValue: View {
    let key: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
        }
    }
}

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    TransactionsListView()
        .modelContainer(for: [Account.self, Transaction.self])
}
