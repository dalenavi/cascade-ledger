//
//  TransactionsView.swift
//  cascade-ledger
//
//  Transaction list view
//

import SwiftUI
import SwiftData

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    let selectedAccount: Account?

    @State private var searchText = ""
    @State private var selectedTransactions: Set<UUID> = []
    @State private var showingDetail: LedgerEntry?
    @State private var showingCategorizationAgent = false
    @State private var categorizationMessages: [ChatMessage] = []
    @State private var isCategorizing = false
    @State private var showingFilters = false
    @State private var filterBy: GroupByDimension = .category
    @State private var visibleGroups: Set<String> = []
    @State private var showUncategorized = true

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                VStack(spacing: 0) {
                    // Filter panel
                    if showingFilters {
                        TransactionFilterPanel(
                            filterBy: $filterBy,
                            visibleGroups: $visibleGroups,
                            showUncategorized: $showUncategorized,
                            account: account
                        )
                    }

                    // Selection toolbar
                    if !selectedTransactions.isEmpty {
                        HStack {
                            Text("\(selectedTransactions.count) selected")
                                .font(.headline)

                            Spacer()

                            Button("Deselect All") {
                                selectedTransactions = []
                            }
                            .buttonStyle(.bordered)

                            Button(action: {
                                requestCategorization(account: account)
                            }) {
                                if isCategorizing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                } else {
                                    Label("Categorize Selected", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isCategorizing)
                        }
                        .padding()
                        .background(Color.blue.opacity(0.1))
                    }

                    TransactionsList(
                        account: account,
                        searchText: searchText,
                        selectedTransactions: $selectedTransactions,
                        filterBy: filterBy,
                        visibleGroups: visibleGroups,
                        showUncategorized: showUncategorized,
                        onShowDetail: { transaction in
                            showingDetail = transaction
                        }
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(action: { showingFilters.toggle() }) {
                            Label(showingFilters ? "Hide Filters" : "Filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    ZStack(alignment: .bottomTrailing) {
                        if showingCategorizationAgent {
                            CategorizationAgentWindow(
                                account: account,
                                messages: $categorizationMessages,
                                showingAgent: $showingCategorizationAgent
                            )
                            .frame(width: 450, height: 600)
                            .padding(20)
                        } else if !selectedTransactions.isEmpty {
                            Button(action: { showingCategorizationAgent = true }) {
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
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Select an account to view transactions")
                )
            }
        }
        .navigationTitle("Transactions")
        .searchable(text: $searchText, prompt: "Search transactions")
        .sheet(item: $showingDetail) { transaction in
            TransactionDetailView(entry: transaction)
        }
    }

    private func requestCategorization(account: Account) {
        guard !selectedTransactions.isEmpty else { return }

        showingCategorizationAgent = true
        isCategorizing = true

        // Add system message
        categorizationMessages.append(ChatMessage(
            role: .system,
            content: """
            Starting categorization for \(selectedTransactions.count) selected transactions...

            Claude will analyze each transaction individually and propose:
            - Transaction type (if needs correction)
            - Category
            - Tags
            - Confidence level

            High confidence (>90%) will auto-apply.
            Lower confidence will be marked as tentative for your review.
            """
        ))

        Task {
            do {
                // Get selected transaction entities
                let transactionsToCategorize = try await getSelectedTransactionEntities(account: account)

                if transactionsToCategorize.isEmpty {
                    await MainActor.run {
                        categorizationMessages.append(ChatMessage(
                            role: .system,
                            content: "⚠️ No transactions found to categorize."
                        ))
                        isCategorizing = false
                    }
                    return
                }

                let categorizationService = CategorizationService(modelContext: modelContext)

                // Show progress message
                await MainActor.run {
                    categorizationMessages.append(ChatMessage(
                        role: .system,
                        content: "Processing \(transactionsToCategorize.count) transactions in batches of 10 (chronological order)..."
                    ))
                }

                // Categorize in batches
                let attempts = try await categorizationService.categorizeTransactions(
                    transactionsToCategorize,
                    account: account
                )

                // Summary of results
                let highConfidence = attempts.filter { $0.confidence >= 0.9 }.count
                let mediumConfidence = attempts.filter { $0.confidence >= 0.5 && $0.confidence < 0.9 }.count
                let lowConfidence = attempts.filter { $0.confidence < 0.5 }.count

                await MainActor.run {
                    categorizationMessages.append(ChatMessage(
                        role: .system,
                        content: """
                        ✅ Categorization complete!

                        \(transactionsToCategorize.count) transactions processed in chronological order.

                        Results:
                        • \(highConfidence) high confidence (≥90%) - auto-applied
                        • \(mediumConfidence) medium confidence (50-90%) - marked as tentative
                        • \(lowConfidence) low confidence (<50%) - needs review

                        Check the transaction list for proposed categories (shown in blue sparkles).
                        """
                    ))
                    isCategorizing = false
                }
            } catch {
                await MainActor.run {
                    categorizationMessages.append(ChatMessage(
                        role: .system,
                        content: "❌ Error: \(error.localizedDescription)"
                    ))
                    isCategorizing = false
                }
            }
        }
    }

    private func getSelectedTransactionEntities(account: Account) async throws -> [LedgerEntry] {
        let descriptor = FetchDescriptor<LedgerEntry>()
        let allEntries = try modelContext.fetch(descriptor)

        return allEntries.filter { selectedTransactions.contains($0.id) }
    }
}

struct TransactionsList: View {
    let account: Account
    let searchText: String
    @Binding var selectedTransactions: Set<UUID>
    let filterBy: GroupByDimension
    let visibleGroups: Set<String>
    let showUncategorized: Bool
    let onShowDetail: (LedgerEntry) -> Void

    @Query private var entries: [LedgerEntry]

    init(
        account: Account,
        searchText: String,
        selectedTransactions: Binding<Set<UUID>>,
        filterBy: GroupByDimension,
        visibleGroups: Set<String>,
        showUncategorized: Bool,
        onShowDetail: @escaping (LedgerEntry) -> Void
    ) {
        self.account = account
        self.searchText = searchText
        self._selectedTransactions = selectedTransactions
        self.filterBy = filterBy
        self.visibleGroups = visibleGroups
        self.showUncategorized = showUncategorized
        self.onShowDetail = onShowDetail

        let accountId = account.id
        // Configure query based on account
        _entries = Query(
            filter: #Predicate<LedgerEntry> { entry in
                entry.account?.id == accountId
            },
            sort: \LedgerEntry.date,
            order: .reverse
        )
    }

    private var filteredEntries: [LedgerEntry] {
        entries.filter { entry in
            // Uncategorized filter
            if entry.effectiveCategory == "Uncategorized" && !showUncategorized {
                return false
            }

            // Dimension-based filter
            if visibleGroups.isEmpty {
                return true // No filters applied yet
            }

            let groupKey = filterBy.groupKey(for: entry)
            return visibleGroups.contains(groupKey)
        }
    }

    var body: some View {
        List(selection: $selectedTransactions) {
            if filteredEntries.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "list.bullet.rectangle",
                    description: Text(entries.isEmpty ? "Import data using Parse Studio to see transactions" : "No transactions match the current filters")
                )
            } else {
                ForEach(filteredEntries) { entry in
                    TransactionRowWithCategorization(
                        entry: entry,
                        isSelected: selectedTransactions.contains(entry.id),
                        onToggleSelection: {
                            toggleSelection(entry)
                        },
                        onShowDetail: {
                            onShowDetail(entry)
                        }
                    )
                    .tag(entry.id)
                }
            }
        }
    }

    private func toggleSelection(_ entry: LedgerEntry) {
        if selectedTransactions.contains(entry.id) {
            selectedTransactions.remove(entry.id)
        } else {
            selectedTransactions.insert(entry.id)
        }
    }
}

