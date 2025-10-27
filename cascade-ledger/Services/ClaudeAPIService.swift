//
//  ClaudeAPIService.swift
//  cascade-ledger
//
//  Claude API client for agent integration
//

import Foundation
import Combine

@MainActor
class ClaudeAPIService: ObservableObject {
    static let shared = ClaudeAPIService()

    private let apiEndpoint = "https://api.anthropic.com/v1/messages"
    private let model = "claude-haiku-4-5"
    private let apiVersion = "2023-06-01"

    nonisolated var currentModel: String {
        model
    }

    @Published var isConfigured = false
    @Published var lastError: Error?

    private init() {
        checkConfiguration()
    }

    func checkConfiguration() {
        isConfigured = KeychainService.shared.hasClaudeAPIKey()
    }

    // MARK: - API Key Validation

    func validateAPIKey(_ key: String) async throws -> Bool {
        let request = ClaudeRequest(
            model: model,
            maxTokens: 100,
            messages: [
                ClaudeMessage(role: "user", content: "Reply with 'ok' if you can read this.")
            ]
        )

        let response = try await sendRequest(request, apiKey: key)
        return response.content.first?.text?.contains("ok") ?? false
    }

    // MARK: - Message API

    func sendMessage(
        messages: [ClaudeMessage],
        system: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double = 0.3,
        stream: Bool = false
    ) async throws -> ClaudeResponse {
        guard let apiKey = try KeychainService.shared.getClaudeAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        let request = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: messages,
            stream: stream
        )

        return try await sendRequest(request, apiKey: apiKey)
    }

    func streamMessage(
        messages: [ClaudeMessage],
        system: String? = nil,
        maxTokens: Int = 4096,
        temperature: Double = 0.3,
        onChunk: @escaping (String) -> Void
    ) async throws {
        guard let apiKey = try KeychainService.shared.getClaudeAPIKey() else {
            throw ClaudeAPIError.noAPIKey
        }

        let request = ClaudeRequest(
            model: model,
            maxTokens: maxTokens,
            temperature: temperature,
            system: system,
            messages: messages,
            stream: true
        )

        try await streamRequest(request, apiKey: apiKey, onChunk: onChunk)
    }

    // MARK: - Private Helpers

    private func sendRequest(_ request: ClaudeRequest, apiKey: String) async throws -> ClaudeResponse {
        guard let url = URL(string: apiEndpoint) else {
            throw ClaudeAPIError.invalidURL(apiEndpoint)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        // Log request for debugging
        if let requestBody = String(data: urlRequest.httpBody ?? Data(), encoding: .utf8) {
            print("=== Claude API Request ===")
            print("URL: \(apiEndpoint)")
            print("Model: \(request.model)")
            print("Body preview: \(requestBody.prefix(500))")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            // Enhance network errors with hostname
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                throw ClaudeAPIError.networkError(
                    hostname: url.host ?? "api.anthropic.com",
                    details: error.localizedDescription
                )
            }
            throw error
        }

        // Log response for debugging
        let responseBody = String(data: data, encoding: .utf8) ?? "[Binary data]"
        print("=== Claude API Response ===")
        print("Status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
        print("Body: \(responseBody)")

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(
                responseType: String(describing: type(of: response)),
                responseBody: responseBody
            )
        }

        guard httpResponse.statusCode == 200 else {
            // Try to decode error response
            if let errorResponse = try? JSONDecoder().decode(ClaudeErrorResponse.self, from: data) {
                throw ClaudeAPIError.apiError(errorResponse.error.message)
            }

            // Provide more context for common errors
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw ClaudeAPIError.httpError(
                statusCode: httpResponse.statusCode,
                body: responseBody,
                hostname: url.host ?? "api.anthropic.com"
            )
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(ClaudeResponse.self, from: data)
        } catch {
            // Provide detailed decoding error
            let responseBody = String(data: data, encoding: .utf8) ?? "Unable to decode response body"
            throw ClaudeAPIError.decodingError(
                details: error.localizedDescription,
                responseBody: responseBody
            )
        }
    }

    private func streamRequest(
        _ request: ClaudeRequest,
        apiKey: String,
        onChunk: @escaping (String) -> Void
    ) async throws {
        guard let url = URL(string: apiEndpoint) else {
            throw ClaudeAPIError.invalidURL(apiEndpoint)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse(
                responseType: String(describing: type(of: response)),
                responseBody: "Streaming response - cannot capture body"
            )
        }

        guard httpResponse.statusCode == 200 else {
            throw ClaudeAPIError.httpError(
                statusCode: httpResponse.statusCode,
                body: "Streaming response - check console logs",
                hostname: url.host ?? "api.anthropic.com"
            )
        }

        // Parse SSE stream
        var buffer = ""
        for try await byte in asyncBytes {
            let char = Character(UnicodeScalar(byte))
            buffer.append(char)

            if buffer.hasSuffix("\n\n") {
                // Process SSE event
                if let text = parseSSEEvent(buffer) {
                    onChunk(text)
                }
                buffer = ""
            }
        }
    }

    private func parseSSEEvent(_ event: String) -> String? {
        let lines = event.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                guard jsonString != "[DONE]",
                      let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let delta = json["delta"] as? [String: Any],
                      let text = delta["text"] as? String else {
                    continue
                }
                return text
            }
        }
        return nil
    }
}

