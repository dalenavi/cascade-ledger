//
//  main.swift
//  cascade-ledger-cli
//
//  CLI with direct model access
//

import Foundation
import SwiftData

print("Starting CLI...")

// Connect to database
let dbURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Containers/navispiral.cascade-ledger/Data/Library/Application Support/default.store")

print("Database URL: \(dbURL.path)")
print("Database exists: \(FileManager.default.fileExists(atPath: dbURL.path))")

do {
    print("Creating ModelContainer...")
    let container = try ModelContainer(
        for: Account.self, Transaction.self, JournalEntry.self,
        configurations: ModelConfiguration(url: dbURL)
    )

    print("Creating ModelContext...")
    let context = ModelContext(container)

    print("Context created successfully!")

    // Get command
    let command = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "help"

    // Execute command
    switch command {
case "accounts":
    let accounts = try! context.fetch(FetchDescriptor<Account>())
    print("\n📊 YOUR ACCOUNTS (via SwiftData):")
    print(String(repeating: "=", count: 60))
    for account in accounts {
        print("\n  • \(account.name)")
        print("    Active Transactions: \(account.activeTransactions.count)")
        print("    Sessions: \(account.categorizationSessions.count)")
        if let balance = account.balanceInstrument {
            print("    Balance Instrument: \(balance)")
        }
    }
    print()

case "tx":
    let limit = CommandLine.arguments.count >= 3 ? Int(CommandLine.arguments[2]) ?? 10 : 10

    var descriptor = FetchDescriptor<Transaction>(
        sortBy: [SortDescriptor(\.date, order: .reverse)]
    )
    descriptor.fetchLimit = limit

    let txs = try! context.fetch(descriptor)
    print("\n💰 YOUR TRANSACTIONS (via SwiftData):")
    print(String(repeating: "=", count: 60))
    for tx in txs {
        print("\n  \(tx.date.formatted(date: .numeric, time: .omitted))")
        print("  \(tx.transactionDescription)")
        print("  Type: \(tx.transactionType.rawValue)")
        print("  Balanced: \(tx.isBalanced ? "✅" : "❌") ← computed property!")
        print("  Journal Entries: \(tx.journalEntries.count) ← relationship!")

        // Show journal entries using the relationship
        for entry in tx.journalEntries.prefix(3) {
            let amt = entry.debitAmount ?? entry.creditAmount ?? 0
            let side = entry.debitAmount != nil ? "DR" : "CR"
            print("    → \(entry.accountName): $\(amt) \(side)")
        }
    }
    print()

case "unbalanced":
    let allTx = try! context.fetch(FetchDescriptor<Transaction>())
    let unbalanced = allTx.filter { !$0.isBalanced }

    print("\n⚠️ UNBALANCED TRANSACTIONS (using .isBalanced property):")
    print(String(repeating: "=", count: 60))
    print("Found: \(unbalanced.count) of \(allTx.count)")

    for tx in unbalanced.prefix(10) {
        print("\n  \(tx.date.formatted(date: .numeric, time: .omitted)): \(tx.transactionDescription)")
        print("  Debits: $\(tx.totalDebits) | Credits: $\(tx.totalCredits)")
        print("  Difference: $\(abs(tx.totalDebits - tx.totalCredits))")
    }
    print()

case "stats":
    let accountCount = try! context.fetchCount(FetchDescriptor<Account>())
    let txCount = try! context.fetchCount(FetchDescriptor<Transaction>())
    let entryCount = try! context.fetchCount(FetchDescriptor<JournalEntry>())

    print("\n📊 STATISTICS (via SwiftData):")
    print(String(repeating: "=", count: 60))
    print("\n  Accounts: \(accountCount)")
    print("  Transactions: \(txCount)")
    print("  Journal Entries: \(entryCount)")

    // Use SwiftData queries, not SQL!
    let allTx = try! context.fetch(FetchDescriptor<Transaction>())

    let byType = Dictionary(grouping: allTx, by: { $0.transactionType })
    print("\n  By Type:")
    for (type, txs) in byType.sorted(by: { $0.value.count > $1.value.count }) {
        print("    \(type.rawValue): \(txs.count)")
    }

    let unbalanced = allTx.filter { !$0.isBalanced }
    let duplicates = allTx.filter { $0.isDuplicate }

    print("\n  Data Quality:")
    print("    Unbalanced: \(unbalanced.count)")
    print("    Duplicates: \(duplicates.count)")
    print()

default:
    print("""

    Cascade CLI - Direct SwiftData Model Access

    Commands:
      accounts           List accounts
      tx [limit]         List transactions (default: 10)
      unbalanced         Find unbalanced transactions
      stats              Statistics

    Examples:
      ./cascade accounts
      ./cascade tx 20
      ./cascade unbalanced
      ./cascade stats

    Features:
      ✅ Uses SwiftData models (NOT SQL!)
      ✅ Access computed properties (.isBalanced, .netCashImpact)
      ✅ Navigate relationships (.journalEntries, .activeTransactions)
      ✅ Same models as GUI
      ✅ Changes sync automatically
    """)
    }
} catch {
    print("ERROR: Failed to initialize database: \(error)")
    print("\nPossible causes:")
    print("  • GUI app is running (database might be locked)")
    print("  • Database file doesn't exist")
    print("  • Permission issues")
    exit(1)
}
