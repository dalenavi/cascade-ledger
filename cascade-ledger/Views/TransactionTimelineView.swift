//
//  TransactionTimelineView.swift
//  cascade-ledger
//
//  Filtered transaction list view with analytics-style filtering
//

import SwiftUI
import SwiftData

struct TransactionTimelineView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var filterBy: GroupByDimension = .category
    @State private var visibleGroups: Set<String> = []
    @State private var showUncategorized = true
    @State private var searchText = ""
    @State private var showingDetail: LedgerEntry?

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                TimelineContent(
                    account: account,
                    timeRange: $timeRange,
                    filterBy: $filterBy,
                    visibleGroups: $visibleGroups,
                    showUncategorized: $showUncategorized,
                    searchText: $searchText,
                    showingDetail: $showingDetail
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "list.timeline.rectangle",
                    description: Text("Select an account to view timeline")
                )
            }
        }
        .navigationTitle("Transaction Timeline")
        .searchable(text: $searchText, prompt: "Search transactions")
        .sheet(item: $showingDetail) { transaction in
            TransactionDetailView(entry: transaction)
        }
    }
}

struct TimelineContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var filterBy: GroupByDimension
    @Binding var visibleGroups: Set<String>
    @Binding var showUncategorized: Bool
    @Binding var searchText: String
    @Binding var showingDetail: LedgerEntry?

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LedgerEntry]

    @State private var groupSummaries: [GroupSummary] = []

    init(
        account: Account,
        timeRange: Binding<TimeRange>,
        filterBy: Binding<GroupByDimension>,
        visibleGroups: Binding<Set<String>>,
        showUncategorized: Binding<Bool>,
        searchText: Binding<String>,
        showingDetail: Binding<LedgerEntry?>
    ) {
        self.account = account
        self._timeRange = timeRange
        self._filterBy = filterBy
        self._visibleGroups = visibleGroups
        self._showUncategorized = showUncategorized
        self._searchText = searchText
        self._showingDetail = showingDetail

        let accountId = account.id
        _allEntries = Query(
            filter: #Predicate<LedgerEntry> { entry in
                entry.account?.id == accountId
            },
            sort: \LedgerEntry.date,
            order: .reverse
        )
    }

    private var filteredEntries: [LedgerEntry] {
        let dateRange = timeRange.dateRange

        return allEntries.filter { entry in
            // Date range filter
            guard entry.date >= dateRange.start && entry.date <= dateRange.end else {
                return false
            }

            // Uncategorized filter
            if entry.effectiveCategory == "Uncategorized" && !showUncategorized {
                return false
            }

            // Dimension filter
            if !visibleGroups.isEmpty {
                let groupKey = filterBy.groupKey(for: entry)
                guard visibleGroups.contains(groupKey) else {
                    return false
                }
            }

            // Search filter
            if !searchText.isEmpty {
                let lowercased = searchText.lowercased()
                return entry.transactionDescription.lowercased().contains(lowercased)
                    || entry.effectiveCategory.lowercased().contains(lowercased)
                    || entry.tags.contains { $0.lowercased().contains(lowercased) }
            }

            return true
        }
    }

    private var uncategorizedCount: Int {
        filteredEntries.filter { $0.effectiveCategory == "Uncategorized" }.count
    }

    private var tentativeCount: Int {
        filteredEntries.filter { $0.hasTentativeCategorization }.count
    }

    var body: some View {
        HSplitView {
            // Left: Breakdown summary
            GroupBreakdownPanel(
                groupSummaries: groupSummaries,
                visibleGroups: $visibleGroups,
                groupBy: filterBy
            )
            .frame(minWidth: 300, idealWidth: 350)

            // Right: Transaction list
            VStack(spacing: 0) {
                // Controls
                HStack {
                    Picker("Time Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .frame(width: 200)

                    Picker("Group By", selection: $filterBy) {
                        ForEach(GroupByDimension.allCases, id: \.self) { dim in
                            Text(dim.displayName).tag(dim)
                        }
                    }
                    .frame(width: 180)

                    Spacer()

                    HStack(spacing: 16) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(filteredEntries.count)")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("visible")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(uncategorizedCount)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(uncategorizedCount > 0 ? .orange : .green)
                            Text("uncategorized")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(tentativeCount)")
                                .font(.title3)
                                .fontWeight(.bold)
                                .foregroundColor(tentativeCount > 0 ? .blue : .secondary)
                            Text("tentative")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Transaction list
                List {
                    if filteredEntries.isEmpty {
                        ContentUnavailableView(
                            "No Transactions",
                            systemImage: "list.bullet.rectangle",
                            description: Text("No transactions match the filters")
                        )
                    } else {
                        ForEach(filteredEntries) { entry in
                            TransactionRowWithCategorization(
                                entry: entry,
                                isSelected: false,
                                onToggleSelection: {},
                                onShowDetail: {
                                    showingDetail = entry
                                }
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            aggregateData()
        }
        .onChange(of: timeRange) { _, _ in aggregateData() }
        .onChange(of: filterBy) { _, _ in aggregateData() }
    }

    private func aggregateData() {
        let dateRange = timeRange.dateRange
        let relevantEntries = allEntries.filter { entry in
            entry.date >= dateRange.start && entry.date <= dateRange.end
        }

        var summaries: [String: GroupSummary] = [:]

        for entry in relevantEntries {
            let groupKey = filterBy.groupKey(for: entry)

            if summaries[groupKey] == nil {
                summaries[groupKey] = GroupSummary(
                    groupKey: groupKey,
                    displayName: groupKey,
                    total: 0,
                    count: 0,
                    entries: []
                )
            }
            summaries[groupKey]?.total += entry.amount
            summaries[groupKey]?.count += 1
            summaries[groupKey]?.entries.append(entry)
        }

        groupSummaries = summaries.values.sorted { abs($0.total) > abs($1.total) }

        // Initialize visible groups if empty
        if visibleGroups.isEmpty {
            visibleGroups = Set(groupSummaries.map { $0.groupKey })
        }
    }
}
