//
//  AnalyticsView.swift
//  cascade-ledger
//
//  Transaction analytics with time series charts
//

import SwiftUI
import SwiftData
import Charts

// This is a complete rewrite with category grouping and cumulative mode working
// Replace the existing AnalyticsView.swift with this

struct AnalyticsView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var chartMode: ChartMode = .flow
    @State private var groupBy: GroupByDimension = .category
    @State private var visibleGroups: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                AnalyticsContent(
                    account: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    chartMode: $chartMode,
                    groupBy: $groupBy,
                    visibleGroups: $visibleGroups
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.xyaxis.line",
                    description: Text("Select an account to view analytics")
                )
            }
        }
        .navigationTitle("Analytics")
    }
}

struct AnalyticsContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var chartMode: ChartMode
    @Binding var groupBy: GroupByDimension
    @Binding var visibleGroups: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LedgerEntry]

    @State private var timeSeriesData: [TimeSeriesDataPoint] = []
    @State private var groupSummaries: [GroupSummary] = []

    init(
        account: Account,
        timeRange: Binding<TimeRange>,
        granularity: Binding<TimeGranularity>,
        chartMode: Binding<ChartMode>,
        groupBy: Binding<GroupByDimension>,
        visibleGroups: Binding<Set<String>>
    ) {
        self.account = account
        self._timeRange = timeRange
        self._granularity = granularity
        self._chartMode = chartMode
        self._groupBy = groupBy
        self._visibleGroups = visibleGroups

        let accountId = account.id
        _allEntries = Query(
            filter: #Predicate<LedgerEntry> { entry in
                entry.account?.id == accountId
            },
            sort: \LedgerEntry.date
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .frame(width: 200)

                Picker("Group By", selection: $groupBy) {
                    ForEach(GroupByDimension.allCases, id: \.self) { dim in
                        Text(dim.displayName).tag(dim)
                    }
                }
                .frame(width: 180)

                Picker("Granularity", selection: $granularity) {
                    ForEach(TimeGranularity.allCases, id: \.self) { gran in
                        Text(gran.displayName).tag(gran)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Picker("Mode", selection: $chartMode) {
                    ForEach(ChartMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content: split view
            HSplitView {
                // Left: Breakdown cards
                GroupBreakdownPanel(
                    groupSummaries: groupSummaries,
                    visibleGroups: $visibleGroups,
                    groupBy: groupBy
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Time series chart
                TimeSeriesChartPanel(
                    timeSeriesData: filteredTimeSeriesData,
                    chartMode: chartMode,
                    granularity: granularity,
                    groupBy: groupBy
                )
                .frame(minWidth: 500, idealWidth: 700)
            }
        }
        .onAppear {
            aggregateData()
        }
        .onChange(of: timeRange) { _, _ in aggregateData() }
        .onChange(of: granularity) { _, _ in aggregateData() }
        .onChange(of: chartMode) { _, _ in aggregateData() }
        .onChange(of: groupBy) { _, _ in aggregateData() }
    }

    private var filteredTimeSeriesData: [TimeSeriesDataPoint] {
        timeSeriesData.filter { point in
            visibleGroups.contains(point.groupKey)
        }
    }

    private func aggregateData() {
        let dateRange = timeRange.dateRange
        let relevantEntries = allEntries.filter { entry in
            entry.date >= dateRange.start && entry.date <= dateRange.end
        }

        // Aggregate summaries
        groupSummaries = aggregateByDimension(relevantEntries, dimension: groupBy)

        // Initialize visible groups if empty
        if visibleGroups.isEmpty {
            visibleGroups = Set(groupSummaries.map { $0.groupKey })
        }

        // Create time series
        timeSeriesData = createTimeSeries(
            relevantEntries,
            granularity: granularity,
            groupBy: groupBy,
            chartMode: chartMode
        )
    }

    private func aggregateByDimension(_ entries: [LedgerEntry], dimension: GroupByDimension) -> [GroupSummary] {
        var summaries: [String: GroupSummary] = [:]

        for entry in entries {
            let groupKey = dimension.groupKey(for: entry)

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

        return summaries.values.sorted { abs($0.total) > abs($1.total) }
    }

    private func createTimeSeries(
        _ entries: [LedgerEntry],
        granularity: TimeGranularity,
        groupBy: GroupByDimension,
        chartMode: ChartMode
    ) -> [TimeSeriesDataPoint] {
        let calendar = Calendar.current
        var grouped: [Date: [String: Decimal]] = [:]

        // Group by period and dimension
        for entry in entries {
            let periodStart = granularity.periodStart(for: entry.date, calendar: calendar)
            let groupKey = groupBy.groupKey(for: entry)

            if grouped[periodStart] == nil {
                grouped[periodStart] = [:]
            }

            let currentAmount = grouped[periodStart]?[groupKey] ?? 0
            grouped[periodStart]?[groupKey] = currentAmount + entry.amount
        }

        // Convert to points
        var points: [TimeSeriesDataPoint] = []
        for (date, groupAmounts) in grouped.sorted(by: { $0.key < $1.key }) {
            for (groupKey, amount) in groupAmounts {
                points.append(TimeSeriesDataPoint(
                    date: date,
                    groupKey: groupKey,
                    amount: amount
                ))
            }
        }

        // Apply cumulative if needed
        if chartMode == .cumulative {
            points = calculateCumulative(points)
        }

        return points
    }

    private func calculateCumulative(_ points: [TimeSeriesDataPoint]) -> [TimeSeriesDataPoint] {
        var cumulative: [String: Decimal] = [:]
        var result: [TimeSeriesDataPoint] = []

        for point in points.sorted(by: { $0.date < $1.date }) {
            let current = cumulative[point.groupKey] ?? 0
            let newTotal = current + point.amount
            cumulative[point.groupKey] = newTotal

            result.append(TimeSeriesDataPoint(
                date: point.date,
                groupKey: point.groupKey,
                amount: newTotal
            ))
        }

        return result
    }
}

// MARK: - Supporting Views

struct GroupBreakdownPanel: View {
    let groupSummaries: [GroupSummary]
    @Binding var visibleGroups: Set<String>
    let groupBy: GroupByDimension

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(groupBy.displayName + " Breakdown", systemImage: "square.grid.2x2")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(groupSummaries, id: \.groupKey) { summary in
                        GroupSummaryCard(
                            summary: summary,
                            isVisible: visibleGroups.contains(summary.groupKey),
                            onToggle: {
                                toggleVisibility(summary.groupKey)
                            },
                            showReturns: groupBy == .asset
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func toggleVisibility(_ groupKey: String) {
        if visibleGroups.contains(groupKey) {
            visibleGroups.remove(groupKey)
        } else {
            visibleGroups.insert(groupKey)
        }
    }
}

struct GroupSummaryCard: View {
    let summary: GroupSummary
    let isVisible: Bool
    let onToggle: () -> Void
    var showReturns: Bool = false

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isVisible ? "checkmark.square.fill" : "square")
                    .foregroundColor(isVisible ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(summary.count) transactions")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if showReturns {
                        HStack(spacing: 4) {
                            Text("Return:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(summary.netReturn, format: .currency(code: "USD"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(summary.netReturn >= 0 ? .green : .red)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(abs(summary.total), format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(summary.total >= 0 ? .green : .red)

                    if showReturns {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down")
                                .font(.caption2)
                                .foregroundColor(.red)
                            Text(abs(summary.buys), format: .currency(code: "USD"))
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Image(systemName: "arrow.up")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text(abs(summary.sells), format: .currency(code: "USD"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(isVisible ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isVisible ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TimeSeriesChartPanel: View {
    let timeSeriesData: [TimeSeriesDataPoint]
    let chartMode: ChartMode
    let granularity: TimeGranularity
    let groupBy: GroupByDimension

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label(chartMode.displayName, systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if timeSeriesData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No data in selected range")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(timeSeriesData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Amount", NSDecimalNumber(decimal: point.amount).doubleValue)
                    )
                    .foregroundStyle(by: .value("Group", point.groupKey))
                    .symbol(by: .value("Group", point.groupKey))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.month().day())
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text(doubleValue, format: .currency(code: "USD"))
                            }
                        }
                    }
                }
                .chartLegend(position: .bottom)
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Data Models

struct TimeSeriesDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let groupKey: String  // Category name or Type.rawValue
    let amount: Decimal
}

struct GroupSummary {
    let groupKey: String
    let displayName: String
    var total: Decimal
    var count: Int
    var entries: [LedgerEntry]

    // For asset analysis
    var buys: Decimal {
        entries.filter { $0.effectiveTransactionType == .buy }
            .reduce(0) { $0 + $1.amount }
    }

    var sells: Decimal {
        entries.filter { $0.effectiveTransactionType == .sell }
            .reduce(0) { $0 + $1.amount }
    }

    var netReturn: Decimal {
        sells - buys // Positive = profit, Negative = loss
    }
}

struct TypeSummary {
    let type: TransactionType
    var total: Decimal
    var count: Int
    var entries: [LedgerEntry]
}

struct CategorySummary {
    let category: String
    var total: Decimal
    var count: Int
    var entries: [LedgerEntry]
}

enum GroupByDimension: String, CaseIterable {
    case category = "category"
    case type = "type"
    case topLevelCategory = "top_level"
    case asset = "asset"

    var displayName: String {
        switch self {
        case .category: return "Category"
        case .type: return "Type"
        case .topLevelCategory: return "Top-Level"
        case .asset: return "Asset"
        }
    }

    func groupKey(for entry: LedgerEntry) -> String {
        switch self {
        case .category:
            return entry.effectiveCategory
        case .type:
            return entry.effectiveTransactionType.rawValue.capitalized
        case .topLevelCategory:
            let category = entry.effectiveCategory
            if let colonIndex = category.firstIndex(of: ":") {
                return String(category[..<colonIndex])
            }
            return category
        case .asset:
            return entry.assetId ?? "Cash"
        }
    }
}

enum TimeRange: String, CaseIterable {
    case last7Days = "last_7_days"
    case last30Days = "last_30_days"
    case last90Days = "last_90_days"
    case last6Months = "last_6_months"
    case lastYear = "last_year"
    case allTime = "all_time"

    var displayName: String {
        switch self {
        case .last7Days: return "Last 7 Days"
        case .last30Days: return "Last 30 Days"
        case .last90Days: return "Last 90 Days"
        case .last6Months: return "Last 6 Months"
        case .lastYear: return "Last Year"
        case .allTime: return "All Time"
        }
    }

    var dateRange: (start: Date, end: Date) {
        let end = Date()
        let calendar = Calendar.current
        let start: Date

        switch self {
        case .last7Days:
            start = calendar.date(byAdding: .day, value: -7, to: end)!
        case .last30Days:
            start = calendar.date(byAdding: .day, value: -30, to: end)!
        case .last90Days:
            start = calendar.date(byAdding: .day, value: -90, to: end)!
        case .last6Months:
            start = calendar.date(byAdding: .month, value: -6, to: end)!
        case .lastYear:
            start = calendar.date(byAdding: .year, value: -1, to: end)!
        case .allTime:
            start = calendar.date(byAdding: .year, value: -10, to: end)!
        }

        return (start, end)
    }
}

enum TimeGranularity: String, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var displayName: String {
        rawValue.capitalized
    }

    func periodStart(for date: Date, calendar: Calendar) -> Date {
        switch self {
        case .daily:
            return calendar.startOfDay(for: date)
        case .weekly:
            let weekday = calendar.component(.weekday, from: date)
            let daysToSubtract = (weekday + 7 - calendar.firstWeekday) % 7
            return calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: date))!
        case .monthly:
            let components = calendar.dateComponents([.year, .month], from: date)
            return calendar.date(from: components)!
        }
    }
}

enum ChartMode: String, CaseIterable {
    case flow = "flow"
    case cumulative = "cumulative"

    var displayName: String {
        switch self {
        case .flow: return "Flow"
        case .cumulative: return "Cumulative"
        }
    }
}
