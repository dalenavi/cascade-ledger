//
//  Account.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData

@Model
final class Account {
    var id: UUID
    var name: String
    var institution: Institution?

    @Relationship(deleteRule: .cascade, inverse: \ParsePlan.account)
    var parsePlans: [ParsePlan]

    var defaultParsePlanID: UUID?

    // Computed property for default parse plan
    var defaultParsePlan: ParsePlan? {
        parsePlans.first { $0.id == defaultParsePlanID }
    }

    @Relationship(deleteRule: .cascade, inverse: \ImportBatch.account)
    var importBatches: [ImportBatch]

    // Categorization mode selection (optional for backward compatibility)
    var categorizationMode: CategorizationMode?

    @Relationship(deleteRule: .cascade, inverse: \CategorizationSession.account)
    var categorizationSessions: [CategorizationSession]

    // Active categorization session (which set of transactions is "real" right now)
    var activeCategorizationSessionId: UUID?

    // Mapping support for source row transformations
    @Relationship(deleteRule: .cascade)
    var mappings: [Mapping]

    // Active mapping (determines which transactions are visible)
    var activeMappingId: UUID?

    // CSV field mapping configuration
    var csvFieldMappingJSON: Data?  // Encoded CSVFieldMapping

    // Balance instrument configuration
    // Defines which asset/cash account represents the "cash balance" for this account
    // Examples: "SPAXX" (Fidelity), "Cash USD" (banks), "VMMXX" (Vanguard)
    var balanceInstrument: String? = "Cash USD"  // Default to Cash USD

    // Categorization context for AI learning
    var categorizationContext: String?

    // Computed property with default
    var effectiveCategorizationMode: CategorizationMode {
        categorizationMode ?? .ruleBased
    }

    // Get the active categorization session
    var activeCategorizationSession: CategorizationSession? {
        guard let activeId = activeCategorizationSessionId else { return nil }
        return categorizationSessions.first { $0.id == activeId }
    }

    // Get the active mapping
    var activeMapping: Mapping? {
        guard let activeId = activeMappingId else { return nil }
        return mappings.first { $0.id == activeId }
    }

    // Get transactions from active session
    var activeTransactions: [Transaction] {
        // If mapping system is active, use mapping transactions
        if let activeMapping = activeMapping {
            return activeMapping.transactions
        }
        // Otherwise fall back to categorization session
        return activeCategorizationSession?.transactions ?? []
    }

    // Activate a categorization session
    func activate(_ session: CategorizationSession) {
        activeCategorizationSessionId = session.id
    }

    func deactivate() {
        activeCategorizationSessionId = nil
    }

    // Activate a mapping
    func activateMapping(_ mapping: Mapping) {
        activeMappingId = mapping.id
    }

    func deactivateMapping() {
        activeMappingId = nil
    }

    var createdAt: Date
    var updatedAt: Date

    init(name: String, institution: Institution? = nil) {
        self.id = UUID()
        self.name = name
        self.institution = institution
        self.parsePlans = []
        self.importBatches = []
        self.categorizationSessions = []
        self.mappings = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - CSV Field Mapping

extension Account {
    /// Decoded CSV field mapping
    var csvFieldMapping: CSVFieldMapping? {
        get {
            guard let data = csvFieldMappingJSON else { return nil }
            return try? JSONDecoder().decode(CSVFieldMapping.self, from: data)
        }
        set {
            if let mapping = newValue {
                csvFieldMappingJSON = try? JSONEncoder().encode(mapping)
            } else {
                csvFieldMappingJSON = nil
            }
            updatedAt = Date()
        }
    }

    /// Update categorization context with a new entry
    func updateCategorizationContext(_ update: String) {
        if let existing = categorizationContext, !existing.isEmpty {
            categorizationContext = "\(existing)\n\n\(update)"
        } else {
            categorizationContext = update
        }
        updatedAt = Date()
    }

    /// Clear categorization context
    func clearCategorizationContext() {
        categorizationContext = nil
        updatedAt = Date()
    }
}

enum CategorizationMode: String, Codable {
    case ruleBased = "rule_based"       // Parse Plans (traditional)
    case aiDirect = "ai_direct"         // AI Direct Categorization
}

@Model
final class Institution {
    var id: String // e.g., "fidelity", "vanguard"
    var displayName: String // e.g., "Fidelity Investments"

    @Relationship(deleteRule: .nullify)
    var accounts: [Account]

    @Relationship(deleteRule: .cascade)
    var commonParsePlans: [ParsePlan]

    init(id: String, displayName: String) {
        self.id = id
        self.displayName = displayName
        self.accounts = []
        self.commonParsePlans = []
    }
}