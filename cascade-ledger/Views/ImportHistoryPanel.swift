//
//  ImportHistoryPanel.swift
//  cascade-ledger
//
//  Shows import history in ParseStudio sidebar
//

import SwiftUI
import SwiftData

struct ImportHistoryPanel: View {
    let account: Account
    @Binding var selectedFile: RawFile?
    @Binding var selectedBatches: Set<UUID>
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ImportBatch.timestamp, order: .reverse) private var allBatches: [ImportBatch]

    @State private var showingDeleteAlert = false
    @State private var batchToDelete: ImportBatch?
    @State private var showingEditMetadata = false
    @State private var batchToEdit: ImportBatch?

    private var accountBatches: [ImportBatch] {
        allBatches.filter { $0.account?.id == account.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Data Uploads")
                        .font(.headline)

                    Spacer()

                    Text("\(selectedBatches.count) of \(accountBatches.count) selected")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text("\(account.name)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            // Import list
            ScrollView {
                LazyVStack(spacing: 12) {
                    if accountBatches.isEmpty {
                        EmptyHistoryView()
                    } else {
                        ForEach(accountBatches) { batch in
                            DataUploadCard(
                                batch: batch,
                                isChecked: selectedBatches.contains(batch.id),
                                onToggle: {
                                    if selectedBatches.contains(batch.id) {
                                        selectedBatches.remove(batch.id)
                                    } else {
                                        selectedBatches.insert(batch.id)
                                    }
                                },
                                onEdit: {
                                    batchToEdit = batch
                                    showingEditMetadata = true
                                },
                                onDelete: {
                                    batchToDelete = batch
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 250, idealWidth: 300, maxWidth: 400, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingEditMetadata) {
            if let batch = batchToEdit {
                EditDataUploadSheet(batch: batch, onComplete: {
                    showingEditMetadata = false
                    batchToEdit = nil
                })
            }
        }
        .alert("Delete Data Upload?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                batchToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let batch = batchToDelete {
                    deleteBatch(batch)
                }
            }
        } message: {
            if let batch = batchToDelete {
                Text("This will delete the data upload and \(batch.successfulRows) generated transactions from '\(batch.batchName ?? batch.rawFile?.fileName ?? "Unknown")'")
            }
        }
    }

    private func deleteBatch(_ batch: ImportBatch) {
        // Delete all transactions from this batch
        for transaction in batch.transactions {
            modelContext.delete(transaction)
        }

        // Delete the batch itself
        modelContext.delete(batch)

        do {
            try modelContext.save()
            print("✓ Deleted data upload: \(batch.batchName ?? "Unknown")")
        } catch {
            print("Failed to delete: \(error)")
        }

        batchToDelete = nil
        selectedBatches.remove(batch.id)
        if selectedFile?.id == batch.rawFile?.id {
            selectedFile = nil
        }
    }
}

// MARK: - Data Upload Card

struct DataUploadCard: View {
    let batch: ImportBatch
    let isChecked: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    private var hasTransactions: Bool {
        batch.successfulRows > 0
    }

    private var parsePlanVersion: String {
        if let version = batch.parsePlanVersion {
            return "v\(version.versionNumber)"
        }
        return "No parse plan"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with file name
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { isChecked },
                    set: { _ in onToggle() }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .controlSize(.small)

                Image(systemName: "doc.text")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))

                Text(batch.batchName ?? batch.rawFile?.fileName ?? "Unknown File")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                if hasTransactions {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }
            }

            // File stats
            HStack(spacing: 12) {
                if let rawFile = batch.rawFile {
                    let lineCount = calculateLineCount(rawFile)
                    Label("\(lineCount) lines", systemImage: "list.number")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(formatFileSize(rawFile.fileSize), systemImage: "doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Date range (if available)
            if let startDate = batch.dateRangeStart, let endDate = batch.dateRangeEnd {
                HStack(spacing: 4) {
                    Text(startDate.formatted(date: .abbreviated, time: .omitted))
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                    Text(endDate.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            // Processing status
            if hasTransactions {
                HStack(spacing: 4) {
                    Text("Processed with \(parsePlanVersion)")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text("\(batch.successfulRows) transactions")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            } else {
                Text("Not yet processed")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            // Upload date
            Text("Uploaded \(batch.timestamp.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Actions
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button(action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundColor(.red)

                Spacer()
            }
        }
        .padding(12)
        .background(isChecked ? Color.accentColor.opacity(0.05) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isChecked ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.2), lineWidth: 1)
        )
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func calculateLineCount(_ rawFile: RawFile) -> Int {
        guard let content = String(data: rawFile.content, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - Empty State

struct EmptyHistoryView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Uploads Yet")
                .font(.headline)

            Text("Drop a CSV file or click Import to get started")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Edit Metadata Sheet

struct EditDataUploadSheet: View {
    let batch: ImportBatch
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date

    init(batch: ImportBatch, onComplete: @escaping () -> Void) {
        self.batch = batch
        self.onComplete = onComplete
        _title = State(initialValue: batch.batchName ?? batch.rawFile?.fileName ?? "")
        _startDate = State(initialValue: batch.dateRangeStart ?? Date())
        _endDate = State(initialValue: batch.dateRangeEnd ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Data Upload Details") {
                    TextField("Title", text: $title)

                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)

                    DatePicker("End Date", selection: $endDate, displayedComponents: .date)
                }

                Section("File Information") {
                    if let rawFile = batch.rawFile {
                        LabeledContent("File", value: rawFile.fileName)
                        LabeledContent("Size", value: formatFileSize(rawFile.fileSize))
                        LabeledContent("Lines", value: "\(calculateLineCount(rawFile))")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Edit Data Upload")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
    }

    private func saveChanges() {
        batch.batchName = title.isEmpty ? nil : title
        batch.dateRangeStart = startDate
        batch.dateRangeEnd = endDate

        do {
            try modelContext.save()
            onComplete()
        } catch {
            print("Failed to save: \(error)")
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func calculateLineCount(_ rawFile: RawFile) -> Int {
        guard let content = String(data: rawFile.content, encoding: .utf8) else {
            return 0
        }
        return content.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
}

// MARK: - Preview

#Preview {
    let account = Account(name: "Fidelity")
    return ImportHistoryPanel(account: account, selectedFile: .constant(nil), selectedBatches: .constant([]))
        .modelContainer(ModelContainer.preview)
        .frame(width: 300, height: 600)
}
