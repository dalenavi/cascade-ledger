//
//  DoubleEntryTestView.swift
//  cascade-ledger
//
//  Test view for double-entry bookkeeping transactions
//

import SwiftUI
import SwiftData

struct DoubleEntryTestView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @State private var selectedAccount: Account?
    @State private var showImportSheet = false
    @State private var usdBalance: Decimal = 0
    @State private var isCalculating = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Double-Entry Transactions")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Text("USD Balance: \(usdBalance.formatted())")
                    .font(.title2)
                    .foregroundColor(usdBalance >= 0 ? .green : .red)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                Button("Import CSV") {
                    showImportSheet = true
                }
                .buttonStyle(.borderedProminent)

                Button("Calculate USD") {
                    calculateUSDBalance()
                }
                .disabled(isCalculating)
            }
            .padding()

            Divider()

            // Transaction List
            if transactions.isEmpty {
                ContentUnavailableView(
                    "No Transactions",
                    systemImage: "doc.text",
                    description: Text("Import a CSV file using double-entry mode")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(transactions) { transaction in
                            TransactionCard(transaction: transaction)
                        }
                    }
                    .padding()
                }
            }
        }
        .onAppear {
            calculateUSDBalance()
        }
        .sheet(isPresented: $showImportSheet) {
            DoubleEntryImportSheet(selectedAccount: $selectedAccount)
        }
    }

    private func calculateUSDBalance() {
        isCalculating = true
        defer { isCalculating = false }

        // Calculate USD from all cash journal entries
        let cashEntries = transactions.flatMap { $0.journalEntries }
            .filter { $0.accountType == .cash && $0.accountName == "USD" }

        usdBalance = cashEntries.reduce(0) { sum, entry in
            sum + (entry.debitAmount ?? 0) - (entry.creditAmount ?? 0)
        }

        print("=== USD Balance Calculation ===")
        print("Total transactions: \(transactions.count)")
        print("Total cash entries: \(cashEntries.count)")
        print("USD Balance: \(usdBalance)")
        print("===============================")
    }
}

struct TransactionCard: View {
    let transaction: Transaction

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(transaction.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(transaction.transactionDescription)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(transaction.transactionType.rawValue.capitalized)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(typeColor.opacity(0.2))
                        .foregroundColor(typeColor)
                        .cornerRadius(4)

                    Text("Cash: \(transaction.netCashImpact.formatted())")
                        .font(.subheadline)
                        .foregroundColor(transaction.netCashImpact >= 0 ? .green : .red)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }

            // Journal Entries
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Journal Entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(transaction.journalEntries) { entry in
                        JournalEntryRow(entry: entry)
                    }

                    // Balance Check
                    HStack {
                        Text("Balance Check")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        if transaction.isBalanced {
                            Label("Balanced", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Label("Unbalanced", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(.top, 4)

                    HStack {
                        Text("Debits: \(transaction.totalDebits.formatted())")
                            .font(.caption)
                        Spacer()
                        Text("Credits: \(transaction.totalCredits.formatted())")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.leading, 16)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }

    private var typeColor: Color {
        switch transaction.transactionType {
        case .buy: return .blue
        case .sell: return .orange
        case .dividend: return .green
        case .transfer: return .purple
        case .fee: return .red
        default: return .gray
        }
    }
}

struct JournalEntryRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack {
            // Account
            HStack(spacing: 4) {
                Image(systemName: entry.accountType.systemImage)
                    .font(.caption)
                    .foregroundColor(entry.accountType.color)

                Text(entry.accountName)
                    .font(.system(.body, design: .monospaced))
            }
            .frame(minWidth: 150, alignment: .leading)

            Spacer()

            // Quantity (if applicable)
            if let qty = entry.quantity {
                Text("\(qty.formatted()) \(entry.quantityUnit ?? "")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 80, alignment: .trailing)
            }

            // Debit
            if let debit = entry.debitAmount {
                Text(debit.formatted())
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(minWidth: 100, alignment: .trailing)
            } else {
                Text("")
                    .frame(minWidth: 100)
            }

            // Credit
            if let credit = entry.creditAmount {
                Text(credit.formatted())
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.orange)
                    .frame(minWidth: 100, alignment: .trailing)
            } else {
                Text("")
                    .frame(minWidth: 100)
            }
        }
        .font(.footnote)
    }
}

struct DoubleEntryImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAccount: Account?
    @Query(sort: \ImportBatch.createdAt, order: .reverse) private var allImportBatches: [ImportBatch]
    @State private var selectedImportBatch: ImportBatch?
    @State private var isImporting = false
    @State private var errorMessage: String?

