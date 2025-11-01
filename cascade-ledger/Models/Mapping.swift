//
//  Mapping.swift
//  cascade-ledger
//
//  Represents a versioned interpretation of source data for an account
//

import Foundation
import SwiftData

/// Status of a mapping's completeness and validation
enum MappingStatus: String, Codable, CaseIterable {
    case inProgress = "in_progress"
    case complete = "complete"
    case validated = "validated"
}

/// A versioned interpretation of source data
@Model
final class Mapping {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var status: MappingStatus

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \Account.mappings)
    var account: Account?

    @Relationship(deleteRule: .cascade, inverse: \Transaction.mapping)
    var transactions: [Transaction]

    @Relationship(deleteRule: .nullify)
    var sourceFiles: [RawFile]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = .inProgress
        self.transactions = []
        self.sourceFiles = []
    }

    /// Create a new mapping by copying another
    init(from existing: Mapping, name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = .inProgress
        self.transactions = []
        self.sourceFiles = []
        self.account = existing.account
    }
}
