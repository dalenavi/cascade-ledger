//
//  RawFileStore.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import SwiftData
import CryptoKit
import Combine

@MainActor
class RawFileStore: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // Save a raw file with SHA256 deduplication
    func saveRawFile(fileName: String, content: Data, mimeType: String = "text/csv") async throws -> RawFile {
        let hash = content.sha256Hash()

        // Check if file already exists
        if let existingFile = try await findByHash(hash: hash) {
            return existingFile
        }

        // Create new raw file
        let rawFile = RawFile(fileName: fileName, content: content, mimeType: mimeType)
        modelContext.insert(rawFile)

        try modelContext.save()
        return rawFile
    }

    // Find raw file by hash
    func findByHash(hash: String) async throws -> RawFile? {
        let descriptor = FetchDescriptor<RawFile>(
            predicate: #Predicate { $0.sha256Hash == hash }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    // Get raw file by ID
    func getRawFile(id: UUID) async throws -> RawFile? {
        let descriptor = FetchDescriptor<RawFile>(
            predicate: #Predicate { $0.id == id }
        )
        let results = try modelContext.fetch(descriptor)
        return results.first
    }

    // List all raw files
    func listRawFiles() async throws -> [RawFile] {
        let descriptor = FetchDescriptor<RawFile>(
            sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // Delete raw file if no imports reference it
    func deleteRawFile(_ rawFile: RawFile) async throws {
        guard rawFile.importBatches.isEmpty else {
            throw RawFileError.hasImports
        }

        modelContext.delete(rawFile)
        try modelContext.save()
    }

    // Get CSV content as string
    func getCSVContent(_ rawFile: RawFile) -> String? {
        guard rawFile.mimeType == "text/csv" else { return nil }
        return String(data: rawFile.content, encoding: .utf8)
    }

    // Parse CSV headers
    func parseHeaders(_ rawFile: RawFile) -> [String]? {
        guard let csvContent = getCSVContent(rawFile) else { return nil }

        let lines = csvContent.components(separatedBy: .newlines)
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }

        // Simple CSV parsing for headers (can be enhanced with proper CSV parser)
        return firstLine.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

enum RawFileError: LocalizedError {
    case hasImports
    case invalidFormat
    case decodingError

    var errorDescription: String? {
        switch self {
        case .hasImports:
            return "Cannot delete raw file that has associated imports"
        case .invalidFormat:
            return "Invalid file format"
        case .decodingError:
            return "Failed to decode file content"
        }
    }
}