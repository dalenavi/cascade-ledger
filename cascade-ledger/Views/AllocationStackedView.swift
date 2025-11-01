//
//  AllocationStackedView.swift
//  cascade-ledger
//
//  Stacked cumulative asset allocation - shows % allocation with cumulative lines
//

import SwiftUI
import SwiftData
import Charts

struct AllocationStackedView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                AllocationStackedContent(
                    account: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Select an account to view stacked allocation")
                )
            }
        }
        .navigationTitle("Allocation (Stacked)")
    }
}

struct AllocationStackedContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [Transaction]
    @Query private var allPrices: [AssetPrice]

    @State private var stackedAllocationData: [StackedAllocationPoint] = []
    @State private var assetSummaries: [AssetAllocationSummary] = []
    @State private var totalValue: Decimal = 0
    @State private var totalValueTimeline: [TotalValuePoint] = []

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
                // Left: Asset allocation cards (same as AllocationView)
                AssetAllocationPanel(
                    assetSummaries: assetSummaries,
                    selectedAssets: $selectedAssets
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Dual chart view (stacked vertically)
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        // Top: Stacked allocation % (2/3 of space)
                        StackedAllocationChartView(
                            stackedData: filteredStackedData,
                            granularity: granularity,
                            xAxisDomain: xAxisDomain
                        )
                        .frame(height: geometry.size.height * 2 / 3)

                        Divider()

                        // Bottom: Total portfolio value (1/3 of space)
                        TotalValueChartView(
                            totalValueData: filteredTotalValueData,
                            granularity: granularity,
                            xAxisDomain: xAxisDomain
                        )
                        .frame(height: geometry.size.height / 3)
                    }
                }
                .frame(minWidth: 500)
            }
        }
        .onAppear {
            calculateAllocation()
        }
        .onChange(of: timeRange) { _, _ in calculateAllocation() }
        .onChange(of: granularity) { _, _ in calculateAllocation() }
        .onChange(of: selectedAssets) { _, _ in updateStackedData() }
    }

    private var filteredStackedData: [StackedAllocationPoint] {
        // Filter and recalculate cumulative for selected assets only
        let selectedSummaries = assetSummaries.filter { selectedAssets.contains($0.assetId) }
        let orderedAssets = selectedSummaries.map { $0.assetId }

        // Get all unique dates
        let uniqueDates = Set(stackedAllocationData.map { $0.date }).sorted()

        var cumulativePoints: [StackedAllocationPoint] = []

        for date in uniqueDates {
            var cumulative: Decimal = 0

            // Stack in order of left panel
            for assetId in orderedAssets {
                if let point = stackedAllocationData.first(where: { $0.date == date && $0.assetId == assetId }) {
                    cumulative += point.individualPercentage

                    cumulativePoints.append(StackedAllocationPoint(
                        date: date,
                        assetId: assetId,
                        individualPercentage: point.individualPercentage,
                        cumulativePercentage: cumulative
                    ))
                }
            }
        }

        return cumulativePoints
    }

    private var filteredTotalValueData: [TotalValuePoint] {
        // Filter total value timeline to only show when selected assets have changed
        // This keeps the total value chart synchronized with asset selection
        totalValueTimeline
    }

    // Compute X-axis domain for perfect alignment between charts
    private var xAxisDomain: ClosedRange<Date> {
        let allDates = stackedAllocationData.map { $0.date } + totalValueTimeline.map { $0.date }
        guard let minDate = allDates.min(), let maxDate = allDates.max() else {
            return Date()...Date()
        }
        return minDate...maxDate
    }

    private func calculateAllocation() {
        print("\n=== Stacked Allocation Calculation ===")
        let dateRange = timeRange.dateRange
        let calendar = Calendar.current

        // Build position timeline for all assets
        var assetTimelines: [String: [(Date, Decimal)]] = [:]
        var cashTimeline: [(Date, Decimal)] = []
        var spaxxTimeline: [(Date, Decimal)] = []

        var cashBalance: Decimal = 0
        var spaxxBalance: Decimal = 0

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

        // Generate sample dates
        let sampleDates = generateSampleDates(from: dateRange.start, to: dateRange.end, granularity: granularity, calendar: calendar)

        // Calculate allocation at each sample date
        var allocationByDate: [Date: [String: Decimal]] = [:]
        var totalValuePoints: [TotalValuePoint] = []

        for sampleDate in sampleDates {
            var assetValues: [String: Decimal] = [:]
            var totalAtDate: Decimal = 0

            // Cash USD
            if let cashAtDate = cashTimeline.filter({ $0.0 <= sampleDate }).last?.1, abs(cashAtDate) > 0.01 {
                assetValues["Cash USD"] = cashAtDate
                totalAtDate += cashAtDate
            }

            // SPAXX
            if let spaxxAtDate = spaxxTimeline.filter({ $0.0 <= sampleDate }).last?.1, abs(spaxxAtDate) > 0.01 {
                assetValues["SPAXX"] = spaxxAtDate
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

            // Store total value for timeline chart
            totalValuePoints.append(TotalValuePoint(
                date: sampleDate,
                value: totalAtDate
            ))

            // Store percentages
            if totalAtDate > 0 {
                var percentages: [String: Decimal] = [:]
                for (assetId, value) in assetValues {
                    percentages[assetId] = (value / totalAtDate) * 100
                }
                allocationByDate[sampleDate] = percentages
            }
        }

        totalValueTimeline = totalValuePoints

        // Calculate current allocation for left panel
        calculateCurrentAllocation()

        // Build stacked points in order of current allocation (biggest to smallest)
        var stackedPoints: [StackedAllocationPoint] = []

        for (date, percentages) in allocationByDate.sorted(by: { $0.key < $1.key }) {
            var cumulative: Decimal = 0

            // Stack in order of assetSummaries (sorted by value)
            for summary in assetSummaries {
                if let individualPercentage = percentages[summary.assetId] {
                    cumulative += individualPercentage

                    stackedPoints.append(StackedAllocationPoint(
                        date: date,
                        assetId: summary.assetId,
                        individualPercentage: individualPercentage,
                        cumulativePercentage: cumulative
                    ))
                }
            }
        }

        stackedAllocationData = stackedPoints

        print("Generated \(stackedPoints.count) stacked points")
        print("===================================\n")

        updateStackedData()
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

        // Build summaries sorted by value (largest first)
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

    private func updateStackedData() {
        // Recalculate happens in filteredStackedData computed property
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

struct StackedAllocationChartView: View {
    let stackedData: [StackedAllocationPoint]
    let granularity: TimeGranularity
    let xAxisDomain: ClosedRange<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Stacked Allocation % Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if stackedData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.bar.xaxis")
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
                Chart(stackedData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Cumulative %", NSDecimalNumber(decimal: point.cumulativePercentage).doubleValue)
                    )
                    .foregroundStyle(by: .value("Asset", point.assetId))
                    .symbol(by: .value("Asset", point.assetId))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXScale(domain: xAxisDomain)
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

struct TotalValueChartView: View {
    let totalValueData: [TotalValuePoint]
    let granularity: TimeGranularity
    let xAxisDomain: ClosedRange<Date>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Total Portfolio Value", systemImage: "dollarsign.circle")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if totalValueData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No value data available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(totalValueData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", NSDecimalNumber(decimal: point.value).doubleValue)
                    )
                    .foregroundStyle(Color.blue)
                    .symbol(Circle())
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
                .chartXScale(domain: xAxisDomain)
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
                                Text(doubleValue, format: .currency(code: "USD"))
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .padding()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Data Models

struct StackedAllocationPoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let individualPercentage: Decimal      // This asset's % of portfolio
    let cumulativePercentage: Decimal      // Cumulative % (stacked)
}

struct TotalValuePoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Decimal
}
