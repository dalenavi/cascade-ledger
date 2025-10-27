//
//  ParsePlansView.swift
//  cascade-ledger
//
//  Parse plans management view
//

import SwiftUI
import SwiftData

struct ParsePlansView: View {
    @Query(sort: \ParsePlan.updatedAt, order: .reverse)
    private var parsePlans: [ParsePlan]

    @State private var selectedParsePlan: ParsePlan?
    @State private var showingNewParsePlanSheet = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedParsePlan) {
                if parsePlans.isEmpty {
                    ContentUnavailableView(
                        "No Parse Plans",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Parse plans will be created when you import data")
                    )
                } else {
                    ForEach(parsePlans) { plan in
                        ParsePlanRow(plan: plan)
                            .tag(plan)
                    }
                }
            }
            .navigationTitle("Parse Plans")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewParsePlanSheet = true }) {
                        Label("New Parse Plan", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewParsePlanSheet) {
            Text("Parse Plan Editor")
                .frame(minWidth: 600, minHeight: 400)
        }
    }
}

struct ParsePlanRow: View {
    let plan: ParsePlan

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name)
                    .font(.headline)

                HStack {
                    if let account = plan.account {
                        Label(account.name, systemImage: "banknote")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let institution = plan.institution {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(institution.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(plan.versions.count) versions")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(plan.updatedAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}