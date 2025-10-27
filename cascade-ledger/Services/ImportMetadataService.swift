//
//  ImportMetadataService.swift
//  cascade-ledger
//
//  Service to infer import batch metadata from CSV
//

import Foundation

class ImportMetadataService {
    static let shared = ImportMetadataService()

    private init() {}

    // Infer date range from CSV data
    func inferDateRange(from rawFile: RawFile) -> (start: Date?, end: Date?) {
        let csvParser = CSVParser()
        guard let csvContent = String(data: rawFile.content, encoding: .utf8),
              let csvData = try? csvParser.parse(csvContent) else {
            return (nil, nil)
        }

        // Try to find date column
        let dateColumnIndex = findDateColumn(headers: csvData.headers)
        guard let dateIndex = dateColumnIndex else {
            return (nil, nil)
        }

        // Extract and parse dates
        var dates: [Date] = []
        for row in csvData.rows {
            guard dateIndex < row.count else { continue }
            let dateString = row[dateIndex]

            if let date = parseDate(dateString) {
                dates.append(date)
            }
        }

        guard !dates.isEmpty else {
            return (nil, nil)
        }

        return (dates.min(), dates.max())
    }

    // Suggest a name for the import batch
    func suggestBatchName(from rawFile: RawFile, account: Account, dateRange: (start: Date?, end: Date?)) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short

        if let start = dateRange.start, let end = dateRange.end {
            let startStr = dateFormatter.string(from: start)
            let endStr = dateFormatter.string(from: end)
            return "\(account.name) - \(startStr) to \(endStr)"
        } else {
            let timestamp = DateFormatter()
            timestamp.dateStyle = .short
            timestamp.timeStyle = .short
            return "\(account.name) - \(timestamp.string(from: Date()))"
        }
    }

    // MARK: - Private Helpers

    private func findDateColumn(headers: [String]) -> Int? {
        for (index, header) in headers.enumerated() {
            let lowercased = header.lowercased()
            if lowercased.contains("date") || lowercased.contains("time") {
                return index
            }
        }
        return nil
    }

    private func parseDate(_ dateString: String) -> Date? {
        let formats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "M/d/yyyy",
            "yyyy/MM/dd",
            "MM-dd-yyyy",
            "dd-MM-yyyy"
        ]

        let formatter = DateFormatter()
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }

        // Try ISO8601
        let isoFormatter = ISO8601DateFormatter()
        return isoFormatter.date(from: dateString)
    }
}
