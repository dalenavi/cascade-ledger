//
//  TransactionsPreviewPanel.swift
//  cascade-ledger
//
//  Shows materialized Transaction domain objects with JournalEntry legs
//

import SwiftUI
import SwiftData

struct TransactionsPreviewPanel: View {
    let account: Account
    let selectedBatches: Set<UUID>
    @Binding var selectedVersion: ParsePlanVersion?
    @Binding var parsePlan: ParsePlan?
    @Binding var selectedCategorizationSession: CategorizationSession?
    @Binding var hoveredRowIndex: Int?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ImportBatch.timestamp) private var allBatches: [ImportBatch]

    @State private var previewTransactions: [Transaction] = []
    @State private var rowGroups: [RowGroup] = []
    @State private var isGenerating = false
    @State private var viewMode: TransactionViewMode = .transactions
    @State private var validationReport: ValidationReport?

    private var effectiveDefinition: ParsePlanDefinition? {
        // Use selected version if available, otherwise use working copy
        if let version = selectedVersion {
            print("📋 Using selected version v\(version.versionNumber) with \(version.definition.schema.fields.count) fields")
            return version.definition
        } else if let workingCopy = parsePlan?.workingCopy {
            print("📋 Using working copy with \(workingCopy.schema.fields.count) fields")
            return workingCopy
        } else {
            print("⚠️ No definition available - no version selected and no working copy")
        }
        return nil
    }

    enum TransactionViewMode: String, CaseIterable {
        case transactions = "Transactions"
        case grouping = "Grouping Debug"
        case agentView = "Agent View"
    }

    private var accountBatches: [ImportBatch] {
        allBatches.filter { $0.account?.id == account.id && selectedBatches.contains($0.id) }
    }

    private var effectiveTransactions: [Transaction] {
        // In AI Direct mode, use categorization session transactions
        // Note: SwiftData @Relationship automatically updates when session.transactions changes
        let transactions: [Transaction]
        if account.effectiveCategorizationMode == .aiDirect,
           let session = selectedCategorizationSession {
            // Fetch latest transactions from session (reactive)
            transactions = session.transactions
            // print("🔄 Displaying \(transactions.count) transactions from session (live update)")  // Too noisy
        } else {
            // In Rule-Based mode, use live-calculated preview transactions
            transactions = previewTransactions
        }

        // Sort chronologically (newest first)
        return transactions.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Panel header
            HStack {
                Label("Transactions", systemImage: "list.bullet.rectangle")
                    .font(.headline)

                Picker("View", selection: $viewMode) {
                    ForEach(TransactionViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                if isGenerating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(effectiveTransactions.count) txns")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Content based on view mode
            switch viewMode {
            case .transactions:
                transactionsView
            case .grouping:
                groupingDebugView
            case .agentView:
                agentContextView
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .task(id: "\(selectedVersion?.id.uuidString ?? "working")_\(parsePlan?.workingCopyData?.hashValue ?? 0)_\(selectedBatches.hashValue)_\(selectedCategorizationSession?.id.uuidString ?? "none")_\(selectedCategorizationSession?.transactionCount ?? 0)") {
            // Auto-generate when version, working copy, selected batches, or categorization session changes
            // Note: transactionCount in task ID ensures UI updates as transactions are added incrementally
            if account.effectiveCategorizationMode == .ruleBased {
                // Rule-based mode: live calculation
                if effectiveDefinition != nil && !selectedBatches.isEmpty {
                    await generatePreview()
                }
            } else {
                // AI Direct mode: Use categorization session transactions (already computed, updates live)
                // Squelched noisy log
                // if let session = selectedCategorizationSession {
                //     print("🔄 Transactions panel updated: \(session.transactionCount) transactions")
                // }
            }
        }
    }

    // MARK: - Transactions View

    private var transactionsView: some View {
        Group {
            if !effectiveTransactions.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(effectiveTransactions) { transaction in
                            TransactionPreviewCard(transaction: transaction, hoveredRowIndex: $hoveredRowIndex)
                        }
                    }
                    .padding()
                }
            } else if isGenerating {
                VStack(alignment: .leading, spacing: 16) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Generating transactions...")
                        .font(.headline)

                    Text("Processing rows through settlement detection and double-entry materialization")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Transactions")
                        .font(.headline)

                    Text("Upload data and select a parse plan version to begin")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Grouping Debug View

    private var groupingDebugView: some View {
        Group {
            if !rowGroups.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Text("Settlement Pattern: Fidelity (Asset + Settlement)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                            .padding(.top)

                        ForEach(rowGroups.indices, id: \.self) { groupIndex in
                            RowGroupCard(
                                group: rowGroups[groupIndex],
                                groupNumber: groupIndex + 1,
                                hoveredRowIndex: $hoveredRowIndex
                            )
                        }
                    }
                    .padding()
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Grouping Data")
                        .font(.headline)

                    Text("Select data and parse plan to see row grouping")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    // MARK: - Agent Context View

    private var agentContextView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Agent Context & Validation")
                    .font(.headline)

                // Validation Report (AI Direct mode only)
                if account.effectiveCategorizationMode == .aiDirect, let report = validationReport {
                    ValidationReportView(report: report)

                    Divider()
                }

                // Grouping Analysis (Rule-Based mode)
                if !rowGroups.isEmpty {
                    Text("Grouping Statistics:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    AgentStatsView(groups: rowGroups, transactions: effectiveTransactions)

                    Divider()

                    Text("Pattern Analysis:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    AgentPatternView(groups: rowGroups)

                    Divider()

                    Text("Suggested Adjustments:")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    AgentSuggestionsView(groups: rowGroups, transactions: effectiveTransactions)
                } else if account.effectiveCategorizationMode == .ruleBased {
                    Text("No grouping data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .task(id: selectedCategorizationSession?.id) {
            // Run validation when categorization session changes
            if account.effectiveCategorizationMode == .aiDirect,
               let session = selectedCategorizationSession {
                await runValidation(for: session)
            }
        }
    }

    private func runValidation(for session: CategorizationSession) async {
        // Gather source rows
        let sourceRows = await getAllCSVRows()

        // Get headers
        var headers: [String] = []
        for batch in accountBatches {
            guard let rawFile = batch.rawFile,
                  let content = String(data: rawFile.content, encoding: .utf8) else {
                continue
            }

            let parser = CSVParser()
            if let csvData = try? parser.parse(content) {
                headers = csvData.headers
                break
            }
        }

        // Run validation
        let report = CategorizationValidator.validate(
            session: session,
            sourceRows: sourceRows,
            csvHeaders: headers
        )

        await MainActor.run {
            validationReport = report
            print("✅ Validation complete: \(report.overallStatus)")
        }
    }

    // MARK: - Data Generation

    private func generatePreview() async {
        guard let definition = effectiveDefinition else {
            print("⚠️ TransactionsPreview: No definition (no version and no working copy)")
            return
        }

        print("🔄 TransactionsPreview: Starting generation with \(definition.schema.fields.count) fields")

        isGenerating = true
        defer { isGenerating = false }

        // Configure AssetRegistry with ModelContext
        AssetRegistry.shared.configure(modelContext: modelContext)

        // Get all CSV rows from all uploads
        let allRows = await getAllCSVRows()
        print("📊 TransactionsPreview: Got \(allRows.count) CSV rows")

        // Transform rows
        let transformedRows = transformRows(allRows, with: definition)
        print("✓ TransactionsPreview: Transformed \(transformedRows.count) rows")

        // Debug: Show first transformed row
        if let firstRow = transformedRows.first {
            print("📝 First transformed row keys: \(firstRow.keys.sorted().joined(separator: ", "))")
            if let action = firstRow["metadata.action"] {
                print("   metadata.action = '\(action)'")
            }
            if let transactionType = firstRow["transactionType"] {
                print("   transactionType = '\(transactionType)'")
            }
            if let type = firstRow["type"] {
                print("   type = '\(type)'")
            }
        }

        // Group rows by settlement pattern
        let detector = FidelitySettlementDetector()
        let groupedArrays = detector.groupRows(transformedRows)
        print("🔗 TransactionsPreview: Grouped into \(groupedArrays.count) groups")

        // Build row groups for debugging
        var debugGroups: [RowGroup] = []
        for (index, group) in groupedArrays.enumerated() {
            let rowNums = group.compactMap { $0["rowNumber"] as? Int }
            let isPrimary = group.first?["metadata.action"] as? String != nil &&
                           !(group.first?["metadata.action"] as? String ?? "").isEmpty
            let hasSettlement = group.count > 1

            debugGroups.append(RowGroup(
                id: index,
                rowIndices: rowNums,
                rows: group,
                type: isPrimary ? (hasSettlement ? .primaryWithSettlement : .standalone) : .orphanedSettlement,
                patternMatched: "Fidelity: Asset + Settlement"
            ))
        }

        // Build transactions (preview only, not saved)
        var transactions: [Transaction] = []
        for (index, group) in groupedArrays.enumerated() {
            do {
                let transaction = try TransactionBuilder.createTransaction(
                    from: group,
                    account: account,
                    importSession: nil,
                    assetRegistry: AssetRegistry.shared
                )
                transactions.append(transaction)
            } catch {
                print("❌ TransactionsPreview: Failed to build transaction #\(index): \(error)")
            }
        }

        print("✅ TransactionsPreview: Created \(transactions.count) transactions")
        print("   Balanced: \(transactions.filter { $0.isBalanced }.count)")
        print("   Unbalanced: \(transactions.filter { !$0.isBalanced }.count)")

        await MainActor.run {
            previewTransactions = transactions
            rowGroups = debugGroups
            print("🎯 TransactionsPreview: Updated UI with \(transactions.count) transactions")
        }
    }

    private func getAllCSVRows() async -> [[String: String]] {
        print("📦 getAllCSVRows: accountBatches.count = \(accountBatches.count)")
        print("📦 getAllCSVRows: selectedBatches = \(selectedBatches)")

        var allRows: [[String: String]] = []
        var rowNumber = 1  // 1-based row numbering

        for (batchIndex, batch) in accountBatches.enumerated() {
            guard let rawFile = batch.rawFile,
                  let content = String(data: rawFile.content, encoding: .utf8) else {
                print("⚠️ Batch \(batchIndex): No raw file or content")
                continue
            }

            // Use proper CSV parser instead of naive string splitting
            let parser = CSVParser()
            guard let csvData = try? parser.parse(content) else {
                print("⚠️ Batch \(batchIndex): CSV parse failed")
                continue
            }

            print("📄 Batch \(batchIndex) (\(batch.rawFile?.fileName ?? "unknown")): \(csvData.rowCount) data rows")

            for row in csvData.rows {
                var rowDict = Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))
                rowDict["rowNumber"] = "\(rowNumber)"  // 1-based row number
                allRows.append(rowDict)
                rowNumber += 1
            }
        }

        print("📦 getAllCSVRows: Total rows collected = \(allRows.count) (rows 1-\(rowNumber - 1))")
        return allRows
    }

    private func transformRows(_ rows: [[String: String]], with definition: ParsePlanDefinition) -> [[String: Any]] {
        let executor = TransformExecutor()

        return rows.enumerated().compactMap { (index, row) in
            do {
                var transformed = try executor.transformRow(
                    row,
                    schema: definition.schema,
                    transforms: definition.transforms
                )
                transformed["rowNumber"] = index  // Preserve row number
                return transformed
            } catch {
                print("Transform error: \(error)")
                return nil
            }
        }
    }
}

// MARK: - Supporting Types

struct RowGroup: Identifiable {
    let id: Int
    let rowIndices: [Int]
    let rows: [[String: Any]]
    let type: GroupType
    let patternMatched: String

    enum GroupType {
        case primaryWithSettlement  // Asset row + settlement row(s)
        case standalone            // Single row, no settlement
        case orphanedSettlement    // Settlement without primary (error)
    }

    var displayType: String {
        switch type {
        case .primaryWithSettlement: return "Primary + Settlement"
        case .standalone: return "Standalone"
        case .orphanedSettlement: return "⚠️ Orphaned Settlement"
        }
    }

    var typeColor: Color {
        switch type {
        case .primaryWithSettlement: return .green
        case .standalone: return .blue
        case .orphanedSettlement: return .red
        }
    }
}

// MARK: - Transaction Preview Card

struct TransactionPreviewCard: View {
    let transaction: Transaction
    @State private var isExpanded = false
    @Binding var hoveredRowIndex: Int?

    private var sourceRowNumbers: [Int] {
        transaction.sourceRowNumbers
    }

    private var isHovered: Bool {
        guard let hovered = hoveredRowIndex else { return false }
        return sourceRowNumbers.contains(hovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Collapsible header
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Image(systemName: transactionIcon)
                        .foregroundColor(transactionColor)

                    Text(transaction.transactionDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    Spacer()

                    Text(formatAmount(transaction.amount))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
            }
            .buttonStyle(.plain)
            .background(isHovered ? Color.yellow.opacity(0.2) : Color(nsColor: .controlBackgroundColor))

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    // Source rows section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Source Rows:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        HStack {
                            ForEach(sourceRowNumbers, id: \.self) { rowNum in
                                Text("Row \(rowNum)")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }

                    // Balance indicator
                    HStack(spacing: 4) {
                        if transaction.isBalanced {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        Text("Debits: \(formatAmount(transaction.totalDebits)) | Credits: \(formatAmount(transaction.totalCredits))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    // Journal entries
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Journal Entries:")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)

                        ForEach(transaction.journalEntries) { entry in
                            HStack(spacing: 8) {
                                // Debit/Credit indicator
                                if entry.isDebit {
                                    Text("DR")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.blue)
                                        .frame(width: 24)
                                } else {
                                    Text("CR")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                        .frame(width: 24)
                                }

                                // Account
                                Text("\(entry.accountType.displayName): \(entry.accountName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                // Amount
                                Text(formatAmount(entry.amount))
                                    .font(.caption)
                                    .fontWeight(.medium)

                                // Quantity
                                if let qty = entry.quantity, let unit = entry.quantityUnit {
                                    Text("(\(formatQuantity(qty)) \(unit))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                // Asset link indicator
                                if entry.asset != nil {
                                    Image(systemName: "link.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                        .help("Linked to Asset: \(entry.asset?.symbol ?? "")")
                                }
                            }
                        }
                    }
                    .padding(.leading, 8)
                }
                .padding(12)
            }
        }
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isHovered ? Color.yellow.opacity(0.6) :
                    transaction.isBalanced ? Color.green.opacity(0.3) : Color.red,
                    lineWidth: isHovered ? 2 : 1
                )
        )
    }

    private var transactionIcon: String {
        switch transaction.transactionType {
        case .buy: return "arrow.down.circle"
        case .sell: return "arrow.up.circle"
        case .dividend: return "dollarsign.circle"
        case .interest: return "percent"
        case .fee: return "minus.circle"
        case .transfer: return "arrow.left.arrow.right"
        default: return "circle"
        }
    }

    private var transactionColor: Color {
        switch transaction.transactionType {
        case .buy, .withdrawal, .fee, .tax: return .red
        case .sell, .deposit, .dividend, .interest: return .green
        case .transfer: return .blue
        default: return .gray
        }
    }

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: amount as NSDecimalNumber) ?? "$0.00"
    }

    private func formatQuantity(_ quantity: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        formatter.minimumFractionDigits = 0
        return formatter.string(from: quantity as NSDecimalNumber) ?? "0"
    }
}

// MARK: - Row Group Card (Grouping Debug View)

struct RowGroupCard: View {
    let group: RowGroup
    let groupNumber: Int
    @Binding var hoveredRowIndex: Int?

    private var isHovered: Bool {
        guard let hovered = hoveredRowIndex else { return false }
        return group.rowIndices.contains(hovered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Group header
            HStack {
                Text("Group #\(groupNumber)")
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(group.displayType)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(group.typeColor.opacity(0.2))
                    .cornerRadius(4)

                Spacer()

                Text("\(group.rows.count) rows")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Row indices
            HStack {
                Text("Rows:")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                ForEach(group.rowIndices, id: \.self) { rowIndex in
                    Text("#\(rowIndex)")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(3)
                }
            }

            // Pattern matched
            Text("Pattern: \(group.patternMatched)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()

            // Show row details
            VStack(alignment: .leading, spacing: 4) {
                ForEach(group.rows.indices, id: \.self) { rowIdx in
                    let row = group.rows[rowIdx]
                    let action = row["metadata.action"] as? String ?? ""
                    let symbol = row["assetId"] as? String ?? ""
                    let amount = row["amount"] as? Decimal ?? 0

                    HStack(spacing: 6) {
                        Circle()
                            .fill(rowIdx == 0 ? Color.blue : Color.gray)
                            .frame(width: 6, height: 6)

                        if action.isEmpty && symbol.isEmpty {
                            Text("[Settlement Row]")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        } else {
                            Text(action.isEmpty ? symbol : action)
                                .font(.caption2)
                                .lineLimit(1)
                        }

                        Spacer()

                        if amount != 0 {
                            Text("$\(amount.formatted())")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.leading, 12)
        }
        .padding(12)
        .background(isHovered ? Color.yellow.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? Color.yellow : group.typeColor.opacity(0.3), lineWidth: isHovered ? 2 : 1)
        )
    }
}

// MARK: - Agent Context Views

struct AgentStatsView: View {
    let groups: [RowGroup]
    let transactions: [Transaction]

    private var totalRows: Int {
        groups.reduce(0) { $0 + $1.rows.count }
    }

    private var groupingAccuracy: Double {
        let balanced = transactions.filter { $0.isBalanced }.count
        return transactions.isEmpty ? 0 : Double(balanced) / Double(transactions.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                StatRow(label: "Total Rows", value: "\(totalRows)")
                StatRow(label: "Groups Created", value: "\(groups.count)")
                StatRow(label: "Transactions", value: "\(transactions.count)")
            }

            HStack(spacing: 16) {
                StatRow(label: "Balanced", value: "\(transactions.filter { $0.isBalanced }.count)")
                StatRow(label: "Unbalanced", value: "\(transactions.filter { !$0.isBalanced }.count)")
                StatRow(label: "Accuracy", value: "\(Int(groupingAccuracy * 100))%")
            }

            Text("Grouping Pattern: Fidelity (Asset row followed by settlement rows)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .italic()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

struct AgentPatternView: View {
    let groups: [RowGroup]

    private var primaryWithSettlement: Int {
        groups.filter { $0.type == .primaryWithSettlement }.count
    }

    private var standalone: Int {
        groups.filter { $0.type == .standalone }.count
    }

    private var orphaned: Int {
        groups.filter { $0.type == .orphanedSettlement }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Group Type Distribution:")
                .font(.caption)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                PatternBadge(label: "Primary + Settlement", count: primaryWithSettlement, color: .green)
                PatternBadge(label: "Standalone", count: standalone, color: .blue)
                if orphaned > 0 {
                    PatternBadge(label: "Orphaned", count: orphaned, color: .red)
                }
            }

            if orphaned > 0 {
                Text("⚠️ Orphaned settlement rows detected - these may indicate incorrect grouping logic")
                    .font(.caption2)
                    .foregroundColor(.red)
                    .italic()
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

struct PatternBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }
}

struct AgentSuggestionsView: View {
    let groups: [RowGroup]
    let transactions: [Transaction]

    private var unbalancedCount: Int {
        transactions.filter { !$0.isBalanced }.count
    }

    private var orphanedCount: Int {
        groups.filter { $0.type == .orphanedSettlement }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if unbalancedCount > 0 {
                SuggestionCard(
                    icon: "exclamationmark.triangle",
                    color: .red,
                    title: "\(unbalancedCount) Unbalanced Transactions",
                    suggestion: "Review TransactionBuilder logic for these transaction types. Debits must equal credits."
                )
            }

            if orphanedCount > 0 {
                SuggestionCard(
                    icon: "doc.questionmark",
                    color: .orange,
                    title: "\(orphanedCount) Orphaned Settlement Rows",
                    suggestion: "Settlement detector may need adjustment. Check if settlement pattern has changed or if there are rows without proper primary transactions."
                )
            }

            if unbalancedCount == 0 && orphanedCount == 0 {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All groupings appear correct")
                        .font(.caption)
                }
            }

            Text("For Agent: Copy this context when asking for settlement detection improvements")
                .font(.caption2)
                .foregroundColor(.purple)
                .italic()
        }
        .padding(12)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(8)
    }
}

struct SuggestionCard: View {
    let icon: String
    let color: Color
    let title: String
    let suggestion: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(suggestion)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Validation Report View

struct ValidationReportView: View {
    let report: ValidationReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Overall status
            HStack {
                Image(systemName: statusIcon)
                    .foregroundColor(statusColor)
                    .font(.title2)

                Text("Validation: \(statusText)")
                    .font(.headline)

                Spacer()
            }
            .padding()
            .background(statusColor.opacity(0.1))
            .cornerRadius(8)

            // Critical issues
            if !report.criticalIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Critical Issues:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)

                    ForEach(report.criticalIssues, id: \.self) { issue in
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text(issue)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.red.opacity(0.05))
                .cornerRadius(8)
            }

            // Warnings
            if !report.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Warnings:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)

                    ForEach(report.warnings, id: \.self) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(warning)
                                .font(.caption)
                        }
                    }
                }
                .padding()
                .background(Color.orange.opacity(0.05))
                .cornerRadius(8)
            }

            // Detailed checks
            VStack(alignment: .leading, spacing: 8) {
                ValidationCheckRow(
                    label: "Row Coverage",
                    status: report.rowCoverage.isPerfect ? .pass : .critical,
                    detail: "\(report.rowCoverage.coveredRows)/\(report.rowCoverage.totalSourceRows) rows"
                )

                ValidationCheckRow(
                    label: "Transaction Balance",
                    status: report.transactionBalance.isPerfect ? .pass : .critical,
                    detail: "\(report.transactionBalance.balancedCount)/\(report.transactionBalance.totalTransactions) balanced"
                )

                ValidationCheckRow(
                    label: "Running Cash Balance",
                    status: report.runningBalance.isPerfect ? .pass : (report.runningBalance.available ? .warning : .skip),
                    detail: report.runningBalance.available ?
                        (report.runningBalance.isPerfect ? "Matches CSV" : "\(report.runningBalance.discrepancies.count) discrepancies") :
                        "N/A"
                )

                ValidationCheckRow(
                    label: "Asset Positions",
                    status: report.assetPositions.isPerfect ? .pass : .warning,
                    detail: "\(report.assetPositions.assetCount) assets tracked"
                )

                ValidationCheckRow(
                    label: "Settlement Pairing",
                    status: report.settlementPairing.isPerfect ? .pass : .warning,
                    detail: "\(report.settlementPairing.properlyPaired) paired correctly"
                )
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }

    private var statusIcon: String {
        switch report.overallStatus {
        case .pass: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.seal.fill"
        }
    }

    private var statusColor: Color {
        switch report.overallStatus {
        case .pass: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private var statusText: String {
        switch report.overallStatus {
        case .pass: return "Pass"
        case .warning: return "Warnings"
        case .critical: return "Critical Issues"
        }
    }
}

struct ValidationCheckRow: View {
    let label: String
    let status: CheckStatus
    let detail: String

    enum CheckStatus {
        case pass
        case warning
        case critical
        case skip
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
                .frame(width: 16)

            Text(label)
                .font(.caption)
                .foregroundColor(.primary)

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var icon: String {
        switch status {
        case .pass: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .skip: return "minus.circle"
        }
    }

    private var color: Color {
        switch status {
        case .pass: return .green
        case .warning: return .orange
        case .critical: return .red
        case .skip: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    let account = Account(name: "Fidelity")
    return TransactionsPreviewPanel(
        account: account,
        selectedBatches: [],
        selectedVersion: .constant(nil),
        parsePlan: .constant(nil),
        selectedCategorizationSession: .constant(nil),
        hoveredRowIndex: .constant(nil)
    )
    .modelContainer(ModelContainer.preview)
    .frame(width: 400, height: 600)
}
