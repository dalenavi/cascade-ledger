//
//  Job.swift
//  cascade-ledger
//
//  Job management system for background tasks
//

import Foundation
import SwiftData

/// Persistent job entity - survives app restarts
@Model
final class Job {
    var id: UUID
    var type: JobType
    var status: JobStatus

    // Display info
    var title: String
    var subtitle: String?

    // Progress tracking (for UI and resumability)
    var progress: Double              // 0.0 to 1.0
    var currentStep: String?
    var processedItemsCount: Int      // e.g., CSV rows processed
    var totalItemsCount: Int

    // Lifecycle timestamps
    var createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
    var pausedAt: Date?
    var lastUpdateAt: Date

    // Error handling
    var errorType: JobErrorType?
    var errorMessage: String?
    var retryCount: Int
    var maxRetries: Int

    // Remote execution tracking (for Claude API jobs)
    var remoteExecutionId: String?    // Latest Claude message ID
    var remoteExecutionIdsJSON: Data? // All message IDs (chunked jobs)

    // Computed property for remoteExecutionIds
    var remoteExecutionIds: [String] {
        get {
            guard let data = remoteExecutionIdsJSON,
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            remoteExecutionIdsJSON = try? JSONEncoder().encode(newValue)
        }
    }

    // Job-specific parameters and results
    var parametersJSON: Data?         // Type-specific input params
    var resultDataJSON: Data?         // Type-specific output
    var metadataJSON: Data?           // Additional context

    // Relationships
    @Relationship var account: Account?
    @Relationship var categorizationSession: CategorizationSession?

    // Execution records (history of attempts)
    @Relationship(deleteRule: .cascade, inverse: \JobExecution.job)
    var executions: [JobExecution]

    init(id: UUID = UUID(), type: JobType, title: String) {
        self.id = id
        self.type = type
        self.status = .pending
        self.title = title
        self.progress = 0.0
        self.processedItemsCount = 0
        self.totalItemsCount = 0
        self.retryCount = 0
        self.maxRetries = 5  // Default
        self.remoteExecutionIdsJSON = try? JSONEncoder().encode([String]())
        self.executions = []
        self.createdAt = Date()
        self.lastUpdateAt = Date()
    }
}

/// Job execution attempt record (for audit trail)
@Model
final class JobExecution {
    var id: UUID
    var attemptNumber: Int

    var startedAt: Date
    var completedAt: Date?
    var status: JobStatus

    var errorMessage: String?
    var outputSummary: String?        // Brief summary of what was accomplished

    // Performance metrics
    var durationSeconds: Double
    var itemsProcessed: Int

    // API usage (for categorization jobs)
    var inputTokens: Int?
    var outputTokens: Int?
    var apiCalls: Int?

    @Relationship var job: Job?

    init(attemptNumber: Int, job: Job) {
        self.id = UUID()
        self.attemptNumber = attemptNumber
        self.startedAt = Date()
        self.status = .running
        self.durationSeconds = 0
        self.itemsProcessed = 0
        self.job = job
    }
}

enum JobType: String, Codable {
    case categorization    // AI categorization of transactions
    case importCSV         // Future: CSV import
    case reconciliation    // Future: balance reconciliation
    case export            // Future: data export
}

enum JobStatus: String, Codable {
    case pending        // Created, not started
    case running        // Currently executing
    case paused         // User paused
    case completed      // Successfully finished
    case failed         // Error occurred (non-recoverable)
    case cancelled      // User cancelled
    case interrupted    // App restarted while running (recoverable)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .pending, .running, .paused, .interrupted:
            return false
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .paused, .interrupted, .failed:
            return true  // Can retry/resume
        default:
            return false
        }
    }
}

enum JobErrorType: String, Codable {
    case transient      // Rate limit, timeout - auto-retry
    case actionable     // Credit balance, config issue - needs user action
    case fatal          // Network error, API error - mark failed
    case userCancelled  // User cancelled or paused
}
