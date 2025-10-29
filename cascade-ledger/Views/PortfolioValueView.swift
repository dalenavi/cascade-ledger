//
//  PortfolioValueView.swift
//  cascade-ledger
//
//  Portfolio market value view - shows USD value of holdings over time
//

import SwiftUI
import SwiftData
import Charts

struct PortfolioValueView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                PortfolioValueContent(
                    account: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Select an account to view portfolio value")
                )
            }
        }
        .navigationTitle("Portfolio Value")
    }
}

struct PortfolioValueContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [Transaction]
    @Query private var allPrices: [AssetPrice]

    @State private var valueData: [MarketValuePoint] = []
    @State private var assetSummaries: [AssetValueSummary] = []
    @State private var totalValue: Decimal = 0
    @State private var totalCost: Decimal = 0
    @State private var totalGain: Decimal = 0

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
                    Text("Portfolio Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(totalValue, format: .currency(code: "USD"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    HStack(spacing: 4) {
                        Text("P&L:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(totalGain, format: .currency(code: "USD"))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(totalGain >= 0 ? .green : .red)
                        if totalCost > 0 {
                            let percentage = (Double(truncating: totalGain as NSDecimalNumber) / Double(truncating: totalCost as NSDecimalNumber)) * 100
                            Text("(\(percentage, specifier: "%.1f")%)")
                                .font(.caption2)
                                .foregroundColor(totalGain >= 0 ? .green : .red)
                        }
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Split view
            HSplitView {
                // Left: Asset value cards
                AssetValuePanel(
                    assetSummaries: assetSummaries,
                    selectedAssets: $selectedAssets
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Market value chart
                MarketValueChartView(
                    valueData: filteredValueData,
                    granularity: granularity
                )
                .frame(minWidth: 500)
            }
        }
        .onAppear {
            calculatePortfolioValue()
        }
        .onChange(of: timeRange) { _, _ in calculatePortfolioValue() }
        .onChange(of: granularity) { _, _ in calculatePortfolioValue() }
        .onChange(of: selectedAssets) { _, _ in updateChart() }
    }

    private var filteredValueData: [MarketValuePoint] {
        valueData.filter { selectedAssets.contains($0.assetId) }
    }

    private func calculatePortfolioValue() {
        print("\n=== Portfolio Value Calculation ===")
        let dateRange = timeRange.dateRange

        // Calculate current holdings by analyzing journal entries
        var assetHoldings: [String: Decimal] = [:]  // assetName -> quantity
        var assetCostBasis: [String: Decimal] = [:]  // assetName -> cost basis
        var assetUnits: [String: String] = [:]       // assetName -> unit type
        var usdBalance: Decimal = 0
        var journalEntryCount = 0

        print("\nAnalyzing journal entries from \(allEntries.count) transactions...")

        for transaction in allEntries {
            for entry in transaction.journalEntries {
                journalEntryCount += 1

                let debit = entry.debitAmount ?? 0
                let credit = entry.creditAmount ?? 0

                switch entry.accountType {
                case .cash:
                    // Cash: Debit increases, Credit decreases
                    if entry.accountName == "Cash USD" {
                        usdBalance += debit - credit
                        if journalEntryCount <= 20 {
                            print("  Cash: \(transaction.date.formatted(date: .abbreviated, time: .omitted)) \(transaction.transactionDescription.prefix(30)) DR:\(debit) CR:\(credit) → balance:\(usdBalance)")
                        }
                    }

                case .asset:
                    // Asset: Debit increases, Credit decreases
                    let assetName = entry.accountName
                    let quantity = entry.quantity ?? 0

                    if debit > 0 {
                        // Buying - increase quantity and cost basis
                        assetHoldings[assetName, default: 0] += quantity
                        assetCostBasis[assetName, default: 0] += debit
                        assetUnits[assetName] = entry.quantityUnit ?? "shares"

                        if journalEntryCount <= 20 {
                            print("  Buy \(assetName): +\(quantity) @ \(debit) → holding:\(assetHoldings[assetName] ?? 0)")
                        }
                    } else if credit > 0 {
                        // Selling - decrease quantity and cost basis (proportionally)
                        let currentQty = assetHoldings[assetName, default: 0]
                        let currentCost = assetCostBasis[assetName, default: 0]

                        assetHoldings[assetName, default: 0] -= quantity

                        // Reduce cost basis proportionally to quantity sold
                        if currentQty > 0 {
                            let costReduction = (quantity / currentQty) * currentCost
                            assetCostBasis[assetName, default: 0] -= costReduction
                        }

                        if journalEntryCount <= 20 {
                            print("  Sell \(assetName): -\(quantity) @ \(credit) → holding:\(assetHoldings[assetName] ?? 0)")
                        }
                    }

                case .equity, .income, .expense, .liability:
                    // These don't affect holdings
                    break
                }
            }
        }

        print("\nJournal entries analyzed: \(journalEntryCount)")
        print("Final USD balance: \(usdBalance)")
        print("\nAsset Holdings:")
        for (asset, qty) in assetHoldings.sorted(by: { $0.key < $1.key }) {
            print("  \(asset): \(qty) \(assetUnits[asset] ?? "units")")
        }

        // Build summaries
        var summaries: [String: AssetValueSummary] = [:]

        // Add USD
        if abs(usdBalance) > 0.01 {
            summaries["USD"] = AssetValueSummary(
                assetId: "USD",
                currentQuantity: usdBalance,
                unit: "USD",
                costBasis: usdBalance,  // For cash, cost basis = market value
                currentPrice: 1.0,
                marketValue: usdBalance
            )
        }

        // Add assets
        for (assetName, quantity) in assetHoldings {
            // Only show if we have a non-trivial position
            guard abs(quantity) > 0.0001 else { continue }

            summaries[assetName] = AssetValueSummary(
                assetId: assetName,
                currentQuantity: quantity,
                unit: assetUnits[assetName] ?? "shares",
                costBasis: assetCostBasis[assetName] ?? 0,
                currentPrice: 0,
                marketValue: 0
            )
        }

        // Get latest prices and calculate market values for assets
        for assetId in summaries.keys where assetId != "USD" {
            let price = getLatestPrice(for: assetId) ?? 1.0
            let quantity = summaries[assetId]!.currentQuantity

            summaries[assetId]?.currentPrice = price
            summaries[assetId]?.marketValue = quantity * price
        }

        assetSummaries = summaries.values
            .filter { abs($0.currentQuantity) > 0.0001 || $0.assetId == "USD" }
            .sorted { abs($0.marketValue) > abs($1.marketValue) }

        print("\nAsset Summaries:")
        for summary in assetSummaries {
            print("  \(summary.assetId): qty=\(summary.currentQuantity) value=\(summary.marketValue)")
        }

        // Calculate totals
        totalValue = assetSummaries.reduce(0) { $0 + $1.marketValue }
        totalCost = assetSummaries.reduce(0) { $0 + $1.costBasis }
        totalGain = totalValue - totalCost

        // Initialize selection
        if selectedAssets.isEmpty {
            selectedAssets = Set(assetSummaries.map { $0.assetId })
        }

        updateChart()
    }

    private func updateChart() {
        var points: [MarketValuePoint] = []

        for assetId in selectedAssets {
            if assetId == "USD" {
                // USD uses different calculation (cash balance, not quantity-based)
                points.append(contentsOf: calculateUSDValueOverTime())
            } else {
                // Filter transactions that have journal entries for this asset
                let entries = allEntries.filter { transaction in
                    transaction.date >= timeRange.dateRange.start &&
                    transaction.date <= timeRange.dateRange.end &&
                    transaction.journalEntries.contains { entry in
                        entry.accountType == .asset && entry.accountName == assetId
                    }
                }

                points.append(contentsOf: calculateMarketValueOverTime(entries, assetId: assetId))
            }
        }

        valueData = points.sorted { $0.date < $1.date }
    }

    private func calculateUSDValueOverTime() -> [MarketValuePoint] {
        print("\n=== USD Chart Calculation ===")
        let calendar = Calendar.current
        let dateRange = timeRange.dateRange

        // Collect all cash journal entries sorted by date
        var cashJournalEntries: [(date: Date, debit: Decimal, credit: Decimal, description: String)] = []

        for transaction in allEntries {
            for entry in transaction.journalEntries {
                if entry.accountType == .cash && entry.accountName == "Cash USD" {
                    let debit = entry.debitAmount ?? 0
                    let credit = entry.creditAmount ?? 0
                    if debit > 0 || credit > 0 {
                        cashJournalEntries.append((
                            date: transaction.date,
                            debit: debit,
                            credit: credit,
                            description: transaction.transactionDescription
                        ))
                    }
                }
            }
        }

        cashJournalEntries.sort { $0.date < $1.date }

        print("Found \(cashJournalEntries.count) cash journal entries")

        var cumulativeBalance: Decimal = 0
        var points: [MarketValuePoint] = []

        // Calculate starting balance (all entries before date range)
        let priorEntries = cashJournalEntries.filter { $0.date < dateRange.start }
        for entry in priorEntries {
            cumulativeBalance += entry.debit - entry.credit
        }
        print("Starting USD balance (before range): \(cumulativeBalance)")

        // Get entries in range
        let entriesInRange = cashJournalEntries.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }

        // Add starting point
        if !entriesInRange.isEmpty {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: entriesInRange.first!.date)!
            points.append(MarketValuePoint(
                date: dayBefore,
                assetId: "USD",
                quantity: cumulativeBalance,
                price: 1.0,
                value: cumulativeBalance
            ))
            print("  Start: \(dayBefore.formatted(date: .abbreviated, time: .omitted)) → $\(cumulativeBalance)")
        }

        // Track balance changes
        for (index, entry) in entriesInRange.enumerated() {
            cumulativeBalance += entry.debit - entry.credit

            let periodStart = granularity.periodStart(for: entry.date, calendar: calendar)

            points.append(MarketValuePoint(
                date: periodStart,
                assetId: "USD",
                quantity: cumulativeBalance,
                price: 1.0,
                value: cumulativeBalance
            ))

            if index < 10 {  // Log first 10
                print("  \(entry.date.formatted(date: .abbreviated, time: .omitted)): \(entry.description.prefix(30)) DR:\(entry.debit) CR:\(entry.credit) → balance: \(cumulativeBalance)")
            }
        }

        print("Final USD balance in chart: \(cumulativeBalance)")
        print("USD chart points created: \(points.count)")
        print("============================\n")

        return points
    }

    private func calculateMarketValueOverTime(_ entries: [Transaction], assetId: String) -> [MarketValuePoint] {
        let calendar = Calendar.current
        let dateRange = timeRange.dateRange

        // Build position timeline from journal entries
        var positionTimeline: [(Date, Decimal)] = []  // (date, quantity held)
        var cumulativeQty: Decimal = 0

        for transaction in entries.sorted(by: { $0.date < $1.date }) {
            for entry in transaction.journalEntries {
                if entry.accountType == .asset && entry.accountName == assetId {
                    let qty = entry.quantity ?? 0

                    if entry.debitAmount != nil {
                        // Debit increases asset
                        cumulativeQty += qty
                    } else if entry.creditAmount != nil {
                        // Credit decreases asset
                        cumulativeQty -= qty
                    }

                    if qty != 0 {
                        positionTimeline.append((transaction.date, cumulativeQty))
                    }
                }
            }
        }

        guard !positionTimeline.isEmpty else { return [] }

        // Get all price dates for this asset in range
        let pricesForAsset = allPrices.filter { price in
            price.assetId == assetId &&
            price.date >= dateRange.start &&
            price.date <= dateRange.end
        }.sorted { $0.date < $1.date }

        guard !pricesForAsset.isEmpty else {
            // No price data - fall back to transaction dates only
            print("⚠️ No price data for \(assetId), showing transaction dates only")
            return calculateValueAtTransactionDates(positionTimeline, assetId: assetId)
        }

        var points: [MarketValuePoint] = []

        // For each price date, find the quantity held at that time
        for pricePoint in pricesForAsset {
            // Find quantity held on this date
            let quantityOnDate = positionTimeline
                .filter { $0.0 <= pricePoint.date }
                .last?.1 ?? 0

            // Skip if we didn't own any
            guard quantityOnDate != 0 else { continue }

            // Calculate market value
            let marketValue = quantityOnDate * pricePoint.price

            // Aggregate by granularity
            let periodStart = granularity.periodStart(for: pricePoint.date, calendar: calendar)

            // Check if we already have a point for this period
            if let existingIndex = points.firstIndex(where: {
                calendar.isDate($0.date, equalTo: periodStart, toGranularity: .day)
            }) {
                // Update with latest value for this period
                points[existingIndex] = MarketValuePoint(
                    date: periodStart,
                    assetId: assetId,
                    quantity: quantityOnDate,
                    price: pricePoint.price,
                    value: marketValue
                )
            } else {
                points.append(MarketValuePoint(
                    date: periodStart,
                    assetId: assetId,
                    quantity: quantityOnDate,
                    price: pricePoint.price,
                    value: marketValue
                ))
            }
        }

        return points.sorted { $0.date < $1.date }
    }

    // Fallback when no price data available
    private func calculateValueAtTransactionDates(_ positionTimeline: [(Date, Decimal)], assetId: String) -> [MarketValuePoint] {
        let calendar = Calendar.current

        return positionTimeline.map { (date, quantity) in
            let periodStart = granularity.periodStart(for: date, calendar: calendar)
            let price = getPrice(for: assetId, on: date)
            return MarketValuePoint(
                date: periodStart,
                assetId: assetId,
                quantity: quantity,
                price: price,
                value: quantity * price
            )
        }
    }

    private func getPrice(for assetId: String, on date: Date) -> Decimal {
        // SPAXX is always $1.00
        if assetId.uppercased() == "SPAXX" {
            return 1.0
        }

        // Find price on or before this date
        let dayStart = Calendar.current.startOfDay(for: date)

        let prices = allPrices.filter { price in
            price.assetId == assetId && price.date <= dayStart
        }

        guard let latestPrice = prices.sorted(by: { $0.date > $1.date }).first else {
            return 0  // No price data available
        }

        return latestPrice.price
    }

    private func getLatestPrice(for assetId: String) -> Decimal? {
        // SPAXX is always $1.00
        if assetId.uppercased() == "SPAXX" {
            return 1.0
        }

        let prices = allPrices.filter { $0.assetId == assetId }
        return prices.sorted(by: { $0.date > $1.date }).first?.price
    }
}

