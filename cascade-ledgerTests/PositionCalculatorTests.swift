//
//  PositionCalculatorTests.swift
//  cascade-ledgerTests
//
//  Tests for PositionCalculator service
//

import XCTest
import SwiftData
@testable import cascade_ledger

final class PositionCalculatorTests: XCTestCase {
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var calculator: PositionCalculator!

    override func setUp() async throws {
        let schema = Schema([
            Account.self,
            Asset.self,
            Position.self,
            Transaction.self,
            JournalEntry.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)

        calculator = PositionCalculator()
        await calculator.configure(modelContext: modelContext)
    }

    override func tearDown() async throws {
        modelContainer = nil
        modelContext = nil
    }

    func test_recalculateAllPositions_singleAsset() async throws {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "SPY")
        modelContext.insert(account)
        modelContext.insert(asset)

        // Create buy transaction
        let buy = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let buyEntry = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: 1000,
            creditAmount: nil,
            quantity: 10,
            quantityUnit: "shares",
            transaction: buy
        )
        buyEntry.asset = asset
        buy.journalEntries.append(buyEntry)
        modelContext.insert(buy)

        // Recalculate
        try await calculator.recalculateAllPositions(for: account)

        // Verify position created
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate<Position> { position in
                position.account?.id == account.id
            }
        )
        let positions = try modelContext.fetch(descriptor)

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions.first?.quantity, 10)
        XCTAssertEqual(positions.first?.asset?.symbol, "SPY")
    }

    func test_recalculateAllPositions_multipleAssets() async throws {
        let account = Account(name: "Test", institution: nil)
        let spy = Asset(symbol: "SPY")
        let aapl = Asset(symbol: "AAPL")
        modelContext.insert(account)
        modelContext.insert(spy)
        modelContext.insert(aapl)

        // Create transactions for both assets
        let buySPY = Transaction(date: Date(), description: "Buy SPY", type: .buy, account: account)
        let spyEntry = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: 1000,
            quantity: 10,
            quantityUnit: "shares",
            transaction: buySPY
        )
        spyEntry.asset = spy
        buySPY.journalEntries.append(spyEntry)
        modelContext.insert(buySPY)

        let buyAAPL = Transaction(date: Date(), description: "Buy AAPL", type: .buy, account: account)
        let aaplEntry = JournalEntry(
            accountType: .asset,
            accountName: "AAPL",
            debitAmount: 2000,
            quantity: 20,
            quantityUnit: "shares",
            transaction: buyAAPL
        )
        aaplEntry.asset = aapl
        buyAAPL.journalEntries.append(aaplEntry)
        modelContext.insert(buyAAPL)

        // Recalculate
        try await calculator.recalculateAllPositions(for: account)

        // Verify both positions
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate<Position> { position in
                position.account?.id == account.id
            }
        )
        let positions = try modelContext.fetch(descriptor)

        XCTAssertEqual(positions.count, 2)

        let spyPosition = positions.first { $0.asset?.symbol == "SPY" }
        let aaplPosition = positions.first { $0.asset?.symbol == "AAPL" }

        XCTAssertEqual(spyPosition?.quantity, 10)
        XCTAssertEqual(aaplPosition?.quantity, 20)
    }

    func test_cleanupZeroPositions() async throws {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "SPY")
        modelContext.insert(account)
        modelContext.insert(asset)

        // Buy and sell equal amounts
        let buy = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let buyEntry = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: 1000,
            quantity: 10,
            quantityUnit: "shares",
            transaction: buy
        )
        buyEntry.asset = asset
        buy.journalEntries.append(buyEntry)
        modelContext.insert(buy)

        let sell = Transaction(date: Date(), description: "Sell", type: .sell, account: account)
        let sellEntry = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            creditAmount: 1000,
            quantity: 10,
            quantityUnit: "shares",
            transaction: sell
        )
        sellEntry.asset = asset
        sell.journalEntries.append(sellEntry)
        modelContext.insert(sell)

        // Recalculate - should create then delete zero position
        try await calculator.recalculateAllPositions(for: account)

        // Verify no positions exist
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate<Position> { position in
                position.account?.id == account.id
            }
        )
        let positions = try modelContext.fetch(descriptor)

        XCTAssertEqual(positions.count, 0)
    }

    func test_recalculateAfterSale() async throws {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "AAPL")
        modelContext.insert(account)
        modelContext.insert(asset)

        // Buy 100 shares
        let buy = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let buyEntry = JournalEntry(
            accountType: .asset,
            accountName: "AAPL",
            debitAmount: 10000,
            quantity: 100,
            quantityUnit: "shares",
            transaction: buy
        )
        buyEntry.asset = asset
        buy.journalEntries.append(buyEntry)
        modelContext.insert(buy)

        // Initial calculation
        try await calculator.recalculateAllPositions(for: account)

        // Sell 30 shares
        let sell = Transaction(date: Date(), description: "Sell", type: .sell, account: account)
        let sellEntry = JournalEntry(
            accountType: .asset,
            accountName: "AAPL",
            creditAmount: 3000,
            quantity: 30,
            quantityUnit: "shares",
            transaction: sell
        )
        sellEntry.asset = asset
        sell.journalEntries.append(sellEntry)
        modelContext.insert(sell)

        // Recalculate after sale
        try await calculator.recalculateAllPositions(for: account)

        // Verify position updated
        let descriptor = FetchDescriptor<Position>(
            predicate: #Predicate<Position> { position in
                position.account?.id == account.id
            }
        )
        let positions = try modelContext.fetch(descriptor)

        XCTAssertEqual(positions.count, 1)
        XCTAssertEqual(positions.first?.quantity, 70)
    }
}
