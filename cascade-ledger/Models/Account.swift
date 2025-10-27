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

    var createdAt: Date
    var updatedAt: Date

    init(name: String, institution: Institution? = nil) {
        self.id = UUID()
        self.name = name
        self.institution = institution
        self.parsePlans = []
        self.importBatches = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
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