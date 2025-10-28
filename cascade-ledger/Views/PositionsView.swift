//
//  PositionsView.swift
//  cascade-ledger
//
//  Asset positions view - tracks actual quantities (shares, BTC, etc.)
//

import SwiftUI
import SwiftData
import Charts

struct PositionsView: View {
    let selectedAccount: Account?

    @State private var timeRange: TimeRange = .allTime
    @State private var granularity: TimeGranularity = .weekly
    @State private var selectedAssets: Set<String> = []

    var body: some View {
        NavigationStack {
            if let account = selectedAccount {
                PositionsContent(
                    account: account,
                    timeRange: $timeRange,
                    granularity: $granularity,
                    selectedAssets: $selectedAssets
                )
            } else {
                ContentUnavailableView(
                    "No Account Selected",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select an account to view positions")
                )
            }
        }
        .navigationTitle("Positions")
    }
}

struct PositionsContent: View {
    let account: Account
    @Binding var timeRange: TimeRange
    @Binding var granularity: TimeGranularity
    @Binding var selectedAssets: Set<String>

    @Environment(\.modelContext) private var modelContext
    @Query private var allEntries: [Transaction]

    @State private var positionData: [PositionPoint] = []
    @State private var positionSummaries: [PositionSummary] = []

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
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Split view
            HSplitView {
                // Left: Position cards
                PositionSelectorPanel(
                    positionSummaries: positionSummaries,
                    selectedAssets: $selectedAssets
                )
                .frame(minWidth: 300, idealWidth: 350)

                // Right: Quantity chart
                PositionChartView(
                    positionData: filteredPositionData,
                    granularity: granularity
                )
                .frame(minWidth: 500)
            }
        }
        .onAppear {
            calculatePositions()
        }
        .onChange(of: timeRange) { _, _ in calculatePositions() }
        .onChange(of: granularity) { _, _ in calculatePositions() }
        .onChange(of: selectedAssets) { _, _ in updateChart() }
    }

    private var filteredPositionData: [PositionPoint] {
        positionData.filter { selectedAssets.contains($0.assetId) }
    }

    private func calculatePositions() {
        print("\n=== Positions View Debug ===")
        let accountEntries = allEntries.filter { $0.account?.id == account.id }
        print("Total entries in account: \(accountEntries.count)")
        print("Entries with quantity: \(accountEntries.filter { $0.quantity != nil }.count)")
        print("Entries with assetId: \(accountEntries.filter { $0.assetId != nil }.count)")
        print("Entries with BOTH: \(accountEntries.filter { $0.quantity != nil && $0.assetId != nil }.count)")

        // Sample entries
        for entry in accountEntries.prefix(5) {
            print("  Sample: \(entry.transactionDescription.prefix(40)) | asset=\(entry.assetId ?? "nil") | qty=\(entry.quantity?.description ?? "nil")")
        }

        let dateRange = timeRange.dateRange
        let relevantEntries = allEntries.filter { entry in
            entry.date >= dateRange.start &&
            entry.date <= dateRange.end &&
            entry.quantity != nil &&
            entry.assetId != nil
        }

        print("In date range with quantity: \(relevantEntries.count)")

        // Calculate current positions (all time)
        var summaries: [String: PositionSummary] = [:]

        for entry in allEntries where entry.quantity != nil && entry.assetId != nil {
            let assetId = entry.assetId!.trimmingCharacters(in: .whitespaces)
            let qty = entry.quantity!

            // Skip empty asset IDs or zero quantities (cash movements without position change)
            guard !assetId.isEmpty && qty != 0 else { continue }

            if summaries[assetId] == nil {
                summaries[assetId] = PositionSummary(
                    assetId: assetId,
                    currentQuantity: 0,
                    unit: entry.quantityUnit ?? "units",
                    costBasis: 0,
                    transactionCount: 0
                )
            }

            let amt = entry.amount
            print("  \(assetId): \(entry.effectiveTransactionType.rawValue) qty=\(qty) amount=\(amt)")

            // Use quantity sign to determine position change
            // Positive quantity = adding to position (buy, dividend reinvest, interest)
            // Negative quantity = removing from position (sell, redemption)
            if qty > 0 {
                // Position increases
                summaries[assetId]?.currentQuantity += qty
                summaries[assetId]?.costBasis += abs(amt)
                print("    → ADD: position +\(qty), cost +\(abs(amt))")
            } else if qty < 0 {
                // Position decreases
                summaries[assetId]?.currentQuantity += qty // qty is already negative
                summaries[assetId]?.costBasis -= abs(amt)
                print("    → REMOVE: position \(qty), cost -\(abs(amt))")
            }

            summaries[assetId]?.transactionCount += 1
        }

        print("Summaries created: \(summaries.count)")
        for (asset, summary) in summaries {
            print("  \(asset): \(summary.currentQuantity) \(summary.unit)")
        }

        positionSummaries = summaries.values
            .filter { abs($0.currentQuantity) > 0.0001 || $0.transactionCount > 0 }
            .sorted { lhs, rhs in
                // USD first, then alphabetical
                if lhs.assetId == "USD" { return true }
                if rhs.assetId == "USD" { return false }
                return lhs.assetId < rhs.assetId
            }

        print("Final summaries after filter: \(positionSummaries.count)")
        print("============================\n")

        // Initialize selection
        if selectedAssets.isEmpty {
            selectedAssets = Set(positionSummaries.map { $0.assetId })
        }

        updateChart()
    }

    private func updateChart() {
        var points: [PositionPoint] = []

        for assetId in selectedAssets {
            let entries = allEntries.filter { entry in
                entry.assetId == assetId &&
                entry.quantity != nil &&
                entry.date >= timeRange.dateRange.start &&
                entry.date <= timeRange.dateRange.end
            }

            points.append(contentsOf: calculateQuantityOverTime(entries, assetId: assetId))
        }

        positionData = points.sorted { $0.date < $1.date }
    }

    private func calculateQuantityOverTime(_ entries: [Transaction], assetId: String) -> [PositionPoint] {
        let calendar = Calendar.current
        var grouped: [Date: Decimal] = [:]

        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard let qty = entry.quantity, qty != 0 else { continue }

            let periodStart = granularity.periodStart(for: entry.date, calendar: calendar)

            // Use quantity sign directly
            // Positive qty = adding to position
            // Negative qty = removing from position
            grouped[periodStart, default: 0] += qty
        }

        var cumulative: Decimal = 0
        var points: [PositionPoint] = []

        // Start at 0
        if let firstDate = grouped.keys.min() {
            let dayBefore = calendar.date(byAdding: .day, value: -1, to: firstDate)!
            points.append(PositionPoint(
                date: dayBefore,
                assetId: assetId,
                quantity: 0
            ))
        }

        // Accumulate quantities
        for (date, qtyChange) in grouped.sorted(by: { $0.key < $1.key }) {
            cumulative += qtyChange
            points.append(PositionPoint(
                date: date,
                assetId: assetId,
                quantity: cumulative
            ))
        }

        return points
    }
}

