//
//  MainView.swift
//  cascade-ledger
//
//  Main interface for Cascade Ledger with Parse Studio
//

import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [Account]
    @Query private var institutions: [Institution]

    @State private var selectedTab = "accounts"
    @State private var selectedAccount: Account?

    // Persistent session for Parse Studio
    @StateObject private var parseStudioSession = ParseStudioSession()

    var body: some View {
        NavigationSplitView {
            // Sidebar
            List(selection: $selectedTab) {
                Section("Financial Data") {
                    Label("Accounts", systemImage: "banknote")
                        .tag("accounts")

                    Label("Parse Studio", systemImage: "doc.text.magnifyingglass")
                        .tag("parse-studio")

                    Label("Transactions", systemImage: "list.bullet.rectangle")
                        .tag("transactions")

                    Label("Timeline", systemImage: "clock.arrow.2.circlepath")
                        .tag("timeline")

                    Label("Analytics", systemImage: "chart.xyaxis.line")
                        .tag("analytics")

                    Label("Positions", systemImage: "chart.bar.doc.horizontal")
                        .tag("positions")

                    Label("Portfolio Value", systemImage: "chart.line.uptrend.xyaxis")
                        .tag("portfolio-value")

                    Label("Asset Allocation", systemImage: "chart.pie")
                        .tag("allocation")

                    Label("Allocation (Stacked)", systemImage: "chart.bar.xaxis")
                        .tag("allocation-stacked")

                    Label("Total Wealth", systemImage: "chart.bar.xaxis")
                        .tag("total-wealth")

                    Label("Balance", systemImage: "chart.bar.fill")
                        .tag("balance")
                }

                Section("Management") {
                    Label("Import History", systemImage: "clock.arrow.circlepath")
                        .tag("imports")

                    Label("Parse Plans", systemImage: "doc.badge.gearshape")
                        .tag("parse-plans")

                    Label("Background Jobs", systemImage: "gearshape.2")
                        .tag("jobs")

                    Label("Price Data", systemImage: "chart.line.uptrend.xyaxis.circle")
                        .tag("price-data")

                    Label("Settings", systemImage: "gearshape")
                        .tag("settings")
                }

                Section("Testing") {
                    Label("Double-Entry Test", systemImage: "arrow.left.arrow.right")
                        .tag("double-entry-test")

                    Label("Parse Plan Debug", systemImage: "ladybug")
                        .tag("parse-plan-debug")
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 250)
            .listStyle(.sidebar)
        } detail: {
            // Detail view based on selection
            switch selectedTab {
            case "accounts":
                AccountsView(selectedAccount: $selectedAccount)
            case "parse-studio":
                ParseStudioView(
                    selectedAccount: $selectedAccount,
                    session: parseStudioSession
                )
            case "transactions":
                TransactionsView(selectedAccount: selectedAccount)
            case "timeline":
                TransactionTimelineView(selectedAccount: selectedAccount)
            case "analytics":
                AnalyticsView(selectedAccount: selectedAccount)
            case "positions":
                PositionsView(selectedAccount: selectedAccount)
            case "portfolio-value":
                PortfolioValueView(selectedAccount: selectedAccount)
            case "allocation":
                AllocationView(selectedAccount: selectedAccount)
            case "allocation-stacked":
                AllocationStackedView(selectedAccount: selectedAccount)
            case "total-wealth":
                TotalWealthView(selectedAccount: selectedAccount)
            case "balance":
                BalanceView(selectedAccount: selectedAccount)
            case "imports":
                ImportHistoryView()
            case "parse-plans":
                ParsePlansView()
            case "jobs":
                JobsView()
            case "price-data":
                PriceDataView()
            case "settings":
                SettingsView()
            case "double-entry-test":
                DoubleEntryTestView()
            case "parse-plan-debug":
                ParsePlanDebugView()
            default:
                EmptyStateView()
            }
        }
        .navigationTitle("Cascade Ledger")
        .onAppear {
            initializeStores()
        }
    }

    private func initializeStores() {
        // Initialize stores that need the model context
        _ = AccountStore(modelContext: modelContext)

        // Configure JobManager for background job management
        JobManager.shared.configure(modelContext: modelContext)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Welcome to Cascade Ledger")
                .font(.largeTitle)

            Text("Select an option from the sidebar to get started")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainView()
        .modelContainer(for: [
            Account.self,
            Institution.self,
            ImportSession.self,
            RawFile.self,
            ParsePlan.self,
            ParsePlanVersion.self,
            Asset.self,
            Position.self,
            Transaction.self,
            JournalEntry.self
        ])
}