//
//  ParsePlanVersionsPanel.swift
//  cascade-ledger
//
//  Version-based parse plan management
//

import SwiftUI
import SwiftData

struct ParsePlanVersionsPanel: View {
    let account: Account
    let selectedBatches: Set<UUID>
    @Binding var selectedVersion: ParsePlanVersion?
    @Binding var selectedCategorizationSession: CategorizationSession?
    @Binding var parsePlan: ParsePlan?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportBatch.timestamp) private var allBatches: [ImportBatch]
    @Query(sort: \CategorizationBatch.batchNumber) private var allCategorizationBatches: [CategorizationBatch]

    @State private var showingCreateVersion = false
    @State private var showingEditWorkingCopy = false
    @State private var showingAgentOverlay = false
    @State private var agent: AutonomousParseAgent?
    @State private var directService: DirectCategorizationService?
    @State private var showingErrorAlert = false
    @State private var lastError: CategorizationError?
    @State private var pendingCategorizationData: (rows: [[String: String]], headers: [String])?
    @State private var selectedBatchForDetail: CategorizationBatch?
    @State private var showingBatchDetail = false
    @State private var showingClearConfirm = false

    private var accountBatches: [ImportBatch] {
        allBatches.filter { $0.account?.id == account.id && selectedBatches.contains($0.id) }
    }

    private var versions: [ParsePlanVersion] {
        parsePlan?.versions.sorted(by: { $0.versionNumber > $1.versionNumber }) ?? []
    }

    private var hasWorkingCopy: Bool {
        parsePlan?.workingCopy != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Categorization")
                        .font(.headline)

                    Picker("Mode", selection: Binding(
                        get: { account.effectiveCategorizationMode },
                        set: { newMode in
                            account.categorizationMode = newMode
                            try? modelContext.save()
                        }
                    )) {
                        Text("Parse Rules").tag(CategorizationMode.ruleBased)
                        Text("AI Direct").tag(CategorizationMode.aiDirect)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }

                Spacer()

                HStack(spacing: 8) {
                    if !accountBatches.isEmpty {
                        if let service = directService {
                            if case .processing = service.status {
                                Button(action: { service.pause() }) {
                                    Label("Pause", systemImage: "pause.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else if case .paused = service.status {
                                Button(action: activateAgent) {
                                    Label("Resume", systemImage: "play.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(.purple)
                            } else {
                                Button(action: activateAgent) {
                                    Label("Agent", systemImage: "sparkles")
                                        .font(.caption)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .tint(.purple)
                            }
                        } else {
                            Button(action: activateAgent) {
                                Label("Agent", systemImage: "sparkles")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(.purple)
                        }
                    }

                    Menu {
                        if account.effectiveCategorizationMode == .ruleBased {
                            Button("Create New Parse Plan", action: createNewParsePlan)
                            if parsePlan != nil {
                                Button("Edit Working Copy", action: { showingEditWorkingCopy = true })
                                Divider()
                                Button("Commit as New Version", action: commitWorkingCopy)
                                    .disabled(!hasWorkingCopy)
                            }
                        } else {
                            // AI Direct mode menu
                            if !account.categorizationSessions.isEmpty {
                                Button("Clear All Sessions", role: .destructive, action: { showingClearConfirm = true })
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24, height: 24)
                }
            }
            .padding()

            Divider()

            // Agent status banner (for both modes)
            if let agent = agent, agent.status != .idle {
                AgentProgressBanner(
                    status: agent.status.displayText,
                    step: agent.currentStep,
                    progress: agent.progress,
                    recentLogs: Array(agent.log.suffix(3).map { ($0.icon, $0.color, $0.message) })
                )
            } else if let service = directService, service.status != .idle {
                DirectServiceProgressBanner(
                    service: service,
                    step: service.currentStep,
                    onStop: {
                        service.pause()
                        // Mark as stopped (pause + don't resume)
                        pendingCategorizationData = nil
                    }
                )
            }

            // Content based on mode
            // Squelched noisy logs
            // let _ = print("🔀 Current categorization mode: \(account.effectiveCategorizationMode)")

            if account.effectiveCategorizationMode == .ruleBased {
                // Parse Plans mode
                // let _ = print("🎨 Rendering Parse Rules mode")
                if let plan = parsePlan {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            // Working copy indicator
                            if hasWorkingCopy {
                                WorkingCopyCard(
                                    parsePlan: plan,
                                    onEdit: { showingEditWorkingCopy = true },
                                    onCommit: commitWorkingCopy
                                )
                            }

                            // Committed versions
                            ForEach(versions) { version in
                                ParsePlanVersionCard(
                                    version: version,
                                    isSelected: selectedVersion?.id == version.id,
                                    onSelect: {
                                        selectedVersion = version
                                    }
                                )
                            }

                            if versions.isEmpty && !hasWorkingCopy {
                                Text("No versions yet")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
                        }
                        .padding()
                    }
                } else {
                    // No parse plan
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("No Parse Plan")
                            .font(.headline)

                        Text("Create a parse plan to define how CSV data maps to transactions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)

                        Button("Create Parse Plan") {
                            createNewParsePlan()
                        }

                        Spacer()
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            } else {
                // AI Direct mode
                // Squelched: let _ = print("🎨 Rendering AI Direct mode: \(account.categorizationSessions.count) sessions")

                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(account.categorizationSessions.sorted(by: { $0.createdAt > $1.createdAt })) { session in
                            let isSelected = selectedCategorizationSession?.id == session.id
                            let isActive = account.activeCategorizationSessionId == session.id
                            // Squelched: let _ = print("📌 Rendering session v\(session.versionNumber), selected=\(isSelected), active=\(isActive)")

                            VStack(alignment: .leading, spacing: 8) {
                                CategorizationSessionCard(
                                    session: session,
                                    isSelected: isSelected,
                                    isActive: isActive,
                                    onSelect: {
                                        print("👆 User selected session v\(session.versionNumber)")
                                        selectedCategorizationSession = session
                                    },
                                    onActivate: !isActive ? {
                                        print("✨ Activating session v\(session.versionNumber)")
                                        account.activate(session)
                                        try? modelContext.save()
                                    } : nil,
                                    onResume: session.isPaused ? {
                                        resumeSession(session)
                                    } : nil
                                )

                                // Show batches for this session
                                if isSelected {
                                    // Squelched: let _ = print("✨ Showing batches for v\(session.versionNumber)")

                                    // Direct inline rendering
                                    let sessionBatches = allCategorizationBatches.filter { $0.session?.id == session.id }
                                    // Squelched batch count log

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("Batches (\(sessionBatches.count)):")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)

                                            Spacer()

                                            Button(action: { showingClearConfirm = true }) {
                                                Text("Clear All")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundColor(.red)
                                        }
                                        .padding(.leading, 16)

                                        ForEach(sessionBatches.sorted(by: { $0.batchNumber < $1.batchNumber })) { batch in
                                            Button(action: {
                                                print("👆 Clicked batch #\(batch.batchNumber)")
                                                selectedBatchForDetail = batch
                                                showingBatchDetail = true
                                            }) {
                                                HStack {
                                                    Text("#\(batch.batchNumber)")
                                                        .font(.caption)
                                                        .fontWeight(.semibold)
                                                        .foregroundColor(.purple)
                                                        .frame(width: 24)

                                                    Text("Rows \(batch.startRow)-\(batch.endRow)")
                                                        .font(.caption)

                                                    Image(systemName: "arrow.right")
                                                        .font(.caption2)

                                                    Text("\(batch.transactionCount) txns")
                                                        .font(.caption)
                                                        .foregroundColor(.green)

                                                    Spacer()

                                                    Image(systemName: "info.circle")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                .padding(8)
                                                .background(Color.purple.opacity(0.05))
                                                .cornerRadius(4)
                                            }
                                            .buttonStyle(.plain)
                                            .padding(.leading, 16)
                                        }
                                    }
                                }
                                // Squelched "not showing batches" log
                            }
                        }

                        if account.categorizationSessions.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Image(systemName: "brain")
                                    .font(.system(size: 48))
                                    .foregroundColor(.purple)

                                Text("No AI Categorizations")
                                    .font(.headline)

                                Text("Click 'Agent' to have AI directly categorize your uploaded CSV data into transactions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.leading)

                                Spacer()
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(minWidth: 250, idealWidth: 300, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
        .sheet(isPresented: $showingBatchDetail) {
            if let batch = selectedBatchForDetail {
                BatchDetailView(batch: batch)
            }
        }
        .alert("Clear All Categorizations?", isPresented: $showingClearConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete All", role: .destructive) {
                clearAllCategorizations()
            }
        } message: {
            Text("This will delete all \(account.categorizationSessions.count) categorization sessions and their batches for this account. This cannot be undone.")
        }
        .alert("Categorization Failed", isPresented: $showingErrorAlert) {
            Button("Cancel", role: .cancel) {
                pendingCategorizationData = nil
                lastError = nil
            }
            Button("Retry", action: retryDirectCategorization)
        } message: {
            if let error = lastError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error.userFriendlyMessage)
                    Text("\nTechnical Details:")
                        .font(.caption)
                    Text(error.technicalDetails)
                        .font(.caption2)
                }
            }
        }
        .onAppear {
            if agent == nil {
                agent = AutonomousParseAgent(modelContext: modelContext)
            }
            if directService == nil {
                directService = DirectCategorizationService(modelContext: modelContext)
            }

            // Auto-select active session if none selected
            if selectedCategorizationSession == nil, let activeSession = account.activeCategorizationSession {
                selectedCategorizationSession = activeSession
                print("🔄 Auto-selected active session v\(activeSession.versionNumber)")
            }
        }
    }

    private func activateAgent() {
        if account.effectiveCategorizationMode == .aiDirect {
            activateDirectCategorization()
        } else {
            activateRuleBasedAgent()
        }
    }

    private func activateDirectCategorization() {
        guard !accountBatches.isEmpty, let service = directService else { return }

        // Check if resuming a paused session
        if case .paused = service.status, let session = selectedCategorizationSession {
            resumeSession(session)
            return
        }

        Task {
            do {
                // Gather all CSV rows with file provenance
                var allRows: [[String: String]] = []
                var headers: [String] = []
                var globalRowNumber = 1  // Global row number across all files

                for batch in accountBatches.sorted(by: { $0.timestamp < $1.timestamp }) {
                    guard let rawFile = batch.rawFile,
                          let content = String(data: rawFile.content, encoding: .utf8) else {
                        continue
                    }

                    let parser = CSVParser()
                    if let csvData = try? parser.parse(content) {
                        if headers.isEmpty {
                            headers = csvData.headers
                        }

                        for (fileRowIndex, row) in csvData.rows.enumerated() {
                            var rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))
                            // Add provenance metadata
                            rowDict["_sourceFile"] = rawFile.fileName
                            rowDict["_fileRowNumber"] = "\(fileRowIndex + 1)"  // Row in this file
                            rowDict["_globalRowNumber"] = "\(globalRowNumber)"  // Row in combined dataset
                            allRows.append(rowDict)
                            globalRowNumber += 1
                        }
                    }
                }

                print("📁 Collected \(allRows.count) rows from \(accountBatches.count) files with full provenance")

                // Store data for retry/resume
                pendingCategorizationData = (allRows, headers)

                // Create session immediately and select it so batches appear live
                let rowHashes = allRows.map { row in
                    let rowString = headers.map { row[$0] ?? "" }.joined(separator: "|")
                    return rowString.sha256()
                }

                let existingSessions = account.categorizationSessions.sorted { $0.versionNumber > $1.versionNumber }
                let nextVersion = (existingSessions.first?.versionNumber ?? 0) + 1

                let newSession = CategorizationSession(
                    sessionName: "Version \(nextVersion)",
                    sourceRowHashes: rowHashes,
                    account: account,
                    versionNumber: nextVersion,
                    baseVersion: nil,
                    mode: .full
                )
                modelContext.insert(newSession)

                // Select immediately so batch list updates live
                selectedCategorizationSession = newSession
                print("🎯 Created and selected session v\(nextVersion) - batches will appear as they're generated")

                // Call service (will process in chunks and add to this session)
                let session = try await service.categorizeRows(
                    csvRows: allRows,
                    headers: headers,
                    account: account,
                    existingSession: newSession
                )

                print("✅ AI Direct Categorization complete: \(session.transactionCount) transactions, \(session.batches.count) batches")

                // Auto-activate this session when complete
                if session.isComplete && session.isValid {
                    print("✨ Auto-activating completed session v\(session.versionNumber)")
                    account.activate(session)
                    try? modelContext.save()
                }

                pendingCategorizationData = nil

            } catch let error as CategorizationError {
                print("❌ AI Direct Categorization failed: \(error)")
                lastError = error
                showingErrorAlert = true
            } catch let error as ClaudeAPIError {
                // Rate limits are auto-handled with countdown - don't show error dialog
                if case .httpError(let statusCode, _, _) = error, statusCode == 429 {
                    print("⏱️ Rate limit reached max retries - job will pause")
                    // The auto-retry already tried 5 times, pausing is correct
                    // Don't show error, user can resume later
                } else {
                    print("❌ AI Direct Categorization failed: \(error)")
                    if case .networkError(_, let details) = error, details.contains("timed out") {
                        lastError = .networkTimeout
                    } else {
                        lastError = .apiError(error.localizedDescription)
                    }
                    showingErrorAlert = true
                }
            } catch {
                print("❌ AI Direct Categorization failed: \(error)")
                // Don't show error for rate limits
                if error.localizedDescription.contains("rate_limit") || error.localizedDescription.contains("rate limit") {
                    print("⏱️ Rate limit in generic error - auto-handled")
                } else if error.localizedDescription.contains("timed out") {
                    lastError = .networkTimeout
                    showingErrorAlert = true
                } else {
                    lastError = .unknown(error.localizedDescription)
                    showingErrorAlert = true
                }
            }
        }
    }

    private func resumeSession(_ session: CategorizationSession) {
        guard let data = pendingCategorizationData, let service = directService else {
            return
        }

        service.resume()

        Task {
            do {
                let resumedSession = try await service.categorizeRows(
                    csvRows: data.rows,
                    headers: data.headers,
                    account: account,
                    existingSession: session
                )

                print("✅ Resumed categorization: \(resumedSession.transactionCount) total transactions")
                selectedCategorizationSession = resumedSession

                if resumedSession.isComplete {
                    pendingCategorizationData = nil
                }

            } catch let error as CategorizationError {
                lastError = error
                showingErrorAlert = true
            } catch let error as ClaudeAPIError {
                // Rate limits are auto-handled - don't show dialog
                if case .httpError(let statusCode, _, _) = error, statusCode == 429 {
                    print("⏱️ Rate limit - auto-handled")
                } else if case .networkError(_, let details) = error, details.contains("timed out") {
                    lastError = .networkTimeout
                    showingErrorAlert = true
                } else {
                    lastError = .apiError(error.localizedDescription)
                    showingErrorAlert = true
                }
            } catch {
                if error.localizedDescription.contains("rate_limit") || error.localizedDescription.contains("rate limit") {
                    print("⏱️ Rate limit - auto-handled")
                } else if error.localizedDescription.contains("timed out") {
                    lastError = .networkTimeout
                    showingErrorAlert = true
                } else {
                    lastError = .unknown(error.localizedDescription)
                    showingErrorAlert = true
                }
            }
        }
    }

    private func retryDirectCategorization() {
        guard let data = pendingCategorizationData, let service = directService else {
            return
        }

        showingErrorAlert = false

        Task {
            do {
                let session = try await service.categorizeRows(
                    csvRows: data.rows,
                    headers: data.headers,
                    account: account
                )

                print("✅ AI Direct Categorization complete: \(session.transactionCount) transactions")
                selectedCategorizationSession = session
                pendingCategorizationData = nil
                lastError = nil

            } catch let error as CategorizationError {
                lastError = error
                showingErrorAlert = true
            } catch let error as ClaudeAPIError {
                // Rate limits are auto-handled - don't show dialog
                if case .httpError(let statusCode, _, _) = error, statusCode == 429 {
                    print("⏱️ Rate limit - auto-handled")
                } else if case .networkError(_, let details) = error, details.contains("timed out") {
                    lastError = .networkTimeout
                    showingErrorAlert = true
                } else {
                    lastError = .apiError(error.localizedDescription)
                    showingErrorAlert = true
                }
            } catch {
                if error.localizedDescription.contains("rate_limit") || error.localizedDescription.contains("rate limit") {
                    print("⏱️ Rate limit - auto-handled")
                } else if error.localizedDescription.contains("timed out") {
                    lastError = .networkTimeout
                    showingErrorAlert = true
                } else {
                    lastError = .unknown(error.localizedDescription)
                    showingErrorAlert = true
                }
            }
        }
    }

    private func activateRuleBasedAgent() {
        guard let plan = parsePlan, !accountBatches.isEmpty else { return }

        // Gather CSV data from selected batches
        Task {
            var allRows: [[String: String]] = []
            var headers: [String] = []

            for batch in accountBatches {
                guard let rawFile = batch.rawFile,
                      let content = String(data: rawFile.content, encoding: .utf8) else {
                    continue
                }

                let parser = CSVParser()
                if let csvData = try? parser.parse(content) {
                    if headers.isEmpty {
                        headers = csvData.headers
                    }

                    for row in csvData.rows {
                        let rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))
                        allRows.append(rowDict)
                    }
                }
            }

            // Launch agent
            await agent?.configure(
                csvRows: allRows,
                headers: headers,
                parsePlan: plan,
                account: account
            )
        }
    }

    private func createNewParsePlan() {
        let newPlan = ParsePlan(name: "Parse Plan for \(account.name)", account: account)
        modelContext.insert(newPlan)

        // Set as account's default
        account.defaultParsePlanID = newPlan.id

        parsePlan = newPlan
        showingCreateVersion = true
    }

    private func commitWorkingCopy() {
        guard let plan = parsePlan, plan.workingCopy != nil else {
            return
        }

        let version = plan.commitVersion(message: "Version \(plan.versions.count + 1)")

        do {
            try modelContext.save()
            selectedVersion = version
            print("✓ Committed v\(version.versionNumber)")
        } catch {
            print("Failed to commit: \(error)")
        }
    }

    private func clearAllCategorizations() {
        print("🗑️ Clearing all categorization sessions for account")

        // Delete all sessions (cascade will delete batches and transactions)
        for session in account.categorizationSessions {
            print("   Deleting session v\(session.versionNumber) with \(session.batches.count) batches, \(session.transactionCount) txns")
            modelContext.delete(session)
        }

        selectedCategorizationSession = nil

        do {
            try modelContext.save()
            print("✅ Cleared all categorizations")
        } catch {
            print("❌ Failed to clear: \(error)")
        }
    }
}

// MARK: - Working Copy Card

struct WorkingCopyCard: View {
    let parsePlan: ParsePlan
    let onEdit: () -> Void
    let onCommit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "pencil.circle.fill")
                    .foregroundColor(.orange)

                Text("Working Copy")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("Uncommitted")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }

            if let workingCopy = parsePlan.workingCopy {
                Text("\(workingCopy.schema.fields.count) fields mapped")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Text("Edit")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Button(action: onCommit) {
                    Text("Commit")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                Spacer()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange, lineWidth: 1)
        )
    }
}

