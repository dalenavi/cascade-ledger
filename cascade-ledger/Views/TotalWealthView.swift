//
//  TotalWealthView.swift
//  cascade-ledger
//
//  Stacked wealth chart showing total portfolio value composition
//

import SwiftUI
import SwiftData
import Charts

struct TotalWealthView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                TotalWealthContent(
                    account: account,
                    timeRange: $timeRange,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.bar.fill",
                    description: Text("Select an account to view total wealth")
                )
            }
        }
        .navigationTitle("Total Wealth")
    }
}

struct TotalWealthContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [LedgerEntry]
    @Query private var allPrices: [AssetPrice]

    @State private var wealthData: [StackedWealthPoint] = []
    @State private var assetSummaries: [AssetValueSummary] = []
    @State private var totalValue: Decimal = 0
    @State private var totalGain: Decimal = 0

    init(
        account: Account,
        timeRange: Binding<TimeRange>,
        selectedAssets: Binding<Set<String>>
    ) {
        self.account = account
        self._timeRange = timeRange
        self._selectedAssets = selectedAssets

        let accountId = account.id
        _allEntries = Query(
            filter: #Predicate<LedgerEntry> { entry in
                entry.account?.id == accountId
            },
            sort: \LedgerEntry.date
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

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Wealth")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(totalValue, format: .currency(code: "USD"))
                        .font(.title)
                        .fontWeight(.bold)

                    if totalGain != 0 {
                        HStack(spacing: 4) {
                            Image(systemName: totalGain >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption)
                            Text(abs(totalGain), format: .currency(code: "USD"))
                                .font(.caption)
                        }
                        .foregroundColor(totalGain >= 0 ? .green : .red)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Split view
            HSplitView {
                // Left: Asset selector
                AssetValuePanel(
                    assetSummaries: assetSummaries,
                    selectedAssets: $selectedAssets
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Stacked area chart
                StackedWealthChartView(
                    wealthData: wealthData
                )
                .frame(minWidth: 500)
            }
        }
        .onAppear {
            calculateWealthData()
        }
        .onChange(of: timeRange) { _, _ in calculateWealthData() }
        .onChange(of: selectedAssets) { _, _ in calculateWealthData() }
    }

    private func calculateWealthData() {
        let dateRange = timeRange.dateRange

        // Get unique assets with non-zero holdings
        var assetHoldings: [String: (quantity: Decimal, cost: Decimal)] = [:]

        // Track USD (cash not in specific assets)
        var usdBalance: Decimal = 0

        for entry in allEntries {
            if let assetId = entry.assetId?.trimmingCharacters(in: .whitespaces),
               !assetId.isEmpty,
               entry.quantity != nil {
                // Asset-based transaction
                let qty = entry.quantity!
                guard qty != 0 else { continue }

                if assetHoldings[assetId] == nil {
                    assetHoldings[assetId] = (0, 0)
                }

                assetHoldings[assetId]?.quantity += qty
                if qty > 0 {
                    assetHoldings[assetId]?.cost += abs(entry.amount)
                } else {
                    assetHoldings[assetId]?.cost -= abs(entry.amount)
                }
            } else {
                // USD cash transaction (no assetId)
                usdBalance += entry.amount
            }
        }

        // Add USD as an asset if there's a balance
        if usdBalance != 0 {
            assetHoldings["USD"] = (usdBalance, usdBalance)
        }

        // Filter to assets with non-zero quantity
        let assets = assetHoldings.filter { abs($0.value.quantity) > 0.0001 }.map { $0.key }

        // Initialize selection
        if selectedAssets.isEmpty {
            selectedAssets = Set(assets)
        }

        print("=== Calculating Total Wealth ===")
        let startTime = Date()

        // Pre-build position timelines once (OPTIMIZATION)
        var positionTimelines: [String: [(Date, Decimal)]] = [:]
        for assetId in selectedAssets where assetId != "USD" {
            positionTimelines[assetId] = buildPositionTimeline(assetId: assetId)
        }
        if selectedAssets.contains("USD") {
            positionTimelines["USD"] = buildUSDTimeline()
        }

        print("Built \(positionTimelines.count) position timelines in \(Date().timeIntervalSince(startTime))s")

        // Build unified timeline from all price dates
        var allDates: Set<Date> = []
        for assetId in selectedAssets where assetId != "USD" {
            let assetPrices = allPrices.filter { price in
                price.assetId == assetId &&
                price.date >= dateRange.start &&
                price.date <= dateRange.end
            }
            allDates.formUnion(assetPrices.map { $0.date })
        }

        let sortedDates = Array(allDates.sorted())
        print("Processing \(sortedDates.count) unique price dates")

        // Pre-build price lookup (OPTIMIZATION)
        var priceLookup: [String: [Date: Decimal]] = [:]
        for assetId in selectedAssets where assetId != "USD" {
            var pricesByDate: [Date: Decimal] = [:]
            for price in allPrices where price.assetId == assetId {
                pricesByDate[price.date] = price.price
            }
            priceLookup[assetId] = pricesByDate
        }

        print("Built price lookup in \(Date().timeIntervalSince(startTime))s")

        // For each date, calculate value of each asset (OPTIMIZED)
        var stackedPoints: [StackedWealthPoint] = []

        for date in sortedDates {
            for assetId in selectedAssets.sorted() {
                let value: Decimal

                if assetId == "USD" {
                    // Find USD balance at this date
                    value = positionTimelines["USD"]?
                        .filter { $0.0 <= date }
                        .last?.1 ?? 0
                } else {
                    // Find quantity held at this date
                    guard let timeline = positionTimelines[assetId] else { continue }
                    let quantity = timeline
                        .filter { $0.0 <= date }
                        .last?.1 ?? 0

                    guard quantity != 0 else { continue }

                    // Get price (with lookup, not search)
                    let price = priceLookup[assetId]?
                        .filter { $0.key <= date }
                        .max(by: { $0.key < $1.key })?.value ?? (assetId == "SPAXX" ? 1.0 : 0)

                    guard price > 0 else { continue }

                    value = quantity * price
                }

                guard value != 0 else { continue }

                stackedPoints.append(StackedWealthPoint(
                    date: date,
                    assetId: assetId,
                    value: value
                ))
            }
        }

        wealthData = stackedPoints
        print("Calculated \(wealthData.count) data points in \(Date().timeIntervalSince(startTime))s total")
        print("==============================")

        // Calculate summaries
        var summaries: [String: AssetValueSummary] = [:]
        for (assetId, holding) in assetHoldings where abs(holding.quantity) > 0.0001 {
            let price = getLatestPrice(for: assetId)
            let marketValue = holding.quantity * price

            summaries[assetId] = AssetValueSummary(
                assetId: assetId,
                currentQuantity: holding.quantity,
                unit: "units",  // Not important for this view
                costBasis: holding.cost,
                currentPrice: price,
                marketValue: marketValue
            )
        }

        assetSummaries = summaries.values.sorted { abs($0.marketValue) > abs($1.marketValue) }
        totalValue = assetSummaries.reduce(0) { $0 + $1.marketValue }
        totalGain = totalValue - assetSummaries.reduce(0) { $0 + $1.costBasis }
    }

    // Cached position timelines to avoid recalculating for every date
    private func buildPositionTimeline(assetId: String) -> [(Date, Decimal)] {
        var timeline: [(Date, Decimal)] = []
        var cumulative: Decimal = 0

        let assetEntries = allEntries.filter { entry in
            entry.assetId == assetId &&
            entry.quantity != nil
        }.sorted { $0.date < $1.date }

        for entry in assetEntries {
            let qty = entry.quantity ?? 0
            guard qty != 0 else { continue }

            cumulative += qty
            timeline.append((entry.date, cumulative))
        }

        return timeline
    }

    private func buildUSDTimeline() -> [(Date, Decimal)] {
        var timeline: [(Date, Decimal)] = []
        var cumulative: Decimal = 0

        let cashEntries = allEntries.filter { entry in
            entry.assetId == nil || entry.assetId?.trimmingCharacters(in: .whitespaces).isEmpty == true
        }.sorted { $0.date < $1.date }

        for entry in cashEntries {
            cumulative += entry.amount
            timeline.append((entry.date, cumulative))
        }

        return timeline
    }

    private func getQuantityHeld(assetId: String, on date: Date) -> Decimal {
        // This is still called but we'll optimize the main calculation
        let relevantEntries = allEntries.filter { entry in
            entry.assetId == assetId &&
            entry.date <= date &&
            entry.quantity != nil
        }

        return relevantEntries.reduce(0) { total, entry in
            let qty = entry.quantity ?? 0
            guard qty != 0 else { return total }
            return total + qty
        }
    }

    private func getUSDBalance(on date: Date) -> Decimal {
        let cashEntries = allEntries.filter { entry in
            entry.date <= date &&
            (entry.assetId == nil || entry.assetId?.trimmingCharacters(in: .whitespaces).isEmpty == true)
        }

        return cashEntries.reduce(0) { $0 + $1.amount }
    }

    private func getPrice(assetId: String, on date: Date) -> Decimal {
        // USD is always $1.00
        if assetId == "USD" {
            return 1.0
        }

        // SPAXX is always $1.00
        if assetId.uppercased() == "SPAXX" {
            return 1.0
        }

        // Find price on this exact date or nearest before
        let dayStart = Calendar.current.startOfDay(for: date)

        let prices = allPrices.filter { price in
            price.assetId == assetId && price.date <= dayStart
        }

        return prices.sorted(by: { $0.date > $1.date }).first?.price ?? 0
    }

    private func getLatestPrice(for assetId: String) -> Decimal {
        if assetId == "USD" || assetId.uppercased() == "SPAXX" {
            return 1.0
        }

        let prices = allPrices.filter { $0.assetId == assetId }
        return prices.sorted(by: { $0.date > $1.date }).first?.price ?? 0
    }
}

struct StackedWealthChartView: View {
    let wealthData: [StackedWealthPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Wealth Composition", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if wealthData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No price data available")
                        .foregroundColor(.secondary)
                    Text("Fetch prices in Price Data tab")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(wealthData) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Value", NSDecimalNumber(decimal: point.value).doubleValue)
                    )
                    .foregroundStyle(by: .value("Asset", point.assetId))
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

struct StackedWealthPoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let value: Decimal
}
