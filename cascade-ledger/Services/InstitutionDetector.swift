//
//  InstitutionDetector.swift
//  cascade-ledger
//
//  Detects which financial institution a CSV file came from
//

import Foundation

/// Detects institution from CSV headers and content patterns
struct InstitutionDetector {

    /// Known institutions we can detect
    enum Institution: String, CaseIterable {
        case fidelity = "fidelity"
        case coinbase = "coinbase"
        case schwab = "schwab"
        case unknown = "unknown"

        var displayName: String {
            switch self {
            case .fidelity: return "Fidelity Investments"
            case .coinbase: return "Coinbase"
            case .schwab: return "Charles Schwab"
            case .unknown: return "Unknown"
            }
        }
    }

    /// Detection confidence level
    enum Confidence {
        case high      // Multiple strong signals
        case medium    // Some indicators
        case low       // Weak match
        case none      // No match
    }

    /// Detection result
    struct DetectionResult {
        let institution: Institution
        let confidence: Confidence
        let indicators: [String]  // What patterns matched

        var isConfident: Bool {
            confidence == .high || confidence == .medium
        }
    }

    // MARK: - Detection

    /// Detect institution from CSV headers and sample rows
    func detect(headers: [String], sampleRows: [[String]] = []) -> DetectionResult {
        // Try each institution's pattern
        let fidelityResult = detectFidelity(headers: headers, sampleRows: sampleRows)
        let coinbaseResult = detectCoinbase(headers: headers, sampleRows: sampleRows)
        let schwabResult = detectSchwab(headers: headers, sampleRows: sampleRows)

        // Return the most confident match
        let results = [fidelityResult, coinbaseResult, schwabResult]
        let best = results.max(by: { a, b in
            confidenceScore(a.confidence) < confidenceScore(b.confidence)
        }) ?? DetectionResult(institution: .unknown, confidence: .none, indicators: [])

        return best
    }

    // MARK: - Institution-Specific Detection

    private func detectFidelity(headers: [String], sampleRows: [[String]]) -> DetectionResult {
        var indicators: [String] = []
        var score = 0

        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Strong indicators
        if normalizedHeaders.contains("run date") {
            indicators.append("Has 'Run Date' column")
            score += 3
        }

        if normalizedHeaders.contains("action") {
            indicators.append("Has 'Action' column")
            score += 2
        }

        if normalizedHeaders.contains("symbol") {
            indicators.append("Has 'Symbol' column")
            score += 1
        }

        // Fidelity specific: Settlement Price column
        if normalizedHeaders.contains("settlement price") {
            indicators.append("Has 'Settlement Price' column")
            score += 3
        }

        // Check for Fidelity action patterns in sample data
        if !sampleRows.isEmpty, let actionIndex = normalizedHeaders.firstIndex(of: "action") {
            let actions = sampleRows.compactMap { $0.indices.contains(actionIndex) ? $0[actionIndex] : nil }
            let fidelityActions = actions.filter {
                $0.contains("YOU BOUGHT") || $0.contains("YOU SOLD") || $0.contains("DIVIDEND")
            }

            if fidelityActions.count > 0 {
                indicators.append("Found Fidelity action patterns")
                score += 3
            }
        }

        let confidence: Confidence
        if score >= 6 {
            confidence = .high
        } else if score >= 3 {
            confidence = .medium
        } else if score > 0 {
            confidence = .low
        } else {
            confidence = .none
        }

        return DetectionResult(institution: .fidelity, confidence: confidence, indicators: indicators)
    }

    private func detectCoinbase(headers: [String], sampleRows: [[String]]) -> DetectionResult {
        var indicators: [String] = []
        var score = 0

        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Coinbase specific headers
        if normalizedHeaders.contains("timestamp") {
            indicators.append("Has 'Timestamp' column")
            score += 1
        }

        if normalizedHeaders.contains("transaction type") {
            indicators.append("Has 'Transaction Type' column")
            score += 2
        }

        if normalizedHeaders.contains("asset") || normalizedHeaders.contains("currency") {
            indicators.append("Has 'Asset' or 'Currency' column")
            score += 1
        }

        // Coinbase has Quantity Transacted, not just Quantity
        if normalizedHeaders.contains("quantity transacted") {
            indicators.append("Has 'Quantity Transacted' column")
            score += 3
        }

        // Coinbase patterns: Buy, Sell, Send, Receive, Rewards
        if !sampleRows.isEmpty, let typeIndex = normalizedHeaders.firstIndex(of: "transaction type") {
            let types = sampleRows.compactMap { $0.indices.contains(typeIndex) ? $0[typeIndex] : nil }
            let coinbaseTypes = types.filter {
                $0 == "Buy" || $0 == "Sell" || $0 == "Send" || $0 == "Receive" || $0 == "Rewards"
            }

            if coinbaseTypes.count > 0 {
                indicators.append("Found Coinbase transaction types")
                score += 3
            }
        }

        let confidence: Confidence
        if score >= 6 {
            confidence = .high
        } else if score >= 3 {
            confidence = .medium
        } else if score > 0 {
            confidence = .low
        } else {
            confidence = .none
        }

        return DetectionResult(institution: .coinbase, confidence: confidence, indicators: indicators)
    }

    private func detectSchwab(headers: [String], sampleRows: [[String]]) -> DetectionResult {
        var indicators: [String] = []
        var score = 0

        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // Schwab specific patterns
        if normalizedHeaders.contains("date") && normalizedHeaders.contains("action") {
            indicators.append("Has 'Date' and 'Action' columns")
            score += 1
        }

        if normalizedHeaders.contains("description") && normalizedHeaders.contains("fees & comm") {
            indicators.append("Has 'Fees & Comm' column")
            score += 2
        }

        let confidence: Confidence
        if score >= 3 {
            confidence = .medium
        } else if score > 0 {
            confidence = .low
        } else {
            confidence = .none
        }

        return DetectionResult(institution: .schwab, confidence: confidence, indicators: indicators)
    }

    // MARK: - Helpers

    private func confidenceScore(_ confidence: Confidence) -> Int {
        switch confidence {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}
