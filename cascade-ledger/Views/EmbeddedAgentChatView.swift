//
//  EmbeddedAgentChatView.swift
//  cascade-ledger
//
//  Floating agent chat for Parse Studio
//

import SwiftUI
import SwiftData

struct DraggableFloatingChatWindow: View {
    @Binding var parsePlan: ParsePlan?
    let account: Account
    let selectedFile: RawFile?
    @Binding var messages: [ChatMessage]
    @Binding var showingChat: Bool

    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        FloatingChatWindow(
            parsePlan: $parsePlan,
            account: account,
            selectedFile: selectedFile,
            messages: $messages,
            showingChat: $showingChat,
            isDragging: $isDragging
        )
        .frame(width: 450, height: 600)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    offset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    // Keep the final position
                    offset = value.translation
                }
        )
        .padding(20)
    }
}

struct FloatingChatWindow: View {
    @Binding var parsePlan: ParsePlan?
    let account: Account
    let selectedFile: RawFile?
    @Binding var messages: [ChatMessage]
    @Binding var showingChat: Bool
    let isDragging: Binding<Bool>

    @Environment(\.modelContext) private var modelContext

    @State private var currentMessage = ""
    @State private var isProcessing = false
    @State private var streamingMessage = ""
    @State private var errorMessage: String?

    private var agentService: ParseAgentService {
        ParseAgentService(modelContext: modelContext)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header (drag handle)
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Claude Assistant")
                    .font(.headline)
                Spacer()

                if !ClaudeAPIService.shared.isConfigured {
                    Text("No API Key")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(4)
                }

                Text(ClaudeAPIService.shared.currentModel)
                    .font(.caption2)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)

                Button(action: { showingChat = false }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Minimize to button")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .opacity(isDragging.wrappedValue ? 0.8 : 1.0)

            Divider()

            // Chat messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }

                        // Streaming message in progress
                        if isProcessing && !streamingMessage.isEmpty {
                            ChatBubbleView(message: ChatMessage(
                                role: .assistant,
                                content: streamingMessage
                            ))
                        }

                        // Thinking indicator
                        if isProcessing && streamingMessage.isEmpty {
                            ThinkingIndicator()
                                .padding()
                        }

                        if let error = errorMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text("Error Details")
                                        .font(.headline)
                                        .foregroundColor(.red)
                                }

