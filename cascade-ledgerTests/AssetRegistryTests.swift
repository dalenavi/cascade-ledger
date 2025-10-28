//
//  AssetRegistryTests.swift
//  cascade-ledgerTests
//
//  Tests for AssetRegistry service
//

import XCTest
import SwiftData
@testable import cascade_ledger

@MainActor
final class AssetRegistryTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var registry: AssetRegistry!

    override func setUp() async throws {
        let schema = Schema([Asset.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        registry = AssetRegistry.shared
        registry.clearCache()
        registry.configure(modelContext: modelContext)
    }

    override func tearDown() async throws {
        registry.clearCache()
        modelContainer = nil
        modelContext = nil
    }

    func test_findOrCreate_newAsset() {
        let asset = registry.findOrCreate(symbol: "AAPL", name: "Apple Inc.")

        XCTAssertEqual(asset.symbol, "AAPL")
        XCTAssertEqual(asset.name, "Apple Inc.")
    }

    func test_findOrCreate_deduplication() {
        let asset1 = registry.findOrCreate(symbol: "AAPL")
        let asset2 = registry.findOrCreate(symbol: "AAPL")

        XCTAssertEqual(asset1.id, asset2.id)
    }

    func test_symbolNormalization() {
        let asset1 = registry.findOrCreate(symbol: "spy")
        let asset2 = registry.findOrCreate(symbol: "SPY")
        let asset3 = registry.findOrCreate(symbol: " SPY ")

        XCTAssertEqual(asset1.id, asset2.id)
        XCTAssertEqual(asset2.id, asset3.id)
        XCTAssertEqual(asset1.symbol, "SPY")
    }

    func test_institutionMapping() {
        registry.registerMapping(
            institution: "Fidelity",
            alias: "CASH",
            canonical: "USD"
        )

        let asset1 = registry.findOrCreate(symbol: "USD")
        let asset2 = registry.findOrCreate(symbol: "CASH", institution: "Fidelity")

        XCTAssertEqual(asset1.id, asset2.id)
        XCTAssertEqual(asset1.symbol, "USD")
    }

    func test_caching() {
        // Create asset directly in database
        let asset = Asset(symbol: "MSFT", name: "Microsoft")
        modelContext.insert(asset)

        // Clear cache to force registry to query database
        registry.clearCache()

        // Should find from database
        let found = registry.findOrCreate(symbol: "MSFT")
        XCTAssertEqual(found.id, asset.id)

        // Should now be in cache
        let cached = registry.findOrCreate(symbol: "MSFT")
        XCTAssertEqual(cached.id, asset.id)
    }

    func test_distinctAssets() {
        // FBTC and BTC should be different assets
        let fbtc = registry.findOrCreate(symbol: "FBTC", name: "Fidelity Bitcoin Fund")
        let btc = registry.findOrCreate(symbol: "BTC", name: "Bitcoin")

        XCTAssertNotEqual(fbtc.id, btc.id)
        XCTAssertNotEqual(fbtc.symbol, btc.symbol)
    }

    func test_allAssets() {
        _ = registry.findOrCreate(symbol: "AAPL")
        _ = registry.findOrCreate(symbol: "MSFT")
        _ = registry.findOrCreate(symbol: "GOOGL")

        XCTAssertEqual(registry.allAssets.count, 3)
    }
}