struct AssetValuePanel: View {
    let assetSummaries: [AssetValueSummary]
    @Binding var selectedAssets: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Market Value", systemImage: "dollarsign.circle")
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
                        AssetValueCard(
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

struct AssetValueCard: View {
    let summary: AssetValueSummary
    let isSelected: Bool
    let onToggle: () -> Void

    private var gainLoss: Decimal {
        summary.marketValue - summary.costBasis
    }

    private var gainPercentage: Double {
        guard summary.costBasis > 0 else { return 0 }
        return (Double(truncating: gainLoss as NSDecimalNumber) / Double(truncating: summary.costBasis as NSDecimalNumber)) * 100
    }

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

                    Text(formatQuantity(summary.currentQuantity, unit: summary.unit))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if summary.currentPrice > 0 {
                        Text("@ \(summary.currentPrice, format: .currency(code: "USD"))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(abs(summary.marketValue), format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    if gainLoss != 0 {
                        HStack(spacing: 4) {
                            Image(systemName: gainLoss >= 0 ? "arrow.up" : "arrow.down")
                                .font(.caption2)
                            Text(abs(gainLoss), format: .currency(code: "USD"))
                                .font(.caption)
                            Text("(\(gainPercentage, specifier: "%.1f")%)")
                                .font(.caption2)
                        }
                        .foregroundColor(gainLoss >= 0 ? .green : .red)
                    }

                    Text("Cost: \(abs(summary.costBasis), format: .currency(code: "USD"))")
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

    private func formatQuantity(_ quantity: Decimal, unit: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = unit == "BTC" ? 4 : 2

        let num = NSDecimalNumber(decimal: quantity)
        let formatted = formatter.string(from: num) ?? "\(quantity)"

        return "\(formatted) \(unit)"
    }
}

struct MarketValueChartView: View {
    let valueData: [MarketValuePoint]
    let granularity: TimeGranularity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Market Value Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if valueData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No price data available")
                        .foregroundColor(.secondary)
                    Text("Fetch prices in Price Data tab to enable market value tracking")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 300)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(valueData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Value", NSDecimalNumber(decimal: point.value).doubleValue)
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

struct MarketValuePoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let quantity: Decimal
    let price: Decimal
    let value: Decimal  // quantity × price
}

struct AssetValueSummary {
    let assetId: String
    var currentQuantity: Decimal
    let unit: String
    var costBasis: Decimal
    var currentPrice: Decimal
    var marketValue: Decimal

    var gainLoss: Decimal {
        marketValue - costBasis
    }
}
