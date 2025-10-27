//
//  AccountsView.swift
//  cascade-ledger
//
//  Account management interface
//

import SwiftUI
import SwiftData

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Account.name) private var accounts: [Account]
    @Query(sort: \Institution.displayName) private var institutions: [Institution]

    @Binding var selectedAccount: Account?
    @State private var showingNewAccountSheet = false
    @State private var accountToClear: Account?
    @State private var showingClearConfirmation = false

    var body: some View {
        NavigationStack {
            List(selection: $selectedAccount) {
                if accounts.isEmpty {
                    ContentUnavailableView(
                        "No Accounts",
                        systemImage: "banknote",
                        description: Text("Add your first financial account to get started")
                    )
                } else {
                    ForEach(accounts) { account in
                        AccountRowView(account: account)
                            .tag(account)
                            .contextMenu {
                                Button(role: .destructive) {
                                    accountToClear = account
                                    showingClearConfirmation = true
                                } label: {
                                    Label("Clear All Imports", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete(perform: deleteAccounts)
                }
            }
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingNewAccountSheet = true }) {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewAccountSheet) {
                NewAccountView()
            }
            .alert("Clear All Imports?", isPresented: $showingClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    if let account = accountToClear {
                        clearAllImports(for: account)
                    }
                }
            } message: {
                if let account = accountToClear {
                    Text("This will delete all import batches and \(account.importBatches.reduce(0) { $0 + $1.successfulRows }) transactions for \(account.name). Parse plans will be kept. This cannot be undone.")
                }
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        for index in offsets {
            let account = accounts[index]
            // Only delete if no imports exist
            if account.importBatches.isEmpty {
                modelContext.delete(account)
            }
        }
    }

    private func clearAllImports(for account: Account) {
        print("Clearing all imports for account: \(account.name)")
        let batchCount = account.importBatches.count
        let transactionCount = account.importBatches.reduce(0) { $0 + $1.ledgerEntries.count }

        // Delete all import batches (cascade deletes ledger entries)
        for batch in account.importBatches {
            modelContext.delete(batch)
        }

        do {
            try modelContext.save()
            print("✓ Cleared \(batchCount) import batches and \(transactionCount) transactions")
        } catch {
            print("Failed to clear imports: \(error)")
        }
    }
}

struct AccountRowView: View {
    let account: Account

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)

                if let institution = account.institution {
                    Text(institution.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(account.importBatches.count) imports")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let defaultPlan = account.defaultParsePlan {
                    Label(defaultPlan.name, systemImage: "doc.badge.gearshape")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct NewAccountView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Institution.displayName) private var institutions: [Institution]

    @State private var accountName = ""
    @State private var selectedInstitution: Institution?
    @State private var customInstitutionName = ""
    @State private var useCustomInstitution = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Account Information") {
                    TextField("Account Name", text: $accountName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Financial Institution") {
                    Toggle("Use custom institution", isOn: $useCustomInstitution)

                    if useCustomInstitution {
                        TextField("Institution Name", text: $customInstitutionName)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Picker("Institution", selection: $selectedInstitution) {
                            Text("None").tag(nil as Institution?)
                            ForEach(institutions) { institution in
                                Text(institution.displayName)
                                    .tag(institution as Institution?)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createAccount()
                    }
                    .disabled(accountName.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func createAccount() {
        var institution = selectedInstitution

        // Create custom institution if needed
        if useCustomInstitution && !customInstitutionName.isEmpty {
            let id = customInstitutionName.lowercased().replacingOccurrences(of: " ", with: "_")
            institution = Institution(id: id, displayName: customInstitutionName)
            modelContext.insert(institution!)
        }

        let account = Account(name: accountName, institution: institution)
        modelContext.insert(account)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to create account: \(error)")
        }
    }
}

#Preview {
    @Previewable @State var selectedAccount: Account? = nil
    return AccountsView(selectedAccount: $selectedAccount)
        .modelContainer(for: [Account.self, Institution.self])
}