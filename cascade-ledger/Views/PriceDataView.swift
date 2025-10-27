//
//  PriceDataView.swift
//  cascade-ledger
//
//  Manage asset price data
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PriceDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allPrices: [AssetPrice]
    @Query private var allAccounts: [Account]

    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var isFetchingAPI = false
    @State private var importResult: PriceImportResult?
    @State private var showingResult = false
    @State private var fetchProgress = ""
    @State private var selectedAccount: Account?

    private var assetStats: [(asset: String, count: Int, dateRange: (Date?, Date?))] {
        let grouped = Dictionary(grouping: allPrices, by: { $0.assetId })
        return grouped.map { (asset, prices) in
            let sortedPrices = prices.sorted { $0.date < $1.date }
            return (
                asset: asset,
                count: prices.count,
                dateRange: (sortedPrices.first?.date, sortedPrices.last?.date)
            )
        }.sorted { $0.asset < $1.asset }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Info banner
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Price Data")
                            .font(.title2)
                        Text("\(allPrices.count) price points for \(assetStats.count) assets")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    HStack(spacing: 12) {
                        if !allAccounts.isEmpty {
                            Picker("Account", selection: $selectedAccount) {
                                Text("Select Account").tag(nil as Account?)
                                ForEach(allAccounts) { account in
                                    Text(account.name).tag(account as Account?)
                                }
                            }
                            .frame(width: 200)

                            if let account = selectedAccount {
                                Button(action: { fetchAllHoldings(account: account) }) {
                                    if isFetchingAPI {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                        Text("Fetching...")
                                    } else {
                                        Label("Fetch All Holdings", systemImage: "arrow.down.circle")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isFetchingAPI)
                            }
                        }

                        Button(action: { showingFileImporter = true }) {
                            if isImporting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting || isFetchingAPI)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Asset list
                if assetStats.isEmpty {
                    ContentUnavailableView(
                        "No Price Data",
                        systemImage: "chart.line.uptrend.xyaxis.circle",
                        description: Text("Import price history CSVs or fetch from APIs to enable market value tracking")
                    )
                } else {
                    VStack(spacing: 0) {
                        // Re-fetch toolbar
                        if selectedAccount != nil {
                            HStack {
                                Text("Re-fetch all assets to update prices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button(action: {
                                    if let account = selectedAccount {
                                        fetchAllHoldings(account: account)
                                    }
                                }) {
                                    if isFetchingAPI {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Label("Re-fetch All", systemImage: "arrow.clockwise")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(isFetchingAPI)
                            }
                            .padding()
                            .background(Color.blue.opacity(0.1))

                            Divider()
                        }

                        List {
                            ForEach(assetStats, id: \.asset) { stat in
                                AssetPriceRow(
                                    asset: stat.asset,
                                    priceCount: stat.count,
                                    dateRange: stat.dateRange,
                                    onDelete: {
                                        deletePriceData(for: stat.asset)
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .navigationTitle("Price Data")
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            onCompletion: handlePriceFileImport
        )
        .alert("Price Import Complete", isPresented: $showingResult) {
            Button("OK", role: .cancel) {}
        } message: {
            if let result = importResult {
                Text("""
                Imported: \(result.imported)
                Updated: \(result.updated)
                Skipped: \(result.skipped)
                Errors: \(result.errors.count)
                """)
            }
        }
    }

    private func handlePriceFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            guard let content = try? String(contentsOf: url) else {
                print("Failed to read price file")
                return
            }

            isImporting = true

            Task {
                do {
                    let priceService = PriceDataService(modelContext: modelContext)
                    let importResult = try await priceService.importPricesFromCSV(content)

                    await MainActor.run {
                        self.importResult = importResult
                        showingResult = true
                        isImporting = false
                    }
                } catch {
                    print("Price import failed: \(error)")
                    await MainActor.run {
                        isImporting = false
                    }
                }
            }
        case .failure(let error):
            print("File selection failed: \(error)")
        }
    }

    private func fetchAllHoldings(account: Account) {
        isFetchingAPI = true
        fetchProgress = "Starting..."

        Task {
            do {
                let priceAPIService = PriceAPIService(modelContext: modelContext)
                let results = try await priceAPIService.fetchPricesForAllHoldings(account: account)

                let totalImported = results.values.reduce(0, +)

                await MainActor.run {
                    importResult = PriceImportResult(
                        imported: totalImported,
                        updated: 0,
                        skipped: 0,
                        errors: []
                    )
                    showingResult = true
                    isFetchingAPI = false
                    fetchProgress = ""
                }
            } catch {
                print("API fetch failed: \(error)")
                await MainActor.run {
                    isFetchingAPI = false
                    fetchProgress = ""
                }
            }
        }
    }

    private func deletePriceData(for assetId: String) {
        print("Deleting all price data for \(assetId)")

        let descriptor = FetchDescriptor<AssetPrice>(
            predicate: #Predicate<AssetPrice> { price in
                price.assetId == assetId
            }
        )

        do {
            let prices = try modelContext.fetch(descriptor)
            print("Found \(prices.count) price points to delete")

            for price in prices {
                modelContext.delete(price)
            }

            try modelContext.save()
            print("✓ Deleted \(prices.count) price points for \(assetId)")
        } catch {
            print("Failed to delete price data: \(error)")
        }
    }
}

struct AssetPriceRow: View {
    let asset: String
    let priceCount: Int
    let dateRange: (Date?, Date?)
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(asset)
                    .font(.headline)

                if let start = dateRange.0, let end = dateRange.1 {
                    Text("\(start.formatted(date: .abbreviated, time: .omitted)) - \(end.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(priceCount) days")
                    .font(.headline)
                    .foregroundColor(.blue)

                Text("Price points")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button(action: { showingDeleteConfirmation = true }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete all price data for \(asset)")
        }
        .padding(.vertical, 4)
        .alert("Delete Price Data?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                onDelete()
            }
        } message: {
            Text("Delete all \(priceCount) price points for \(asset)? This will affect market value calculations. You can re-fetch the data afterwards.")
        }
    }
}
