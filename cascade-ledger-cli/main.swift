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
        for: Account.self, Transaction.self, JournalEntry.self, Mapping.self, RawFile.self, SourceRow.self,
        configurations: ModelConfiguration(url: dbURL)
    )

    print("Creating ModelContext...")
    let context = ModelContext(container)

    print("Context created successfully!")

    // Get command
    let command = CommandLine.arguments.count >= 2 ? CommandLine.arguments[1] : "help"
    let subcommand = CommandLine.arguments.count >= 3 ? CommandLine.arguments[2] : ""

    // Execute command
    switch command {
case "mapping":
    switch subcommand {
    case "list":
        let mappings = try! context.fetch(FetchDescriptor<Mapping>())
        print("\n🗂️  MAPPINGS:")
        print(String(repeating: "=", count: 60))
        if mappings.isEmpty {
            print("  No mappings found")
        }
        for mapping in mappings {
            let active = mapping.account?.activeMappingId == mapping.id ? " ⭐" : ""
            print("\n  • \(mapping.name)\(active)")
            print("    Status: \(mapping.status.rawValue)")
            print("    Account: \(mapping.account?.name ?? "none")")
            print("    Transactions: \(mapping.transactions.count)")
        }
        print()

    case "create":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade mapping create <name> [--account <account-name>]")
            break
        }
        let name = CommandLine.arguments[3]
        let mapping = Mapping(name: name)

        // Check for --account flag
        if CommandLine.arguments.count >= 6 && CommandLine.arguments[4] == "--account" {
            let accountName = CommandLine.arguments[5]
            let accountDesc = FetchDescriptor<Account>(
                predicate: #Predicate { $0.name.contains(accountName) }
            )
            if let account = try? context.fetch(accountDesc).first {
                mapping.account = account
            }
        }

        context.insert(mapping)
        try! context.save()
        print("✓ Created mapping '\(name)'")

    case "activate":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade mapping activate <name>")
            break
        }
        let name = CommandLine.arguments[3]
        let mappingDesc = FetchDescriptor<Mapping>(
            predicate: #Predicate { $0.name == name }
        )
        if let mapping = try? context.fetch(mappingDesc).first,
           let account = mapping.account {
            account.activateMapping(mapping)
            try! context.save()
            print("✓ Activated mapping '\(name)' for account '\(account.name)'")
        } else {
            print("Error: Mapping '\(name)' not found or has no account")
        }

    default:
        print("""
        Mapping commands:
          mapping list              List all mappings
          mapping create <name> [--account <name>]
          mapping activate <name>   Activate a mapping
        """)
    }

case "source":
    switch subcommand {
    case "list":
        let files = try! context.fetch(FetchDescriptor<RawFile>(sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]))
        print("\n📁 SOURCE FILES:")
        print(String(repeating: "=", count: 60))
        if files.isEmpty {
            print("  No source files found")
        }
        for file in files {
            print("\n  • \(file.fileName)")
            print("    Size: \(file.fileSize) bytes")
            print("    Rows: \(file.sourceRows.count)")
            print("    Hash: \(String(file.sha256Hash.prefix(12)))...")
            print("    Uploaded: \(file.uploadedAt.formatted(date: .numeric, time: .shortened))")
        }
        print()

    default:
        print("""
        Source file commands:
          source list               List all source files
        """)
    }

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
      mapping list                    List all mappings
      mapping create <name>           Create new mapping
      mapping activate <name>         Activate a mapping

      source list                     List source files

      accounts                        List accounts
      tx [limit]                      List transactions (default: 10)
      unbalanced                      Find unbalanced transactions
      stats                           Statistics

    Examples:
      ./cascade mapping list
      ./cascade mapping create "v2" --account "Fidelity"
      ./cascade mapping activate "v2"
      ./cascade accounts
      ./cascade tx 20

    Features:
      ✅ Uses SwiftData models (NOT SQL!)
      ✅ Access computed properties (.isBalanced, .netCashImpact)
      ✅ Navigate relationships (.journalEntries, .activeTransactions)
      ✅ Mapping system for versioned interpretations
      ✅ Same models as GUI - changes sync automatically
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
