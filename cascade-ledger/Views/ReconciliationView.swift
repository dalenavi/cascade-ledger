//
//  ReconciliationView.swift
//  cascade-ledger
//
//  Balance reconciliation UI
//

import SwiftUI
import SwiftData

struct ReconciliationView: View {
    @Environment(\.modelContext) private var modelContext
    let session: CategorizationSession
    let csvRows: [[String: String]]

    @State private var reconciliationSession: ReconciliationSession?
    @State private var isReconciling = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Balance Reconciliation")
                    .font(.title)
                    .bold()

                Text("Compare CSV balances to calculated balances from journal entries")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            if let reconciliation = reconciliationSession {
                reconciliationStatusView(reconciliation)
            } else {
                startReconciliationView
            }

            Spacer()
        }
        .padding()
    }

    private var startReconciliationView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Ready to Reconcile")
                .font(.title2)
                .bold()

            Text("This will compare your CSV balance data to calculated balances and identify discrepancies.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Button(action: startReconciliation) {
                HStack {
                    if isReconciling {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isReconciling ? "Reconciling..." : "Start Reconciliation")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isReconciling)
        }
        .frame(maxWidth: 500)
    }

    private func reconciliationStatusView(_ reconciliation: ReconciliationSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Summary
            HStack(spacing: 40) {
                statBox(
                    title: "Checkpoints",
                    value: "\(reconciliation.checkpointsBuilt)",
                    color: .blue
                )

                statBox(
                    title: "Discrepancies",
                    value: "\(reconciliation.discrepanciesFound)",
                    color: reconciliation.discrepanciesFound > 0 ? .orange : .green
                )

                statBox(
                    title: "Resolved",
                    value: "\(reconciliation.discrepanciesResolved)",
                    color: .green
                )

                statBox(
                    title: "Fixes Applied",
                    value: "\(reconciliation.fixesApplied)",
                    color: .purple
                )
            }

            Divider()

            // Status
            HStack {
                Image(systemName: reconciliation.isFullyReconciled ? "checkmark.circle.fill" : "clock.fill")
                    .foregroundColor(reconciliation.isFullyReconciled ? .green : .orange)

                Text(reconciliation.isFullyReconciled ? "Fully Reconciled" : "Partially Reconciled")
                    .font(.headline)

                Spacer()

                Text("Iterations: \(reconciliation.iterations)")
                    .foregroundColor(.secondary)
            }

            // Max discrepancy
            if reconciliation.finalMaxDiscrepancy > 0 {
                HStack {
                    Text("Max Remaining Discrepancy:")
                    Spacer()
                    Text("$\(reconciliation.finalMaxDiscrepancy as NSDecimalNumber, formatter: numberFormatter)")
                        .foregroundColor(.red)
                        .bold()
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            // Discrepancies list
            if !reconciliation.discrepancies.isEmpty {
                Divider()

                Text("Discrepancies")
                    .font(.headline)

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(reconciliation.discrepancies, id: \.id) { discrepancy in
                            DiscrepancyRow(discrepancy: discrepancy)
                        }
                    }
                }
                .frame(maxHeight: 400)
            }

            // Actions
            HStack {
                if !reconciliation.isFullyReconciled && !isReconciling {
                    Button("Run Another Iteration") {
                        // TODO: Implement iteration
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("Close") {
                    // Dismiss view
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func statBox(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .bold()
                .foregroundColor(color)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 100)
    }

    private func startReconciliation() {
        isReconciling = true
        errorMessage = nil

        Task {
            do {
                // Create services
                let claudeService = ClaudeAPIService.shared
                let reconciliationService = ReconciliationService(claudeAPIService: claudeService)
                let reviewService = TransactionReviewService(modelContext: modelContext)

                // Run reconciliation
                let result = try await reconciliationService.reconcile(
                    session: session,
                    csvRows: csvRows,
                    reviewService: reviewService,
                    modelContext: modelContext,
                    maxIterations: 3
                )

                await MainActor.run {
                    reconciliationSession = result
                    isReconciling = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Reconciliation failed: \(error.localizedDescription)"
                    isReconciling = false
                }
            }
        }
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}

struct DiscrepancyRow: View {
    let discrepancy: Discrepancy

    var body: some View {
        HStack {
            // Severity indicator
            Circle()
                .fill(severityColor)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(discrepancy.summary)
                    .font(.subheadline)
                    .bold()

                Text(discrepancy.evidence)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if discrepancy.isResolved {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            if let delta = discrepancy.delta {
                Text("$\(delta as NSDecimalNumber, formatter: numberFormatter)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
    }

    private var severityColor: Color {
        switch discrepancy.severity {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .blue
        }
    }

    private var numberFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }
}