                                ScrollView {
                                    Text(error)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.red)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 200)
                            }
                            .padding()
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: streamingMessage) { _, _ in
                    withAnimation {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input field
            HStack {
                TextField("Ask Claude about your parse plan...", text: $currentMessage)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendMessage()
                    }
                    .disabled(isProcessing || !ClaudeAPIService.shared.isConfigured)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                }
                .disabled(currentMessage.isEmpty || isProcessing || !ClaudeAPIService.shared.isConfigured)
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onAppear {
            if messages.isEmpty {
                startConversation()
            }
        }
        .onChange(of: selectedFile?.id) { oldValue, newValue in
            if oldValue != newValue && newValue != nil {
                // CSV changed - notify in chat
                messages.append(ChatMessage(
                    role: .system,
                    content: """
                    🔄 **CSV file updated**

                    New file: \(selectedFile?.fileName ?? "Unknown")

                    The agent will see the new CSV context in subsequent messages.
                    You can ask Claude to analyze the new data or adjust the parse plan.
                    """
                ))
            }
        }
    }

    private func startConversation() {
        guard let file = selectedFile else { return }

        // Show the full system prompt that will be sent to Claude
        let systemPrompt = agentService.buildSystemPrompt(
            file: file,
            account: account,
            parsePlan: parsePlan
        )

        messages.append(ChatMessage(
            role: .system,
            content: """
            **System Prompt (sent to Claude):**

            ```
            \(systemPrompt)
            ```

            ---

            Automatically requesting Claude to create a parse plan...
            """
        ))

        // Automatically send request to create parse plan
        currentMessage = "Create a parse plan for this CSV file. Map all fields to appropriate ledger fields, using metadata.* for institution-specific fields that don't match canonical schema."
        sendMessage()
    }

    private func sendMessage() {
        guard !currentMessage.isEmpty else { return }
        guard let file = selectedFile else { return }

        // Check for API key
        guard ClaudeAPIService.shared.isConfigured else {
            messages.append(ChatMessage(
                role: .system,
                content: "⚠️ No API key configured. Please add your Anthropic API key to use Claude.\n\nYou can get an API key from: https://console.anthropic.com/settings/keys"
            ))
            return
        }

        // Add user message
        messages.append(ChatMessage(
            role: .user,
            content: currentMessage
        ))

        let userQuery = currentMessage
        currentMessage = ""
        isProcessing = true
        streamingMessage = ""
        errorMessage = nil

        // Call real Claude API with streaming
        Task {
            await callClaudeAPI(userQuery: userQuery, file: file)
        }
    }

    @MainActor
    private func callClaudeAPI(userQuery: String, file: RawFile) async {
        do {
            var fullResponse = ""

            // Stream response from Claude
            try await agentService.streamMessage(
                userMessage: userQuery,
                conversationHistory: messages.filter { $0.role != .system },
                file: file,
                account: account,
                parsePlan: parsePlan
            ) { chunk in
                fullResponse += chunk
                streamingMessage = fullResponse
            }

            // Add complete message
            messages.append(ChatMessage(
                role: .assistant,
                content: fullResponse
            ))

            // Try to extract and apply parse plan from response
            if let definition = agentService.extractParsePlan(from: fullResponse) {
                applyParsePlan(definition)
            }

        } catch {
            let fullErrorMessage = """
            ❌ Claude API Error

            \(error.localizedDescription)

            ---

            Debug Info:
            - Model: \(ClaudeAPIService.shared.currentModel)
            - Account: \(account.name)
            - File: \(file.fileName)
            - Message: \(userQuery.prefix(100))...

            Check the Xcode console for full request/response details.
            """

            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                role: .system,
                content: fullErrorMessage
            ))
        }

        isProcessing = false
        streamingMessage = ""
    }

    private func applyParsePlan(_ definition: ParsePlanDefinition) {
        // Create parse plan if needed
        if parsePlan == nil, let file = selectedFile {
            let plan = ParsePlan(
                name: "Parse Plan for \(file.fileName)",
                account: account
            )
            modelContext.insert(plan)
            parsePlan = plan
        }

        guard let plan = parsePlan else { return }

        // Apply the definition
        plan.workingCopy = definition

        messages.append(ChatMessage(
            role: .system,
            content: "✅ Parse plan updated with \(definition.schema.fields.count) field mappings"
        ))
    }
}

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        if message.role == .system {
            // System message - full width
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                    Text("System Context")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                }

                Text(message.content)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        } else {
            // User or assistant message
            HStack(alignment: .top, spacing: 8) {
                if message.role == .user {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                    if message.role == .assistant {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                            Text("Claude")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.purple)
                    }

                    Text(message.content)
                        .padding(10)
                        .background(
                            message.role == .user
                                ? Color.blue.opacity(0.1)
                                : Color(NSColor.controlBackgroundColor)
                        )
                        .cornerRadius(12)
                        .textSelection(.enabled)

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if message.role == .assistant {
                    Spacer(minLength: 60)
                }
            }
        }
    }
}

// Chat message model
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    let timestamp = Date()
}

enum ChatRole {
    case user
    case assistant
    case system
}

struct SystemMessageView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("System Context")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ThinkingIndicator: View {
    @State private var dotCount = 0

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 60)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption)
                    Text("Claude")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.purple)

                HStack(spacing: 4) {
                    Text("Thinking")
                        .foregroundColor(.secondary)
                    Text(String(repeating: ".", count: dotCount))
                        .frame(width: 20, alignment: .leading)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
            }

            Spacer(minLength: 60)
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            dotCount = (dotCount + 1) % 4
        }
    }
}