    var accountImportBatches: [ImportBatch] {
        guard let account = selectedAccount else { return [] }
        return allImportBatches.filter { $0.account?.id == account.id }
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Re-process with Double-Entry")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Select an existing import to re-process using double-entry bookkeeping")
                .foregroundColor(.secondary)

            // Account Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Step 1: Select Account")
                    .font(.headline)

                Picker("Account", selection: $selectedAccount) {
                    Text("Select Account").tag(nil as Account?)
                    ForEach(allImportBatches.compactMap(\.account).unique()) { account in
                        Text(account.name).tag(account as Account?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 400)
                .onChange(of: selectedAccount) { oldValue, newValue in
                    selectedImportBatch = nil  // Reset import batch when account changes
                }
            }

            // Import Batch Selection
            if selectedAccount != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Step 2: Select Import Batch (\(accountImportBatches.count) available)")
                        .font(.headline)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(accountImportBatches) { batch in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(batch.batchName ?? batch.rawFile?.fileName ?? "Unnamed Import")
                                            .font(.system(.body, design: .monospaced))
                                        HStack {
                                            Text("\(batch.totalRows) rows")
                                            Text("•")
                                            Text(batch.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            if batch.parsePlanVersion != nil {
                                                Text("•")
                                                Label("Has Parse Plan", systemImage: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundColor(.green)
                                                    .labelStyle(.iconOnly)
                                            }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if selectedImportBatch?.id == batch.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                                .padding(8)
                                .background(selectedImportBatch?.id == batch.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                .cornerRadius(4)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedImportBatch = batch
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                }
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Re-process with Double-Entry") {
                    Task {
                        await importWithDoubleEntry()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedImportBatch == nil || isImporting)
            }

            if isImporting {
                ProgressView("Processing...")
                    .progressViewStyle(.linear)
            }
        }
        .padding(40)
        .frame(minWidth: 600, minHeight: 500)
    }

    private func importWithDoubleEntry() async {
        guard let selectedBatch = selectedImportBatch,
              let account = selectedAccount else {
            errorMessage = "Please select an import batch"
            return
        }

        isImporting = true
        errorMessage = nil

        do {
            // Get the parse plan - first try the one used for this import batch
            let parsePlanVersion: ParsePlanVersion?

            if let batchPlanVersion = selectedBatch.parsePlanVersion {
                // Use the parse plan that was used for this import
                parsePlanVersion = batchPlanVersion
                print("Using parse plan from import batch: \(batchPlanVersion.id)")
            } else {
                // For older imports without parsePlanVersion, try to find any parse plan for this account
                print("Import batch has no parse plan stored, looking for alternatives...")

                // First try the account's default parse plan
                if let defaultPlanVersion = account.defaultParsePlan?.currentVersion {
                    parsePlanVersion = defaultPlanVersion
                    print("Using account's default parse plan: \(defaultPlanVersion.id)")
                } else {
                    // Last resort: Find ANY parse plan for this account
                    let accountId = account.id
                    let descriptor = FetchDescriptor<ParsePlan>(
                        predicate: #Predicate<ParsePlan> { plan in
                            plan.account?.id == accountId
                        }
                    )

                    if let anyPlan = try? modelContext.fetch(descriptor).first,
                       let currentVersion = anyPlan.currentVersion {
                        parsePlanVersion = currentVersion
                        print("Using first available parse plan for account: \(currentVersion.id)")
                    } else {
                        errorMessage = "No parse plan found. Please create one in Parse Studio for this account first."
                        isImporting = false
                        return
                    }
                }
            }

            guard let planVersion = parsePlanVersion else {
                errorMessage = "Unable to locate parse plan for this import."
                isImporting = false
                return
            }

            // Use ParseEngineV2 for double-entry import
            let engine = ParseEngineV2(modelContext: modelContext)
            let (transactions, parseRun) = try await engine.importWithDoubleEntry(
                importBatch: selectedBatch,
                parsePlanVersion: planVersion
            )

            print("Successfully imported \(transactions.count) transactions")
            isImporting = false
            dismiss()

        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
            isImporting = false
        }
    }
}

// Helper extension to get unique accounts
extension Array where Element == Account {
    func unique() -> [Account] {
        var seen = Set<UUID>()
        return filter { account in
            guard !seen.contains(account.id) else { return false }
            seen.insert(account.id)
            return true
        }
    }
}

#Preview {
    DoubleEntryTestView()
        .modelContainer(for: [
            Transaction.self,
            JournalEntry.self,
            Account.self,
            ImportBatch.self,
            ParsePlan.self,
            ParsePlanVersion.self
        ])
}