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
    @State private var currentJobId: UUID?
    @State private var jobManager = JobManager.shared
    @State private var showingErrorAlert = false
    @State private var lastError: CategorizationError?
    @State private var pendingCategorizationData: (rows: [[String: String]], headers: [String])?
    @State private var selectedBatchForDetail: CategorizationBatch?
    @State private var showingBatchDetail = false
    @State private var showingClearConfirm = false
    @State private var refreshTrigger = 0  // Force refresh during batch processing
    @State private var isFillingGaps = false
    @State private var showingReconciliation = false
    @State private var reconciliationSession: CategorizationSession?
    @State private var balanceDiscrepancyCheck: BalanceDiscrepancyCheck?
    @State private var isReconciling = false
    @State private var isRecalculatingBalances = false
    @State private var lastLoggedSessionId: UUID? = nil  // Track what we've already logged

    private var accountBatches: [ImportBatch] {
        allBatches.filter { $0.account?.id == account.id && selectedBatches.contains($0.id) }
    }

    private var versions: [ParsePlanVersion] {
        parsePlan?.versions.sorted(by: { $0.versionNumber > $1.versionNumber }) ?? []
    }

    private var hasWorkingCopy: Bool {
        parsePlan?.workingCopy != nil
    }

    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }

    // Get current job for this session
    private var currentJob: Job? {
        guard let jobId = currentJobId else {
            // Check if there's a job for the selected session
            if let session = selectedCategorizationSession {
                return jobManager.getJobsFor(session: session).first { !$0.status.isTerminal }
            }
            return nil
        }
        return jobManager.getJob(id: jobId)
    }

    @ViewBuilder
    private var balanceReconciliationBanner: some View {
        if let session = selectedCategorizationSession, session.isComplete, let check = balanceDiscrepancyCheck {
            if check.hasDiscrepancies {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: check.criticalCount > 0 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundColor(check.criticalCount > 0 ? .red : .orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Balance Discrepancies Detected")
                                .font(.headline)
                                .foregroundColor(check.criticalCount > 0 ? .red : .orange)

                            Text(check.message)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 8) {
                                if check.criticalCount > 0 {
                                    Label("\(check.criticalCount) critical", systemImage: "exclamationmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                if check.highCount > 0 {
                                    Label("\(check.highCount) high", systemImage: "exclamationmark.circle")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                if check.mediumCount > 0 {
                                    Label("\(check.mediumCount) medium", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundColor(.yellow)
                                }

                                Text("• Max: $\(check.maxDiscrepancy as NSDecimalNumber, formatter: currencyFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(action: { reconcileBalances(session) }) {
                            HStack(spacing: 6) {
                                if isReconciling {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Reconciling...")
                                } else {
                                    Image(systemName: "wand.and.stars")
                                    Text("Auto-Fix Balances")
                                }
                            }
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(check.criticalCount > 0 ? .red : .blue)
                        .controlSize(.large)
                        .disabled(isReconciling)
                    }
                }
                .padding(16)
                .background((check.criticalCount > 0 ? Color.red : Color.blue).opacity(0.1))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(check.criticalCount > 0 ? Color.red : Color.blue, lineWidth: 2)
                )
                .padding(.horizontal)
            }
        }
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
                    session: selectedCategorizationSession,
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
                        // BALANCE RECONCILIATION BANNER
                        balanceReconciliationBanner

                        // PROMINENT COVERAGE WARNING for selected session
                        if let session = selectedCategorizationSession, session.isComplete {
                            let coveredRows = session.buildCoverageIndex().count
                            let uncoveredRows = session.findUncoveredRows()
                            let excludedCount = session.excludedRowNumbers.count
                            let effectiveTotal = session.effectiveSourceRows

                            if !uncoveredRows.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.title2)
                                            .foregroundColor(.orange)

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Incomplete Coverage Detected")
                                                .font(.headline)
                                                .foregroundColor(.orange)

                                            Text("\(uncoveredRows.count) CSV rows are not covered by any transaction")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)

                                            HStack(spacing: 4) {
                                                Text("Coverage: \(coveredRows)/\(effectiveTotal) transactional rows (\(String(format: "%.1f", session.coveragePercentage * 100))%)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)

                                                if excludedCount > 0 {
                                                    Text("• \(excludedCount) excluded")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary.opacity(0.7))
                                                }
                                            }
                                        }

                                        Spacer()

                                        Button(action: { fillGapsInSession(session) }) {
                                            HStack(spacing: 6) {
                                                if isFillingGaps {
                                                    ProgressView()
                                                        .scaleEffect(0.7)
                                                    Text("Processing...")
                                                } else {
                                                    Image(systemName: "wand.and.stars")
                                                    Text("Fill Gaps Now")
                                                }
                                            }
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.orange)
                                        .controlSize(.large)
                                        .disabled(isFillingGaps)
                                    }
                                }
                                .padding(16)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.orange, lineWidth: 2)
                                )
                                .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 2)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            } else if excludedCount > 0 {
                                // All gaps filled, show excluded count for info
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)

                                    Text("100% coverage (\(excludedCount) non-transactional rows excluded)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                                .padding(.horizontal)
                                .padding(.top, 8)
                            }
                        }

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
                                    onResume: (!session.isComplete || session.isPaused) ? {
                                        resumeIncompleteSession(session)
                                    } : nil,
                                    onFillGaps: session.isComplete ? {
                                        fillGapsInSession(session)
                                    } : nil,
                                    onReconcile: session.isComplete ? {
                                        openReconciliation(session)
                                    } : nil,
                                    isFillingGaps: isFillingGaps
                                )
                                .id("\(session.id)-\(session.transactionCount)-\(session.batches.count)-\(refreshTrigger)")

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
        .sheet(isPresented: $showingReconciliation) {
            if let session = reconciliationSession {
                ReconciliationView(
                    session: session,
                    csvRows: getAllCSVRows()
                )
                .frame(minWidth: 800, minHeight: 600)
            }
        }
        .onChange(of: selectedCategorizationSession?.id) { oldId, newSessionId in
            // Only log full details once per session
            if let session = selectedCategorizationSession, session.id != lastLoggedSessionId {
                logSessionDetails(session)
                lastLoggedSessionId = session.id
            }

            // Auto-check balance when session changes
            if let session = selectedCategorizationSession, session.isComplete {
                // If transactions don't have balances calculated, calculate them first
                let hasBalances = session.transactions.first?.calculatedBalance != nil

                if !hasBalances {
                    recalculateBalances(session)
                } else {
                    checkBalanceDiscrepancies(for: session)
                }
            } else {
                balanceDiscrepancyCheck = nil
            }
        }
        .onChange(of: selectedCategorizationSession?.isComplete) { oldValue, newValue in
            print("\n🎯 onChange(isComplete): \(oldValue ?? false) → \(newValue ?? false)")

            // When session becomes complete, calculate balances
            if newValue == true, let session = selectedCategorizationSession {
                print("✅ Session v\(session.versionNumber) just completed - calculating balances")

                // Check if already has balances
                let hasBalances = session.transactions.first?.calculatedBalance != nil
                print("   Already has balances: \(hasBalances)")

                if !hasBalances {
                    recalculateBalances(session)
                } else {
                    checkBalanceDiscrepancies(for: session)
                }
            }
        }
        .onChange(of: refreshTrigger) { _, _ in
            print("\n🔄 onChange(refreshTrigger): \(refreshTrigger)")
            // Re-check balance after operations complete
            if let session = selectedCategorizationSession, session.isComplete {
                checkBalanceDiscrepancies(for: session)
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

            // Check balance for selected session on startup
            if let session = selectedCategorizationSession, session.isComplete {
                print("\n🔍 onAppear: Checking session v\(session.versionNumber)")
                print("   Transactions: \(session.transactions.count)")
                print("   First txn calculatedBalance: \(session.transactions.first?.calculatedBalance?.description ?? "nil")")
                print("   First txn csvBalance: \(session.transactions.first?.csvBalance?.description ?? "nil")")

                // If transactions don't have balances calculated, calculate them first
                let hasBalances = session.transactions.first?.calculatedBalance != nil

                if !hasBalances {
                    print("⚠️ Session v\(session.versionNumber) missing balances - recalculating...")
                    recalculateBalances(session)
                } else {
                    print("✓ Session already has balances - checking for discrepancies")
                    checkBalanceDiscrepancies(for: session)
                }
            } else if let session = selectedCategorizationSession {
                print("\n🔍 onAppear: Session v\(session.versionNumber) not complete (isComplete: \(session.isComplete))")
            } else {
                print("\n🔍 onAppear: No session selected")
            }

            // Start periodic refresh while processing
            Task { @MainActor in
                while true {
                    try? await Task.sleep(for: .milliseconds(500))

                    guard let service = directService else { break }

                    if case .processing = service.status {
                        refreshTrigger += 1
                    } else if case .completed = service.status {
                        // One final refresh
                        refreshTrigger += 1
                        break
                    } else if case .failed = service.status {
                        // One final refresh
                        refreshTrigger += 1
                        break
                    }
                }
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
        guard !accountBatches.isEmpty else { return }

        // Check if there's a running job for this session
        if let job = currentJob {
            if job.status == .paused {
                print("▶️ Resuming paused job")
                Task { await jobManager.resumeJob(id: job.id) }
                return
            } else if job.status == .running {
                print("ℹ️ Job already running")
                return
            }
        }

        // Check if there's an incomplete session that can be resumed
        if let session = selectedCategorizationSession, !session.isComplete {
            print("🔄 Found incomplete session v\(session.versionNumber) - attempting to resume")
            resumeIncompleteSession(session)
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

                // Create SourceRow entities for provenance
                print("📝 Creating SourceRow entities...")
                let sourceRowService = SourceRowService(modelContext: modelContext)
                for batch in accountBatches.sorted(by: { $0.timestamp < $1.timestamp }) {
                    guard let rawFile = batch.rawFile else { continue }

                    // Get rows for this file
                    let fileRows = allRows.filter { $0["_sourceFile"] == rawFile.fileName }
                    if !fileRows.isEmpty {
                        _ = try sourceRowService.createSourceRows(
                            from: fileRows,
                            headers: headers,
                            sourceFile: rawFile,
                            account: account
                        )
                    }
                }

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

                // Create job parameters
                let params = CategorizationJobParameters(
                    accountId: account.id,
                    sessionId: newSession.id,
                    csvRows: allRows,
                    headers: headers,
                    startFromRow: 0
                )

                // Create and submit job
                let job = Job(
                    type: .categorization,
                    title: "Categorize \(allRows.count) transactions"
                )
                job.subtitle = "Account: \(account.name)"
                job.account = account
                job.categorizationSession = newSession
                job.totalItemsCount = allRows.count
                job.parametersJSON = try? JSONEncoder().encode(params)

                try await jobManager.submitJob(job)
                currentJobId = job.id

                print("🚀 Submitted categorization job: \(job.id)")
                pendingCategorizationData = nil

            } catch let error as CategorizationError {
                print("❌ AI Direct Categorization failed: \(error)")
                // Error is now stored inline in session.errorMessage
                // No alert needed - will show in progress banner
            } catch let error as ClaudeAPIError {
                print("❌ AI Direct Categorization failed: \(error)")
                // Error is now stored inline in session.errorMessage
                // No alert needed - will show in progress banner
            } catch {
                print("❌ AI Direct Categorization failed: \(error)")
                // Error is now stored inline in session.errorMessage
                // No alert needed - will show in progress banner
            }
        }
    }

    private func resumeIncompleteSession(_ session: CategorizationSession) {
        guard let service = directService else { return }

        print("🔄 Resuming incomplete session v\(session.versionNumber)")

        Task {
            do {
                // Gather all CSV rows (same as activateDirectCategorization)
                let allRows = getAllCSVRows()
                let headers = allRows.first?.keys.map { $0 } ?? []

                print("   Got \(allRows.count) CSV rows")
                print("   Session has \(session.transactionCount) transactions so far")
                print("   Processed \(session.processedRowsCount)/\(session.totalSourceRows) rows")

                // Store for future resume attempts
                pendingCategorizationData = (allRows, headers)

                // Clear error message on resume
                session.errorMessage = nil
                session.isPaused = false

                let resumedSession = try await service.categorizeRows(
                    csvRows: allRows,
                    headers: headers,
                    account: account,
                    existingSession: session
                )

                print("✅ Resumed categorization: \(resumedSession.transactionCount) total transactions")
                selectedCategorizationSession = resumedSession

                if resumedSession.isComplete {
                    pendingCategorizationData = nil
                }

            } catch let error as CategorizationError {
                print("❌ Resume failed: \(error)")
            } catch let error as ClaudeAPIError {
                print("❌ Resume failed: \(error)")
            } catch {
                print("❌ Resume failed: \(error)")
            }
        }
    }

    private func resumeSession(_ session: CategorizationSession) {
        guard let data = pendingCategorizationData, let service = directService else {
            // If no pending data, use resumeIncompleteSession instead
            resumeIncompleteSession(session)
            return
        }

        // Clear error message on resume
        session.errorMessage = nil
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
                print("❌ Resume failed: \(error)")
                // Error is now stored inline in session.errorMessage
            } catch let error as ClaudeAPIError {
                print("❌ Resume failed: \(error)")
                // Error is now stored inline in session.errorMessage
            } catch {
                print("❌ Resume failed: \(error)")
                // Error is now stored inline in session.errorMessage
            }
        }
    }

    // Removed - errors are now handled inline with pause/resume

    private func openReconciliation(_ session: CategorizationSession) {
        reconciliationSession = session
        showingReconciliation = true
    }

    private func logSessionDetails(_ session: CategorizationSession) {
        print("\n" + String(repeating: "=", count: 80))
        print("📊 CATEGORIZATION SESSION LOADED: v\(session.versionNumber)")
        print(String(repeating: "=", count: 80))

        // Session metadata
        print("\n📋 Session Info:")
        print("   ID: \(session.id)")
        print("   Name: \(session.sessionName)")
        print("   Status: \(session.isComplete ? "✅ Complete" : "⏳ In Progress")")
        print("   Account: \(account.name)")
        print("   Balance Instrument: \(account.balanceInstrument ?? "Cash USD")")
        print("   Created: \(session.createdAt.formatted())")

        // Transaction summary
        let transactions = session.transactions.sorted { t1, t2 in
            let minRow1 = t1.sourceRowNumbers.min() ?? Int.max
            let minRow2 = t2.sourceRowNumbers.min() ?? Int.max
            return minRow1 < minRow2  // CSV file order (oldest first)
        }

        print("\n📈 Transactions: \(transactions.count) total")
        print("   Batches: \(session.batches.count)")
        print("   Source rows covered: \(Set(transactions.flatMap { $0.sourceRowNumbers }).count)")

        // Balance analysis
        let withCSVBalance = transactions.filter { $0.csvBalance != nil }.count
        let withDiscrepancies = transactions.filter { $0.hasBalanceDiscrepancy }.count
        let maxDiscrepancy = transactions.compactMap { $0.balanceDiscrepancy }.map { abs($0) }.max() ?? 0

        print("\n💰 Balance Tracking:")
        print("   Transactions with CSV balance: \(withCSVBalance)/\(transactions.count)")
        print("   Transactions with discrepancies: \(withDiscrepancies)")
        if withDiscrepancies > 0 {
            print("   Max discrepancy: $\(maxDiscrepancy)")
        }

        // Show first 10 and last 10 transactions with full details
        print("\n📝 Transaction Details (first 10, oldest):")
        for (idx, txn) in transactions.prefix(10).enumerated() {
            let rowsStr = txn.sourceRowNumbers.isEmpty ? "?" : txn.sourceRowNumbers.sorted().map { "#\($0)" }.joined(separator: ",")
            let calcBal = txn.calculatedBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil"
            let csvBal = txn.csvBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil"
            let disc = txn.balanceDiscrepancy.map { String(format: "$%.2f", NSDecimalNumber(decimal: abs($0)).doubleValue) } ?? "0"
            let discMarker = txn.hasBalanceDiscrepancy ? "❌" : "✅"

            print("   [\(idx)] \(txn.date.formatted(date: .numeric, time: .omitted)) | rows:\(rowsStr) | calc:\(calcBal) csv:\(csvBal) off:\(disc) \(discMarker)")
            print("       \(txn.transactionDescription.prefix(60))")

            // Show journal entries for problematic transactions
            if txn.hasBalanceDiscrepancy && idx < 3 {
                for entry in txn.journalEntries {
                    let dr = entry.debitAmount.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? ""
                    let cr = entry.creditAmount.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? ""
                    print("         \(entry.isDebit ? "DR" : "CR"): \(entry.accountName) \(dr)\(cr)")
                }
            }
        }

        if transactions.count > 10 {
            print("\n   ... (\(transactions.count - 20) transactions omitted) ...")

            print("\n📝 Transaction Details (last 10, newest):")
            for (idx, txn) in transactions.suffix(10).enumerated() {
                let actualIdx = transactions.count - 10 + idx
                let rowsStr = txn.sourceRowNumbers.isEmpty ? "?" : txn.sourceRowNumbers.sorted().map { "#\($0)" }.joined(separator: ",")
                let calcBal = txn.calculatedBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil"
                let csvBal = txn.csvBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil"
                let disc = txn.balanceDiscrepancy.map { String(format: "$%.2f", NSDecimalNumber(decimal: abs($0)).doubleValue) } ?? "0"
                let discMarker = txn.hasBalanceDiscrepancy ? "❌" : "✅"

                print("   [\(actualIdx)] \(txn.date.formatted(date: .numeric, time: .omitted)) | rows:\(rowsStr) | calc:\(calcBal) csv:\(csvBal) off:\(disc) \(discMarker)")
                print("       \(txn.transactionDescription.prefix(60))")
            }
        }

        // Balance progression summary
        if let firstTxn = transactions.first, let lastTxn = transactions.last {
            print("\n📊 Balance Progression:")
            print("   First transaction: \(firstTxn.date.formatted(date: .abbreviated, time: .omitted))")
            print("     Calculated: \(firstTxn.calculatedBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil")")
            print("     CSV: \(firstTxn.csvBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil")")
            print("   Last transaction: \(lastTxn.date.formatted(date: .abbreviated, time: .omitted))")
            print("     Calculated: \(lastTxn.calculatedBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil")")
            print("     CSV: \(lastTxn.csvBalance.map { String(format: "$%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "nil")")
        }

        print(String(repeating: "=", count: 80) + "\n")
    }

    private func recalculateBalances(_ session: CategorizationSession) {
        guard !isRecalculatingBalances else {
            print("⚠️ Balance recalculation already in progress")
            return
        }

        print("\n🚀 recalculateBalances() called for session v\(session.versionNumber)")

        isRecalculatingBalances = true

        Task {
            do {
                print("📦 Task started for balance recalculation")

                // Get all CSV rows
                let allRows = getAllCSVRows()
                print("   Got \(allRows.count) CSV rows")

                // Create service and recalculate
                let categorizationService = DirectCategorizationService(modelContext: modelContext)
                print("   Created DirectCategorizationService")

                categorizationService.recalculateBalances(for: session, csvRows: allRows)
                print("   recalculateBalances() completed")

                // Check first transaction after calculation
                if let firstTxn = session.transactions.first {
                    print("   First txn after recalc:")
                    print("     calculatedBalance: \(firstTxn.calculatedBalance?.description ?? "nil")")
                    print("     csvBalance: \(firstTxn.csvBalance?.description ?? "nil")")
                    print("     balanceDiscrepancy: \(firstTxn.balanceDiscrepancy?.description ?? "nil")")
                }

                // Save context
                try modelContext.save()
                print("   Context saved")

                // Re-check for discrepancies
                checkBalanceDiscrepancies(for: session)

                // Force UI refresh
                refreshTrigger += 1

                await MainActor.run {
                    isRecalculatingBalances = false
                }

                print("✅ Balance recalculation complete\n")

            } catch {
                print("❌ Balance recalculation failed: \(error)")

                await MainActor.run {
                    isRecalculatingBalances = false
                }
            }
        }
    }

    private func reconcileBalances(_ session: CategorizationSession) {
        guard !isReconciling else {
            print("⚠️ Reconciliation already in progress")
            return
        }

        isReconciling = true

        Task {
            do {
                print("\n💰 Starting automatic balance reconciliation for session v\(session.versionNumber)")

                // Get all CSV rows
                let allRows = getAllCSVRows()

                // Create services
                let claudeService = ClaudeAPIService.shared
                let reconciliationService = ReconciliationService(claudeAPIService: claudeService)
                let reviewService = TransactionReviewService(modelContext: modelContext)

                // Run reconciliation
                let reconciliationSession = try await reconciliationService.reconcile(
                    session: session,
                    csvRows: allRows,
                    reviewService: reviewService,
                    modelContext: modelContext,
                    maxIterations: 3
                )

                print("✅ Reconciliation complete!")
                print("   Checkpoints: \(reconciliationSession.checkpointsBuilt)")
                print("   Discrepancies found: \(reconciliationSession.discrepanciesFound)")
                print("   Discrepancies resolved: \(reconciliationSession.discrepanciesResolved)")
                print("   Fixes applied: \(reconciliationSession.fixesApplied)")
                print("   Fully reconciled: \(reconciliationSession.isFullyReconciled)")

                // Re-check balances
                checkBalanceDiscrepancies(for: session)

                // Force UI refresh
                refreshTrigger += 1

                isReconciling = false

            } catch {
                print("❌ Reconciliation failed: \(error)")

                await MainActor.run {
                    isReconciling = false
                    // TODO: Show error to user
                }
            }
        }
    }

    private func fillGapsInSession(_ session: CategorizationSession) {
        guard !isFillingGaps else {
            print("⚠️ Gap filling already in progress")
            return
        }

        isFillingGaps = true

        Task {
            do {
                print("\n🔍 Starting gap filling for session v\(session.versionNumber)")

                // Get all CSV rows
                let allRows = getAllCSVRows()

                // Create review service
                let reviewService = TransactionReviewService(modelContext: modelContext)

                // Fill gaps
                let reviewSession = try await reviewService.fillGaps(
                    in: session,
                    csvRows: allRows
                )

                print("✅ Gap filling complete!")
                print("   Transactions created: \(reviewSession.transactionsCreated)")
                print("   Final coverage: \(session.buildCoverageIndex().count)/\(session.totalSourceRows) rows")

                // Force UI refresh
                refreshTrigger += 1

                isFillingGaps = false

            } catch ReviewError.noRowsToReview {
                print("✅ No gaps to fill - session already has 100% coverage")
                isFillingGaps = false
            } catch {
                print("❌ Gap filling failed: \(error)")
                isFillingGaps = false
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

    private func getAllCSVRows() -> [[String: String]] {
        var allRows: [[String: String]] = []
        var globalRowNumber = 1

        print("📦 getAllCSVRows: accountBatches.count = \(accountBatches.count)")
        print("📦 getAllCSVRows: selectedBatches = \(selectedBatches)")

        for (batchIndex, batch) in accountBatches.sorted(by: { $0.timestamp < $1.timestamp }).enumerated() {
            guard let rawFile = batch.rawFile,
                  let content = String(data: rawFile.content, encoding: .utf8) else {
                print("⚠️ Batch \(batchIndex): No raw file or content")
                continue
            }

            let parser = CSVParser()
            if let csvData = try? parser.parse(content) {
                print("📄 Batch \(batchIndex) (\(rawFile.fileName)): \(csvData.rows.count) data rows")

                for (fileRowIndex, row) in csvData.rows.enumerated() {
                    var rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))
                    // Add provenance metadata
                    rowDict["_sourceFile"] = rawFile.fileName
                    rowDict["_fileRowNumber"] = "\(fileRowIndex + 1)"
                    rowDict["_globalRowNumber"] = "\(globalRowNumber)"
                    allRows.append(rowDict)
                    globalRowNumber += 1
                }
            }
        }

        print("📦 getAllCSVRows: Total rows collected = \(allRows.count) (rows 1-\(globalRowNumber - 1))")
        return allRows
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
    let session: CategorizationSession?
    let onStop: () -> Void

    var statusText: String {
        switch service.status {
        case .idle: return "Ready"
        case .analyzing: return "Analyzing CSV..."
        case .processing(let chunk, let total): return "Generating Batch \(chunk) of ~\(total)"
        case .waitingForRateLimit(let seconds): return "⏱ Rate Limit - Retrying in \(seconds)s"
        case .paused: return "⏸ Paused"
        case .completed: return "✓ Categorization Complete"
        case .failed(let reason): return "⚠️ Error (Paused)"
        }
    }

    private var rowCoverage: String? {
        guard let session = session else { return nil }
        let covered = Set(session.transactions.flatMap { $0.sourceRowNumbers }).count
        let total = session.totalSourceRows
        return "\(covered)/\(total) rows → \(session.transactionCount) txns"
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

            // Error message (if paused due to error)
            if case .failed = service.status, let session = session, let errorMsg = session.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)

                        Text("Error")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                    }

                    Text(errorMsg)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(6)
            }

            ProgressView(value: service.progress)
                .progressViewStyle(.linear)

            HStack {
                if let coverage = rowCoverage {
                    Text(coverage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

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

// MARK: - Balance Discrepancy Check

struct BalanceDiscrepancyCheck {
    var hasDiscrepancies: Bool
    var criticalCount: Int
    var highCount: Int
    var mediumCount: Int
    var maxDiscrepancy: Decimal
    var checkpointCount: Int
    var message: String
}

extension ParsePlanVersionsPanel {
    func checkBalanceDiscrepancies(for session: CategorizationSession) {
        Task {
            do {
                // Get all CSV rows
                let allRows = getAllCSVRows()
                guard !allRows.isEmpty else { return }

                // Create services
                let claudeService = ClaudeAPIService.shared
                let reconciliationService = ReconciliationService(claudeAPIService: claudeService)

                // Build checkpoints (quick, local operation)
                let checkpoints = reconciliationService.buildBalanceCheckpoints(
                    session: session,
                    csvRows: allRows,
                    modelContext: modelContext
                )

                // Count discrepancies by severity
                let discrepancies = checkpoints.filter { $0.hasDiscrepancy }
                let criticalCount = discrepancies.filter { $0.severity == .critical }.count
                let highCount = discrepancies.filter { $0.severity == .high }.count
                let mediumCount = discrepancies.filter { $0.severity == .medium }.count

                guard !discrepancies.isEmpty else {
                    // No discrepancies - all good!
                    await MainActor.run {
                        balanceDiscrepancyCheck = BalanceDiscrepancyCheck(
                            hasDiscrepancies: false,
                            criticalCount: 0,
                            highCount: 0,
                            mediumCount: 0,
                            maxDiscrepancy: 0,
                            checkpointCount: checkpoints.count,
                            message: "All balance checkpoints validate ✓"
                        )
                    }
                    return
                }

                // Calculate max discrepancy
                let maxDiscrepancy = discrepancies.map { abs($0.discrepancyAmount) }.max() ?? 0

                // Build message
                var message = "\(discrepancies.count) balance discrepancies found"
                if criticalCount > 0 {
                    message += " (\(criticalCount) critical)"
                }

                await MainActor.run {
                    balanceDiscrepancyCheck = BalanceDiscrepancyCheck(
                        hasDiscrepancies: true,
                        criticalCount: criticalCount,
                        highCount: highCount,
                        mediumCount: mediumCount,
                        maxDiscrepancy: maxDiscrepancy,
                        checkpointCount: checkpoints.count,
                        message: message
                    )
                }

            } catch {
                print("⚠️ Balance check failed: \(error)")
            }
        }
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
    let onFillGaps: (() -> Void)?
    let onReconcile: (() -> Void)?
    let isFillingGaps: Bool

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

                // Error message (if paused due to error)
                if let errorMsg = session.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)

                        Text(errorMsg)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }

                // Show resume button for any incomplete session
                if let resume = onResume {
                    Button(action: resume) {
                        Label(session.isPaused ? "Resume" : "Continue", systemImage: "play.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(.purple)
                }
            } else {
                // Completed session stats
                let coveredRows = session.buildCoverageIndex().count
                let uncoveredRows = session.findUncoveredRows()
                let excludedCount = session.excludedRowNumbers.count
                let hasGaps = !uncoveredRows.isEmpty

                HStack(spacing: 12) {
                    Label("\(session.effectiveSourceRows) rows", systemImage: "arrow.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label("\(session.transactionCount) txns", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundColor(.green)

                    if hasGaps {
                        Label("\(String(format: "%.0f", session.coveragePercentage * 100))% covered", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if excludedCount > 0 {
                        Label("100%", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }

            Text("Created \(session.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.secondary)

            // Coverage warning - MOST IMPORTANT
            if session.isComplete {
                let coveredRows = session.buildCoverageIndex().count
                let uncoveredRows = session.findUncoveredRows()
                let excludedCount = session.excludedRowNumbers.count

                if !uncoveredRows.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(uncoveredRows.count) rows not covered")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.orange)

                                Text("Coverage: \(coveredRows)/\(session.effectiveSourceRows) rows (\(String(format: "%.1f", session.coveragePercentage * 100))%)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                if excludedCount > 0 {
                                    Text("\(excludedCount) excluded")
                                        .font(.caption2)
                                        .foregroundColor(.secondary.opacity(0.7))
                                }
                            }

                            Spacer()
                        }

                        if let fillGaps = onFillGaps {
                            Button(action: fillGaps) {
                                HStack(spacing: 4) {
                                    if isFillingGaps {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                            .frame(width: 12, height: 12)
                                        Text("Filling...")
                                    } else {
                                        Image(systemName: "wand.and.stars")
                                        Text("Fill Gaps")
                                    }
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                            .disabled(isFillingGaps)
                        }

                        if let reconcile = onReconcile {
                            Button(action: reconcile) {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Reconcile")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.blue)
                            .controlSize(.small)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.orange, lineWidth: 1.5)
                    )
                }
            }

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
                            ForEach(batch.transactions.sorted(by: { t1, t2 in
                                let minRow1 = t1.sourceRowNumbers.min() ?? Int.max
                                let minRow2 = t2.sourceRowNumbers.min() ?? Int.max
                                return minRow1 < minRow2  // Lower row = newer (Fidelity is reverse chronological)
                            })) { txn in
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
                    ForEach(batch.transactions.sorted(by: { t1, t2 in
                        let minRow1 = t1.sourceRowNumbers.min() ?? Int.max
                        let minRow2 = t2.sourceRowNumbers.min() ?? Int.max
                        return minRow1 < minRow2  // Lower row = newer (Fidelity is reverse chronological)
                    })) { txn in
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

