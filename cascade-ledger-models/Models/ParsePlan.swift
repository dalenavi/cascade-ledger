//
//  ParsePlan.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData

@Model
final class ParsePlan {
    var id: UUID
    var name: String
    var planDescription: String?

    @Relationship
    var account: Account?

    @Relationship
    var institution: Institution?

    // Working copy - mutable until committed (stored as Data)
    var workingCopyData: Data?

    var workingCopy: ParsePlanDefinition? {
        get {
            guard let data = workingCopyData else { return nil }
            return try? JSONDecoder().decode(ParsePlanDefinition.self, from: data)
        }
        set {
            guard let newValue = newValue else {
                workingCopyData = nil
                return
            }
            workingCopyData = try? JSONEncoder().encode(newValue)
        }
    }

    @Relationship(deleteRule: .cascade, inverse: \ParsePlanVersion.parsePlan)
    var versions: [ParsePlanVersion]

    var currentVersionID: UUID?

    // Computed property for current version
    var currentVersion: ParsePlanVersion? {
        versions.first { $0.id == currentVersionID }
    }

    var createdAt: Date
    var updatedAt: Date

    init(name: String, account: Account? = nil, institution: Institution? = nil) {
        self.id = UUID()
        self.name = name
        self.account = account
        self.institution = institution
        let defaultDefinition = ParsePlanDefinition()
        self.workingCopyData = try? JSONEncoder().encode(defaultDefinition)
        self.versions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // Commit the working copy as a new version
    func commitVersion(message: String? = nil) -> ParsePlanVersion {
        let newVersion = ParsePlanVersion(
            parsePlan: self,
            definition: workingCopy ?? ParsePlanDefinition(),
            parentVersion: currentVersion,
            message: message
        )
        versions.append(newVersion)
        currentVersionID = newVersion.id
        updatedAt = Date()
        return newVersion
    }
}

@Model
final class ParsePlanVersion {
    var id: UUID
    var versionNumber: Int
    var commitMessage: String?

    @Relationship
    var parsePlan: ParsePlan?

    @Relationship
    var parentVersion: ParsePlanVersion?

    var definitionData: Data

    var definition: ParsePlanDefinition {
        get {
            (try? JSONDecoder().decode(ParsePlanDefinition.self, from: definitionData)) ?? ParsePlanDefinition()
        }
        set {
            definitionData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    @Relationship(deleteRule: .nullify)
    var importBatches: [ImportBatch]

    var committedAt: Date

    init(parsePlan: ParsePlan, definition: ParsePlanDefinition, parentVersion: ParsePlanVersion? = nil, message: String? = nil) {
        self.id = UUID()
        self.parsePlan = parsePlan
        self.definitionData = (try? JSONEncoder().encode(definition)) ?? Data()
        self.parentVersion = parentVersion
        self.commitMessage = message
        self.importBatches = []
        self.committedAt = Date()

        // Calculate version number
        if let parent = parentVersion {
            self.versionNumber = parent.versionNumber + 1
        } else {
            self.versionNumber = 1
        }
    }
}

// Parse plan definition using Frictionless standards
struct ParsePlanDefinition: Codable {
    var dialect: CSVDialect
    var schema: TableSchema
    var transforms: [Transform]
    var validations: [ValidationRule]

    init() {
        self.dialect = CSVDialect()
        self.schema = TableSchema()
        self.transforms = []
        self.validations = []
    }
}

// Frictionless CSV Dialect
struct CSVDialect: Codable {
    var delimiter: String = ","
    var lineTerminator: String = "\n"
    var quoteChar: String = "\""
    var doubleQuote: Bool = true
    var skipInitialSpace: Bool = false
    var header: Bool = true
    var encoding: String = "UTF-8"
}

// Frictionless Table Schema
struct TableSchema: Codable {
    var fields: [Field]
    var primaryKey: [String]?
    var missingValues: [String]?

    init() {
        self.fields = []
        self.missingValues = ["", "NA", "N/A", "null"]
    }
}

struct Field: Codable {
    var name: String
    var type: FieldType
    var format: String?
    var constraints: FieldConstraints?
    var mapping: String? // Maps to canonical field name
}

enum FieldType: String, Codable, CaseIterable {
    case string
    case number
    case integer
    case boolean
    case date
    case datetime
    case currency
}

struct FieldConstraints: Codable {
    var required: Bool?
    var unique: Bool?
    var minimum: Double?
    var maximum: Double?
    var minLength: Int?
    var maxLength: Int?
    var pattern: String?
    var enumValues: [String]?
}

// Transform using JSONata/JOLT
struct Transform: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var type: TransformType
    var expression: String // JSONata expression or JOLT spec
    var targetField: String?
}

enum TransformType: String, Codable, CaseIterable {
    case jsonata
    case jolt
    case regex
    case calculation
}

// Validation rules
struct ValidationRule: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var type: ValidationType
    var expression: String
    var errorMessage: String
    var severity: ValidationSeverity
}

enum ValidationType: String, Codable, CaseIterable {
    case required
    case format
    case range
    case uniqueness
    case consistency
    case custom
}

enum ValidationSeverity: String, Codable, CaseIterable {
    case error
    case warning
    case info
}