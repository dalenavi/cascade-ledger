//
//  CategorizationReviewView.swift
//  cascade-ledger
//
//  Review and approve AI categorization proposals
//

import SwiftUI
import SwiftData

struct CategorizationReviewView: View {
    let attempts: [CategorizationAttempt]
    let account: Account
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAttempts: Set<UUID> = []
    @State private var editingAttempt: CategorizationAttempt?
    @State private var showingPromptView = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header stats
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(attempts.count) Categorization Proposals")
                            .font(.title2)
                        Text("\(selectedAttempts.count) selected to apply")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("View Prompt") {
                        showingPromptView = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                // Proposals list
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(attempts) { attempt in
                            CategorizationProposalRow(
                                attempt: attempt,
                                isSelected: selectedAttempts.contains(attempt.id),
                                onToggle: { toggleSelection(attempt) },
                                onEdit: { editingAttempt = attempt }
                            )
                        }
                    }
                    .padding()
                }

                Divider()

                // Actions
                HStack {
                    Button("Select All") {
                        selectedAttempts = Set(attempts.map { $0.id })
                    }
                    .buttonStyle(.bordered)

                    Button("Deselect All") {
                        selectedAttempts = []
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)

                    Button("Apply Selected (\(selectedAttempts.count))") {
                        applySelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedAttempts.isEmpty)
                }
                .padding()
            }
        }
        .frame(minWidth: 700, minHeight: 600)
        .sheet(item: $editingAttempt) { attempt in
            CategorizationCorrectionSheet(
                attempt: attempt,
                account: account
            )
        }
        .sheet(isPresented: $showingPromptView) {
            CategorizationPromptView(account: account)
        }
    }

    private func toggleSelection(_ attempt: CategorizationAttempt) {
        if selectedAttempts.contains(attempt.id) {
            selectedAttempts.remove(attempt.id)
        } else {
            selectedAttempts.insert(attempt.id)
        }
    }

    private func applySelected() {
        for attempt in attempts where selectedAttempts.contains(attempt.id) {
            if attempt.status == .tentative {
                attempt.apply()
            }
        }

        do {
            try modelContext.save()
            onComplete()
            dismiss()
        } catch {
            print("Failed to apply categorizations: \(error)")
        }
    }
}

struct CategorizationProposalRow: View {
    let attempt: CategorizationAttempt
    let isSelected: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            // Transaction info
            VStack(alignment: .leading, spacing: 4) {
                if let transaction = attempt.transaction {
                    Text(transaction.transactionDescription)
                        .font(.headline)
                        .lineLimit(1)

                    HStack {
                        Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        Text("•")
                        Text(transaction.amount, format: .currency(code: "USD"))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                // Proposal
                HStack(spacing: 8) {
                    if let category = attempt.proposedCategory {
                        Text(category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }

                    ForEach(attempt.proposedTags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(4)
                    }

                    ConfidenceBadge(confidence: attempt.confidence)
                }
            }

            Spacer()

            Button("Edit") {
                onEdit()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ConfidenceBadge: View {
    let confidence: Double

    var body: some View {
        Text("\(Int(confidence * 100))%")
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor.opacity(0.2))
            .foregroundColor(confidenceColor)
            .cornerRadius(4)
    }

    private var confidenceColor: Color {
        if confidence >= 0.9 {
            return .green
        } else if confidence >= 0.5 {
            return .orange
        } else {
            return .red
        }
    }
}

struct CategorizationCorrectionSheet: View {
    let attempt: CategorizationAttempt
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: TransactionType
    @State private var selectedCategory: String
    @State private var selectedTags: [String]
    @State private var updatePrompt = true
    @State private var feedback = ""

    init(attempt: CategorizationAttempt, account: Account) {
        self.attempt = attempt
        self.account = account

        // Initialize with proposed values
        _selectedType = State(initialValue: attempt.proposedType ?? attempt.transaction?.transactionType ?? .other)
        _selectedCategory = State(initialValue: attempt.proposedCategory ?? "")
        _selectedTags = State(initialValue: attempt.proposedTags)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    if let transaction = attempt.transaction {
                        DetailRow(label: "Description", value: transaction.transactionDescription)
                        DetailRow(label: "Amount", value: transaction.amount, format: .currency(code: "USD"))
                        DetailRow(label: "Date", value: transaction.date.formatted())
                    }
                }

                Section("Claude Suggested") {
                    if let category = attempt.proposedCategory {
                        DetailRow(label: "Category", value: category)
                    }
                    if !attempt.proposedTags.isEmpty {
                        DetailRow(label: "Tags", value: attempt.proposedTags.joined(separator: ", "))
                    }
                    ConfidenceBadge(confidence: attempt.confidence)

                    if let reasoning = attempt.reasoning {
                        Text(reasoning)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }

                Section("Your Correction") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(TransactionType.allCases, id: \.self) { type in
                            Text(type.rawValue.capitalized).tag(type)
                        }
                    }

                    TextField("Category", text: $selectedCategory)
                        .textFieldStyle(.roundedBorder)

                    // TODO: Tag selector
                    Text("Tags: \(selectedTags.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Toggle("Update prompt for future", isOn: $updatePrompt)

                    if updatePrompt {
                        TextField("Why is this correct? (optional)", text: $feedback, axis: .vertical)
                            .lineLimit(2...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Correct Categorization")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveCorrection()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func saveCorrection() {
        attempt.correct(
            actualType: selectedType,
            actualCategory: selectedCategory.isEmpty ? nil : selectedCategory,
            actualTags: selectedTags,
            feedback: feedback.isEmpty ? nil : feedback
        )

        if updatePrompt {
            Task {
                let categorizationService = CategorizationService(modelContext: modelContext)
                try? await categorizationService.learnFromCorrection(attempt, account: account)
            }
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save correction: \(error)")
        }
    }
}

struct CategorizationPromptView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext

    @State private var globalPrompt: CategorizationPrompt?
    @State private var accountPrompt: CategorizationPrompt?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let global = globalPrompt {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Global Rules", systemImage: "globe")
                                        .font(.headline)
                                    Spacer()
                                    Text("v\(global.version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(global.promptText)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)

                                HStack {
                                    Text("Success: \(global.successCount)")
                                    Text("•")
                                    Text("Corrections: \(global.correctionCount)")
                                    Text("•")
                                    Text("Accuracy: \(Int(global.accuracyRate * 100))%")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }

                    if let accountPrompt = accountPrompt {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Account Rules: \(account.name)", systemImage: "banknote")
                                        .font(.headline)
                                    Spacer()
                                    Text("v\(accountPrompt.version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Text(accountPrompt.promptText)
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding()
                                    .background(Color(NSColor.textBackgroundColor))
                                    .cornerRadius(4)

                                HStack {
                                    Text("Success: \(accountPrompt.successCount)")
                                    Text("•")
                                    Text("Corrections: \(accountPrompt.correctionCount)")
                                    Text("•")
                                    Text("Accuracy: \(Int(accountPrompt.accuracyRate * 100))%")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Categorization Prompts")
        }
        .frame(minWidth: 600, minHeight: 500)
        .onAppear {
            loadPrompts()
        }
    }

    private func loadPrompts() {
        let categorizationService = CategorizationService(modelContext: modelContext)
        globalPrompt = categorizationService.getGlobalPrompt()
        accountPrompt = categorizationService.getAccountPrompt(account)
    }
}
