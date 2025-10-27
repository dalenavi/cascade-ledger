//
//  SettingsView.swift
//  cascade-ledger
//
//  Settings for API keys and configuration
//

import SwiftUI

struct SettingsView: View {
    @State private var apiKey = ""
    @State private var showingAPIKey = false
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSuccess = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Anthropic API Key")
                            .font(.headline)

                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text("API key is stored in UserDefaults (plain text) on this device only. Keep your device secure.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)

                        HStack {
                            if showingAPIKey {
                                TextField("sk-ant-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("sk-ant-...", text: $apiKey)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button(action: { showingAPIKey.toggle() }) {
                                Image(systemName: showingAPIKey ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        HStack {
                            if hasExistingKey {
                                Button("Update Key") {
                                    saveAPIKey()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKey.isEmpty || isValidating)

                                Button("Delete Key", role: .destructive) {
                                    deleteAPIKey()
                                }
                                .buttonStyle(.bordered)
                            } else {
                                Button("Save API Key") {
                                    saveAPIKey()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(apiKey.isEmpty || isValidating)
                            }

                            if isValidating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Validating...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        if let message = validationMessage {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: validationSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(validationSuccess ? .green : .red)
                                    Text(validationSuccess ? "Success" : "Error")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                }

                                if !validationSuccess {
                                    ScrollView {
                                        Text(message)
                                            .font(.system(.caption, design: .monospaced))
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 200)
                                } else {
                                    Text(message)
                                        .font(.caption)
                                }
                            }
                            .padding(8)
                            .background((validationSuccess ? Color.green : Color.red).opacity(0.1))
                            .cornerRadius(6)
                        }

                        Link("Get API Key →", destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                            .font(.caption)
                    }
                } header: {
                    Label("Claude Integration", systemImage: "sparkles")
                }

                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        if hasExistingKey {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Not Configured", systemImage: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                    }

                    HStack {
                        Text("Model")
                        Spacer()
                        Text("claude-haiku-4-5-20250929")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("API Configuration")
                }

                Section {
                    Text("The Claude Assistant helps you:")
                    BulletPoint(text: "Create parse plans from CSV files")
                    BulletPoint(text: "Map CSV columns to ledger fields")
                    BulletPoint(text: "Fix parsing errors")
                    BulletPoint(text: "Configure field transformations")
                } header: {
                    Text("About Claude Assistant")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            loadExistingKey()
        }
    }

    private var hasExistingKey: Bool {
        KeychainService.shared.hasClaudeAPIKey()
    }

    private func loadExistingKey() {
        if let existingKey = try? KeychainService.shared.getClaudeAPIKey() {
            // Show masked version
            let prefix = String(existingKey.prefix(12))
            apiKey = "\(prefix)..."
        }
    }

    private func saveAPIKey() {
        isValidating = true
        validationMessage = nil

        Task {
            do {
                print("=== Validating API Key ===")
                print("Key prefix: \(apiKey.prefix(12))...")

                // Validate key with Claude API
                let isValid = try await ClaudeAPIService.shared.validateAPIKey(apiKey)

                if isValid {
                    try KeychainService.shared.saveClaudeAPIKey(apiKey)
                    ClaudeAPIService.shared.checkConfiguration()

                    await MainActor.run {
                        validationMessage = "API key validated successfully with model: \(ClaudeAPIService.shared.currentModel)"
                        validationSuccess = true
                    }
                } else {
                    await MainActor.run {
                        validationMessage = """
                        API key validation failed.

                        The API call succeeded but didn't return expected response.
                        Check console for details.
                        """
                        validationSuccess = false
                    }
                }
            } catch {
                print("=== API Key Validation Error ===")
                print(error)

                await MainActor.run {
                    validationMessage = error.localizedDescription
                    validationSuccess = false
                }
            }

            await MainActor.run {
                isValidating = false
            }
        }
    }

    private func deleteAPIKey() {
        do {
            try KeychainService.shared.deleteClaudeAPIKey()
            ClaudeAPIService.shared.checkConfiguration()
            apiKey = ""
            validationMessage = "API key deleted"
            validationSuccess = false
        } catch {
            validationMessage = "Error deleting key: \(error.localizedDescription)"
            validationSuccess = false
        }
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