struct TransactionFilterPanel: View {
    @Binding var filterBy: GroupByDimension
    @Binding var visibleGroups: Set<String>
    @Binding var showUncategorized: Bool
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LedgerEntry]

    init(
        filterBy: Binding<GroupByDimension>,
        visibleGroups: Binding<Set<String>>,
        showUncategorized: Binding<Bool>,
        account: Account
    ) {
        self._filterBy = filterBy
        self._visibleGroups = visibleGroups
        self._showUncategorized = showUncategorized
        self.account = account

        let accountId = account.id
        _allEntries = Query(
            filter: #Predicate<LedgerEntry> { entry in
                entry.account?.id == accountId
            }
        )
    }

    private var availableGroups: [String] {
        let uniqueKeys = Set(allEntries.map { filterBy.groupKey(for: $0) })
        return uniqueKeys.sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Filter by")
                    .font(.headline)

                Picker("", selection: $filterBy) {
                    ForEach(GroupByDimension.allCases, id: \.self) { dim in
                        Text(dim.displayName).tag(dim)
                    }
                }
                .frame(width: 150)
            }

            FlowLayout(spacing: 8) {
                // Uncategorized toggle (only for category filter)
                if filterBy == .category || filterBy == .topLevelCategory {
                    FilterToggle(
                        label: "Uncategorized",
                        isOn: $showUncategorized,
                        color: .gray
                    )
                }

                // Dynamic group toggles
                ForEach(availableGroups, id: \.self) { groupKey in
                    FilterToggle(
                        label: groupKey,
                        isOn: Binding(
                            get: {
                                // If empty, show all
                                if visibleGroups.isEmpty { return true }
                                return visibleGroups.contains(groupKey)
                            },
                            set: { isOn in
                                // Initialize with all groups if first interaction
                                if visibleGroups.isEmpty {
                                    visibleGroups = Set(availableGroups)
                                }

                                if isOn {
                                    visibleGroups.insert(groupKey)
                                } else {
                                    visibleGroups.remove(groupKey)
                                }
                            }
                        ),
                        color: .blue
                    )
                }
            }

            HStack {
                Button("Select All") {
                    visibleGroups = Set(availableGroups)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Deselect All") {
                    visibleGroups = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isOn ? color : .secondary)
                Text(label)
                    .font(.caption)
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.15) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isOn ? color : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x, y: bounds.minY + result.positions[index].y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}

