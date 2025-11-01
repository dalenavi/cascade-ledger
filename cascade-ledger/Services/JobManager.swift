//
//  JobManager.swift
//  cascade-ledger
//
//  Central service for managing background jobs
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class JobManager {
    static let shared = JobManager()

    // Observable state for UI
    private(set) var activeJobs: [Job] = []
    private(set) var allJobs: [Job] = []

    // Internal state
    private var modelContext: ModelContext?
    private var executionTasks: [UUID: Task<Void, Never>] = [:]
    private var executors: [JobType: any JobExecutor] = [:]

    private init() {}

    // MARK: - Configuration

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        registerExecutors()
        loadJobs()
        recoverInterruptedJobs()
    }

    private func registerExecutors() {
        guard let context = modelContext else { return }
        executors[.categorization] = CategorizationJobExecutor(modelContext: context)
        // Future: executors[.importCSV] = ImportJobExecutor(...)
    }

    // MARK: - Job Lifecycle

    func submitJob(_ job: Job) async throws {
        guard let context = modelContext else {
            throw JobManagerError.notConfigured
        }

        // Insert job WITHOUT relationships (executor will fetch them)
        context.insert(job)
        try context.save()

        // Reload jobs list
        loadJobs()

        // CRITICAL: Delay to let SwiftData fully propagate changes to persistent store
        // This ensures all related objects are fully persisted before executor fetches them
        // TODO: Replace with proper background context isolation
        try? await Task.sleep(for: .seconds(1))

        // Start execution (executor will fetch relationships from params)
        await startJob(job)
    }

    func startJob(_ job: Job) async {
        guard let context = modelContext,
              let executor = executors[job.type] else {
            print("⚠️ No executor registered for job type: \(job.type)")
            return
        }

        // CRITICAL: Refetch job to ensure we have a fresh instance
        let jobId = job.id
        let allJobs = (try? context.fetch(FetchDescriptor<Job>())) ?? []
        guard let freshJob = allJobs.first(where: { $0.id == jobId }) else {
            print("⚠️ Could not refetch job")
            return
        }

        // Update status
        freshJob.status = .running
        freshJob.startedAt = Date()
        freshJob.lastUpdateAt = Date()

        // Create execution record
        let execution = JobExecution(attemptNumber: freshJob.executions.count + 1, job: freshJob)
        freshJob.executions.append(execution)
        try? context.save()

        print("🚀 Starting job: \(freshJob.title)")

        // Start async task
        let task = Task {
            do {
                try await executor.execute(
                    job: freshJob,
                    context: context,
                    progressHandler: { [weak self] progress, step in
                        Task { @MainActor in
                            self?.updateJobProgress(freshJob, progress: progress, step: step)
                        }
                    }
                )

                // Success
                await self.completeJob(freshJob, execution: execution)

            } catch let error as JobError {
                // Handle job-specific errors
                await self.failJob(freshJob, execution: execution, error: error)

            } catch {
                // Handle generic errors
                await self.failJob(
                    freshJob,
                    execution: execution,
                    error: JobError.unknown(error.localizedDescription)
                )
            }
        }

        executionTasks[freshJob.id] = task
        loadJobs()
    }

    func pauseJob(id: UUID) async {
        guard let job = getJob(id: id),
              let executor = executors[job.type] else { return }

        await executor.pause(job: job)

        job.status = .paused
        job.pausedAt = Date()
        job.lastUpdateAt = Date()
        try? modelContext?.save()

        print("⏸ Paused job: \(job.title)")
        loadJobs()
    }

    func resumeJob(id: UUID) async {
        guard let job = getJob(id: id) else { return }
        print("▶️ Resuming job: \(job.title)")
        await startJob(job)
    }

    func cancelJob(id: UUID) async {
        guard let job = getJob(id: id) else { return }

        // Cancel task if running
        if let task = executionTasks[id] {
            task.cancel()
            executionTasks.removeValue(forKey: id)
        }

        // Update executor
        if let executor = executors[job.type] {
            await executor.cancel(job: job)
        }

        job.status = .cancelled
        job.completedAt = Date()
        job.lastUpdateAt = Date()
        try? modelContext?.save()

        print("🛑 Cancelled job: \(job.title)")
        loadJobs()
    }

    func deleteJob(id: UUID) {
        guard let context = modelContext,
              let job = getJob(id: id) else { return }

        // Cancel if running
        Task {
            await cancelJob(id: id)
        }

        context.delete(job)
        try? context.save()

        print("🗑️ Deleted job: \(job.title)")
        loadJobs()
    }

    func clearAllJobs() {
        guard let context = modelContext else { return }

        // Cancel all active jobs
        for job in activeJobs {
            Task {
                await cancelJob(id: job.id)
            }
        }

        // Delete all jobs
        for job in allJobs {
            context.delete(job)
        }

        try? context.save()

        print("🗑️ Cleared all jobs")
        loadJobs()
    }

    // MARK: - Progress Tracking

    private func updateJobProgress(_ job: Job, progress: Double, step: String) {
        job.progress = progress
        job.currentStep = step
        job.lastUpdateAt = Date()
        try? modelContext?.save()
        loadJobs()
    }

    private func completeJob(_ job: Job, execution: JobExecution) {
        job.status = .completed
        job.progress = 1.0
        job.completedAt = Date()
        job.lastUpdateAt = Date()

        execution.status = .completed
        execution.completedAt = Date()
        execution.durationSeconds = Date().timeIntervalSince(execution.startedAt)

        try? modelContext?.save()
        executionTasks.removeValue(forKey: job.id)
        loadJobs()

        print("✅ Job completed: \(job.title)")
    }

    private func failJob(_ job: Job, execution: JobExecution, error: JobError) {
        job.errorType = error.errorType
        job.errorMessage = error.localizedDescription

        // Check if should retry
        if error.errorType == .transient && job.retryCount < job.maxRetries {
            job.retryCount += 1
            job.status = .paused
            print("⚠️ Job failed (transient), will retry (\(job.retryCount)/\(job.maxRetries)): \(job.title)")

            // Auto-retry after delay
            Task {
                try? await Task.sleep(for: .seconds(120))
                await self.resumeJob(id: job.id)
            }
        } else {
            job.status = .failed
            job.completedAt = Date()
            print("❌ Job failed: \(job.title) - \(error.localizedDescription)")
        }

        job.lastUpdateAt = Date()

        execution.status = .failed
        execution.errorMessage = error.localizedDescription
        execution.completedAt = Date()
        execution.durationSeconds = Date().timeIntervalSince(execution.startedAt)

        try? modelContext?.save()
        executionTasks.removeValue(forKey: job.id)
        loadJobs()
    }

    // MARK: - Recovery

    private func recoverInterruptedJobs() {
        guard let context = modelContext else { return }

        // Find jobs that were running when app last closed
        // Note: SwiftData predicates don't support enum comparison well,
        // so we fetch all and filter in Swift
        let descriptor = FetchDescriptor<Job>()

        guard let allJobs = try? context.fetch(descriptor) else { return }

        let runningJobs = allJobs.filter { $0.status == .running }

        for job in runningJobs {
            print("🔄 Found interrupted job: \(job.title)")
            job.status = .interrupted
            job.errorType = .fatal
            job.errorMessage = "App restarted while job was running. You can resume this job."
            job.lastUpdateAt = Date()
        }

        try? context.save()

        if runningJobs.count > 0 {
            print("🔄 Marked \(runningJobs.count) job(s) as interrupted")
        }
    }

    // MARK: - Queries

    private func loadJobs() {
        guard let context = modelContext else { return }

        var descriptor = FetchDescriptor<Job>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        // CRITICAL: Don't load relationships - prevents cross-context issues
        descriptor.relationshipKeyPathsForPrefetching = []

        allJobs = (try? context.fetch(descriptor)) ?? []
        activeJobs = allJobs.filter { !$0.status.isTerminal }
    }

    func getJob(id: UUID) -> Job? {
        allJobs.first { $0.id == id }
    }

    func getJobsFor(account: Account) -> [Job] {
        let accountId = account.id
        return allJobs.filter { job in
            if let paramsData = job.parametersJSON,
               let params = try? JSONDecoder().decode(CategorizationJobParameters.self, from: paramsData),
               params.accountId == accountId {
                return true
            }
            return false
        }
    }

    func getJobsFor(session: CategorizationSession) -> [Job] {
        let sessionId = session.id
        return allJobs.filter { job in
            if let paramsData = job.parametersJSON,
               let params = try? JSONDecoder().decode(CategorizationJobParameters.self, from: paramsData),
               params.sessionId == sessionId {
                return true
            }
            return false
        }
    }

    func getJobsWithTag(_ tag: String) -> [Job] {
        allJobs.filter { $0.tags.contains(tag) }
    }
}

enum JobManagerError: LocalizedError {
    case notConfigured
    case noExecutor(JobType)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "JobManager not configured with ModelContext"
        case .noExecutor(let type):
            return "No executor registered for job type: \(type.rawValue)"
        }
    }
}
