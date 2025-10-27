//
//  ImportBatchMetadataSheet.swift
//  cascade-ledger
//
//  Sheet for configuring import batch metadata
//

import SwiftUI
import SwiftData

struct ImportBatchMetadataSheet: View {
    let batch: ImportBatch
    let rawFile: RawFile
    let account: Account
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var batchName: String
    @State private var dateRangeStart: Date
    @State private var dateRangeEnd: Date
    @State private var isInferring = false

    init(batch: ImportBatch, rawFile: RawFile, account: Account, onComplete: @escaping () -> Void) {
        self.batch = batch
        self.rawFile = rawFile
        self.account = account
        self.onComplete = onComplete

        // Initialize with inferred values
        let dateRange = ImportMetadataService.shared.inferDateRange(from: rawFile)
        let suggestedName = ImportMetadataService.shared.suggestBatchName(
            from: rawFile,
            account: account,
            dateRange: dateRange
        )

        _batchName = State(initialValue: suggestedName)
        _dateRangeStart = State(initialValue: dateRange.start ?? Date())
        _dateRangeEnd = State(initialValue: dateRange.end ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Import Information") {
                    HStack {
                        Text("File:")
                        Spacer()
                        Text(rawFile.fileName)
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Account:")
                        Spacer()
                        Text(account.name)
                            .foregroundColor(.secondary)
                    }

                    if let institution = account.institution {
                        HStack {
                            Text("Institution:")
                            Spacer()
                            Text(institution.displayName)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Batch Details") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Batch Name (optional)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g., Q4 2025 Transactions", text: $batchName)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Date Range") {
                    Text("Verify the date range matches your CSV export")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    DatePicker("From:", selection: $dateRangeStart, displayedComponents: .date)

                    DatePicker("To:", selection: $dateRangeEnd, displayedComponents: .date)

                    if isInferring {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Inferring from data...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Text("The date range helps organize your imports and detect duplicates across batches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Import Batch Metadata")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Delete the batch if cancelled
                        modelContext.delete(batch)
                        onComplete()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        saveBatchMetadata()
                        onComplete()
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            inferDateRangeIfNeeded()
        }
    }

    private func inferDateRangeIfNeeded() {
        isInferring = true
        Task {
            let dateRange = ImportMetadataService.shared.inferDateRange(from: rawFile)

            await MainActor.run {
                if let start = dateRange.start {
                    dateRangeStart = start
                }
                if let end = dateRange.end {
                    dateRangeEnd = end
                }
                isInferring = false
            }
        }
    }

    private func saveBatchMetadata() {
        batch.batchName = batchName.isEmpty ? nil : batchName
        batch.dateRangeStart = dateRangeStart
        batch.dateRangeEnd = dateRangeEnd

        try? modelContext.save()
    }
}
