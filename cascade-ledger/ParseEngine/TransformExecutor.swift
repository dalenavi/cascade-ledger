//
//  TransformExecutor.swift
//  cascade-ledger
//
//  Created for Parse Studio implementation
//

import Foundation
import JavaScriptCore

// Transform executor for JSONata and other transformations
class TransformExecutor {
    private let jsContext: JSContext

    init() {
        guard let context = JSContext() else {
            fatalError("Failed to create JavaScript context")
        }
        self.jsContext = context
        setupJSONata()
    }

    // Setup JSONata library in JavaScript context
    private func setupJSONata() {
        // Note: In a real implementation, we would load the JSONata library
        // For now, we'll implement basic transformations
        let jsCode = """
        // Simple JSONata-like transform function
        function transform(data, expression) {
            try {
                // Basic field mapping
                if (expression.startsWith('$.')) {
                    const path = expression.substring(2);
                    return getNestedValue(data, path);
                }

                // Direct value
                if (expression.startsWith('"') && expression.endsWith('"')) {
                    return expression.slice(1, -1);
                }

                // Arithmetic expressions
                if (expression.includes('+') || expression.includes('-') ||
                    expression.includes('*') || expression.includes('/')) {
                    return eval(expression.replace(/\\$/g, 'data.'));
                }

                // Default: return the expression as-is
                return expression;
            } catch (e) {
                return null;
            }
        }

        function getNestedValue(obj, path) {
            return path.split('.').reduce((current, key) => {
                return current ? current[key] : null;
            }, obj);
        }

        // Date parsing
        function parseDate(dateStr, format) {
            // Simple date parsing (can be enhanced)
            return new Date(dateStr).toISOString();
        }

        // Number parsing
        function parseNumber(value) {
            if (typeof value === 'string') {
                // Remove currency symbols and commas
                const cleaned = value.replace(/[$,]/g, '');
                return parseFloat(cleaned);
            }
            return parseFloat(value);
        }

        // String normalization
        function normalizeString(value) {
            if (typeof value !== 'string') return String(value);
            return value.trim().replace(/\\s+/g, ' ');
        }
        """

        jsContext.evaluateScript(jsCode)
    }

    // Execute transform on a single row
    func executeTransform(_ transform: Transform, data: [String: Any]) throws -> Any? {
        switch transform.type {
        case .jsonata:
            return try executeJSONata(transform.expression, data: data)

        case .regex:
            return try executeRegex(transform.expression, data: data)

        case .calculation:
            return try executeCalculation(transform.expression, data: data)

        case .jolt:
            // JOLT transforms would require additional implementation
            return nil
        }
    }

    // Execute JSONata expression
    private func executeJSONata(_ expression: String, data: [String: Any]) throws -> Any? {
        let jsonData = try JSONSerialization.data(withJSONObject: data)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        jsContext.setObject(jsonString, forKeyedSubscript: "jsonData" as NSString)
        jsContext.setObject(expression, forKeyedSubscript: "expression" as NSString)

        let result = jsContext.evaluateScript("""
            const data = JSON.parse(jsonData);
            transform(data, expression);
        """)

        return result?.toObject()
    }

    // Execute regex transformation
    private func executeRegex(_ pattern: String, data: [String: Any]) throws -> Any? {
        // Get the first string value from data
        guard let inputValue = data.values.first as? String else {
            return nil
        }

        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(location: 0, length: inputValue.utf16.count)

        if let match = regex.firstMatch(in: inputValue, options: [], range: range) {
            if match.numberOfRanges > 1 {
                // Return first capture group
                let captureRange = match.range(at: 1)
                if captureRange.location != NSNotFound {
                    return (inputValue as NSString).substring(with: captureRange)
                }
            }
            // Return full match
            return (inputValue as NSString).substring(with: match.range)
        }

        return nil
    }

    // Execute calculation
    private func executeCalculation(_ expression: String, data: [String: Any]) throws -> Any? {
        // Replace field references with values
        var calcExpression = expression

        for (key, value) in data {
            if let numValue = value as? Double {
                calcExpression = calcExpression.replacingOccurrences(of: "$\(key)", with: String(numValue))
            } else if let numValue = value as? Int {
                calcExpression = calcExpression.replacingOccurrences(of: "$\(key)", with: String(numValue))
            }
        }

        // Evaluate the expression
        let result = jsContext.evaluateScript(calcExpression)
        return result?.toObject()
    }

    // Transform entire row based on schema mappings
    func transformRow(_ row: [String: String], schema: TableSchema, transforms: [Transform]) throws -> [String: Any] {
        var transformedRow: [String: Any] = [:]

        // Apply field mappings and type conversions
        for field in schema.fields {
            if let value = row[field.name] {
                // Check for missing values
                if let missingValues = schema.missingValues,
                   missingValues.contains(value) {
                    transformedRow[field.mapping ?? field.name] = nil
                    continue
                }

                // Type conversion
                let convertedValue = try convertFieldValue(value, type: field.type, format: field.format)

                // Validate constraints
                if let constraints = field.constraints {
                    try validateConstraints(convertedValue, constraints: constraints, fieldName: field.name)
                }

                transformedRow[field.mapping ?? field.name] = convertedValue
            }
        }

        // Apply transforms
        for transform in transforms {
            if let targetField = transform.targetField {
                let result = try executeTransform(transform, data: transformedRow)
                transformedRow[targetField] = result
            }
        }

        return transformedRow
    }

