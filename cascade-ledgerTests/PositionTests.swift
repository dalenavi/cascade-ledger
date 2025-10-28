//
//  PositionTests.swift
//  cascade-ledgerTests
//
//  Tests for Position model
//

import XCTest
import SwiftData
@testable import cascade_ledger

final class PositionTests: XCTestCase {

    func test_positionInitialization() {
        let account = Account(name: "Test Account", institution: nil)
        let asset = Asset(symbol: "SPY")
        let position = Position(account: account, asset: asset)

        XCTAssertEqual(position.quantity, 0)
        XCTAssertEqual(position.account?.name, "Test Account")
        XCTAssertEqual(position.asset?.symbol, "SPY")
    }

    func test_positionCalculation_simpleCase() {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "SPY")
        let position = Position(account: account, asset: asset)

        // Create test transactions
        let buy1 = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let entry1 = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: 1000,
            creditAmount: nil,
            quantity: 10,
            quantityUnit: "shares",
            transaction: buy1
        )
        entry1.asset = asset
        buy1.journalEntries.append(entry1)

        let buy2 = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let entry2 = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: 500,
            creditAmount: nil,
            quantity: 5,
            quantityUnit: "shares",
            transaction: buy2
        )
        entry2.asset = asset
        buy2.journalEntries.append(entry2)

        // Recalculate
        position.recalculate(from: [buy1, buy2])

        XCTAssertEqual(position.quantity, 15)  // 10 + 5
    }

    func test_positionCalculation_withSales() {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "AAPL")
        let position = Position(account: account, asset: asset)

        // Buy 100 shares
        let buy = Transaction(date: Date(), description: "Buy", type: .buy, account: account)
        let buyEntry = JournalEntry(
            accountType: .asset,
            accountName: "AAPL",
            debitAmount: 10000,
            creditAmount: nil,
            quantity: 100,
            quantityUnit: "shares",
            transaction: buy
        )
        buyEntry.asset = asset
        buy.journalEntries.append(buyEntry)

        // Sell 30 shares
        let sell = Transaction(date: Date(), description: "Sell", type: .sell, account: account)
        let sellEntry = JournalEntry(
            accountType: .asset,
            accountName: "AAPL",
            debitAmount: nil,
            creditAmount: 3000,
            quantity: 30,
            quantityUnit: "shares",
            transaction: sell
        )
        sellEntry.asset = asset
        sell.journalEntries.append(sellEntry)

        position.recalculate(from: [buy, sell])

        XCTAssertEqual(position.quantity, 70)  // 100 - 30
    }

    func test_zeroPositionDetection() {
        let account = Account(name: "Test", institution: nil)
        let asset = Asset(symbol: "SPY")
        let position = Position(account: account, asset: asset)

        // Buy and sell equal amounts
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

        let sell = Transaction(date: Date(), description: "Sell", type: .sell, account: account)
        let sellEntry = JournalEntry(
            accountType: .asset,
            accountName: "SPY",
            debitAmount: nil,
            creditAmount: 1000,
            quantity: 10,
            quantityUnit: "shares",
            transaction: sell
        )
        sellEntry.asset = asset
        sell.journalEntries.append(sellEntry)

        position.recalculate(from: [buy, sell])

        XCTAssertEqual(position.quantity, 0)
        // Note: In real system, zero positions should be deleted
    }
}
