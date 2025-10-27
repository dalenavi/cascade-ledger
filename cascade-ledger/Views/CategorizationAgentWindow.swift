//
//  CategorizationAgentWindow.swift
//  cascade-ledger
//
//  Floating agent window for transaction categorization
//

import SwiftUI
import SwiftData

struct CategorizationAgentWindow: View {
    let account: Account
    @Binding var messages: [ChatMessage]
    @Binding var showingAgent: Bool

    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    var body: some View {
        VStack(spacing: 0) {
            // Header (drag handle)
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption)

                Image(systemName: "sparkles")
                    .foregroundColor(.purple)
                Text("Categorization Agent")
                    .font(.headline)

                Spacer()

                Text(ClaudeAPIService.shared.currentModel)
                    .font(.caption2)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.purple.opacity(0.2))
                    .cornerRadius(4)

                Button(action: { showingAgent = false }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Minimize to button")
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            .opacity(isDragging ? 0.8 : 1.0)

            Divider()

            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            ChatBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Status footer
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Review proposed categories inline in the transaction list")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    offset = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    offset = value.translation
                }
        )
    }
}
