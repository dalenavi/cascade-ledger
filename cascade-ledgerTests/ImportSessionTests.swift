//
//  ImportSessionTests.swift
//  cascade-ledgerTests
//
//  Tests for ImportSession model
//

import XCTest
import SwiftData
@testable import cascade_ledger

final class ImportSessionTests: XCTestCase {

    func test_fileHashCalculation() {
        let data1 = "test data".data(using: .utf8)!
        let data2 = "test data".data(using: .utf8)!
        let data3 = "different data".data(using: .utf8)!

        let hash1 = ImportSession.calculateHash(data1)
        let hash2 = ImportSession.calculateHash(data2)
        let hash3 = ImportSession.calculateHash(data3)

        XCTAssertEqual(hash1, hash2)  // Same data = same hash
        XCTAssertNotEqual(hash1, hash3)  // Different data = different hash
        XCTAssertEqual(hash1.count, 64)  // SHA256 = 64 hex characters
    }

    func test_importSessionInitialization() {
        let account = Account(name: "Test", institution: nil)
        let plan = ParsePlan(name: "Test Plan", account: nil, institution: nil)
        let version = plan.commitVersion(message: "Test")
        let fileData = "csv data".data(using: .utf8)!

        let session = ImportSession(
            fileName: "test.csv",
            fileData: fileData,
            account: account,
            parsePlanVersion: version
        )

        XCTAssertEqual(session.fileName, "test.csv")
        XCTAssertEqual(session.status, .pending)
        XCTAssertEqual(session.totalRows, 0)
        XCTAssertEqual(session.successfulRows, 0)
        XCTAssertEqual(session.failedRows, 0)
        XCTAssertNotNil(session.fileHash)
    }

    func test_dateRangeValidation() {
        let account = Account(name: "Test", institution: nil)
        let plan = ParsePlan(name: "Test", account: nil, institution: nil)
        let version = plan.commitVersion(message: "Test")
        let fileData = "data".data(using: .utf8)!

        let session = ImportSession(
            fileName: "test.csv",
            fileData: fileData,
            account: account,
            parsePlanVersion: version
        )

        // Set date range
        session.dataStartDate = Date(timeIntervalSince1970: 1000)
        session.dataEndDate = Date(timeIntervalSince1970: 2000)

        XCTAssertTrue(session.dataStartDate <= session.dataEndDate)
    }

    func test_importMode_default() {
        let account = Account(name: "Test", institution: nil)
        let plan = ParsePlan(name: "Test", account: nil, institution: nil)
        let version = plan.commitVersion(message: "Test")
        let fileData = "data".data(using: .utf8)!

        let session = ImportSession(
            fileName: "test.csv",
            fileData: fileData,
            account: account,
            parsePlanVersion: version
        )

        XCTAssertEqual(session.importMode, .append)
    }
}
