//
//  TransactionDetailView.swift
//  cascade-ledger
//
//  Detailed view of a single transaction
//

import SwiftUI
import SwiftData

struct TransactionDetailView: View {
    let entry: Transaction

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var notes: String
    @State private var userCategory: String
    @State private var selectedTransactionType: TransactionType
    @State private var availableCategories = [
        "Income: Salary",
        "Income: Dividend",
        "Income: Interest",
        "Housing: Rent",
        "Housing: Utilities",
        "Transportation: Auto",
        "Food & Dining",
        "Shopping",
        "Healthcare",
        "Entertainment",
        "Travel",
        "Investments: Buy",
        "Investments: Sell",
        "Transfers",
        "Fees & Charges",
        "Taxes",
        "Other"
    ]

    init(entry: Transaction) {
        self.entry = entry
        _notes = State(initialValue: entry.notes ?? "")
        _userCategory = State(initialValue: entry.userCategory ?? entry.category ?? "")
        _selectedTransactionType = State(initialValue: entry.effectiveTransactionType)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Core transaction info
                Section("Transaction Details") {
                    DetailRow(label: "Date", value: entry.date.formatted(date: .abbreviated, time: .omitted))
                    DetailRow(label: "Amount", value: entry.amount, format: .currency(code: "USD"))
                    DetailRow(label: "Description", value: entry.transactionDescription)

                    if let assetId = entry.assetId {
                        DetailRow(label: "Asset", value: assetId)
                    }
                }

                // Transaction type classification
                Section("Transaction Type") {
                    Picker("Type", selection: $selectedTransactionType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }

                    if let rawType = entry.rawTransactionType {
                        HStack {
                            Text("CSV Value:")
                            Text(rawType)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .font(.caption)
                    }

                    if entry.userTransactionType != nil {
                        HStack {
                            Image(systemName: "pencil.circle.fill")
                                .foregroundColor(.blue)
                            Text("User-modified")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }

                // Categorization
                Section("Categorization") {
                    Picker("Category", selection: $userCategory) {
                        Text("None").tag("")
                        ForEach(availableCategories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }

                    if entry.category != nil && entry.category != userCategory {
                        HStack {
                            Text("Auto-detected:")
                            Text(entry.category!)
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        .font(.caption)
                    }

                    if let subcategory = entry.subcategory {
                        DetailRow(label: "Subcategory", value: subcategory)
                    }
                }

                // Metadata (institution-specific fields)
                if !entry.metadata.isEmpty {
                    Section("Additional Fields") {
                        ForEach(Array(entry.metadata.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.caption)
                                Spacer()
                                Text(entry.metadata[key] ?? "")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                // Notes
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .font(.body)
                }

                // Lineage & Import Info
                Section("Import Information") {
                    if let importBatch = entry.importBatch {
                        if let batchName = importBatch.batchName {
                            DetailRow(label: "Batch", value: batchName)
                        }
                        DetailRow(label: "Imported", value: importBatch.timestamp.formatted())

                        if let rawFile = importBatch.rawFile {
                            DetailRow(label: "Source File", value: rawFile.fileName)
                        }
                    }

                    if let sourceRow = entry.sourceRowNumber {
                        DetailRow(label: "Source Row", value: "\(sourceRow)")
                    }

                    if let parseRun = entry.parseRun,
                       let version = parseRun.parsePlanVersion {
                        DetailRow(label: "Parse Plan", value: "v\(version.versionNumber)")
                    }
                }

                // Status
                Section("Status") {
                    Toggle("Reconciled", isOn: .constant(entry.isReconciled))
                        .disabled(true)

                    if entry.isDuplicate, let duplicateId = entry.duplicateOf {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Possible duplicate detected")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Transaction Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private var transactionTypeColor: Color {
        switch entry.transactionType {
        case .other, .deposit, .dividend, .interest, .sell:
            return .green
        case .other, .withdrawal, .fee, .tax, .buy:
            return .red
        case .transfer:
            return .blue
        }
    }

    private func saveChanges() {
        // Save transaction type if user changed it
        if selectedTransactionType != entry.transactionType {
            entry.userTransactionType = selectedTransactionType
        }

        entry.notes = notes.isEmpty ? nil : notes
        entry.userCategory = userCategory.isEmpty ? nil : userCategory
        entry.updatedAt = Date()

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save: \(error)")
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var color: Color?

    init(label: String, value: String, color: Color? = nil) {
        self.label = label
        self.value = value
        self.color = color
    }

    init<T: CustomStringConvertible>(label: String, value: T, color: Color? = nil) {
        self.label = label
        self.value = String(describing: value)
        self.color = color
    }

    init<F: FormatStyle>(label: String, value: F.FormatInput, format: F, color: Color? = nil) where F.FormatOutput == String {
        self.label = label
        self.value = format.format(value)
        self.color = color
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(color ?? .secondary)
                .textSelection(.enabled)
        }
    }
}
