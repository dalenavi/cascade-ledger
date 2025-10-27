//
//  ParsePlanStore.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import Combine

@MainActor
class ParsePlanStore: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Create a new parse plan
    func createParsePlan(name: String, account: Account? = nil, institution: Institution? = nil) -> ParsePlan {
        let parsePlan = ParsePlan(name: name, account: account, institution: institution)
        modelContext.insert(parsePlan)
        try? modelContext.save()
        return parsePlan
    }

    // Update working copy
    func updateWorkingCopy(_ parsePlan: ParsePlan, definition: ParsePlanDefinition) throws {
        parsePlan.workingCopy = definition
        parsePlan.updatedAt = Date()
        try modelContext.save()
    }

    // Commit parse plan version
    func commitVersion(_ parsePlan: ParsePlan, message: String? = nil) throws -> ParsePlanVersion {
        let version = parsePlan.commitVersion(message: message)
        try modelContext.save()
        return version
    }

    // Get parse plans for account
    func getParsePlansForAccount(_ account: Account) async throws -> [ParsePlan] {
        let accountId = account.id
        let descriptor = FetchDescriptor<ParsePlan>(
            predicate: #Predicate<ParsePlan> { plan in
                plan.account?.id == accountId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // Get parse plans for institution
    func getParsePlansForInstitution(_ institution: Institution) async throws -> [ParsePlan] {
        let institutionId = institution.id
        let descriptor = FetchDescriptor<ParsePlan>(
            predicate: #Predicate<ParsePlan> { plan in
                plan.institution?.id == institutionId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // Find compatible parse plans for CSV
    func findCompatibleParsePlans(for rawFile: RawFile, account: Account) async throws -> [ParsePlan] {
        var compatiblePlans: [ParsePlan] = []

        // 1. Account's parse plans
        let accountPlans = try await getParsePlansForAccount(account)
        compatiblePlans.append(contentsOf: accountPlans)

        // 2. Institution's parse plans
        if let institution = account.institution {
            let institutionPlans = try await getParsePlansForInstitution(institution)
            compatiblePlans.append(contentsOf: institutionPlans.filter { plan in
                !compatiblePlans.contains(where: { $0.id == plan.id })
            })
        }

        // 3. Sort by most recently used
        compatiblePlans.sort { $0.updatedAt > $1.updatedAt }

        return compatiblePlans
    }

    // Clone parse plan for another account
    func cloneParsePlan(_ sourcePlan: ParsePlan, for account: Account, name: String? = nil) throws -> ParsePlan {
        let newName = name ?? "\(sourcePlan.name) (Copy)"
        let clonedPlan = ParsePlan(name: newName, account: account, institution: account.institution)

        // Copy working copy
        clonedPlan.workingCopy = sourcePlan.workingCopy

        // If source has committed versions, copy the latest
        if let latestVersion = sourcePlan.currentVersion {
            clonedPlan.workingCopy = latestVersion.definition
        }

        modelContext.insert(clonedPlan)
        try modelContext.save()
        return clonedPlan
    }

    // Delete parse plan
    func deleteParsePlan(_ parsePlan: ParsePlan) throws {
        modelContext.delete(parsePlan)
        try modelContext.save()
    }

    // Export parse plan to JSON
    func exportToJSON(_ parsePlan: ParsePlan) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let definition = parsePlan.workingCopy ?? ParsePlanDefinition()
        return try encoder.encode(definition)
    }

    // Import parse plan from JSON
    func importFromJSON(_ jsonData: Data, name: String, account: Account? = nil) throws -> ParsePlan {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let definition = try decoder.decode(ParsePlanDefinition.self, from: jsonData)
        let parsePlan = ParsePlan(name: name, account: account)
        parsePlan.workingCopy = definition

        modelContext.insert(parsePlan)
        try modelContext.save()
        return parsePlan
    }
}