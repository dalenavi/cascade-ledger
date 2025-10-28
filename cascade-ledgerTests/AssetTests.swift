//
//  AssetTests.swift
//  cascade-ledgerTests
//
//  Tests for Asset model
//

import XCTest
@testable import cascade_ledger

final class AssetTests: XCTestCase {

    func test_symbolNormalization() {
        let asset1 = Asset(symbol: "spy")
        let asset2 = Asset(symbol: "SPY")
        let asset3 = Asset(symbol: " SPY ")

        XCTAssertEqual(asset1.symbol, "SPY")
        XCTAssertEqual(asset2.symbol, "SPY")
        XCTAssertEqual(asset3.symbol, "SPY")
    }

    func test_assetClassInference_crypto() {
        XCTAssertEqual(Asset(symbol: "BTC").assetClass, .crypto)
        XCTAssertEqual(Asset(symbol: "ETH").assetClass, .crypto)
        XCTAssertEqual(Asset(symbol: "SOL").assetClass, .crypto)
    }

    func test_assetClassInference_cash() {
        XCTAssertEqual(Asset(symbol: "USD").assetClass, .cash)
        XCTAssertEqual(Asset(symbol: "SPAXX").assetClass, .cash)
        XCTAssertEqual(Asset(symbol: "VMFXX").assetClass, .cash)
    }

    func test_assetClassInference_mutualFund() {
        XCTAssertEqual(Asset(symbol: "FXAIX").assetClass, .mutualFund)
        XCTAssertEqual(Asset(symbol: "VTSAX").assetClass, .mutualFund)
    }

    func test_assetClassInference_commodity() {
        XCTAssertEqual(Asset(symbol: "GLD").assetClass, .commodity)
        XCTAssertEqual(Asset(symbol: "SLV").assetClass, .commodity)
    }

    func test_assetClassInference_stock_default() {
        // Should default to stock for unknown symbols
        XCTAssertEqual(Asset(symbol: "AAPL").assetClass, .stock)
        XCTAssertEqual(Asset(symbol: "MSFT").assetClass, .stock)
    }

    func test_cashEquivalentFlag() {
        let spaxx = Asset(symbol: "SPAXX")
        XCTAssertFalse(spaxx.isCashEquivalent)  // Default

        spaxx.isCashEquivalent = true
        XCTAssertTrue(spaxx.isCashEquivalent)
    }

    func test_defaultName() {
        let asset = Asset(symbol: "SPY")
        XCTAssertEqual(asset.name, "SPY")  // Defaults to symbol
    }

    func test_customName() {
        let asset = Asset(symbol: "SPY", name: "SPDR S&P 500 ETF")
        XCTAssertEqual(asset.name, "SPDR S&P 500 ETF")
    }

    func test_distinctAssets() {
        // FBTC and BTC are different assets
        let fbtc = Asset(symbol: "FBTC", name: "Fidelity Wise Origin Bitcoin Fund")
        let btc = Asset(symbol: "BTC", name: "Bitcoin")

        XCTAssertNotEqual(fbtc.id, btc.id)
        XCTAssertNotEqual(fbtc.symbol, btc.symbol)
        XCTAssertNotEqual(fbtc.name, btc.name)
    }
}
