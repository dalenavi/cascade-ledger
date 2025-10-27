//
//  ParseStudioView.swift
//  cascade-ledger
//
//  Parse Studio interface for importing financial data
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ParseStudioView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedAccount: Account?
    @ObservedObject var session: ParseStudioSession

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                ParseStudioWorkspace(
                    account: account,
                    selectedFile: $session.selectedFile,
                    parsePlan: $session.parsePlan,
                    parsePreview: $session.parsePreview,
                    isDraggingOver: $session.isDraggingOver,
                    showingAgentChat: $session.showingAgentChat,
                    chatMessages: $session.chatMessages,
                    showingFileImporter: $session.showingFileImporter,
                    importBatch: $session.importBatch,
                    isImporting: $session.isImporting,
                    modelContext: modelContext
                )
            } else {
                NoAccountSelectedView(
                    isDraggingOver: $session.isDraggingOver,
                    showingFileImporter: $session.showingFileImporter
                )
            }
        }
        .navigationTitle("Parse Studio")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    session.showingFileImporter = true
                }) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $session.showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            onCompletion: handleFileImport
        )
        .onDrop(of: [.fileURL], isTargeted: $session.isDraggingOver) { providers in
            handleFileDrop(providers)
            return true
        }
        .sheet(isPresented: $session.showingBatchMetadata) {
            if let batch = session.importBatch, let file = session.selectedFile, let account = selectedAccount {
                ImportBatchMetadataSheet(
                    batch: batch,
                    rawFile: file,
                    account: account,
                    onComplete: {
                        session.showingBatchMetadata = false
                    }
                )
            }
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            importCSVFile(from: url)
        case .failure(let error):
            print("Failed to import file: \(error)")
        }
    }

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                provider.loadObject(ofClass: URL.self) { url, error in
                    if let url = url {
                        DispatchQueue.main.async {
                            importCSVFile(from: url)
                        }
                    }
                }
            }
        }
    }

    private func importCSVFile(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        guard let account = selectedAccount else { return }

        Task {
            let rawFileStore = RawFileStore(modelContext: modelContext)
            if let rawFile = try? await rawFileStore.saveRawFile(
                fileName: url.lastPathComponent,
                content: data
            ) {
                session.selectedFile = rawFile

                // Create import batch and show metadata sheet
                let batch = ImportBatch(account: account, rawFile: rawFile)
                modelContext.insert(batch)
                session.importBatch = batch
                session.showingBatchMetadata = true
            }
        }
    }
}

struct ParseStudioWorkspace: View {
    let account: Account
    @Binding var selectedFile: RawFile?
    @Binding var parsePlan: ParsePlan?
    @Binding var parsePreview: ParsePreview?
    @Binding var isDraggingOver: Bool
    @Binding var showingAgentChat: Bool
    @Binding var chatMessages: [ChatMessage]
    @Binding var showingFileImporter: Bool
    @Binding var importBatch: ImportBatch?
    @Binding var isImporting: Bool
    let modelContext: ModelContext

    @State private var isGeneratingPreview = false

