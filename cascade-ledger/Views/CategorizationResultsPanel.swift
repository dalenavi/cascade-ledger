//
//  CategorizationResultsPanel.swift
//  cascade-ledger
//
//  Shows raw AI categorization output in scannable format
//

import SwiftUI
import SwiftData

struct CategorizationResultsPanel: View {
    let account: Account
    @Binding var selectedCategorizationSession: CategorizationSession?
    @Binding var parsePlan: ParsePlan?

    @State private var viewMode: ViewMode = .structured

    enum ViewMode: String, CaseIterable {
        case structured = "Structured"
        case rawJSON = "Raw JSON"
    }

    private var aiResponse: String? {
        guard let session = selectedCategorizationSession,
              let data = session.aiResponseData else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private var parsedCategorizationData: CategorizationData? {
        guard let response = aiResponse,
              let jsonString = extractJSON(from: response),
              let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        return parseCategorizationJSON(json)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                if account.effectiveCategorizationMode == .aiDirect {
                    Label("AI Categorization", systemImage: "brain")
                        .font(.headline)

                    Picker("View", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                } else {
                    Label("Intermediate Data", systemImage: "doc.on.doc")
                        .font(.headline)

                    Text("Transformed dictionaries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content based on mode
            if account.effectiveCategorizationMode == .aiDirect {
                if let data = parsedCategorizationData {
                    if viewMode == .structured {
                        structuredView(data: data)
                    } else {
                        rawJSONView
                    }
                } else if selectedCategorizationSession == nil {
                    emptyStateView
                } else {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)

                        Text("Could Not Parse Response")
                            .font(.headline)

                        Text("AI response may not contain valid categorization JSON")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                // Rule-based mode placeholder (could show transformed dictionaries here)
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Transformed Data")
                        .font(.headline)

                    Text("In rule-based mode, this would show intermediate transformed dictionaries")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }

    // MARK: - Structured View

    private func structuredView(data: CategorizationData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // Summary card
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Categorized")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(data.transactions.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Balanced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(data.transactions.filter { $0.isBalanced }.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unbalanced")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(data.transactions.filter { !$0.isBalanced }.count)")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.red)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)

                // Transaction cards
                ForEach(data.transactions) { txn in
                    CategorizationTransactionCard(transaction: txn)
                }
            }
            .padding()
        }
    }

    // MARK: - Raw JSON View

    private var rawJSONView: some View {
        Group {
            if let response = aiResponse, let jsonString = extractJSON(from: response) {
                ScrollView([.horizontal, .vertical]) {
                    Text(jsonString)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                }
            } else {
                Text("No JSON found")
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "brain")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("No Categorization")
                .font(.headline)

            Text("Click 'Agent' to have AI categorize your CSV data")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - JSON Parsing

    private func extractJSON(from text: String) -> String? {
        let pattern = "```json\\s*(.+?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: text.utf16.count)) else {
            return nil
        }

        let jsonRange = match.range(at: 1)
        return (text as NSString).substring(with: jsonRange)
    }

    private func parseCategorizationJSON(_ json: [String: Any]) -> CategorizationData? {
        guard let transactionsArray = json["transactions"] as? [[String: Any]] else {
            return nil
        }

        let transactions = transactionsArray.compactMap { parseTransaction($0) }
        return CategorizationData(transactions: transactions)
    }

    private func parseTransaction(_ dict: [String: Any]) -> CategorizationTransaction? {
        guard let sourceRows = dict["sourceRows"] as? [Int],
              let date = dict["date"] as? String,
              let description = dict["description"] as? String,
              let type = dict["transactionType"] as? String,
              let entriesArray = dict["journalEntries"] as? [[String: Any]] else {
            return nil
        }

        let entries = entriesArray.compactMap { parseJournalEntry($0) }

        return CategorizationTransaction(
            sourceRows: sourceRows,
            date: date,
            description: description,
            transactionType: type,
            journalEntries: entries
        )
    }

    private func parseJournalEntry(_ dict: [String: Any]) -> CategorizationJournalEntry? {
        guard let type = dict["type"] as? String,
              let accountType = dict["accountType"] as? String,
              let accountName = dict["accountName"] as? String,
              let amount = dict["amount"] as? Double else {
            return nil
        }

        return CategorizationJournalEntry(
            type: type,
            accountType: accountType,
            accountName: accountName,
            amount: amount,
            quantity: dict["quantity"] as? Double,
            quantityUnit: dict["quantityUnit"] as? String,
            assetSymbol: dict["assetSymbol"] as? String
        )
    }
}

// MARK: - Data Structures

struct CategorizationData {
    let transactions: [CategorizationTransaction]
}

struct CategorizationTransaction: Identifiable {
    let id = UUID()
    let sourceRows: [Int]
    let date: String
    let description: String
    let transactionType: String
    let journalEntries: [CategorizationJournalEntry]

    var totalDebits: Double {
        journalEntries.filter { $0.type == "debit" }.reduce(0) { $0 + $1.amount }
    }

    var totalCredits: Double {
        journalEntries.filter { $0.type == "credit" }.reduce(0) { $0 + $1.amount }
    }

    var isBalanced: Bool {
        abs(totalDebits - totalCredits) < 0.01
    }
}

struct CategorizationJournalEntry {
    let type: String  // "debit" or "credit"
    let accountType: String  // "asset", "cash", "income", etc.
    let accountName: String
    let amount: Double
    let quantity: Double?
    let quantityUnit: String?
    let assetSymbol: String?
}

// MARK: - Transaction Card

struct CategorizationTransactionCard: View {
    let transaction: CategorizationTransaction
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.description)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        HStack(spacing: 8) {
                            Text(transaction.date)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(transaction.transactionType)
                                .font(.caption)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(3)

                            Text("Rows: \(transaction.sourceRows.map { "#\($0)" }.joined(separator: ", "))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    // Balance indicator
                    if transaction.isBalanced {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("$\(String(format: "%.2f", transaction.totalDebits))")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Unbalanced")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            // Expanded journal entries
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journal Entries:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        ForEach(transaction.journalEntries.indices, id: \.self) { index in
                            let entry = transaction.journalEntries[index]

                            HStack(spacing: 8) {
                                // DR/CR badge
                                Text(entry.type.uppercased())
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(entry.type == "debit" ? .blue : .green)
                                    .frame(width: 32)
                                    .padding(.vertical, 2)
                                    .background(entry.type == "debit" ? Color.blue.opacity(0.1) : Color.green.opacity(0.1))
                                    .cornerRadius(4)

                                // Account type + name
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.accountType.capitalized)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(entry.accountName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }

                                Spacer()

                                // Amount
                                Text("$\(String(format: "%.2f", entry.amount))")
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                // Quantity if present
                                if let qty = entry.quantity, let unit = entry.quantityUnit {
                                    Text("(\(String(format: "%.3f", qty)) \(unit))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                // Asset symbol badge
                                if let symbol = entry.assetSymbol {
                                    Text(symbol)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.purple.opacity(0.1))
                                        .cornerRadius(3)
                                }
                            }
                        }
                    }

                    // Balance summary
                    HStack {
                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("Debits:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("$\(String(format: "%.2f", transaction.totalDebits))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }

                            HStack(spacing: 4) {
                                Text("Credits:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("$\(String(format: "%.2f", transaction.totalCredits))")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }

                            Divider()
                                .frame(width: 80)

                            HStack(spacing: 4) {
                                Text("Difference:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("$\(String(format: "%.2f", abs(transaction.totalDebits - transaction.totalCredits)))")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(transaction.isBalanced ? .green : .red)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(transaction.isBalanced ? Color.green.opacity(0.3) : Color.red, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    CategorizationResultsPanel(
        account: Account(name: "Test"),
        selectedCategorizationSession: .constant(nil),
        parsePlan: .constant(nil)
    )
    .modelContainer(ModelContainer.preview)
    .frame(width: 400, height: 600)
}
