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
    @State private var verticalSegments: [VerticalSegment] = []
    @State private var assetSummaries: [AssetValueSummary] = []
    @State private var priceDataWarnings: [String] = []
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
                VStack(spacing: 0) {
                    // Price data warnings
                    if !priceDataWarnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(priceDataWarnings, id: \.self) { warning in
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                    Text(warning)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    MarketValueChartView(
                        valueData: filteredValueData,
                        verticalSegments: filteredVerticalSegments,
                        granularity: granularity
                    )
                }
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

    private var filteredVerticalSegments: [VerticalSegment] {
        verticalSegments.filter { selectedAssets.contains($0.assetId) }
    }

    private func calculatePortfolioValue() {
        print("\n=== Portfolio Value Calculation ===")

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
                    // Support multiple cash account name patterns
                    let isCashAccount = entry.accountName == "Cash USD" ||
                                       entry.accountName == "Cash (USD)" ||
                                       entry.accountName == "Cash"
                    if isCashAccount {
                        usdBalance += debit - credit
                        if journalEntryCount <= 20 {
                            print("  Cash (\(entry.accountName)): \(transaction.date.formatted(date: .abbreviated, time: .omitted)) \(transaction.transactionDescription.prefix(30)) DR:\(debit) CR:\(credit) → balance:\(usdBalance)")
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

                        // Use absolute value - quantities may be stored as negative for sells
                        let sellQty = abs(quantity)
                        assetHoldings[assetName, default: 0] -= sellQty

                        // Reduce cost basis proportionally to quantity sold
                        if currentQty > 0 {
                            let costReduction = (sellQty / currentQty) * currentCost
                            assetCostBasis[assetName, default: 0] -= costReduction
                        }

                        if journalEntryCount <= 20 {
                            print("  Sell \(assetName): -\(sellQty) @ \(credit) → holding:\(assetHoldings[assetName] ?? 0)")
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
        var warnings: [String] = []

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

                // Check if we have sufficient price data
                if let firstTx = entries.first {
                    let pricesForAsset = allPrices.filter { $0.assetId == assetId }
                    if pricesForAsset.isEmpty {
                        warnings.append("\(assetId): No price data - use Price Data tab to fetch")
                    } else if let earliestPrice = pricesForAsset.map({ $0.date }).min(),
                              earliestPrice > firstTx.date.addingTimeInterval(86400 * 30) {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        let gap = earliestPrice.timeIntervalSince(firstTx.date) / 86400
                        warnings.append("\(assetId): Missing \(Int(gap)) days of history (\(formatter.string(from: firstTx.date)) to \(formatter.string(from: earliestPrice))). CoinGecko free tier limited to 365 days.")
                    }
                }

                points.append(contentsOf: calculateMarketValueOverTime(entries, assetId: assetId))
            }
        }

        valueData = points.sorted { $0.date < $1.date }
        priceDataWarnings = warnings

        // Extract vertical segments (consecutive points at same date with different values)
        verticalSegments = extractVerticalSegments(from: valueData)
    }

    private func extractVerticalSegments(from points: [MarketValuePoint]) -> [VerticalSegment] {
        print("\n=== Extracting Vertical Segments ===")
        print("Total points: \(points.count)")

        guard !points.isEmpty else {
            print("No points to extract")
            return []
        }

        var segments: [VerticalSegment] = []

        // Group by asset first to avoid interleaving
        let byAsset = Dictionary(grouping: points) { $0.assetId }

        for (assetId, assetPoints) in byAsset {
            // Sort this asset's points by date
            let sorted = assetPoints.sorted { $0.date < $1.date }

            guard sorted.count >= 2 else { continue }

            if assetId == "SPY" {
                print("\n  Analyzing SPY (\(sorted.count) points):")
            }

            // Find transaction pairs: non-transaction point followed by transaction point within ~2 seconds
            var pairsFound = 0
            for i in 0..<(sorted.count - 1) {
                let p1 = sorted[i]
                let p2 = sorted[i + 1]

                let timeDiff = abs(p2.date.timeIntervalSince(p1.date))

                // Debug SPY checks
                if assetId == "SPY" && i < 25 {
                    print("    [\(i)→\(i+1)] \(p1.date.formatted(date: .abbreviated, time: .omitted)) p1.isTx=\(p1.isTransactionPoint), p2.isTx=\(p2.isTransactionPoint), diff=\(String(format: "%.1f", timeDiff))s")
                }

                // Transaction pair: p1 is NOT transaction point, p2 IS transaction point
                guard !p1.isTransactionPoint && p2.isTransactionPoint else { continue }

                // Must be same segment
                guard p1.segmentId == p2.segmentId else {
                    if assetId == "SPY" {
                        print("      ✗ Different segments")
                    }
                    continue
                }

                // Check if they're within ~2 seconds of each other (transaction pairs are 1 second apart)
                guard timeDiff <= 2 else {
                    if assetId == "SPY" {
                        print("      ✗ Time gap too large: \(timeDiff)s")
                    }
                    continue
                }

                // Create vertical segment
                pairsFound += 1
                print("  ✓ Creating vertical segment #\(pairsFound) at \(p1.date.formatted(date: .abbreviated, time: .omitted)): $\(p1.value) → $\(p2.value) [\(assetId)]")
                segments.append(VerticalSegment(
                    date: p1.date,
                    assetId: assetId,
                    valueStart: p1.value,
                    valueEnd: p2.value,
                    quantityBefore: p1.quantity,
                    quantityAfter: p2.quantity
                ))
            }

            if assetId == "SPY" {
                print("  SPY: Found \(pairsFound) pairs")
            }
        }

        print("\nTotal vertical segments created: \(segments.count)")
        print("====================================\n")

        return segments
    }

    private func calculateUSDValueOverTime() -> [MarketValuePoint] {
        print("\n=== USD Chart Calculation ===")
        let calendar = Calendar.current
        let dateRange = timeRange.dateRange

        // Collect all cash journal entries sorted by date
        var cashJournalEntries: [(date: Date, debit: Decimal, credit: Decimal, description: String)] = []

        for transaction in allEntries {
            for entry in transaction.journalEntries {
                // Support multiple cash account name patterns
                let isCashAccount = entry.accountType == .cash && (
                    entry.accountName == "Cash USD" ||
                    entry.accountName == "Cash (USD)" ||
                    entry.accountName == "Cash"
                )

                if isCashAccount {
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
        let segmentId = UUID()  // USD typically doesn't go to zero, use single segment
        var sequenceCounter = 0

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
                value: cumulativeBalance,
                segmentId: segmentId,
                isTransactionPoint: false,
                sequenceOrder: sequenceCounter
            ))
            sequenceCounter += 1
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
                value: cumulativeBalance,
                segmentId: segmentId,
                isTransactionPoint: false,
                sequenceOrder: sequenceCounter
            ))
            sequenceCounter += 1

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

        print("\n=== Calculate Market Value: \(assetId) ===")
        print("Date range: \(dateRange.start.formatted(date: .abbreviated, time: .omitted)) to \(dateRange.end.formatted(date: .abbreviated, time: .omitted))")

        // Build position timeline from journal entries WITH transaction tracking
        var positionEvents: [PositionEvent] = []
        var cumulativeQty: Decimal = 0

        // Get ALL transactions (including before date range) to track position correctly
        let allTransactions = allEntries.filter { tx in
            tx.journalEntries.contains { entry in
                entry.accountType == .asset && entry.accountName == assetId
            }
        }.sorted { $0.date < $1.date }

        // Aggregate position changes by DAY
        var dailyPositionChanges: [(day: Date, qtyStart: Decimal, qtyEnd: Decimal)] = []
        var currentDay: Date?
        var dayStartQty: Decimal = 0

        for transaction in allTransactions {
            for entry in transaction.journalEntries {
                if entry.accountType == .asset && entry.accountName == assetId {
                    let qty = entry.quantity ?? 0
                    guard qty != 0 else { continue }

                    let txDay = calendar.startOfDay(for: transaction.date)

                    // If this is a new day, record the previous day's changes
                    if let prevDay = currentDay, prevDay != txDay, dayStartQty != cumulativeQty {
                        dailyPositionChanges.append((day: prevDay, qtyStart: dayStartQty, qtyEnd: cumulativeQty))
                        dayStartQty = cumulativeQty
                    } else if currentDay == nil {
                        currentDay = txDay
                        dayStartQty = cumulativeQty
                    }

                    currentDay = txDay

                    if entry.debitAmount != nil {
                        cumulativeQty += qty  // Buy
                    } else if entry.creditAmount != nil {
                        cumulativeQty -= qty  // Sell
                    }
                }
            }
        }

        // Add final day if there were changes
        if let lastDay = currentDay, dayStartQty != cumulativeQty {
            dailyPositionChanges.append((day: lastDay, qtyStart: dayStartQty, qtyEnd: cumulativeQty))
        }

        // Convert to PositionEvent array
        positionEvents = dailyPositionChanges.map { change in
            PositionEvent(
                date: change.day,
                quantityBefore: change.qtyStart,
                quantityAfter: change.qtyEnd,
                isTransaction: true
            )
        }

        // Log aggregated position changes
        for event in positionEvents {
            let inRange = event.date >= dateRange.start && event.date <= dateRange.end
            print("  \(inRange ? "✓" : "○") \(event.date.formatted(date: .abbreviated, time: .omitted)) - \(event.quantityBefore) → \(event.quantityAfter) shares")
        }

        print("Total position events (aggregated by day): \(positionEvents.count)")

        // Filter to events in range for chart display
        let eventsInRange = positionEvents.filter { $0.date >= dateRange.start && $0.date <= dateRange.end }
        print("Events in display range: \(eventsInRange.count)")

        if let firstEvent = eventsInRange.first {
            print("First event in range: \(firstEvent.date.formatted(date: .abbreviated, time: .omitted)) - \(firstEvent.quantityBefore) → \(firstEvent.quantityAfter)")
            if firstEvent.quantityBefore == 0 {
                print("  ⚠️ This is the INITIAL BUY - should show vertical from $0")
            }
        }

        guard !positionEvents.isEmpty else { return [] }

        // Get all price dates for this asset in range
        let pricesForAsset = allPrices.filter { price in
            price.assetId == assetId &&
            price.date >= dateRange.start &&
            price.date <= dateRange.end
        }.sorted { $0.date < $1.date }

        guard !pricesForAsset.isEmpty else {
            // No price data - fall back to transaction dates only
            print("⚠️ No price data for \(assetId), showing transaction dates only")
            return calculateValueAtTransactionDates(positionEvents, assetId: assetId)
        }

        var points: [MarketValuePoint] = []
        var currentSegmentId = UUID()
        var previousQuantity: Decimal = 0
        var sequenceCounter = 0

        // Group prices by period (daily/weekly/monthly) and use CLOSE price (last of period)
        var pricesByPeriod: [Date: Decimal] = [:]
        for pricePoint in pricesForAsset {
            let periodStart = granularity.periodStart(for: pricePoint.date, calendar: calendar)
            // Keep updating - last price wins (close price for the period)
            pricesByPeriod[periodStart] = pricePoint.price
        }

        // Collect ALL unique dates (price dates + transaction dates)
        var allDates = Set(pricesByPeriod.keys)
        let transactionDatesInRange = positionEvents.filter({ $0.date >= dateRange.start && $0.date <= dateRange.end })
        for event in transactionDatesInRange {
            let periodDate = granularity.periodStart(for: event.date, calendar: calendar)
            allDates.insert(periodDate)
        }

        if assetId == "SPY" {
            print("  Price data dates: \(pricesByPeriod.keys.sorted().prefix(5).map { $0.formatted(date: .abbreviated, time: .omitted) })")
            print("  Transaction dates added: \(transactionDatesInRange.prefix(5).map { $0.date.formatted(date: .abbreviated, time: .omitted) })")
            print("  Total unique dates: \(allDates.count)")
        }

        // Iterate through all dates (transactions + prices)
        var iterationCount = 0
        for periodDate in allDates.sorted() {
            iterationCount += 1

            // Get close price for this period (or interpolate from nearest)
            let closePrice = pricesByPeriod[periodDate] ?? getPrice(for: assetId, on: periodDate)

            // Debug first few iterations for SPY
            if assetId == "SPY" && iterationCount <= 25 {
                print("  [\(iterationCount)] Processing \(periodDate.formatted(date: .abbreviated, time: .omitted)), price: $\(closePrice)")
            }

            // Find position at this period
            let positionAtPeriod = positionEvents
                .filter { $0.date <= periodDate }
                .last?.quantityAfter ?? 0

            // Check if there's a position change in this period FIRST
            let positionChangeInPeriod = positionEvents.first { event in
                let eventPeriod = granularity.periodStart(for: event.date, calendar: calendar)
                return eventPeriod == periodDate
            }

            if assetId == "SPY" && positionChangeInPeriod != nil && positionChangeInPeriod!.quantityBefore == 0 {
                print("  🔍 Found initial buy at \(periodDate.formatted(date: .abbreviated, time: .omitted)): \(positionChangeInPeriod!.quantityBefore) → \(positionChangeInPeriod!.quantityAfter)")
            }

            // Skip if we don't own any AND there's no position change
            guard positionAtPeriod != 0 || positionChangeInPeriod != nil else {
                previousQuantity = positionAtPeriod
                continue
            }

            if let change = positionChangeInPeriod {
                // POSITION CHANGE PERIOD
                let isInitialBuy = change.quantityBefore == 0

                // For initial buy, create new segment and use it for ALL subsequent points
                let segmentForThisTransaction: UUID
                if isInitialBuy {
                    segmentForThisTransaction = UUID()
                    print("  🆕 New position segment starting at \(periodDate.formatted(date: .abbreviated, time: .omitted))")
                } else {
                    segmentForThisTransaction = currentSegmentId
                }

                // MIDDAY: Transaction points at 12:00
                let midday = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: periodDate)!

                // Before point
                if change.quantityBefore != 0 || isInitialBuy {
                    let valueBefore = change.quantityBefore * closePrice
                    if assetId == "SPY" && isInitialBuy {
                        print("    Creating BEFORE point: date=\(midday.formatted()), value=$\(valueBefore), segmentId=\(segmentForThisTransaction)")
                    }
                    points.append(MarketValuePoint(
                        date: midday,
                        assetId: assetId,
                        quantity: change.quantityBefore,
                        price: closePrice,
                        value: valueBefore,
                        segmentId: segmentForThisTransaction,
                        isTransactionPoint: false,
                        sequenceOrder: sequenceCounter
                    ))
                    sequenceCounter += 1
                }

                // After point (1 second later for vertical)
                if change.quantityAfter != 0 {
                    let valueAfter = change.quantityAfter * closePrice
                    if assetId == "SPY" && isInitialBuy {
                        print("    Creating AFTER point: date=\(midday.addingTimeInterval(1).formatted()), value=$\(valueAfter), segmentId=\(segmentForThisTransaction)")
                    }
                    points.append(MarketValuePoint(
                        date: midday.addingTimeInterval(1),
                        assetId: assetId,
                        quantity: change.quantityAfter,
                        price: closePrice,
                        value: valueAfter,
                        segmentId: segmentForThisTransaction,
                        isTransactionPoint: true,
                        sequenceOrder: sequenceCounter
                    ))
                    sequenceCounter += 1
                }

                // Update current segment for subsequent points
                if isInitialBuy {
                    currentSegmentId = segmentForThisTransaction
                }

                // MIDNIGHT: Price point at end of period
                let midnight = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: periodDate)!
                let endValue = change.quantityAfter * closePrice
                if assetId == "SPY" && isInitialBuy {
                    print("    Creating END-OF-DAY point: date=\(midnight.formatted()), value=$\(endValue), segmentId=\(currentSegmentId)")
                }
                points.append(MarketValuePoint(
                    date: midnight,
                    assetId: assetId,
                    quantity: change.quantityAfter,
                    price: closePrice,
                    value: endValue,
                    segmentId: currentSegmentId,
                    isTransactionPoint: false,
                    sequenceOrder: sequenceCounter
                ))
                sequenceCounter += 1

                // Bridge gap: Fill intermediate periods until next data point
                if granularity != .daily {
                    // Find next date in our set after this transaction
                    let sortedDates = allDates.sorted()
                    if let currentIndex = sortedDates.firstIndex(of: periodDate),
                       currentIndex + 1 < sortedDates.count {
                        let nextDataDate = sortedDates[currentIndex + 1]

                        // Fill all periods between transaction and next data point
                        var currentPeriod = periodDate
                        var iterationLimit = 100  // Safety limit

                        while currentPeriod < nextDataDate && iterationLimit > 0 {
                            iterationLimit -= 1

                            // Advance to next period
                            let increment: Calendar.Component = granularity == .weekly ? .weekOfYear : .month
                            guard let nextPeriod = calendar.date(byAdding: increment, value: 1, to: currentPeriod) else { break }
                            let nextPeriodStart = granularity.periodStart(for: nextPeriod, calendar: calendar)

                            // Stop if we've reached or passed the next data point
                            if nextPeriodStart >= nextDataDate { break }

                            // Add bridge point
                            let bridgePrice = getPrice(for: assetId, on: nextPeriodStart)
                            let bridgeValue = change.quantityAfter * bridgePrice
                            if assetId == "SPY" && isInitialBuy {
                                print("    Creating BRIDGE point: date=\(nextPeriodStart.formatted()), value=$\(bridgeValue), segmentId=\(currentSegmentId)")
                            }
                            points.append(MarketValuePoint(
                                date: nextPeriodStart,
                                assetId: assetId,
                                quantity: change.quantityAfter,
                                price: bridgePrice,
                                value: bridgeValue,
                                segmentId: currentSegmentId,
                                isTransactionPoint: false,
                                sequenceOrder: sequenceCounter
                            ))
                            sequenceCounter += 1

                            currentPeriod = nextPeriodStart
                        }
                    }
                }

            } else {
                // REGULAR PRICE PERIOD - no position change
                // MIDNIGHT: Price point only
                let midnight = calendar.startOfDay(for: periodDate)
                let value = positionAtPeriod * closePrice

                points.append(MarketValuePoint(
                    date: midnight,
                    assetId: assetId,
                    quantity: positionAtPeriod,
                    price: closePrice,
                    value: value,
                    segmentId: currentSegmentId,
                    isTransactionPoint: false,
                    sequenceOrder: sequenceCounter
                ))
                sequenceCounter += 1
            }

            previousQuantity = positionAtPeriod
        }

        let sorted = points.sorted {
            if $0.date == $1.date {
                return $0.sequenceOrder < $1.sequenceOrder
            }
            return $0.date < $1.date
        }

        print("Total points created for \(assetId): \(sorted.count)")
        print("====================================\n")

        return sorted
    }

    private func calculateValueAtTransactionDates(_ positionEvents: [PositionEvent], assetId: String) -> [MarketValuePoint] {
        let calendar = Calendar.current
        var currentSegmentId = UUID()
        var previousQuantity: Decimal = 0
        var sequenceCounter = 0

        var points: [MarketValuePoint] = []

        for event in positionEvents {
            let periodStart = granularity.periodStart(for: event.date, calendar: calendar)
            let price = getPrice(for: assetId, on: event.date)

            // Check if position changed from zero to non-zero (new segment starts)
            if previousQuantity == 0 && event.quantityAfter != 0 {
                currentSegmentId = UUID()
            }

            let valueBefore = event.quantityBefore * price
            let valueAfter = event.quantityAfter * price

            let isInitialBuy = event.quantityBefore == 0

            // For initial buy from zero, use NEW segment for both points
            let segmentForThisTransaction: UUID
            if isInitialBuy {
                segmentForThisTransaction = UUID()
            } else {
                segmentForThisTransaction = currentSegmentId
            }

            // Transaction points offset by 12 hours from period start
            let transactionTime = calendar.date(byAdding: .hour, value: 12, to: periodStart)!

            // Add "before" point (ALWAYS add for initial buy, even if $0)
            if valueBefore != 0 || isInitialBuy {
                points.append(MarketValuePoint(
                    date: transactionTime,
                    assetId: assetId,
                    quantity: event.quantityBefore,
                    price: price,
                    value: valueBefore,
                    segmentId: segmentForThisTransaction,
                    isTransactionPoint: false,
                    sequenceOrder: sequenceCounter
                ))
                sequenceCounter += 1
            }

            // Add "after" point - offset by 1 second
            if valueAfter != 0 {
                let afterDate = calendar.date(byAdding: .second, value: 1, to: transactionTime)!
                points.append(MarketValuePoint(
                    date: afterDate,
                    assetId: assetId,
                    quantity: event.quantityAfter,
                    price: price,
                    value: valueAfter,
                    segmentId: segmentForThisTransaction,
                    isTransactionPoint: true,
                    sequenceOrder: sequenceCounter
                ))
                sequenceCounter += 1
            }

            // Update current segment after adding both points
            if isInitialBuy {
                currentSegmentId = segmentForThisTransaction
            }

            previousQuantity = event.quantityAfter
        }

        return points.sorted {
            if $0.date == $1.date {
                return $0.sequenceOrder < $1.sequenceOrder
            }
            return $0.date < $1.date
        }
    }

    // Helper struct for fallback function
    struct PositionEvent {
        let date: Date
        let quantityBefore: Decimal
        let quantityAfter: Decimal
        let isTransaction: Bool
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
    let verticalSegments: [VerticalSegment]
    let granularity: TimeGranularity

    private var dateRange: ClosedRange<Date>? {
        guard let minDate = valueData.map({ $0.date }).min(),
              let maxDate = valueData.map({ $0.date }).max() else {
            return nil
        }
        return minDate...maxDate
    }

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
                Chart {
                    // SINGLE continuous line including ALL points (transactions + price movements)
                    ForEach(valueData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Value", NSDecimalNumber(decimal: point.value).doubleValue),
                            series: .value("Series", "\(point.assetId)-\(point.segmentId.uuidString)")
                        )
                        .foregroundStyle(by: .value("Asset", point.assetId))
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                    }

                    // Subtle thicker marks on vertical transaction segments
                    ForEach(verticalSegments) { segment in
                        RectangleMark(
                            x: .value("Date", segment.date),
                            yStart: .value("Start", NSDecimalNumber(decimal: min(segment.valueStart, segment.valueEnd)).doubleValue),
                            yEnd: .value("End", NSDecimalNumber(decimal: max(segment.valueStart, segment.valueEnd)).doubleValue),
                            width: .fixed(4.5)
                        )
                        .foregroundStyle(by: .value("Asset", segment.assetId))
                        .annotation(position: .top, alignment: .center) {
                            Text(segment.isBuy ? "▲" : "▼")
                                .font(.caption2)
                                .foregroundColor(segment.isBuy ? .green : .red)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .month, count: 1)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let date = value.as(Date.self),
                               let minDate = dateRange?.lowerBound {
                                let calendar = Calendar.current
                                let month = calendar.component(.month, from: date)

                                // Show year for first month in data range or every January
                                let isFirstMonth = calendar.isDate(date, equalTo: minDate, toGranularity: .month)

                                if isFirstMonth || month == 1 {
                                    Text(date, format: .dateTime.month(.abbreviated).year())
                                        .font(.caption2)
                                } else {
                                    Text(date, format: .dateTime.month(.abbreviated))
                                        .font(.caption2)
                                }
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
    let segmentId: UUID  // Unique ID per holding period (to break lines at zero)
    let isTransactionPoint: Bool  // True if this point represents the "after" state of a buy/sell
    let sequenceOrder: Int  // To ensure proper ordering when multiple points share same date
}

struct VerticalSegment: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let valueStart: Decimal
    let valueEnd: Decimal
    let quantityBefore: Decimal
    let quantityAfter: Decimal

    var changeAmount: Decimal {
        valueEnd - valueStart
    }

    var quantityChange: Decimal {
        quantityAfter - quantityBefore
    }

    var isBuy: Bool {
        valueEnd > valueStart
    }
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
