//
//  JobsView.swift
//  cascade-ledger
//
//  Job management UI for monitoring and controlling background tasks
//

import SwiftUI
import SwiftData

struct JobsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var jobManager = JobManager.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Background Jobs")
                        .font(.title2)
                        .fontWeight(.bold)

                    if jobManager.activeJobs.isEmpty {
                        Text("No active jobs")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    } else {
                        Text("\(jobManager.activeJobs.count) active job\(jobManager.activeJobs.count == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    }
                }

                Spacer()

                if !jobManager.allJobs.isEmpty {
                    Button(action: {
                        jobManager.clearAllJobs()
                    }) {
                        Label("Clear All", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Job list
            if jobManager.allJobs.isEmpty {
                emptyState
            } else {
                List {
                    if !jobManager.activeJobs.isEmpty {
                        Section("Active Jobs") {
                            ForEach(jobManager.activeJobs, id: \.id) { job in
                                JobRow(job: job)
                            }
                        }
                    }

                    let completedJobs = jobManager.allJobs.filter { $0.status.isTerminal }
                    if !completedJobs.isEmpty {
                        Section("Completed") {
                            ForEach(completedJobs, id: \.id) { job in
                                JobRow(job: job)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("No Jobs")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Background jobs will appear here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JobRow: View {
    let job: Job
    @State private var jobManager = JobManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title)
                        .font(.headline)

                    if let subtitle = job.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                statusBadge
            }

            // Progress bar (if running or paused)
            if !job.status.isTerminal {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)

                    if let step = job.currentStep {
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Error message
            if let errorMessage = job.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.vertical, 4)
            }

            // Timestamps
            HStack(spacing: 12) {
                Label(job.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let duration = jobDuration(job) {
                    Label(formatDuration(duration), systemImage: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Actions
            HStack(spacing: 8) {
                if job.status == .running {
                    Button(action: {
                        Task { await jobManager.pauseJob(id: job.id) }
                    }) {
                        Label("Pause", systemImage: "pause.fill")
                            .font(.caption)
                    }
                } else if job.status.isRecoverable {
                    Button(action: {
                        Task { await jobManager.resumeJob(id: job.id) }
                    }) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption)
                    }
                }

                if !job.status.isTerminal {
                    Button(action: {
                        Task { await jobManager.cancelJob(id: job.id) }
                    }) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                if job.status.isTerminal {
                    Button(action: {
                        jobManager.deleteJob(id: job.id)
                    }) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Group {
            switch job.status {
            case .pending:
                Label("Pending", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .running:
                Label("Running", systemImage: "play.circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            case .paused:
                Label("Paused", systemImage: "pause.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            case .completed:
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            case .failed:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            case .cancelled:
                Label("Cancelled", systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .interrupted:
                Label("Interrupted", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
    }

    private func jobDuration(_ job: Job) -> TimeInterval? {
        if let completed = job.completedAt, let started = job.startedAt {
            return completed.timeIntervalSince(started)
        } else if let started = job.startedAt, job.status == .running {
            return Date().timeIntervalSince(started)
        }
        return nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}

#Preview {
    JobsView()
        .modelContainer(for: [Job.self, JobExecution.self], inMemory: true)
}
