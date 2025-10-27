//
//  ParseAgentService.swift
//  cascade-ledger
//
//  Parse agent that uses Claude to help create parse plans
//

import Foundation
import SwiftData
import Combine

@MainActor
class ParseAgentService: ObservableObject {
    private let claudeAPI = ClaudeAPIService.shared
    private let modelContext: ModelContext

    @Published var tokenUsage: (input: Int, output: Int) = (0, 0)

    // Cache for tool use
    private var currentRawFile: RawFile?
    private var currentPreview: ParsePreview?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Tool Definitions

    private func getTools() -> [ClaudeTool] {
        return [
            ClaudeTool(
                name: "get_csv_data",
                description: "Retrieve CSV input data with pagination. Returns rows in pages of 100.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "page": [
                            "type": "integer",
                            "description": "Page number (0-indexed). Each page contains 100 rows."
                        ],
                        "start_row": [
                            "type": "integer",
                            "description": "Optional: Specific starting row (overrides page)"
                        ],
                        "count": [
                            "type": "integer",
                            "description": "Optional: Number of rows to return (max 100)"
                        ]
                    ],
                    "required": ["page"]
                ]
            ),
            ClaudeTool(
                name: "get_transformed_data",
                description: "Retrieve transformed output data after parse plan is applied. Shows how the CSV data looks after transformation.",
                inputSchema: [
                    "type": "object",
                    "properties": [
                        "page": [
                            "type": "integer",
                            "description": "Page number (0-indexed). Each page contains 20 transformed rows."
                        ],
                        "include_errors": [
                            "type": "boolean",
                            "description": "If true, only return rows with transformation errors"
                        ]
                    ],
                    "required": ["page"]
                ]
            )
        ]
    }

    // MARK: - Tool Execution

    func executeToolCall(_ toolName: String, input: [String: Any], file: RawFile, preview: ParsePreview?) -> String {
        currentRawFile = file
        currentPreview = preview

        switch toolName {
        case "get_csv_data":
            return executeGetCSVData(input: input, file: file)
        case "get_transformed_data":
            return executeGetTransformedData(input: input, preview: preview)
        default:
            return "{\"error\": \"Unknown tool: \(toolName)\"}"
        }
    }

    private func executeGetCSVData(input: [String: Any], file: RawFile) -> String {
        let page = input["page"] as? Int ?? 0
        let count = input["count"] as? Int ?? 100
        let startRow = input["start_row"] as? Int ?? (page * 100)

        let csvParser = CSVParser()
        guard let csvContent = String(data: file.content, encoding: .utf8),
              let csvData = try? csvParser.parse(csvContent) else {
            return "{\"error\": \"Failed to parse CSV\"}"
        }

        let endRow = min(startRow + count, csvData.rowCount)
        let rows = Array(csvData.rows[startRow..<endRow])

        let result = rows.map { row in
            Dictionary(uniqueKeysWithValues: zip(csvData.headers, row))
        }

        let jsonData = try? JSONSerialization.data(withJSONObject: [
            "page": page,
            "start_row": startRow,
            "end_row": endRow,
            "total_rows": csvData.rowCount,
            "headers": csvData.headers,
            "rows": result
        ], options: .prettyPrinted)

        return String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
    }

    private func executeGetTransformedData(input: [String: Any], preview: ParsePreview?) -> String {
        guard let preview = preview else {
            return "{\"error\": \"No transformed data available. Create a parse plan first.\"}"
        }

        let page = input["page"] as? Int ?? 0
        let includeErrors = input["include_errors"] as? Bool ?? false
        let pageSize = 20

        let filteredRows = includeErrors
            ? preview.transformedRows.filter { !$0.isValid }
            : preview.transformedRows

        let startIndex = page * pageSize
        let endIndex = min(startIndex + pageSize, filteredRows.count)

        guard startIndex < filteredRows.count else {
            return "{\"total_rows\": \(filteredRows.count), \"page\": \(page), \"rows\": []}"
        }

        let pageRows = Array(filteredRows[startIndex..<endIndex])

        let result = pageRows.map { row in
            [
                "row_number": row.rowNumber,
                "is_valid": row.isValid,
                "transformed_data": row.transformedData,
                "validation_errors": row.validationResults.filter { !$0.passed }.map { $0.message ?? "" }
            ] as [String: Any]
        }

        let jsonData = try? JSONSerialization.data(withJSONObject: [
            "page": page,
            "page_size": pageSize,
            "start_index": startIndex,
            "end_index": endIndex,
            "total_rows": filteredRows.count,
            "success_rate": preview.successRate,
            "rows": result
        ], options: .prettyPrinted)

        return String(data: jsonData ?? Data(), encoding: .utf8) ?? "{}"
    }

    // MARK: - System Prompt Generation

    func buildSystemPrompt(
        file: RawFile,
        account: Account,
        parsePlan: ParsePlan?
    ) -> String {
        let csvParser = CSVParser()
        let csvData = try? csvParser.parsePreview(
            String(data: file.content, encoding: .utf8) ?? "",
            limit: 10
        )

        let headers = csvData?.headers ?? []
        let sampleRows = csvData?.rows.prefix(5).map { row in
            Dictionary(uniqueKeysWithValues: zip(headers, row))
        } ?? []

        let sampleDataJSON = (try? JSONSerialization.data(
            withJSONObject: sampleRows,
            options: .prettyPrinted
        )).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let currentParsePlan = parsePlan?.workingCopy.flatMap { definition in
            (try? JSONSerialization.data(
                withJSONObject: [
                    "fields": definition.schema.fields.map { field in
                        [
                            "name": field.name,
                            "type": field.type.rawValue,
                            "mapping": field.mapping ?? field.name
                        ]
                    }
                ],
                options: .prettyPrinted
            )).flatMap { String(data: $0, encoding: .utf8) }
        } ?? "No parse plan yet"

        return """
        You are a financial data parsing assistant helping users import CSV data into their Cascade Ledger.

        # CONTEXT

        **File:** \(file.fileName)
        **Account:** \(account.name)
        **Institution:** \(account.institution?.displayName ?? "None")

        **CSV Structure:**
        Headers: \(headers.joined(separator: ", "))
        Total Rows: ~\(csvData?.rowCount ?? 0)

        **Sample Data (first 5 rows):**
        ```json
        \(sampleDataJSON)
        ```

        **Current Parse Plan:**
        ```json
        \(currentParsePlan)
        ```

        # PARSE PLAN SYSTEM

        Parse plans use **Frictionless Data** standards to define how CSV data transforms into ledger entries.

        **Required Components:**
        1. **Field Mappings** - Map CSV columns to canonical ledger fields
        2. **Data Types** - Specify how to interpret each field
        3. **Transformations** (optional) - JSONata expressions for complex mappings
        4. **Validations** (optional) - Rules to ensure data quality

        **Available Data Types:**
        - `date` - Transaction date (supports various formats)
        - `currency` - Monetary amounts (Decimal precision)
        - `string` - Text fields
        - `number` - Numeric values
        - `integer` - Whole numbers

        **Canonical Ledger Fields (map here when possible):**
        - `date` (required) - Transaction date
        - `amount` (required) - Transaction amount in USD
        - `quantity` - Number of units (100 shares, 0.5 BTC) for buy/sell transactions
        - `transactionDescription` (required) - Description text
        - `transactionType` - Type: debit, credit, buy, sell, transfer, dividend, interest, fee, tax
        - `assetId` - Asset identifier (SPY, VOO, FBTC, BTC, ETH, etc.)
        - `category` - Transaction category
        - `subcategory` - Subcategory

        **Metadata Fields (for institution-specific data):**
        For fields that don't match canonical schema, use metadata mapping:
        - Format: `metadata.{fieldname}` (e.g., `metadata.lot_id`, `metadata.confirmation_number`)
        - All metadata preserved as key-value pairs
        - Useful for: broker references, exchange rates, lot IDs, CUSIP numbers, etc.
        - Example: Map "Confirmation #" → `metadata.confirmation_number`

        # RESPONSE FORMAT

        When creating or modifying a parse plan, respond with JSON wrapped in a code block:

        ```json
        {
          "action": "create_parse_plan",
          "explanation": "Brief explanation of your changes",
          "fields": [
            {
              "name": "Date",
              "type": "date",
              "mapping": "date",
              "format": "MM/dd/yyyy"
            },
            {
              "name": "Amount",
              "type": "currency",
              "mapping": "amount"
            },
            {
              "name": "Description",
              "type": "string",
              "mapping": "transactionDescription"
            },
            {
              "name": "Type",
              "type": "string",
              "mapping": "transactionType"
            }
          ]
        }
        ```

        For questions or explanations, respond naturally without JSON.

        # GUIDELINES

        - Map as many fields as possible to canonical fields
        - Detect date formats from sample data
        - Identify amount fields (look for currency symbols, decimals)
        - Find description fields (memo, description, details, etc.)
        - Determine transaction types from context
        - Explain your reasoning for non-obvious mappings
        - Warn about ambiguous or missing required fields
        """
    }

    // MARK: - Agent Interaction

    func sendMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        file: RawFile,
        account: Account,
        parsePlan: ParsePlan?
    ) async throws -> String {
        let systemPrompt = buildSystemPrompt(
            file: file,
            account: account,
            parsePlan: parsePlan
        )

        // Convert chat history to Claude messages
        var claudeMessages: [ClaudeMessage] = []

        for message in conversationHistory {
            if message.role == .user {
                claudeMessages.append(ClaudeMessage(role: "user", content: message.content))
            } else if message.role == .assistant {
                claudeMessages.append(ClaudeMessage(role: "assistant", content: message.content))
            }
            // Skip system messages - they're just UI context
        }

        // Add new user message
        claudeMessages.append(ClaudeMessage(role: "user", content: userMessage))

        // Call Claude API
        let response = try await claudeAPI.sendMessage(
            messages: claudeMessages,
            system: systemPrompt,
            maxTokens: 4096,
            temperature: 0.3
        )

        // Update token usage
        tokenUsage = (response.usage.inputTokens, response.usage.outputTokens)

        return response.content.first?.text ?? ""
    }

    func streamMessage(
        userMessage: String,
        conversationHistory: [ChatMessage],
        file: RawFile,
        account: Account,
        parsePlan: ParsePlan?,
        onChunk: @escaping (String) -> Void
    ) async throws {
        let systemPrompt = buildSystemPrompt(
            file: file,
            account: account,
            parsePlan: parsePlan
        )

        // Convert chat history
        var claudeMessages: [ClaudeMessage] = []
        for message in conversationHistory where message.role != .system {
            let role = message.role == .user ? "user" : "assistant"
            claudeMessages.append(ClaudeMessage(role: role, content: message.content))
        }

        claudeMessages.append(ClaudeMessage(role: "user", content: userMessage))

        // Stream from Claude
        try await claudeAPI.streamMessage(
            messages: claudeMessages,
            system: systemPrompt,
            onChunk: onChunk
        )
    }

    // MARK: - Parse Plan Extraction

    func extractParsePlan(from response: String) -> ParsePlanDefinition? {
        // Look for JSON code blocks
        let pattern = "```json\\s*(.+?)\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(location: 0, length: response.utf16.count)) else {
            return nil
        }

        let jsonRange = match.range(at: 1)
        let jsonString = (response as NSString).substring(with: jsonRange)

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let action = json["action"] as? String,
              action == "create_parse_plan",
              let fieldsArray = json["fields"] as? [[String: Any]] else {
            return nil
        }

        // Build parse plan definition
        var definition = ParsePlanDefinition()
        var fields: [Field] = []

        for fieldDict in fieldsArray {
            guard let name = fieldDict["name"] as? String,
                  let typeString = fieldDict["type"] as? String,
                  let type = FieldType(rawValue: typeString) else {
                continue
            }

            let mapping = fieldDict["mapping"] as? String
            let format = fieldDict["format"] as? String

            let field = Field(
                name: name,
                type: type,
                format: format,
                constraints: nil,
                mapping: mapping
            )
            fields.append(field)
        }

        definition.schema.fields = fields
        return definition
    }
}
