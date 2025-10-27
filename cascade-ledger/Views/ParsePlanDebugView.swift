//
//  ParsePlanDebugView.swift
//  cascade-ledger
//
//  Debug view to inspect parse plan structure
//

import SwiftUI
import SwiftData

struct ParsePlanDebugView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var parsePlans: [ParsePlan]
    @State private var selectedPlan: ParsePlan?

    var body: some View {
        VStack(spacing: 20) {
            Text("Parse Plan Debugger")
                .font(.largeTitle)
                .fontWeight(.bold)

            Picker("Select Parse Plan", selection: $selectedPlan) {
                Text("Select Plan").tag(nil as ParsePlan?)
                ForEach(parsePlans) { plan in
                    Text("\(plan.account?.name ?? "No Account") - \(plan.currentVersion?.versionNumber ?? 0)").tag(plan as ParsePlan?)
                }
            }
            .pickerStyle(.menu)

            if let plan = selectedPlan,
               let version = plan.currentVersion {
                let definition = version.definition

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Field Mappings
                        GroupBox("Field Mappings") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(definition.schema.fields.enumerated()), id: \.offset) { index, field in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(field.name)
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundColor(.blue)
                                            if let mapping = field.mapping {
                                                Text("→ \(mapping)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .frame(width: 250, alignment: .leading)

                                        Spacer()

                                        Text(field.type.rawValue)
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.2))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            .padding()
                        }

                        // Transforms
                        if !definition.transforms.isEmpty {
                            GroupBox("Transforms") {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(definition.transforms) { transform in
                                        VStack(alignment: .leading) {
                                            Text(transform.name)
                                                .font(.headline)
                                            Text("Type: \(transform.type.rawValue)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            if let target = transform.targetField {
                                                Text("Target: \(target)")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                                .padding()
                            }
                        }

                        // Raw JSON
                        GroupBox("Raw JSON") {
                            ScrollView(.horizontal) {
                                Text(formatJSON(definition))
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding()
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Parse Plan Selected",
                    systemImage: "doc.badge.gearshape",
                    description: Text("Select a parse plan to inspect its configuration")
                )
            }
        }
        .padding()
    }

    private func formatJSON(_ definition: ParsePlanDefinition) -> String {
        if let data = try? JSONEncoder().encode(definition),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        return "Unable to format JSON"
    }
}

#Preview {
    ParsePlanDebugView()
        .modelContainer(for: [ParsePlan.self, ParsePlanVersion.self, Account.self])
}