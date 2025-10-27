//
//  ParseStudioSession.swift
//  cascade-ledger
//
//  Persistent session state for Parse Studio
//

import Foundation
import SwiftData
import Combine

@MainActor
class ParseStudioSession: ObservableObject {
    // File and parse state
    @Published var selectedFile: RawFile?
    @Published var parsePlan: ParsePlan?
    @Published var parsePreview: ParsePreview?
    @Published var importBatch: ImportBatch?

    // UI state
    @Published var showingAgentChat = false
    @Published var chatMessages: [ChatMessage] = []
    @Published var showingFileImporter = false
    @Published var showingBatchMetadata = false

    // Flags
    @Published var isDraggingOver = false
    @Published var isImporting = false

    init() {}

    // Reset session (when switching accounts, for example)
    func reset() {
        selectedFile = nil
        parsePlan = nil
        parsePreview = nil
        importBatch = nil
        showingAgentChat = false
        chatMessages = []
        showingFileImporter = false
        showingBatchMetadata = false
        isDraggingOver = false
        isImporting = false
    }

    // Clear just the current import (but keep account context)
    func clearCurrentImport() {
        selectedFile = nil
        parsePlan = nil
        parsePreview = nil
        importBatch = nil
        chatMessages = []
    }
}
