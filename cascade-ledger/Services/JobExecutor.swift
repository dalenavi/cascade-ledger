//
//  JobExecutor.swift
//  cascade-ledger
//
//  Protocol for job execution strategies
//

import Foundation
import SwiftData

/// Protocol for executing specific job types
@MainActor
protocol JobExecutor {
    var jobType: JobType { get }

    /// Execute the job
    func execute(
        job: Job,
        context: ModelContext,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws

    /// Pause the job (if supported)
    func pause(job: Job) async

    /// Resume the job (if supported)
    func resume(job: Job) async

    /// Cancel the job
    func cancel(job: Job) async
}

// Default implementations
extension JobExecutor {
    func pause(job: Job) async {
        // Default: no-op
    }

    func resume(job: Job) async {
        // Default: no-op
    }

    func cancel(job: Job) async {
        // Default: no-op
    }
}
