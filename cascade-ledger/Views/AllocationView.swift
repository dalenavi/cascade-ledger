//
//  AllocationView.swift
//  cascade-ledger
//
//  Asset allocation tracking - shows % allocation by individual asset over time
//

import SwiftUI
import SwiftData
import Charts

struct AllocationView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                AllocationContent(
                    account: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.pie",
                    description: Text("Select an account to view asset allocation")
                )
            }
        }
        .navigationTitle("Asset Allocation")
    }
}

struct AllocationContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [Transaction]
    @Query private var allPrices: [AssetPrice]

    @State private var allocationData: [AllocationPoint] = []
    @State private var assetSummaries: [AssetAllocationSummary] = []
    @State private var totalValue: Decimal = 0

    init(
        account: Account,
        timeRange: Binding<TimeRange>,
        granularity: Binding<TimeGranularity>,
        selectedAssets: Binding<Set<String>>
    ) {
        self.account = account
        self._timeRange = timeRange
        self._granularity = granularity
        self._selectedAssets = selectedAssets

        let accountId = account.id
        _allEntries = Query(
            filter: #Predicate<Transaction> { entry in
                entry.account?.id == accountId
            },
            sort: \Transaction.date
        )

        _allPrices = Query(sort: \AssetPrice.date)
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

                Picker("Granularity", selection: $granularity) {
                    ForEach(TimeGranularity.allCases, id: \.self) { gran in
                        Text(gran.displayName).tag(gran)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Portfolio")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(totalValue, format: .currency(code: "USD"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Split view
            HSplitView {
                // Left: Asset allocation cards
                AssetAllocationPanel(
                    assetSummaries: assetSummaries,
                    selectedAssets: $selectedAssets
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Allocation chart over time
                AllocationChartView(
                    allocationData: filteredAllocationData,
                    granularity: granularity
                )
                .frame(minWidth: 500)
            }
        }
        .onAppear {
            calculateAllocation()
        }
        .onChange(of: timeRange) { _, _ in calculateAllocation() }
        .onChange(of: granularity) { _, _ in calculateAllocation() }
        .onChange(of: selectedAssets) { _, _ in updateChart() }
    }

    private var filteredAllocationData: [AllocationPoint] {
        allocationData.filter { selectedAssets.contains($0.assetId) }
    }

    private func calculateAllocation() {
        print("\n=== Asset Allocation Calculation ===")
        let dateRange = timeRange.dateRange
        let calendar = Calendar.current

        // Build position timeline for all assets
        var assetTimelines: [String: [(Date, Decimal)]] = [:]  // assetId -> [(date, quantity)]
        var cashTimeline: [(Date, Decimal)] = []
        var spaxxTimeline: [(Date, Decimal)] = []

        var cashBalance: Decimal = 0
        var spaxxBalance: Decimal = 0

        print("Building position timelines from \(allEntries.count) transactions...")

        for transaction in allEntries.sorted(by: { $0.date < $1.date }) {
            for entry in transaction.journalEntries {
                let debit = entry.debitAmount ?? 0
                let credit = entry.creditAmount ?? 0

                switch entry.accountType {
                case .cash:
                    if entry.accountName == "Cash USD" {
                        cashBalance += debit - credit
                        cashTimeline.append((transaction.date, cashBalance))
                    } else if entry.accountName.uppercased() == "SPAXX" {
                        spaxxBalance += debit - credit
                        spaxxTimeline.append((transaction.date, spaxxBalance))
                    }

                case .asset:
                    let assetId = entry.accountName
                    let quantity = entry.quantity ?? 0

                    if quantity != 0 {
                        let currentQty = assetTimelines[assetId]?.last?.1 ?? 0
                        let newQty = currentQty + (debit > 0 ? quantity : -quantity)
                        assetTimelines[assetId, default: []].append((transaction.date, newQty))
                    }

                default:
                    break
                }
            }
        }

        print("Asset timelines: \(assetTimelines.keys.sorted())")

        // Generate sample dates
        let sampleDates = generateSampleDates(from: dateRange.start, to: dateRange.end, granularity: granularity, calendar: calendar)

        print("Calculating allocation for \(sampleDates.count) sample dates...")

        // Calculate allocation at each sample date
        var allocationPoints: [AllocationPoint] = []

        for sampleDate in sampleDates {
            // Calculate total portfolio value at this date
            var assetValues: [String: Decimal] = [:]
            var totalAtDate: Decimal = 0

            // Cash USD
            if let cashAtDate = cashTimeline.filter({ $0.0 <= sampleDate }).last?.1, abs(cashAtDate) > 0.01 {
                assetValues["Cash USD"] = cashAtDate
                totalAtDate += cashAtDate
            }

            // SPAXX
            if let spaxxAtDate = spaxxTimeline.filter({ $0.0 <= sampleDate }).last?.1, abs(spaxxAtDate) > 0.01 {
                assetValues["SPAXX"] = spaxxAtDate  // SPAXX is $1/share
                totalAtDate += spaxxAtDate
            }

            // Other assets
            for (assetId, timeline) in assetTimelines {
                if let qtyAtDate = timeline.filter({ $0.0 <= sampleDate }).last?.1, abs(qtyAtDate) > 0.0001 {
                    let price = getPrice(for: assetId, on: sampleDate)
                    let value = qtyAtDate * price
                    if abs(value) > 0.01 {
                        assetValues[assetId] = value
                        totalAtDate += value
                    }
                }
            }

            // Convert to percentages
            if totalAtDate > 0 {
                for (assetId, value) in assetValues {
                    let percentage = (value / totalAtDate) * 100

                    allocationPoints.append(AllocationPoint(
                        date: sampleDate,
                        assetId: assetId,
                        percentage: percentage
                    ))
                }
            }
        }

        allocationData = allocationPoints.sorted { $0.date < $1.date }

        // Calculate current allocation
        calculateCurrentAllocation()

        print("Generated \(allocationData.count) allocation points for \(Set(allocationData.map { $0.assetId }).count) assets")
        print("===================================\n")

        updateChart()
    }

    private func calculateCurrentAllocation() {
        // Calculate current holdings
        var assetHoldings: [String: Decimal] = [:]
        var cashBalance: Decimal = 0
        var spaxxBalance: Decimal = 0

        for transaction in allEntries {
            for entry in transaction.journalEntries {
                let debit = entry.debitAmount ?? 0
                let credit = entry.creditAmount ?? 0

                switch entry.accountType {
                case .cash:
                    if entry.accountName == "Cash USD" {
                        cashBalance += debit - credit
                    } else if entry.accountName.uppercased() == "SPAXX" {
                        spaxxBalance += debit - credit
                    }
                case .asset:
                    let quantity = entry.quantity ?? 0
                    if debit > 0 {
                        assetHoldings[entry.accountName, default: 0] += quantity
                    } else if credit > 0 {
                        assetHoldings[entry.accountName, default: 0] -= quantity
                    }
                default:
                    break
                }
            }
        }

        // Calculate market values
        var assetValues: [String: Decimal] = [:]
        var total: Decimal = 0

        if abs(cashBalance) > 0.01 {
            assetValues["Cash USD"] = cashBalance
            total += cashBalance
        }
        if abs(spaxxBalance) > 0.01 {
            assetValues["SPAXX"] = spaxxBalance
            total += spaxxBalance
        }

        for (assetId, quantity) in assetHoldings where abs(quantity) > 0.0001 {
            let price = getLatestPrice(for: assetId) ?? 0
            let value = quantity * price
            if abs(value) > 0.01 {
                assetValues[assetId] = value
                total += value
            }
        }

        totalValue = total

        // Build summaries
        assetSummaries = assetValues.map { (assetId, value) in
            AssetAllocationSummary(
                assetId: assetId,
                value: value,
                percentage: total > 0 ? (value / total) * 100 : 0
            )
        }.sorted { $0.value > $1.value }

        // Initialize selection
        if selectedAssets.isEmpty {
            selectedAssets = Set(assetSummaries.map { $0.assetId })
        }
    }

    private func updateChart() {
        // Already calculated in calculateAllocation
    }

    private func generateSampleDates(from start: Date, to end: Date, granularity: TimeGranularity, calendar: Calendar) -> [Date] {
        var dates: [Date] = []
        var currentDate = granularity.periodStart(for: start, calendar: calendar)

        while currentDate <= end {
            dates.append(currentDate)
            currentDate = granularity.nextPeriod(after: currentDate, calendar: calendar)
        }

        return dates
    }

    private func getPrice(for assetId: String, on date: Date) -> Decimal {
        let uppercased = assetId.uppercased()
        if uppercased == "SPAXX" || uppercased == "VMMXX" || uppercased == "SWVXX" {
            return 1.0
        }

        let dayStart = Calendar.current.startOfDay(for: date)
        let prices = allPrices.filter { price in
            price.assetId == assetId && price.date <= dayStart
        }

        guard let latestPrice = prices.sorted(by: { $0.date > $1.date }).first else {
            return 0
        }

        return latestPrice.price
    }

    private func getLatestPrice(for assetId: String) -> Decimal? {
        let uppercased = assetId.uppercased()
        if uppercased == "SPAXX" || uppercased == "VMMXX" || uppercased == "SWVXX" {
            return 1.0
        }

        let prices = allPrices.filter { $0.assetId == assetId }
        return prices.sorted(by: { $0.date > $1.date }).first?.price
    }
}