struct TransactionRowWithCategorization: View {
    let entry: LedgerEntry
    let isSelected: Bool
    let onToggleSelection: () -> Void
    let onShowDetail: () -> Void

    private var tentativeAttempt: CategorizationAttempt? {
        entry.categorizationAttempts.first { $0.status == .tentative }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            // Transaction info
            Button(action: onShowDetail) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.transactionDescription)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            Text(entry.date, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Current category
                            let category = entry.effectiveCategory
                            if category != "Uncategorized" {
                                Text(category)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            }

                            // Tentative category (if exists)
                            if let tentative = tentativeAttempt, let proposed = tentative.proposedCategory {
                                HStack(spacing: 4) {
                                    Image(systemName: "sparkles")
                                        .font(.caption2)
                                    Text(proposed)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)

                                Text("\(Int(tentative.confidence * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            // Tags
                            ForEach(entry.tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.15))
                                    .foregroundColor(.purple)
                                    .cornerRadius(3)
                            }

                            if entry.tags.count > 2 {
                                Text("+\(entry.tags.count - 2)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(entry.amount, format: .currency(code: "USD"))
                            .font(.headline)
                            .foregroundColor(amountColor)

                        Text(entry.effectiveTransactionType.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var amountColor: Color {
        switch entry.effectiveTransactionType {
        case .credit, .deposit, .dividend, .interest, .sell:
            return .green
        case .debit, .withdrawal, .fee, .tax, .buy:
            return .red
        case .transfer:
            return .blue
        }
    }
}

struct TransactionRow: View {
    let entry: LedgerEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.transactionDescription)
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Text(entry.date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let category = entry.effectiveCategory
                    if category != "Uncategorized" {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(category)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(entry.amount, format: .currency(code: "USD"))
                    .font(.headline)
                    .foregroundColor(amountColor)

                Text(entry.effectiveTransactionType.rawValue)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var amountColor: Color {
        switch entry.effectiveTransactionType {
        case .credit, .deposit, .dividend, .interest, .sell:
            return .green
        case .debit, .withdrawal, .fee, .tax, .buy:
            return .red
        case .transfer:
            return .blue
        }
    }
}