// MARK: - Version Card

struct ParsePlanVersionCard: View {
    let version: ParsePlanVersion
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "number.circle.fill")
                    .foregroundColor(.blue)

                Text("Version \(version.versionNumber)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 12))
                }
            }

            Text("\(version.definition.schema.fields.count) fields mapped")
                .font(.caption)
                .foregroundColor(.secondary)

            if let message = version.commitMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(2)
            }

            Text("Committed \(version.committedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Show number of imports using this version
            if !version.importBatches.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8))
                    Text("\(version.importBatches.count) uploads")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Agent Progress Banners

struct AgentProgressBanner: View {
    let status: String
    let step: String
    let progress: Double
    let recentLogs: [(String, Color, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(status)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if !step.isEmpty {
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            // Show recent log entries
            if !recentLogs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recentLogs.indices, id: \.self) { index in
                        let log = recentLogs[index]
                        HStack(spacing: 6) {
                            Image(systemName: log.0)
                                .foregroundColor(log.1)
                                .font(.caption2)

                            Text(log.2)
                                .font(.caption)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

struct DirectServiceProgressBanner: View {
    @ObservedObject var service: DirectCategorizationService
    let step: String
    let onStop: () -> Void

    var statusText: String {
        switch service.status {
        case .idle: return "Ready"
        case .analyzing: return "Analyzing CSV..."
        case .processing(let chunk, let total): return "Generating Batch \(chunk) of ~\(total)"
        case .waitingForRateLimit(let seconds): return "⏱ Rate Limit - Retrying in \(seconds)s"
        case .paused: return "⏸ Paused"
        case .completed: return "✓ Categorization Complete"
        case .failed(let reason): return "Failed: \(reason)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if !step.isEmpty {
                        Text(step)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Show controls for active states
                if case .processing = service.status {
                    HStack(spacing: 8) {
                        Button(action: { service.pause() }) {
                            Label("Pause", systemImage: "pause.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: onStop) {
                            Label("Stop", systemImage: "stop.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)

                        ProgressView()
                            .controlSize(.small)
                    }
                } else if case .waitingForRateLimit(let seconds) = service.status {
                    HStack(spacing: 8) {
                        Button(action: { service.pause() }) {
                            Label("Pause", systemImage: "pause.fill")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Text("\(seconds)s")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .monospacedDigit()

                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }

            ProgressView(value: service.progress)
                .progressViewStyle(.linear)

            HStack {
                if service.totalChunks > 0 {
                    Text("Batch \(service.currentChunk) of ~\(service.totalChunks)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if case .waitingForRateLimit = service.status {
                    Text("Auto-retrying...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(12)
        .background(Color.purple.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Categorization Session Card

struct CategorizationSessionCard: View {
    let session: CategorizationSession
    let isSelected: Bool
    let isActive: Bool
    let onSelect: () -> Void
    let onActivate: (() -> Void)?
    let onResume: (() -> Void)?

    private var modeIcon: String {
        switch session.sessionMode {
        case .full: return "square.fill.on.square.fill"
        case .incremental: return "square.stack"
        case .override: return "arrow.triangle.2.circlepath"
        }
    }

    private var modeLabel: String {
        switch session.sessionMode {
        case .full: return "Full"
        case .incremental: return "Incremental"
        case .override: return "Override"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if session.isPaused {
                    Image(systemName: "pause.circle.fill")
                        .foregroundColor(.orange)
                } else {
                    Image(systemName: "brain")
                        .foregroundColor(.purple)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("v\(session.versionNumber)")
                            .font(.subheadline)
                            .fontWeight(.bold)

                        Text(modeLabel)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.2))
                            .cornerRadius(3)

                        if isActive {
                            Text("ACTIVE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .cornerRadius(3)
                        }

                        if let base = session.baseVersionNumber {
                            Text("from v\(base)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    Text(session.sessionName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(spacing: 4) {
                    if session.isComplete && session.isValid {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                    }

                    if let activate = onActivate {
                        Button(action: activate) {
                            Text("Activate")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
            }

            // Progress indicator for incomplete sessions
            if !session.isComplete {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(session.processedRowsCount) of \(session.totalSourceRows) rows")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(session.progressPercentage * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    ProgressView(value: session.progressPercentage)
                        .progressViewStyle(.linear)
                }

                if session.isPaused, let resume = onResume {
                    Button(action: resume) {
                        Label("Resume", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 12) {
                    Label("\(session.totalSourceRows) rows", systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(session.transactionCount) txns", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Text("Created \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            if session.unbalancedCount > 0 {
                Text("⚠️ \(session.unbalancedCount) unbalanced")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.purple.opacity(0.3), lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

// MARK: - Batch List View

struct BatchListView: View {
    let session: CategorizationSession
    let allBatches: [CategorizationBatch]

    @State private var selectedBatch: CategorizationBatch?
    @State private var showingBatchDetail = false

    var body: some View {
        let _ = print("🎬 BatchListView.body EXECUTING for session \(session.id)")

        let sessionBatches = allBatches
            .filter { $0.session?.id == session.id }
            .sorted { $0.batchNumber < $1.batchNumber }

        let _ = print("🔍 BatchListView: session.id=\(session.id), allBatches.count=\(allBatches.count), filtered=\(sessionBatches.count)")
        let _ = print("   Session.batches.count=\(session.batches.count) (relationship)")
        let _ = sessionBatches.enumerated().forEach { index, batch in
            print("   Batch #\(batch.batchNumber): rows \(batch.startRow)-\(batch.endRow), \(batch.transactionCount) txns")
        }

        return VStack(alignment: .leading, spacing: 4) {
            if !sessionBatches.isEmpty {
                Text("Batches (\(sessionBatches.count)):")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
                    .padding(.top, 4)

                ForEach(sessionBatches) { batch in
                    CategorizationBatchCard(batch: batch, onTap: {
                        selectedBatch = batch
                        showingBatchDetail = true
                    })
                    .padding(.leading, 16)
                }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if !session.isComplete {
                        Text("Processing batches...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("No batches found (check console)")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.leading, 16)
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingBatchDetail) {
            if let batch = selectedBatch {
                BatchDetailView(batch: batch)
            }
        }
    }
}

// MARK: - Categorization Batch Card

struct CategorizationBatchCard: View {
    let batch: CategorizationBatch
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Text("#\(batch.batchNumber)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Rows \(batch.startRow)-\(batch.endRow)")
                            .font(.caption)

                        Image(systemName: "arrow.right")
                            .font(.caption2)

                        Text("\(batch.transactionCount) txns")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    HStack(spacing: 8) {
                        Text("\(batch.inputTokens)→\(batch.outputTokens) tokens")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("\(String(format: "%.1f", batch.durationSeconds))s")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color.purple.opacity(0.05))
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Batch Detail View

struct BatchDetailView: View {
    let batch: CategorizationBatch
    @Environment(\.dismiss) private var dismiss
    @State private var showingRequest = false
    @State private var showingResponse = false

    private var aiRequest: String {
        guard let data = batch.aiRequestData else { return "No request data stored" }
        return String(data: data, encoding: .utf8) ?? "Unable to decode request"
    }

    private var aiResponse: String {
        guard let data = batch.aiResponseData else { return "No response data" }
        return String(data: data, encoding: .utf8) ?? "Unable to decode response"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Batch #\(batch.batchNumber) Details")
                    .font(.title2)
                    .fontWeight(.bold)

                Spacer()

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .imageScale(.large)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Batch Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Batch Information")
                            .font(.headline)

                        Group {
                            InfoRow(label: "Batch Number", value: "#\(batch.batchNumber)")
                            InfoRow(label: "Rows Consumed", value: "\(batch.startRow)-\(batch.endRow) (\(batch.endRow - batch.startRow + 1) rows)")
                            InfoRow(label: "Window Size", value: "\(batch.windowSize) rows")
                            InfoRow(label: "Transactions", value: "\(batch.transactionCount)")
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Performance
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance")
                            .font(.headline)

                        Group {
                            Button(action: { showingRequest = true }) {
                                HStack {
                                    Text("Input Tokens")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text("\(batch.inputTokens)")
                                        .font(.caption)
                                        .fontWeight(.medium)

                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(.plain)

                            Button(action: { showingResponse = true }) {
                                HStack {
                                    Text("Output Tokens")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Spacer()

                                    Text("\(batch.outputTokens)")
                                        .font(.caption)
                                        .fontWeight(.medium)

                                    Image(systemName: "doc.text.magnifyingglass")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .buttonStyle(.plain)

                            InfoRow(label: "Duration", value: String(format: "%.2f seconds", batch.durationSeconds))
                            if batch.durationSeconds > 0 {
                                InfoRow(label: "Tokens/sec", value: String(format: "%.0f", Double(batch.outputTokens) / batch.durationSeconds))
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // AI Response
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Response")
                            .font(.headline)

                        ScrollView(.horizontal) {
                            Text(aiResponse)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding()
                        }
                        .frame(height: 200)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)

                    // Transactions
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Transactions Generated (\(batch.transactions.count))")
                            .font(.headline)

                        if batch.transactions.isEmpty {
                            Text("No transactions in this batch")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(batch.transactions.sorted(by: { $0.date < $1.date })) { txn in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(txn.transactionDescription)
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    HStack {
                                        Text("Rows: \(txn.sourceRowNumbers.map { "#\($0)" }.joined(separator: ", "))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)

                                        Spacer()

                                        Text(txn.date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .padding()
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .padding()
            }
        }
        .frame(width: 700, height: 800)
        .sheet(isPresented: $showingRequest) {
            PromptInspectorView(title: "AI Request (Input)", content: aiRequest, tokenCount: batch.inputTokens)
        }
        .sheet(isPresented: $showingResponse) {
            PromptInspectorView(title: "AI Response (Output)", content: aiResponse, tokenCount: batch.outputTokens)
        }
    }
}

// MARK: - Prompt Inspector

struct PromptInspectorView: View {
    let title: String
    let content: String
    let tokenCount: Int
    @Environment(\.dismiss) private var dismiss

    private var charCount: Int {
        content.count
    }

    private var estimatedTokens: Int {
        charCount / 4  // Rough estimate
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(tokenCount) tokens")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(charCount) chars")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(content)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
            }
        }
        .frame(width: 900, height: 700)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview with empty form fix

extension BatchDetailView {
    var oldBody: some View {
        Form {
            Section("Batch Information") {
                LabeledContent("Batch", value: "#\(batch.batchNumber)")
                LabeledContent("Rows Consumed", value: "\(batch.startRow)-\(batch.endRow) (\(batch.endRow - batch.startRow + 1) rows)")
                LabeledContent("Window Size", value: "\(batch.windowSize) rows")
                LabeledContent("Transactions", value: "\(batch.transactionCount)")
            }

            Section("Performance") {
                LabeledContent("Input Tokens", value: "\(batch.inputTokens)")
                LabeledContent("Output Tokens", value: "\(batch.outputTokens)")
                LabeledContent("Duration", value: String(format: "%.2f seconds", batch.durationSeconds))
                if batch.durationSeconds > 0 {
                    LabeledContent("Tokens/sec", value: String(format: "%.0f", Double(batch.outputTokens) / batch.durationSeconds))
                }
            }

            Section("AI Response") {
                ScrollView {
                    Text(aiResponse)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 300)
            }

            Section("Transactions Generated (\(batch.transactions.count))") {
                if batch.transactions.isEmpty {
                    Text("No transactions in this batch")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(batch.transactions.sorted(by: { $0.date < $1.date })) { txn in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(txn.transactionDescription)
                                .font(.caption)
                                .fontWeight(.medium)

                            HStack {
                                Text("Rows: \(txn.sourceRowNumbers.map { "#\($0)" }.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(txn.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 700, height: 800)
    }
}

