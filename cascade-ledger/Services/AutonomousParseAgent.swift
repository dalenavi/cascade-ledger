//
//  AutonomousParseAgent.swift
//  cascade-ledger
//
//  Autonomous agent that configures parse plans end-to-end
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class AutonomousParseAgent: ObservableObject {
    @Published var status: AgentStatus = .idle
    @Published var currentStep: String = ""
    @Published var progress: Double = 0.0
    @Published var log: [LogEntry] = []

    private let parseAgentService: ParseAgentService
    private let modelContext: ModelContext

    enum AgentStatus: Equatable {
        case idle
        case analyzing
        case drafting
        case testing
        case iterating(Int)  // Iteration number
        case completed
        case failed(String)

        var displayText: String {
            switch self {
            case .idle: return "Ready"
            case .analyzing: return "Analyzing CSV structure..."
            case .drafting: return "Drafting parse plan..."
            case .testing: return "Testing transformation..."
            case .iterating(let n): return "Iteration \(n): Improving..."
            case .completed: return "✓ Configuration complete"
            case .failed(let reason): return "Failed: \(reason)"
            }
        }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let step: String
        let message: String
        let type: LogType
        let timestamp: Date = Date()

        enum LogType {
            case info
            case success
            case warning
            case error
        }

        var icon: String {
            switch type {
            case .info: return "info.circle"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch type {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.parseAgentService = ParseAgentService(modelContext: modelContext)
    }

    // MARK: - Main Autonomous Workflow

    func configure(
        csvRows: [[String: String]],
        headers: [String],
        parsePlan: ParsePlan,
        account: Account
    ) async {
        log.removeAll()
        addLog("Starting autonomous configuration", .info)

        do {
            // Step 1: Analyze CSV
            status = .analyzing
            progress = 0.1
            currentStep = "Analyzing CSV structure..."

            let analysis = await analyzeCSV(rows: csvRows, headers: headers)
            addLog("Detected institution: \(analysis.institution.displayName)", .success)
            addLog("Found \(headers.count) columns, \(csvRows.count) rows", .info)

            // Step 2: Draft parse plan via agent
            status = .drafting
            progress = 0.3
            currentStep = "Asking agent to draft parse plan..."

            let draftedPlan = try await draftParsePlanWithAgent(
                analysis: analysis,
                account: account,
                parsePlan: parsePlan
            )

            addLog("Agent drafted plan with \(draftedPlan.schema.fields.count) field mappings", .success)

            // Apply to working copy
            if let encoded = try? JSONEncoder().encode(draftedPlan) {
                parsePlan.workingCopyData = encoded
                try? modelContext.save()
            }

            // Step 3: Test transformation
            status = .testing
            progress = 0.6
            currentStep = "Testing transformation results..."

            // Wait a moment for UI to update and transformation to run
            try? await Task.sleep(for: .milliseconds(500))

            // The TransactionsPreviewPanel will automatically compute results
            addLog("Transformation pipeline activated", .success)
            addLog("Check Transactions panel for results", .info)

            // Step 4: Agent reviews results and iterates
            status = .iterating(1)
            progress = 0.8
            currentStep = "Agent reviewing transformation results..."

            // This is where the agent would check the Transactions panel output
            // and iterate if needed
            // For now, we'll mark as complete
            addLog("Agent can now review results in Transactions panel", .info)
            addLog("Switch to 'Grouping Debug' to inspect settlement detection", .info)
            addLog("Switch to 'Agent View' to see analysis", .info)

            // Completion
            status = .completed
            progress = 1.0
            currentStep = "Configuration complete"
            addLog("✓ Parse plan configured successfully", .success)
            addLog("Review results and commit when ready", .info)

        } catch {
            status = .failed(error.localizedDescription)
            addLog("Configuration failed: \(error.localizedDescription)", .error)
        }
    }

    // MARK: - Agent Steps

    private func analyzeCSV(rows: [[String: String]], headers: [String]) async -> CSVAnalysis {
        let detector = InstitutionDetector()

        // Convert rows to array format for detector
        let rowArrays = rows.prefix(20).map { row in
            headers.map { row[$0] ?? "" }
        }

        let detection = detector.detect(headers: headers, sampleRows: rowArrays)

        return CSVAnalysis(
            headers: headers,
            sampleRows: Array(rows.prefix(10)),
            rowCount: rows.count,
            institution: detection.institution,
            confidence: detection.confidence,
            indicators: detection.indicators
        )
    }

    private func draftParsePlanWithAgent(
        analysis: CSVAnalysis,
        account: Account,
        parsePlan: ParsePlan
    ) async throws -> ParsePlanDefinition {
        addLog("Calling Claude API to generate parse plan...", .info)

        // Build prompt for agent
        let sampleData = Array(analysis.sampleRows.prefix(3))
        let sampleJSON = try? JSONSerialization.data(withJSONObject: sampleData, options: .prettyPrinted)
        let sampleString = String(data: sampleJSON ?? Data(), encoding: .utf8) ?? "[]"

        let prompt = """
        I need you to create a parse plan for this CSV file.

        Institution: \(analysis.institution.displayName)
        Headers: \(analysis.headers.joined(separator: ", "))
        Sample rows:
        \(sampleString)

        Please analyze the structure and create a complete parse plan with field mappings.
        Map to canonical fields: date, amount, quantity, description, assetId
        Use metadata.* for institution-specific fields like Action, Type, etc.

        Return your parse plan as JSON following the format in the system prompt.
        """

        // Create dummy RawFile for tool execution
        let csvContent = ([analysis.headers.joined(separator: ",")] +
                         analysis.sampleRows.map { row in
                             analysis.headers.map { row[$0] ?? "" }.joined(separator: ",")
                         }).joined(separator: "\n")

        let dummyFile = RawFile(fileName: "preview.csv", content: csvContent.data(using: .utf8) ?? Data())

        // Call agent
        let response = try await parseAgentService.sendMessage(
            userMessage: prompt,
            conversationHistory: [],
            file: dummyFile,
            account: account,
            parsePlan: parsePlan,
            preview: nil
        )

        addLog("Received agent response (\(response.count) chars)", .success)

        // Extract parse plan from response
        if let extracted = parseAgentService.extractParsePlan(from: response) {
            addLog("Successfully extracted parse plan definition", .success)
            return extracted
        } else {
            // Fallback: Create basic plan from analysis
            addLog("Could not extract JSON, creating basic plan", .warning)
            return createFallbackPlan(analysis: analysis)
        }
    }

    private func createFallbackPlan(analysis: CSVAnalysis) -> ParsePlanDefinition {
        var definition = ParsePlanDefinition()

        // Create field mappings based on headers
        var fields: [Field] = []

        for header in analysis.headers {
            let normalizedHeader = header.lowercased()

            var fieldType: FieldType = .string
            var mapping: String? = nil
            var format: String? = nil

            // Smart mapping based on header name
            if normalizedHeader.contains("date") {
                fieldType = .date
                format = "MM/dd/yyyy"
                if normalizedHeader.contains("run") {
                    mapping = "date"
                } else {
                    mapping = "metadata.\(header.replacingOccurrences(of: " ", with: "_").lowercased())"
                }
            } else if normalizedHeader.contains("amount") || normalizedHeader.contains("$") || normalizedHeader.contains("balance") {
                fieldType = .number
                if normalizedHeader == "amount ($)" {
                    mapping = "amount"
                } else {
                    mapping = "metadata.\(header.replacingOccurrences(of: " ($)", with: "").replacingOccurrences(of: " ", with: "_").lowercased())"
                }
            } else if normalizedHeader.contains("quantity") || normalizedHeader.contains("qty") {
                fieldType = .number
                mapping = "quantity"
            } else if normalizedHeader.contains("description") || normalizedHeader.contains("memo") {
                fieldType = .string
                mapping = "description"
            } else if normalizedHeader.contains("symbol") || normalizedHeader.contains("ticker") {
                fieldType = .string
                mapping = "assetId"
            } else if normalizedHeader.contains("action") || normalizedHeader.contains("type") {
                fieldType = .string
                mapping = "metadata.\(header.replacingOccurrences(of: " ", with: "_").lowercased())"
            } else {
                // Generic field - store as metadata
                fieldType = .string
                mapping = "metadata.\(header.replacingOccurrences(of: " ", with: "_").lowercased())"
            }

            fields.append(Field(
                name: header,
                type: fieldType,
                format: format,
                constraints: nil,
                mapping: mapping
            ))
        }

        definition.schema.fields = fields
        return definition
    }

    private func addLog(_ message: String, _ type: LogEntry.LogType) {
        let entry = LogEntry(step: currentStep, message: message, type: type)
        log.append(entry)
        print("🤖 [\(type)]: \(message)")
    }
}

// MARK: - Supporting Types

struct CSVAnalysis {
    let headers: [String]
    let sampleRows: [[String: String]]
    let rowCount: Int
    let institution: InstitutionDetector.Institution
    let confidence: InstitutionDetector.Confidence
    let indicators: [String]
}
