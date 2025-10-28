//
//  BalanceView.swift
//  cascade-ledger
//
//  Account balance view with asset holdings
//

import SwiftUI
import SwiftData
import Charts

struct BalanceView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var balanceMode: BalanceMode = .cash
    @State private var selectedAccounts: Set<UUID> = []
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                BalanceContent(
                    primaryAccount: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    balanceMode: $balanceMode,
                    selectedAccounts: $selectedAccounts,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.bar.fill",
                    description: Text("Select an account to view balance")
                )
            }
        }
        .navigationTitle("Account Balance")
    }
}

enum BalanceMode: String, CaseIterable {
    case cash = "cash"
    case holdings = "holdings"

    var displayName: String {
        switch self {
        case .cash: return "Cash Flow"
        case .holdings: return "Holdings"
        }
    }
}

struct BalanceContent: View {
    let primaryAccount: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var balanceMode: BalanceMode
    @Binding var selectedAccounts: Set<UUID>
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allAccounts: [Account]
    @Query private var allEntries: [Transaction]

    @State private var balanceData: [AccountBalancePoint] = []
    @State private var currentBalance: Decimal = 0
    @State private var assetSummaries: [AssetSummary] = []

    init(
        primaryAccount: Account,
        timeRange: Binding<TimeRange>,
        granularity: Binding<TimeGranularity>,
        balanceMode: Binding<BalanceMode>,
        selectedAccounts: Binding<Set<UUID>>,
        selectedAssets: Binding<Set<String>>
    ) {
        self.primaryAccount = primaryAccount
        self._timeRange = timeRange
        self._granularity = granularity
        self._balanceMode = balanceMode
        self._selectedAccounts = selectedAccounts
        self._selectedAssets = selectedAssets

        _allAccounts = Query(sort: \Account.name)
        _allEntries = Query(sort: \Transaction.date)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack {
                Picker("Mode", selection: $balanceMode) {
                    ForEach(BalanceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .frame(width: 180)

                Picker("Granularity", selection: $granularity) {
                    ForEach(TimeGranularity.allCases, id: \.self) { gran in
                        Text(gran.displayName).tag(gran)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Spacer()

                if balanceMode == .cash {
                    VStack(alignment: .trailing) {
                        Text("Current Balance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(currentBalance, format: .currency(code: "USD"))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(currentBalance >= 0 ? .green : .red)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main content
            if balanceMode == .holdings {
                // Holdings mode: Asset selector + chart
                HSplitView {
                    AssetSelectorPanel(
                        assetSummaries: assetSummaries,
                        selectedAssets: $selectedAssets
                    )
                    .frame(minWidth: 300, idealWidth: 350)

                    BalanceChartView(
                        balanceData: balanceData,
                        granularity: granularity
                    )
                    .frame(minWidth: 500)
                }
            } else {
                // Cash flow mode: Just chart
                BalanceChartView(
                    balanceData: balanceData,
                    granularity: granularity
                )
            }
        }
        .onAppear {
            initializeState()
        }
        .onChange(of: timeRange) { _, _ in recalculate() }
        .onChange(of: granularity) { _, _ in recalculate() }
        .onChange(of: balanceMode) { _, _ in recalculate() }
        .onChange(of: selectedAssets) { _, _ in recalculate() }
    }

    private func initializeState() {
        if selectedAccounts.isEmpty {
            selectedAccounts = [primaryAccount.id]
        }
        recalculate()
    }

    private func recalculate() {
        discoverAssets()
        calculateBalance()
    }

    private func discoverAssets() {
        let dateRange = timeRange.dateRange
        let relevantEntries = allEntries.filter { entry in
            entry.account?.id == primaryAccount.id &&
            entry.date >= dateRange.start &&
            entry.date <= dateRange.end
        }

        var summaries: [String: AssetSummary] = [:]

        // Add USD (cash)
        let cashEntries = relevantEntries.filter { $0.assetId == nil }
        if !cashEntries.isEmpty {
            let cashBalance = cashEntries.reduce(0) { $0 + $1.amount }
            summaries["USD"] = AssetSummary(
                asset: "USD",
                currentHoldings: cashBalance,
                transactionCount: cashEntries.count
            )
        }

        // Add other assets - calculate CURRENT holdings (all time)
        let allAccountEntries = allEntries.filter { $0.account?.id == primaryAccount.id }

        for entry in allAccountEntries where entry.assetId != nil {
            let assetId = entry.assetId!

            if summaries[assetId] == nil {
                summaries[assetId] = AssetSummary(
                    asset: assetId,
                    currentHoldings: 0,
                    transactionCount: 0
                )
            }

            // Track current position (all time)
            if entry.effectiveTransactionType == .buy {
                summaries[assetId]?.currentHoldings += abs(entry.amount)
            } else if entry.effectiveTransactionType == .sell {
                summaries[assetId]?.currentHoldings -= abs(entry.amount)
            }
        }

        // Count transactions in selected date range
        for entry in relevantEntries where entry.assetId != nil {
            if let existing = summaries[entry.assetId!] {
                summaries[entry.assetId!] = AssetSummary(
                    asset: existing.asset,
                    currentHoldings: existing.currentHoldings,
                    transactionCount: existing.transactionCount + 1
                )
            }
        }

        // Sort alphabetically for stable order (USD always first)
        assetSummaries = summaries.values
            .filter { $0.transactionCount > 0 || abs($0.currentHoldings) > 0.01 }
            .sorted { lhs, rhs in
                if lhs.asset == "USD" { return true }
                if rhs.asset == "USD" { return false }
                return lhs.asset < rhs.asset
            }

        // Initialize selected assets if empty
        if selectedAssets.isEmpty && balanceMode == .holdings {
            selectedAssets = Set(assetSummaries.map { $0.asset })
        }
    }

    private func calculateBalance() {
        let dateRange = timeRange.dateRange

        if balanceMode == .cash {
            // Cash flow mode
            let accountEntries = allEntries.filter { entry in
                entry.account?.id == primaryAccount.id &&
                entry.date >= dateRange.start &&
                entry.date <= dateRange.end
            }

            balanceData = calculateCumulativeBalance(
                accountEntries,
                name: primaryAccount.name
            )

            currentBalance = allEntries
                .filter { $0.account?.id == primaryAccount.id }
                .reduce(0) { $0 + $1.amount }
        } else {
            // Holdings mode
            var points: [AccountBalancePoint] = []

            for asset in selectedAssets {
                let assetEntries = allEntries.filter { entry in
                    entry.account?.id == primaryAccount.id &&
                    (asset == "USD" ? entry.assetId == nil : entry.assetId == asset) &&
                    entry.date >= dateRange.start &&
                    entry.date <= dateRange.end
                }

                let holdingsPoints = calculateHoldingsForAsset(
                    assetEntries,
                    assetName: asset
                )
                points.append(contentsOf: holdingsPoints)
            }

            balanceData = points.sorted { $0.date < $1.date }
        }
    }

    private func calculateCumulativeBalance(
        _ entries: [Transaction],
        name: String
    ) -> [AccountBalancePoint] {
        let calendar = Calendar.current
        var grouped: [Date: Decimal] = [:]

        for entry in entries {
            let periodStart = granularity.periodStart(for: entry.date, calendar: calendar)
            grouped[periodStart, default: 0] += entry.amount
        }

        var cumulative: Decimal = 0
        var points: [AccountBalancePoint] = []

        for (date, amount) in grouped.sorted(by: { $0.key < $1.key }) {
            cumulative += amount
            points.append(AccountBalancePoint(
                date: date,
                accountName: name,
                balance: cumulative
            ))
        }

        return points
    }

    private func calculateHoldingsForAsset(
        _ entries: [Transaction],
        assetName: String
    ) -> [AccountBalancePoint] {
        guard !entries.isEmpty else { return [] }

        let calendar = Calendar.current
        var grouped: [Date: Decimal] = [:]

        print("=== Holdings for \(assetName) ===")
        print("Processing \(entries.count) entries")

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let periodStart = granularity.periodStart(for: entry.date, calendar: calendar)

            let positionChange: Decimal
            if entry.effectiveTransactionType == .buy {
                // Buy adds to position (you now own more)
                positionChange = abs(entry.amount)
                print("  \(entry.date.formatted(date: .abbreviated, time: .omitted)): BUY \(entry.amount) → position +\(positionChange)")
            } else if entry.effectiveTransactionType == .sell {
                // Sell reduces position (you now own less)
                positionChange = -abs(entry.amount)
                print("  \(entry.date.formatted(date: .abbreviated, time: .omitted)): SELL \(entry.amount) → position \(positionChange)")
            } else {
                positionChange = 0
            }

            grouped[periodStart, default: 0] += positionChange
        }

        var cumulativeHoldings: Decimal = 0
        var points: [AccountBalancePoint] = []

        // Add starting point at 0 before first transaction
        if let firstDate = grouped.keys.min() {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: firstDate)!
            points.append(AccountBalancePoint(
                date: dayBefore,
                accountName: assetName,
                balance: 0
            ))
            print("  Starting point: \(dayBefore.formatted(date: .abbreviated, time: .omitted)) = $0")
        }

        // Accumulate position changes
        for (date, positionChange) in grouped.sorted(by: { $0.key < $1.key }) {
            cumulativeHoldings += positionChange
            points.append(AccountBalancePoint(
                date: date,
                accountName: assetName,
                balance: cumulativeHoldings
            ))
            print("  \(date.formatted(date: .abbreviated, time: .omitted)): change \(positionChange) → holdings \(cumulativeHoldings)")
        }

        print("Final position: \(cumulativeHoldings)")
        print("================")

        return points
    }
}

struct AssetSelectorPanel: View {
    let assetSummaries: [AssetSummary]
    @Binding var selectedAssets: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Asset Holdings", systemImage: "building.columns")
                    .font(.headline)
                Spacer()

                Button("Select All") {
                    selectedAssets = Set(assetSummaries.map { $0.asset })
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Deselect All") {
                    selectedAssets = []
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    ForEach(assetSummaries, id: \.asset) { summary in
                        AssetSummaryCard(
                            summary: summary,
                            isSelected: selectedAssets.contains(summary.asset),
                            onToggle: {
                                toggleAsset(summary.asset)
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func toggleAsset(_ asset: String) {
        if selectedAssets.contains(asset) {
            selectedAssets.remove(asset)
        } else {
            selectedAssets.insert(asset)
        }
    }
}

struct AssetSummaryCard: View {
    let summary: AssetSummary
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.asset)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(summary.transactionCount) transactions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(abs(summary.currentHoldings), format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(summary.currentHoldings >= 0 ? .green : .red)

                    Text("Cost Basis")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

struct BalanceChartView: View {
    let balanceData: [AccountBalancePoint]
    let granularity: TimeGranularity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Balance Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if balanceData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No data in selected range")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(balanceData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Balance", NSDecimalNumber(decimal: point.balance).doubleValue)
                    )
                    .foregroundStyle(by: .value("Asset", point.accountName))
                    .symbol(by: .value("Asset", point.accountName))
                    .lineStyle(StrokeStyle(lineWidth: 2))
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

struct AssetSummary {
    let asset: String
    var currentHoldings: Decimal
    var transactionCount: Int
}

struct AccountBalancePoint: Identifiable {
    let id = UUID()
    let date: Date
    let accountName: String
    let balance: Decimal
}