struct PositionSelectorPanel: View {
    let positionSummaries: [PositionSummary]
    @Binding var selectedAssets: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Positions", systemImage: "chart.bar.doc.horizontal")
                    .font(.headline)
                Spacer()

                Button("Select All") {
                    selectedAssets = Set(positionSummaries.map { $0.assetId })
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
                    ForEach(positionSummaries, id: \.assetId) { summary in
                        PositionCard(
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

struct PositionCard: View {
    let summary: PositionSummary
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

                    Text(formatQuantity(summary.currentQuantity, unit: summary.unit))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if summary.costBasis != 0 {
                        HStack(spacing: 4) {
                            Text("Avg:")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(summary.averagePrice, format: .currency(code: "USD"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(abs(summary.costBasis), format: .currency(code: "USD"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(summary.costBasis >= 0 ? .green : .red)

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

    private func formatQuantity(_ quantity: Decimal, unit: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = unit == "BTC" || unit == "ETH" ? 8 : 2

        let num = NSDecimalNumber(decimal: quantity)
        let formatted = formatter.string(from: num) ?? "\(quantity)"

        return "\(formatted) \(unit)"
    }
}

struct PositionChartView: View {
    let positionData: [PositionPoint]
    let granularity: TimeGranularity

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Quantity Over Time", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            if positionData.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No position data")
                        .foregroundColor(.secondary)
                    Text("Select assets to view quantity holdings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(positionData) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Quantity", NSDecimalNumber(decimal: point.quantity).doubleValue)
                    )
                    .foregroundStyle(by: .value("Asset", point.assetId))
                    .symbol(by: .value("Asset", point.assetId))
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
                                Text("\(doubleValue, specifier: "%.2f")")
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

struct PositionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let assetId: String
    let quantity: Decimal
}

struct PositionSummary {
    let assetId: String
    var currentQuantity: Decimal
    let unit: String
    var costBasis: Decimal
    var transactionCount: Int

    var averagePrice: Decimal {
        guard currentQuantity != 0 else { return 0 }
        return abs(costBasis) / abs(currentQuantity)
    }
}
