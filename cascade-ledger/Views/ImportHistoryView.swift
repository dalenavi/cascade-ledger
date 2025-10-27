//
//  ImportHistoryView.swift
//  cascade-ledger
//
//  Import history view
//

import SwiftUI
import SwiftData

struct ImportHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportBatch.timestamp, order: .reverse)
    private var importBatches: [ImportBatch]

    @State private var selectedBatch: ImportBatch?
    @State private var showingReimportConfirmation = false
    @State private var isReimporting = false

    var body: some View {
        NavigationStack {
            List {
                if importBatches.isEmpty {
                    ContentUnavailableView(
                        "No Import History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Your import history will appear here")
                    )
                } else {
                    ForEach(importBatches) { batch in
                        ImportBatchRow(
                            batch: batch,
                            onReimport: {
                                selectedBatch = batch
                                showingReimportConfirmation = true
                            }
                        )
                    }
                }
            }
            .navigationTitle("Import History")
        }
        .alert("Re-import Data?", isPresented: $showingReimportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Re-import") {
                if let batch = selectedBatch {
                    reimportBatch(batch)
                }
            }
        } message: {
            if let batch = selectedBatch {
                Text("Re-import \(batch.rawFile?.fileName ?? "this file") with the current parse plan? Old ledger entries will be deleted and replaced.")
            }
        }
    }

    private func reimportBatch(_ batch: ImportBatch) {
        guard let rawFile = batch.rawFile,
              let account = batch.account else {
            return
        }

        isReimporting = true

        Task {
            do {
                // Get current/default parse plan for account
                let parsePlan = account.defaultParsePlan ?? account.parsePlans.first

                guard let plan = parsePlan,
                      let version = plan.currentVersion else {
                    print("No committed parse plan available for re-import")
                    await MainActor.run { isReimporting = false }
                    return
                }

                print("Re-importing \(rawFile.fileName) with parse plan v\(version.versionNumber)")

                // Delete old ledger entries from this batch
                for entry in batch.ledgerEntries {
                    modelContext.delete(entry)
                }

                // Execute new import
                let parseEngine = ParseEngine(modelContext: modelContext)
                batch.status = .inProgress

                _ = try await parseEngine.executeImport(
                    importBatch: batch,
                    parsePlanVersion: version
                )

                print("Re-import complete: \(batch.successfulRows) successful")

                await MainActor.run {
                    isReimporting = false
                }
            } catch {
                print("Re-import failed: \(error)")
                await MainActor.run {
                    batch.status = .failed
                    isReimporting = false
                }
            }
        }
    }
}

struct ImportBatchRow: View {
    let batch: ImportBatch
    let onReimport: () -> Void

    private var quantityCount: Int {
        batch.ledgerEntries.filter { $0.hasQuantityData }.count
    }

    private var hasQuantityData: Bool {
        quantityCount > 0
    }

    private var quantityPercentage: Int {
        guard batch.successfulRows > 0 else { return 0 }
        return (quantityCount * 100) / batch.successfulRows
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(batch.rawFile?.fileName ?? "Unknown file")
                    .font(.headline)

                HStack(spacing: 8) {
                    Text(batch.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(batch.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if batch.duplicateRows > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(batch.duplicateRows) duplicates skipped")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }

                    if !hasQuantityData {
                        Text("•")
                            .foregroundColor(.secondary)
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("No quantity data")
                                .font(.caption2)
                        }
                        .foregroundColor(.orange)
                    } else if quantityPercentage < 90 {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("\(quantityPercentage)% quantity data")
                            .font(.caption2)
                            .foregroundColor(quantityPercentage > 50 ? .orange : .red)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    StatusBadge(status: batch.status)

                    Button("Re-import") {
                        onReimport()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("\(batch.successfulRows)/\(batch.totalRows) rows")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatusBadge: View {
    let status: ImportStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(backgroundColor)
            .foregroundColor(.white)
            .cornerRadius(4)
    }

    private var backgroundColor: Color {
        switch status {
        case .success:
            return .green
        case .partialSuccess:
            return .orange
        case .failed:
            return .red
        case .inProgress:
            return .blue
        case .pending:
            return .gray
        }
    }
}