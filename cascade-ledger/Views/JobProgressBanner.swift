//
//  JobProgressBanner.swift
//  cascade-ledger
//
//  Progress banner for job execution
//

import SwiftUI

struct JobProgressBanner: View {
    let job: Job
    let session: CategorizationSession?
    let onPause: () -> Void
    let onResume: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: statusIcon)
                    .font(.title2)
                    .foregroundColor(statusColor)

                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)

                    if let step = job.currentStep {
                        Text(step)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Action buttons
                HStack(spacing: 8) {
                    if job.status == .running {
                        Button(action: onPause) {
                            Label("Pause", systemImage: "pause.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if job.status == .paused || job.status == .interrupted {
                        Button(action: onResume) {
                            Label("Resume", systemImage: "play.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            // Progress bar
            ProgressView(value: job.progress)
                .progressViewStyle(.linear)

            // Stats
            HStack(spacing: 20) {
                if let session = session {
                    Label("\(session.transactionCount) transactions", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(job.processedItemsCount)/\(job.totalItemsCount) rows", systemImage: "chart.bar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if job.progress > 0 {
                    Text("\(Int(job.progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Error message
            if let errorMessage = job.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)

                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var statusIcon: String {
        switch job.status {
        case .pending: return "clock"
        case .running: return "play.circle.fill"
        case .paused: return "pause.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "xmark.circle"
        case .interrupted: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case .pending: return .secondary
        case .running: return .blue
        case .paused: return .orange
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .interrupted: return .yellow
        }
    }
}
