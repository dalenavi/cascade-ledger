//
//  CommitParsePlanSheet.swift
//  cascade-ledger
//
//  Sheet for committing parse plan versions
//

import SwiftUI
import SwiftData

struct CommitParsePlanSheet: View {
    let parsePlan: ParsePlan

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var commitMessage = ""
    @State private var isCommitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Parse Plan") {
                    HStack {
                        Text("Name:")
                        Spacer()
                        Text(parsePlan.name)
                            .foregroundColor(.secondary)
                    }

                    if let workingCopy = parsePlan.workingCopy {
                        HStack {
                            Text("Fields:")
                            Spacer()
                            Text("\(workingCopy.schema.fields.count) mappings")
                                .foregroundColor(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Field Mappings:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(workingCopy.schema.fields.prefix(5), id: \.name) { field in
                                HStack {
                                    Text(field.name)
                                        .font(.caption)
                                    Image(systemName: "arrow.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text(field.mapping ?? field.name)
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }

                            if workingCopy.schema.fields.count > 5 {
                                Text("+ \(workingCopy.schema.fields.count - 5) more fields")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section("Version Information") {
                    HStack {
                        Text("Current Version:")
                        Spacer()
                        if let currentVersion = parsePlan.currentVersion {
                            Text("v\(currentVersion.versionNumber)")
                                .foregroundColor(.secondary)
                        } else {
                            Text("None (first commit)")
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("New Version:")
                        Spacer()
                        let nextVersion = (parsePlan.currentVersion?.versionNumber ?? 0) + 1
                        Text("v\(nextVersion)")
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                    }
                }

                Section("Commit Message (Optional)") {
                    TextField("Describe the changes...", text: $commitMessage, axis: .vertical)
                        .lineLimit(3...6)
                        .textFieldStyle(.roundedBorder)
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Commit Parse Plan")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isCommitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Commit") {
                        commitVersion()
                    }
                    .disabled(isCommitting)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func commitVersion() {
        isCommitting = true
        errorMessage = nil

        do {
            let message = commitMessage.isEmpty ? nil : commitMessage
            _ = parsePlan.commitVersion(message: message)
            try modelContext.save()

            dismiss()
        } catch {
            errorMessage = "Failed to commit: \(error.localizedDescription)"
            isCommitting = false
        }
    }
}
