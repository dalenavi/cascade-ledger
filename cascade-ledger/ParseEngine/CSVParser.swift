//
//  CSVParser.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation

// CSV Parser using Frictionless dialect configuration
class CSVParser {
    private let dialect: CSVDialect

    init(dialect: CSVDialect = CSVDialect()) {
        self.dialect = dialect
    }

    // Parse CSV content into rows
    func parse(_ content: String) throws -> CSVData {
        // Remove BOM if present
        let cleanContent = content.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
            .replacingOccurrences(of: "\u{FEFF}", with: "")

        let lines = cleanContent.components(separatedBy: dialect.lineTerminator)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else {
            throw CSVParseError.emptyFile
        }

        var headers: [String] = []
        var rows: [[String]] = []
        var expectedColumnCount = 0
        var isFirstDataRow = true

        for (originalIndex, line) in lines.enumerated() {
            // Skip lines that look like legal disclaimers or notes
            if isNonDataRow(line) {
                print("Skipping non-data row \(originalIndex): \(line.prefix(50))")
                continue
            }

            let fields = parseLine(line)

            if isFirstDataRow && dialect.header {
                headers = fields.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                expectedColumnCount = headers.count
                isFirstDataRow = false
                print("Parsed headers (\(headers.count)): \(headers.joined(separator: ", "))")
            } else {
                isFirstDataRow = false

                // Handle rows with different column counts
                var normalizedFields = fields
                if fields.count > expectedColumnCount && expectedColumnCount > 0 {
                    // Truncate extra trailing fields
                    normalizedFields = Array(fields.prefix(expectedColumnCount))
                } else if fields.count < expectedColumnCount && expectedColumnCount > 0 {
                    // Pad with empty strings
                    normalizedFields.append(contentsOf: Array(repeating: "", count: expectedColumnCount - fields.count))
                }
                rows.append(normalizedFields)
            }
        }

        print("CSV Parse complete: \(headers.count) headers, \(rows.count) data rows from \(lines.count) total lines")

        return CSVData(headers: headers, rows: rows, dialect: dialect)
    }

    // Detect non-data rows (legal text, disclaimers, etc.)
    private func isNonDataRow(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        // Must be fairly complete line to be considered legal text
        // Avoid matching partial words in transaction descriptions
        let disclaimerPatterns = [
            "brokerage services provided by",
            "member sipc",
            "fdic insured",
            "copyright ",
            "all rights reserved",
            "terms and conditions",
            "privacy policy",
            "for questions about",
            "please visit",
            "disclosures:",
            "legal notice"
        ]

        for pattern in disclaimerPatterns {
            if lowercased.contains(pattern) {
                return true
            }
        }

        // Also skip lines that are too short to be valid data (but not empty - those are already filtered)
        if line.trimmingCharacters(in: .whitespaces).count < 5 {
            return true
        }

        return false
    }

    // Parse a single CSV line considering quotes
    private func parseLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        var previousChar: Character?

        for char in line {
            if char == Character(dialect.quoteChar) {
                if dialect.doubleQuote && previousChar == Character(dialect.quoteChar) {
                    // Escaped quote
                    currentField.append(char)
                    previousChar = nil
                    continue
                } else {
                    inQuotes.toggle()
                }
            } else if char == Character(dialect.delimiter) && !inQuotes {
                // End of field
                let trimmedField = dialect.skipInitialSpace
                    ? currentField.trimmingCharacters(in: .whitespaces)
                    : currentField
                fields.append(trimmedField)
                currentField = ""
            } else {
                currentField.append(char)
            }
            previousChar = char
        }

        // Add the last field
        let trimmedField = dialect.skipInitialSpace
            ? currentField.trimmingCharacters(in: .whitespaces)
            : currentField
        fields.append(trimmedField)

        return fields
    }

    // Parse with row limit for preview
    func parsePreview(_ content: String, limit: Int = 100) throws -> CSVData {
        let lines = content.components(separatedBy: dialect.lineTerminator)
            .filter { !$0.isEmpty }
            .prefix(limit + (dialect.header ? 1 : 0))

        let limitedContent = lines.joined(separator: dialect.lineTerminator)
        return try parse(limitedContent)
    }
}

// CSV data structure
struct CSVData {
    let headers: [String]
    let rows: [[String]]
    let dialect: CSVDialect

    var rowCount: Int {
        rows.count
    }

    var columnCount: Int {
        headers.isEmpty ? (rows.first?.count ?? 0) : headers.count
    }

    // Get row as dictionary
    func getRowAsDict(at index: Int) -> [String: String]? {
        guard index < rows.count else { return nil }
        guard !headers.isEmpty else { return nil }

        let row = rows[index]
        var dict: [String: String] = [:]

        for (headerIndex, header) in headers.enumerated() {
            if headerIndex < row.count {
                dict[header] = row[headerIndex]
            }
        }

        return dict
    }

    // Get column values
    func getColumn(_ columnName: String) -> [String]? {
        guard let columnIndex = headers.firstIndex(of: columnName) else {
            return nil
        }

        return rows.compactMap { row in
            columnIndex < row.count ? row[columnIndex] : nil
        }
    }

    // Sample data for preview
    func sample(_ count: Int = 10) -> CSVData {
        let sampleRows = Array(rows.prefix(count))
        return CSVData(headers: headers, rows: sampleRows, dialect: dialect)
    }
}

enum CSVParseError: LocalizedError {
    case emptyFile
    case invalidFormat
    case encodingError

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "CSV file is empty"
        case .invalidFormat:
            return "Invalid CSV format"
        case .encodingError:
            return "Failed to decode CSV content"
        }
    }
}