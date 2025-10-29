//
//  CategorizationJobExecutor.swift
//  cascade-ledger
//
//  Executor for AI categorization jobs
//

import Foundation
import SwiftData
import Combine

@MainActor
class CategorizationJobExecutor: JobExecutor {
    var jobType: JobType { .categorization }

    private let modelContext: ModelContext
    private var currentService: DirectCategorizationService?
    private var cancellables = Set<AnyCancellable>()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func execute(
        job: Job,
        context: ModelContext,
        progressHandler: @escaping (Double, String) -> Void
    ) async throws {
        // Decode parameters
        guard let parametersData = job.parametersJSON,
              let params = try? JSONDecoder().decode(CategorizationJobParameters.self, from: parametersData) else {
            throw JobError.fatal("Failed to decode job parameters")
        }

        // Get account and session
        guard let account = try? context.fetch(
            FetchDescriptor<Account>(predicate: #Predicate { $0.id == params.accountId })
        ).first else {
            throw JobError.fatal("Account not found")
        }

        guard let session = try? context.fetch(
            FetchDescriptor<CategorizationSession>(predicate: #Predicate { $0.id == params.sessionId })
        ).first else {
            throw JobError.fatal("Categorization session not found")
        }

        // Create service
        let service = DirectCategorizationService(modelContext: context)
        currentService = service

        // Observe service progress
        service.$status
            .sink { status in
                progressHandler(service.progress, service.currentStep)
            }
            .store(in: &cancellables)

        // Run categorization
        do {
            let resultSession = try await service.categorizeRows(
                csvRows: params.csvRows,
                headers: params.headers,
                account: account,
                existingSession: session
            )

            // Store result
            let result = CategorizationJobResult(
                sessionId: resultSession.id,
                transactionsCreated: resultSession.transactionCount,
                rowsProcessed: resultSession.processedRowsCount,
                balanceAccuracy: nil,  // TODO: Calculate from balance discrepancies
                warnings: [],
                totalInputTokens: resultSession.inputTokens,
                totalOutputTokens: resultSession.outputTokens,
                totalAPITime: resultSession.durationSeconds
            )

            job.resultDataJSON = try JSONEncoder().encode(result)

        } catch let error as ClaudeAPIError {
            // Map Claude API errors to job errors
            if case .httpError(let statusCode, let body, _) = error {
                if statusCode == 429 {
                    throw JobError.transient("Rate limit exceeded - will retry")
                } else if statusCode == 400 && body.contains("credit balance is too low") {
                    throw JobError.actionable("Credit balance too low. Add credits at https://console.anthropic.com/settings/plans")
                } else {
                    throw JobError.fatal("API error (\(statusCode)): \(body)")
                }
            } else if case .networkError(let hostname, let details) = error {
                throw JobError.fatal("Network error connecting to \(hostname): \(details)")
            } else {
                throw JobError.fatal(error.localizedDescription)
            }
        } catch {
            throw JobError.unknown(error.localizedDescription)
        }
    }

    func pause(job: Job) async {
        currentService?.pause()
    }

    func resume(job: Job) async {
        currentService?.resume()
    }

    func cancel(job: Job) async {
        currentService?.pause()
        cancellables.removeAll()
        currentService = nil
    }
}

/// Job-specific errors
enum JobError: LocalizedError {
    case transient(String)       // Auto-retry
    case actionable(String)      // User action needed
    case fatal(String)           // Mark failed
    case cancelled               // User cancelled
    case unknown(String)

    var errorType: JobErrorType {
        switch self {
        case .transient: return .transient
        case .actionable: return .actionable
        case .fatal: return .fatal
        case .cancelled: return .userCancelled
        case .unknown: return .fatal
        }
    }

    var errorDescription: String? {
        switch self {
        case .transient(let msg): return msg
        case .actionable(let msg): return msg
        case .fatal(let msg): return msg
        case .cancelled: return "Job cancelled by user"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}