// MARK: - Request/Response Models

struct ClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let temperature: Double?
    let system: String?
    let messages: [ClaudeMessage]
    let stream: Bool?
    let tools: [ClaudeTool]?

    init(
        model: String,
        maxTokens: Int,
        temperature: Double? = nil,
        system: String? = nil,
        messages: [ClaudeMessage],
        stream: Bool? = nil,
        tools: [ClaudeTool]? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.system = system
        self.messages = messages
        self.stream = stream
        self.tools = tools
    }
}

struct ClaudeMessage: Codable {
    let role: String
    let content: String
}

struct ClaudeTool: Codable {
    let name: String
    let description: String
    let inputSchema: [String: Any]

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        // Encode inputSchema manually
        let jsonData = try JSONSerialization.data(withJSONObject: inputSchema)
        let jsonObject = try JSONSerialization.jsonObject(with: jsonData)
        try container.encode(AnyCodable(jsonObject), forKey: .inputSchema)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        let anyCodable = try container.decode(AnyCodable.self, forKey: .inputSchema)
        inputSchema = anyCodable.value as? [String: Any] ?? [:]
    }

    init(name: String, description: String, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let arrayVal as [Any]:
            try container.encode(arrayVal.map { AnyCodable($0) })
        case let dictVal as [String: Any]:
            try container.encode(dictVal.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

struct ClaudeResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ClaudeContent]
    let model: String
    let stopReason: String?
    let usage: ClaudeUsage
}

struct ClaudeContent: Codable {
    let type: String
    let text: String?
    let id: String?
    let name: String?
    let input: [String: Any]?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        text = try? container.decode(String.self, forKey: .text)
        id = try? container.decode(String.self, forKey: .id)
        name = try? container.decode(String.self, forKey: .name)

        if let inputData = try? container.decode(AnyCodable.self, forKey: .input) {
            input = inputData.value as? [String: Any]
        } else {
            input = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        if let input = input {
            try container.encode(AnyCodable(input), forKey: .input)
        }
    }
}

struct ClaudeUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
}

struct ClaudeErrorResponse: Codable {
    let error: ClaudeError
}

struct ClaudeError: Codable {
    let type: String
    let message: String
}

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidURL(String)
    case invalidResponse(responseType: String, responseBody: String)
    case networkError(hostname: String, details: String)
    case httpError(statusCode: Int, body: String, hostname: String)
    case apiError(String)
    case decodingError(details: String, responseBody: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your Anthropic API key in Settings."
        case .invalidURL(let url):
            return "Invalid API URL: \(url)"
        case .invalidResponse(let responseType, let responseBody):
            return """
            Invalid response from Claude API

            Expected: HTTPURLResponse
            Got: \(responseType)

            Response Body:
            \(responseBody)

            This indicates a fundamental protocol error.
            """
        case .networkError(let hostname, let details):
            return "Network error connecting to \(hostname):\n\n\(details)\n\nCheck your internet connection or firewall settings."
        case .httpError(let statusCode, let body, let hostname):
            return "HTTP \(statusCode) error from \(hostname)\n\nFull Response:\n\(body)"
        case .apiError(let message):
            return "Claude API error: \(message)"
        case .decodingError(let details, let responseBody):
            return """
            Failed to decode Claude API response.

            Decoding Error:
            \(details)

            Full Response Body:
            \(responseBody)

            This usually means:
            - API returned unexpected format
            - Model name might be incorrect (check console for model used)
            - API version mismatch
            - Response structure changed
            """
        }
    }
}