    // Convert field value based on type
    private func convertFieldValue(_ value: String, type: FieldType, format: String?) throws -> Any {
        switch type {
        case .string:
            return value

        case .integer:
            guard let intValue = Int(value.replacingOccurrences(of: ",", with: "")) else {
                throw TransformError.typeMismatch(expected: "integer", got: value)
            }
            return intValue

        case .number:
            let cleanValue = value.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "$", with: "")
            guard let doubleValue = Double(cleanValue) else {
                throw TransformError.typeMismatch(expected: "number", got: value)
            }
            return doubleValue

        case .boolean:
            let lowercased = value.lowercased()
            return lowercased == "true" || lowercased == "yes" || lowercased == "1"

        case .date, .datetime:
            return try parseDate(value, format: format)

        case .currency:
            let cleanValue = value.replacingOccurrences(of: ",", with: "")
                .replacingOccurrences(of: "$", with: "")
            guard let decimal = Decimal(string: cleanValue) else {
                throw TransformError.typeMismatch(expected: "currency", got: value)
            }
            return decimal
        }
    }

    // Parse date with format
    private func parseDate(_ value: String, format: String?) throws -> Date {
        let formatter = DateFormatter()

        if let format = format {
            formatter.dateFormat = format
        } else {
            // Try common formats
            let formats = ["yyyy-MM-dd", "MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd HH:mm:ss"]
            for fmt in formats {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: value) {
                    return date
                }
            }
        }

        if let date = formatter.date(from: value) {
            return date
        }

        // Try ISO8601
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: value) {
            return date
        }

        throw TransformError.dateParseError(value: value)
    }

    // Validate field constraints
    private func validateConstraints(_ value: Any?, constraints: FieldConstraints, fieldName: String) throws {
        if constraints.required == true && value == nil {
            throw TransformError.requiredFieldMissing(field: fieldName)
        }

        guard let value = value else { return }

        // Numeric constraints
        if let numValue = value as? Double {
            if let min = constraints.minimum, numValue < min {
                throw TransformError.valueBelowMinimum(field: fieldName, value: numValue, minimum: min)
            }
            if let max = constraints.maximum, numValue > max {
                throw TransformError.valueAboveMaximum(field: fieldName, value: numValue, maximum: max)
            }
        }

        // String constraints
        if let strValue = value as? String {
            if let minLength = constraints.minLength, strValue.count < minLength {
                throw TransformError.stringTooShort(field: fieldName, length: strValue.count, minimum: minLength)
            }
            if let maxLength = constraints.maxLength, strValue.count > maxLength {
                throw TransformError.stringTooLong(field: fieldName, length: strValue.count, maximum: maxLength)
            }
            if let pattern = constraints.pattern {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(location: 0, length: strValue.utf16.count)
                if regex.firstMatch(in: strValue, options: [], range: range) == nil {
                    throw TransformError.patternMismatch(field: fieldName, pattern: pattern)
                }
            }
            if let enumValues = constraints.enumValues, !enumValues.contains(strValue) {
                throw TransformError.valueNotInEnum(field: fieldName, value: strValue, allowed: enumValues)
            }
        }
    }
}

enum TransformError: LocalizedError {
    case typeMismatch(expected: String, got: String)
    case dateParseError(value: String)
    case requiredFieldMissing(field: String)
    case valueBelowMinimum(field: String, value: Double, minimum: Double)
    case valueAboveMaximum(field: String, value: Double, maximum: Double)
    case stringTooShort(field: String, length: Int, minimum: Int)
    case stringTooLong(field: String, length: Int, maximum: Int)
    case patternMismatch(field: String, pattern: String)
    case valueNotInEnum(field: String, value: String, allowed: [String])
    case transformFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .typeMismatch(let expected, let got):
            return "Type mismatch: expected \(expected), got \(got)"
        case .dateParseError(let value):
            return "Failed to parse date: \(value)"
        case .requiredFieldMissing(let field):
            return "Required field missing: \(field)"
        case .valueBelowMinimum(let field, let value, let minimum):
            return "Field \(field) value \(value) is below minimum \(minimum)"
        case .valueAboveMaximum(let field, let value, let maximum):
            return "Field \(field) value \(value) is above maximum \(maximum)"
        case .stringTooShort(let field, let length, let minimum):
            return "Field \(field) length \(length) is less than minimum \(minimum)"
        case .stringTooLong(let field, let length, let maximum):
            return "Field \(field) length \(length) exceeds maximum \(maximum)"
        case .patternMismatch(let field, let pattern):
            return "Field \(field) doesn't match pattern: \(pattern)"
        case .valueNotInEnum(let field, let value, let allowed):
            return "Field \(field) value '\(value)' not in allowed values: \(allowed.joined(separator: ", "))"
        case .transformFailed(let message):
            return "Transform failed: \(message)"
        }
    }
}