//
//  CSVFieldMapping.swift
//  cascade-ledger
//
//  Defines how to map institution-specific CSV headers to standard fields
//

import Foundation

/// Configuration for mapping CSV field names to standardized fields
/// Different financial institutions use different column names - this struct
/// allows account-specific field mapping
struct CSVFieldMapping: Codable {
    // Required fields
    var dateField: String = "Run Date"
    var actionField: String = "Action"

    // Amount & balance (institution-specific!)
    var amountField: String = "Amount ($)"
    var balanceField: String = "Cash Balance ($)"

    // Transaction details
    var symbolField: String? = "Symbol"
    var quantityField: String? = "Quantity"
    var priceField: String? = "Price ($)"
    var descriptionField: String? = "Description"

    // Optional fields
    var settlementDateField: String? = "Settlement Date"
    var commissionField: String? = "Commission ($)"
    var feesField: String? = "Fees ($)"
    var accruedInterestField: String? = "Accrued Interest ($)"
    var typeField: String? = "Type"

    /// Auto-detect field names from CSV headers
    /// Returns a CSVFieldMapping with detected field names
    static func detect(from headers: [String]) -> CSVFieldMapping {
        var mapping = CSVFieldMapping()

        // Detect balance field (multiple possible names)
        if let balanceField = detectBalanceField(headers) {
            mapping.balanceField = balanceField
        }

        // Detect amount field
        if let amountField = detectAmountField(headers) {
            mapping.amountField = amountField
        }

        // Detect date field
        if let dateField = detectDateField(headers) {
            mapping.dateField = dateField
        }

        // Detect action field
        if let actionField = headers.first(where: { $0.lowercased().contains("action") }) {
            mapping.actionField = actionField
        }

        // Detect symbol field
        if let symbolField = headers.first(where: { $0.lowercased().contains("symbol") }) {
            mapping.symbolField = symbolField
        }

        // Detect quantity field
        if let quantityField = headers.first(where: { $0.lowercased().contains("quantity") || $0.lowercased().contains("shares") }) {
            mapping.quantityField = quantityField
        }

        // Detect price field
        if let priceField = headers.first(where: { $0.lowercased().contains("price") }) {
            mapping.priceField = priceField
        }

        // Detect description field
        if let descriptionField = headers.first(where: { $0.lowercased().contains("description") }) {
            mapping.descriptionField = descriptionField
        }

        return mapping
    }

    /// Detect balance field from headers
    private static func detectBalanceField(_ headers: [String]) -> String? {
        let patterns = [
            "Cash Balance",
            "Balance",
            "Account Balance",
            "Ending Balance",
            "Running Balance"
        ]

        for pattern in patterns {
            if let match = headers.first(where: {
                $0.lowercased().contains(pattern.lowercased())
            }) {
                return match
            }
        }

        return nil
    }

    /// Detect amount field from headers
    private static func detectAmountField(_ headers: [String]) -> String? {
        let patterns = [
            "Amount ($)",
            "Amount",
            "Transaction Amount",
            "Value"
        ]

        for pattern in patterns {
            if let match = headers.first(where: {
                $0.lowercased().contains(pattern.lowercased())
            }) {
                return match
            }
        }

        return nil
    }

    /// Detect date field from headers
    private static func detectDateField(_ headers: [String]) -> String? {
        let patterns = [
            "Run Date",
            "Date",
            "Transaction Date",
            "Trade Date"
        ]

        for pattern in patterns {
            if let match = headers.first(where: {
                $0.lowercased().contains(pattern.lowercased())
            }) {
                return match
            }
        }

        return nil
    }
}

// MARK: - Predefined Mappings

extension CSVFieldMapping {
    /// Default mapping for Fidelity CSV format
    static var fidelity: CSVFieldMapping {
        CSVFieldMapping(
            dateField: "Run Date",
            actionField: "Action",
            amountField: "Amount ($)",
            balanceField: "Cash Balance ($)",
            symbolField: "Symbol",
            quantityField: "Quantity",
            priceField: "Price ($)",
            descriptionField: "Description",
            settlementDateField: "Settlement Date"
        )
    }

    /// Generic mapping for standard CSV format
    static var generic: CSVFieldMapping {
        CSVFieldMapping(
            dateField: "Date",
            actionField: "Action",
            amountField: "Amount",
            balanceField: "Balance",
            symbolField: "Symbol",
            quantityField: "Quantity",
            priceField: "Price",
            descriptionField: "Description"
        )
    }
}