    private var parseEngine: ParseEngine {
        ParseEngine(modelContext: modelContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Account context bar at the top
            AccountContextBar(account: account)

            // Three-pane view (always full width)
            HSplitView {
                RawDataPanel(selectedFile: $selectedFile, showingFileImporter: $showingFileImporter)
                    .frame(minWidth: 300, idealWidth: 400)

                ParseRulesPanel(
                    parsePlan: $parsePlan,
                    account: account,
                    selectedFile: selectedFile,
                    showingAgentChat: $showingAgentChat
                )
                .frame(minWidth: 300, idealWidth: 400)

                ResultsPanel(
                    parsePreview: parsePreview,
                    parsePlan: parsePlan,
                    importBatch: importBatch,
                    isImporting: $isImporting
                )
                .frame(minWidth: 300, idealWidth: 400)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: parsePlan?.workingCopyData) { _, _ in
            generatePreview()
        }
        .onChange(of: selectedFile?.id) { oldValue, newValue in
            if oldValue != newValue && newValue != nil {
                // New file loaded - check if we should load existing parse plan
                if parsePlan == nil {
                    loadExistingParsePlan()
                }
            }
            generatePreview()
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack(alignment: .bottomTrailing) {
                // Floating chat window
                if showingAgentChat {
                    DraggableFloatingChatWindow(
                        parsePlan: $parsePlan,
                        account: account,
                        selectedFile: selectedFile,
                        messages: $chatMessages,
                        showingChat: $showingAgentChat
                    )
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingAgentChat)
                } else {
                    // Minimized button
                    Button(action: { showingAgentChat = true }) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Agent")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(24)
                        .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .animation(.spring(response: 0.3), value: showingAgentChat)
                }
            }
        }
        .overlay {
            if isDraggingOver {
                ZStack {
                    Color.blue.opacity(0.1)
                    VStack(spacing: 20) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        Text("Drop CSV file to import")
                            .font(.title2)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func loadExistingParsePlan() {
        // Try to load account's default parse plan
        if let defaultPlan = account.defaultParsePlan {
            print("Auto-loading account's default parse plan: \(defaultPlan.name)")
            parsePlan = defaultPlan
        } else if let firstPlan = account.parsePlans.first {
            print("Auto-loading account's parse plan: \(firstPlan.name)")
            parsePlan = firstPlan
        }
    }

    private func generatePreview() {
        guard let file = selectedFile, let plan = parsePlan else {
            parsePreview = nil
            return
        }

        // Only generate preview if we have field mappings
        guard let workingCopy = plan.workingCopy, !workingCopy.schema.fields.isEmpty else {
            parsePreview = nil
            return
        }

        isGeneratingPreview = true

        Task {
            do {
                // Process ALL rows immediately
                let preview = try await parseEngine.previewParse(
                    rawFile: file,
                    parsePlan: plan
                )

                await MainActor.run {
                    parsePreview = preview
                    isGeneratingPreview = false
                }
            } catch {
                print("Preview generation failed: \(error)")
                await MainActor.run {
                    isGeneratingPreview = false
                }
            }
        }
    }
}

struct AccountContextBar: View {
    let account: Account

    var body: some View {
        HStack {
            Label(account.name, systemImage: "banknote")
                .font(.headline)

            if let institution = account.institution {
                Text("•")
                    .foregroundColor(.secondary)
                Text(institution.displayName)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let parsePlan = account.defaultParsePlan {
                Label(parsePlan.name, systemImage: "doc.badge.gearshape")
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}

struct RawDataPanel: View {
    @Binding var selectedFile: RawFile?
    @Binding var showingFileImporter: Bool
    @State private var viewMode: CSVViewMode = .table
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Label("Raw Data", systemImage: "doc.text")
                    .font(.headline)

                if selectedFile != nil {
                    Picker("View Mode", selection: $viewMode) {
                        Label("Table", systemImage: "tablecells").tag(CSVViewMode.table)
                        Label("Raw", systemImage: "doc.plaintext").tag(CSVViewMode.raw)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }

                Spacer()
                Button(action: { showingFileImporter = true }) {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            if let file = selectedFile,
               let content = String(data: file.content, encoding: .utf8) {
                if viewMode == .table {
                    CSVTableView(content: content)
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        Text(content)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No file selected")
                        .font(.title2)

                    Text("Import a CSV file to begin")
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Button(action: { showingFileImporter = true }) {
                            Label("Choose File", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)

                        Text("or drag & drop a CSV file here")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

struct ParseRulesPanel: View {
    @Binding var parsePlan: ParsePlan?
    let account: Account
    let selectedFile: RawFile?
    @Binding var showingAgentChat: Bool

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Label("Parse Rules", systemImage: "doc.badge.gearshape")
                    .font(.headline)
                Spacer()
                if parsePlan != nil {
                    Button("Edit", action: { showingAgentChat = true })
                        .buttonStyle(.borderless)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            if let plan = parsePlan {
                ParsePlanEditorView(parsePlan: plan, showingAgentChat: $showingAgentChat)
            } else if selectedFile != nil {
                // Parse plan creation/selection state
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)

                    if account.parsePlans.isEmpty {
                        Text("Ready to create a parse plan")
                            .font(.title2)

                        Text("Claude can help you map this CSV to your ledger format")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    } else {
                        Text("Reusing existing parse plan")
                            .font(.title2)

                        Text("Account has \(account.parsePlans.count) parse plan(s). Claude will use and update the existing plan.")
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)
                    }

                    if ClaudeAPIService.shared.isConfigured {
                        Button(action: {
                            createParsePlan()
                            showingAgentChat = true
                        }) {
                            if account.parsePlans.isEmpty {
                                Label("Ask Claude to Create Parse Plan", systemImage: "sparkles")
                            } else {
                                Label("Ask Claude to Review/Update Parse Plan", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        VStack(spacing: 12) {
                            Label("Configure API Key First", systemImage: "key.fill")
                                .foregroundColor(.orange)

                            Text("Go to Settings to add your Anthropic API key")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Import a CSV first",
                    systemImage: "doc.badge.plus",
                    description: Text("Load a CSV file to create a parse plan")
                )
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func loadExistingParsePlan() {
        // Try to load account's default parse plan
        if let defaultPlan = account.defaultParsePlan {
            print("Auto-loading account's default parse plan: \(defaultPlan.name) v\(defaultPlan.currentVersion?.versionNumber ?? 0)")
            parsePlan = defaultPlan
        } else if let firstPlan = account.parsePlans.first {
            print("Auto-loading account's first parse plan: \(firstPlan.name)")
            parsePlan = firstPlan
        }
    }

    private func createParsePlan() {
        if parsePlan != nil {
            return // Already have a plan
        }

        // Check if account has a default parse plan
        if let defaultPlan = account.defaultParsePlan {
            print("Reusing account's default parse plan: \(defaultPlan.name)")
            parsePlan = defaultPlan
            return
        }

        // Check if account has any parse plans
        if let existingPlan = account.parsePlans.first {
            print("Reusing account's existing parse plan: \(existingPlan.name)")
            parsePlan = existingPlan
            return
        }

        // Create new parse plan only if none exist
        if let file = selectedFile {
            let plan = ParsePlan(
                name: "Parse Plan for \(account.name)",
                account: account,
                institution: account.institution
            )
            modelContext.insert(plan)
            parsePlan = plan
            print("Created new parse plan: \(plan.name)")
        }
    }
}

struct ParsePlanEditorView: View {
    let parsePlan: ParsePlan
    @Binding var showingAgentChat: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(parsePlan.name)
                            .font(.title3)
                        if let currentVersion = parsePlan.currentVersion {
                            Text("v\(currentVersion.versionNumber) (committed)")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if parsePlan.versions.isEmpty {
                            Text("Not yet committed")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text("Working copy (uncommitted changes)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    Spacer()
                    Button(action: { showingAgentChat = true }) {
                        Label("Ask Claude", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                }

                // Display current parse plan configuration
                if let workingCopy = parsePlan.workingCopy {
                    GroupBox("Field Mappings") {
                        if workingCopy.schema.fields.isEmpty {
                            Text("No field mappings configured yet")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(workingCopy.schema.fields, id: \.name) { field in
                                HStack {
                                    Text(field.name)
                                        .fontWeight(.medium)
                                    Image(systemName: "arrow.right")
                                        .foregroundColor(.secondary)
                                    Text(field.mapping ?? field.name)
                                        .foregroundColor(.blue)
                                    Spacer()
                                    Text(field.type.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Divider()
                            }
                        }
                    }
                    .padding(.top)
                } else {
                    Text("Click 'Ask Claude' to configure this parse plan")
                        .foregroundColor(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

struct ResultsPanel: View {
    let parsePreview: ParsePreview?
    let parsePlan: ParsePlan?
    let importBatch: ImportBatch?
    @Binding var isImporting: Bool

    @State private var showingCommitSheet = false
    @State private var showingImportConfirmation = false

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Label("Results", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()

                if let preview = parsePreview {
                    Text("\(Int(preview.successRate * 100))% success")
                        .foregroundColor(preview.successRate > 0.9 ? .green : .orange)

                    if let plan = parsePlan {
                        if plan.currentVersion == nil {
                            Button("Commit Parse Plan") {
                                showingCommitSheet = true
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Import Data") {
                                showingImportConfirmation = true
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isImporting)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content
            if let preview = parsePreview {
                ParseResultsView(preview: preview)
            } else {
                ContentUnavailableView(
                    "No preview",
                    systemImage: "eye.slash",
                    description: Text("Configure parse rules to see preview")
                )
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .sheet(isPresented: $showingCommitSheet) {
            if let plan = parsePlan {
                CommitParsePlanSheet(parsePlan: plan)
            }
        }
        .alert("Import Data?", isPresented: $showingImportConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Import") {
                executeImport()
            }
        } message: {
            if let preview = parsePreview {
                Text("Import \(preview.transformedRows.filter { $0.isValid }.count) transactions into the ledger?")
            }
        }
    }

    private func executeImport() {
        guard let plan = parsePlan,
              let version = plan.currentVersion,
              let batch = importBatch else {
            return
        }

        isImporting = true

        Task {
            do {
                let parseEngine = ParseEngine(modelContext: modelContext)
                let parseRun = try await parseEngine.executeImport(
                    importBatch: batch,
                    parsePlanVersion: version
                ) { progress in
                    // Update progress
                }

                await MainActor.run {
                    isImporting = false
                    // Show success
                }
            } catch {
                print("Import failed: \(error)")
                await MainActor.run {
                    isImporting = false
                }
            }
        }
    }
}

struct ParseResultsView: View {
    let preview: ParsePreview

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Stats header
                HStack(spacing: 16) {
                    StatBadge(
                        label: "Total",
                        value: "\(preview.totalRows)",
                        color: .blue
                    )
                    StatBadge(
                        label: "Sampled",
                        value: "\(preview.sampledRows)",
                        color: .purple
                    )
                    StatBadge(
                        label: "Success",
                        value: String(format: "%.0f%%", preview.successRate * 100),
                        color: preview.successRate > 0.9 ? .green : .orange
                    )
                    StatBadge(
                        label: "Errors",
                        value: "\(preview.errors.count)",
                        color: preview.errors.isEmpty ? .green : .red
                    )
                }
                .padding()

                Divider()

                // Show errors if any
                if !preview.errors.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Parse Errors", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundColor(.red)

                            ForEach(preview.errors.prefix(5), id: \.rowNumber) { error in
                                HStack {
                                    Text("Row \(error.rowNumber):")
                                        .fontWeight(.medium)
                                    Text(error.message)
                                        .foregroundColor(.secondary)
                                }
                                .font(.caption)
                            }

                            if preview.errors.count > 5 {
                                Text("+ \(preview.errors.count - 5) more errors")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                // Show successful transformations
                if !preview.transformedRows.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label("Transformed Data (\(preview.transformedRows.count) rows)", systemImage: "checkmark.circle.fill")
                                    .font(.headline)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("Showing all rows")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            ScrollView(.horizontal, showsIndicators: true) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(preview.transformedRows) { row in
                                        HStack(spacing: 8) {
                                            Text("Row \(row.rowNumber)")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                                .frame(width: 50)

                                            if row.isValid {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.green)
                                                    .font(.caption)
                                            } else {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.red)
                                                    .font(.caption)
                                            }

                                            TransformedRowView(row: row)
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct TransformedRowView: View {
    let row: TransformedRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(row.transformedData.keys.sorted()), id: \.self) { key in
                HStack {
                    Text(key + ":")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(width: 120, alignment: .trailing)
                    Text(String(describing: row.transformedData[key] ?? "nil"))
                        .font(.caption)
                        .lineLimit(1)
                }
            }
        }
        .padding(4)
    }
}

struct NoAccountSelectedView: View {
    @Binding var isDraggingOver: Bool
    @Binding var showingFileImporter: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "banknote.fill")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Select an Account")
                .font(.largeTitle)

            Text("Please select an account from the Accounts tab before importing data")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 16) {
                Button("Select Account") {
                    // Switch to accounts tab
                }
                .buttonStyle(.borderedProminent)

                Button("Import File Anyway") {
                    showingFileImporter = true
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDraggingOver {
                ZStack {
                    Color.orange.opacity(0.1)
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 60))
                            .foregroundColor(.orange)
                        Text("Please select an account first")
                            .font(.title2)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}

enum CSVViewMode {
    case raw
    case table
}

struct CSVTableView: View {
    let content: String
    @State private var csvData: CSVData?

    var body: some View {
        Group {
            if let csvData = csvData {
                if #available(macOS 12, *) {
                    CSVTableWithTable(csvData: csvData)
                } else {
                    CSVTableFallback(csvData: csvData)
                }
            } else {
                ProgressView("Parsing CSV...")
                    .padding()
            }
        }
        .onAppear {
            parseCSV()
        }
    }

    private func parseCSV() {
        Task {
            let parser = CSVParser()
            if let parsed = try? parser.parse(content) {
                await MainActor.run {
                    csvData = parsed
                }
            }
        }
    }
}

@available(macOS 12, *)
struct CSVTableWithTable: View {
    let csvData: CSVData

    private var tableRows: [CSVRow] {
        csvData.rows.indices.map { CSVRow(index: $0, cells: csvData.rows[$0]) }
    }

    var body: some View {
        // Use fallback for now - Table with dynamic columns is complex
        CSVTableFallback(csvData: csvData)
    }
}

struct CSVTableFallback: View {
    let csvData: CSVData
    private let columnWidth: CGFloat = 150

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(csvData.headers.indices, id: \.self) { index in
                        Text(csvData.headers[index])
                            .font(.caption)
                            .fontWeight(.bold)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(8)
                            .frame(width: columnWidth, alignment: .leading)
                            .background(Color(NSColor.controlBackgroundColor))
                            .border(Color(NSColor.separatorColor), width: 0.5)
                    }
                }

                // Data rows
                ForEach(csvData.rows.indices, id: \.self) { rowIndex in
                    HStack(spacing: 0) {
                        ForEach(csvData.rows[rowIndex].indices, id: \.self) { colIndex in
                            Text(csvData.rows[rowIndex][colIndex])
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(8)
                                .frame(width: columnWidth, alignment: .leading)
                                .border(Color(NSColor.separatorColor), width: 0.5)
                                .help(csvData.rows[rowIndex][colIndex]) // Tooltip shows full content
                        }
                    }
                    .background(rowIndex % 2 == 0 ? Color.clear : Color(NSColor.controlBackgroundColor).opacity(0.3))
                }
            }
        }
    }
}

struct CSVRow: Identifiable {
    let id: Int
    let cells: [String]

    init(index: Int, cells: [String]) {
        self.id = index
        self.cells = cells
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

extension ModelContainer {
    static var preview: ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Account.self, Institution.self, ImportBatch.self,
            RawFile.self, ParsePlan.self, ParsePlanVersion.self,
            LedgerEntry.self, ParseRun.self,
            configurations: config
        )
        return container
    }
}