struct AssetAllocationPanel: View {
    let assetSummaries: [AssetAllocationSummary]
    @Binding var selectedAssets: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Allocation %", systemImage: "chart.pie")
                    .font(.headline)
                Spacer()

                Button("Select All") {
                    selectedAssets = Set(assetSummaries.map { $0.assetId })
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
                    ForEach(assetSummaries, id: \.assetId) { summary in
                        AssetAllocationCard(
                            summary: summary,
                            isSelected: selectedAssets.contains(summary.assetId),
                            onToggle: {
                                toggleAsset(summary.assetId)
                            }
                        )
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }

    private func toggleAsset(_ assetId: String) {
        if selectedAssets.contains(assetId) {
            selectedAssets.remove(assetId)
        } else {
            selectedAssets.insert(assetId)
        }
    }
}

struct AssetAllocationCard: View {
    let summary: AssetAllocationSummary
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.assetId)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(summary.value, format: .currency(code: "USD"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Double(truncating: summary.percentage as NSDecimalNumber), specifier: "%.1f")%")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
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

struct AllocationChartView: View {
    let allocationData: [AllocationPoint]
    let granularity: TimeGranularity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Allocation % Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if allocationData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No allocation data available")
                        .foregroundColor(.secondary)
                    Text("Complete transactions to see allocation over time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(allocationData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Allocation %", NSDecimalNumber(decimal: point.percentage).doubleValue)
                    )
                    .foregroundStyle(by: .value("Asset", point.assetId))
                    .symbol(by: .value("Asset", point.assetId))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date, format: .dateTime.month(.abbreviated).year())
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let doubleValue = value.as(Double.self) {
                                Text("\(doubleValue, specifier: "%.0f")%")
                            }
                        }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartLegend(position: .bottom)
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Data Models

struct AllocationPoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let percentage: Decimal  // 0-100
}

struct AssetAllocationSummary: Identifiable {
    let id = UUID()
    let assetId: String
    let value: Decimal
    let percentage: Decimal  // 0-100
}

// MARK: - Time Helpers

extension TimeGranularity {
    func nextPeriod(after date: Date, calendar: Calendar) -> Date {
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: date)!
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: 1, to: date)!
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date)!
        }
    }
}
