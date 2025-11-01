//
//  CSVRow.swift
//  cascade-ledger
//
//  Wrapper for CSV row data with convenient access
//

import Foundation

/// Represents a single row from CSV with metadata
struct CSVRowData {
    let data: [String: String]  // Raw CSV data
    let globalRowNumber: Int
    let sourceFileName: String
    let fileRowNumber: Int
    let date: Date

    init(data: [String: String], dateFormatter: DateFormatter) {
        self.data = data
        self.globalRowNumber = Int(data["_globalRowNumber"] ?? "0") ?? 0
        self.sourceFileName = data["_sourceFile"] ?? ""
        self.fileRowNumber = Int(data["_fileRowNumber"] ?? "0") ?? 0

        // Parse date from "Run Date" field
        if let dateStr = data["Run Date"],
           let parsedDate = dateFormatter.date(from: dateStr) {
            self.date = parsedDate
        } else {
            self.date = Date.distantPast
        }
    }
}
