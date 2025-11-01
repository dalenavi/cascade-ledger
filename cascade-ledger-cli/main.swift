//
//  main.swift
//  cascade-ledger-cli
//
//  CLI with direct model access
//

import Foundation
import SwiftData
import CryptoKit

// MARK: - CSV Parser

func parseCSV(fileURL: URL) throws -> (headers: [String], rows: [[String: String]]) {
    let content = try String(contentsOf: fileURL, encoding: .utf8)
    let lines = content.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard let headerLine = lines.first else {
        throw NSError(domain: "CSVParser", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty CSV file"])
    }

    let headers = parseLine(headerLine).map { $0.trimmingCharacters(in: .whitespaces) }

    var rows: [[String: String]] = []
    for line in lines.dropFirst() {
        let values = parseLine(line)
        var row: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            if index < values.count && !values[index].isEmpty {
                row[header] = values[index]
            }
        }
        rows.append(row)
    }

    return (headers, rows)
}

// Parse a single CSV line respecting quotes
func parseLine(_ line: String) -> [String] {
    var fields: [String] = []
    var currentField = ""
    var inQuotes = false

    for char in line {
        if char == "\"" {
            inQuotes.toggle()
        } else if char == "," && !inQuotes {
            // Only split on comma outside quotes
            fields.append(currentField.trimmingCharacters(in: .whitespaces))
            currentField = ""
        } else {
            currentField.append(char)
        }
    }

    // Add the last field
    fields.append(currentField.trimmingCharacters(in: .whitespaces))

    return fields
}

func sha256(data: Data) -> String {
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}

func parseRowNumbers(_ input: String) -> [Int] {
    var result: [Int] = []
    let parts = input.split(separator: ",")

    for part in parts {
        let trimmed = part.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("-") {
            let range = trimmed.split(separator: "-")
            if range.count == 2,
               let start = Int(range[0]),
               let end = Int(range[1]) {
                result.append(contentsOf: start...end)
            }
        } else if let num = Int(trimmed) {
            result.append(num)
        }
    }

    return result
}

// MARK: - Main

print("Starting CLI...")

// Connect to database
let dbURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Containers/navispiral.cascade-ledger/Data/Library/Application Support/default.store")

print("Database URL: \(dbURL.path)")
print("Database exists: \(FileManager.default.fileExists(atPath: dbURL.path))")

do {
    print("Creating ModelContainer...")

    let config = ModelConfiguration(url: dbURL, cloudKitDatabase: .none)

    // Use same schema as GUI to ensure compatibility
    let schema = Schema([
        Account.self,
        Institution.self,
        ParsePlan.self,
        ParsePlanVersion.self,
        RawFile.self,
        Asset.self,
        Position.self,
        ImportSession.self,
        Transaction.self,
        JournalEntry.self,
        Mapping.self,
        SourceRow.self,
        CategorizationAttempt.self,
        CategorizationPrompt.self,
        CategorizationSession.self,
        CategorizationBatch.self,
        Job.self,
        JobExecution.self,
        ImportBatch.self,
        ParseRun.self,
        AssetPrice.self,
        ViewPreferences.self
    ])

    let container = try ModelContainer(
        for: schema,
        configurations: config
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

    case "add":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade source add <file> [--mapping <name>]")
            break
        }
        let filePath = CommandLine.arguments[3]
        let fileURL = URL(fileURLWithPath: filePath)

        guard FileManager.default.fileExists(atPath: filePath) else {
            print("Error: File not found: \(filePath)")
            break
        }

        // Parse optional --mapping flag
        var mappingName: String?
        if CommandLine.arguments.count >= 6 && CommandLine.arguments[4] == "--mapping" {
            mappingName = CommandLine.arguments[5]
        }

        do {
            // Read and hash file
            let fileData = try Data(contentsOf: fileURL)
            let hash = sha256(data: fileData)

            // Check for duplicates
            let existingDesc = FetchDescriptor<RawFile>(
                predicate: #Predicate { $0.sha256Hash == hash }
            )
            if let existing = try context.fetch(existingDesc).first {
                print("⚠️  File already exists: \(existing.fileName)")
                print("  Uploaded: \(existing.uploadedAt.formatted())")
                print("  Use existing file or upload a different version")
                break
            }

            // Parse CSV
            let (headers, csvRows) = try parseCSV(fileURL: fileURL)

            // Create RawFile
            let rawFile = RawFile(
                fileName: fileURL.lastPathComponent,
                content: fileData,
                mimeType: "text/csv"
            )
            context.insert(rawFile)

            // Create SourceRows
            var globalRowNumber = 1
            if let maxGlobal = try? context.fetch(FetchDescriptor<SourceRow>(sortBy: [SortDescriptor(\.globalRowNumber, order: .reverse)])).first {
                globalRowNumber = maxGlobal.globalRowNumber + 1
            }

            print("Debug: CSV has \(headers.count) headers: \(headers.joined(separator: ", "))")

            for (index, csvRow) in csvRows.enumerated() {
                // Parse date - try common formats and field names
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yyyy"
                let dateString = csvRow["Date"] ?? csvRow["Run Date"] ?? csvRow["Settlement Date"]

                if index == 0 {
                    print("Debug: First row date fields - Date: \(csvRow["Date"] ?? "nil"), Run Date: \(csvRow["Run Date"] ?? "nil"), Settlement Date: \(csvRow["Settlement Date"] ?? "nil")")
                    print("Debug: Parsing '\(dateString ?? "nil")' → \(dateString.flatMap { dateFormatter.date(from: $0) } ?? Date())")
                }

                let date = dateString.flatMap { dateFormatter.date(from: $0) } ?? Date()

                // Create mapped data
                let mappedData = MappedRowData(
                    date: date,
                    action: csvRow["Action"] ?? csvRow["Type"] ?? "unknown",
                    symbol: csvRow["Symbol"],
                    quantity: csvRow["Quantity"].flatMap { Decimal(string: $0) },
                    amount: csvRow["Amount ($)"].flatMap { Decimal(string: $0) },
                    price: csvRow["Price ($)"].flatMap { Decimal(string: $0) },
                    description: csvRow["Description"],
                    settlementDate: nil,
                    balance: csvRow["Cash Balance ($)"].flatMap { Decimal(string: $0) }
                )

                let sourceRow = SourceRow(
                    rowNumber: index + 1,
                    globalRowNumber: globalRowNumber + index,
                    sourceFile: rawFile,
                    rawData: csvRow,
                    mappedData: mappedData
                )
                context.insert(sourceRow)
            }

            // Associate with mapping if specified
            if let mapName = mappingName {
                let mappingDesc = FetchDescriptor<Mapping>(
                    predicate: #Predicate { $0.name == mapName }
                )
                if let mapping = try? context.fetch(mappingDesc).first {
                    mapping.sourceFiles.append(rawFile)
                }
            }

            try context.save()

            print("✓ Added source file '\(fileURL.lastPathComponent)'")
            print("  Rows: \(csvRows.count)")
            print("  Hash: \(String(hash.prefix(12)))...")
            if let mapName = mappingName {
                print("  Associated with mapping: \(mapName)")
                print("  Coverage: 0/\(csvRows.count) (0.0%)")
            }

        } catch {
            print("Error: Failed to add source file: \(error)")
        }

    default:
        print("""
        Source file commands:
          source list               List all source files
          source add <file>         Add CSV file [--mapping <name>]
        """)
    }

case "rows":
    guard CommandLine.arguments.count >= 3 else {
        print("Usage: cascade rows <file> [--range START-END] [--show-transactions]")
        break
    }
    let fileName = CommandLine.arguments[2]

    // Parse optional flags
    var rangeStart = 1
    var rangeEnd: Int?
    var showTransactions = false

    var i = 3
    while i < CommandLine.arguments.count {
        if CommandLine.arguments[i] == "--range" && i + 1 < CommandLine.arguments.count {
            let rangeStr = CommandLine.arguments[i + 1]
            let parts = rangeStr.split(separator: "-")
            if parts.count == 2 {
                rangeStart = Int(parts[0]) ?? 1
                rangeEnd = Int(parts[1])
            }
            i += 2
        } else if CommandLine.arguments[i] == "--show-transactions" {
            showTransactions = true
            i += 1
        } else {
            i += 1
        }
    }

    // Find the file
    let fileDesc = FetchDescriptor<RawFile>(
        predicate: #Predicate { $0.fileName == fileName }
    )
    guard let rawFile = try? context.fetch(fileDesc).first else {
        print("Error: File '\(fileName)' not found")
        print("Use 'cascade source list' to see available files")
        break
    }

    // Get rows in range
    let allRows = rawFile.sourceRows.sorted { $0.rowNumber < $1.rowNumber }
    let endIndex = rangeEnd ?? allRows.count
    let rowsToShow = allRows.filter { $0.rowNumber >= rangeStart && $0.rowNumber <= endIndex }

    print("\n📄 ROWS from \(fileName) (rows \(rangeStart)-\(endIndex)):")
    print(String(repeating: "=", count: 80))

    for row in rowsToShow {
        // Decode raw data
        if let rawDict = try? JSONDecoder().decode([String: String].self, from: row.rawDataJSON) {
            let isMapped = !row.journalEntries.isEmpty
            let status = isMapped ? "✓" : "○"

            print("\n  \(status) Row \(row.rowNumber):")
            for (key, value) in rawDict.sorted(by: { $0.key < $1.key }) {
                print("    \(key): \(value)")
            }

            if showTransactions && !row.journalEntries.isEmpty {
                let transactions = Set(row.journalEntries.compactMap { $0.transaction })
                print("    → Mapped to \(transactions.count) transaction(s):")
                for tx in transactions {
                    print("      • \(tx.transactionDescription) (\(tx.transactionType.rawValue))")
                }
            }
        }
    }

    let totalRows = allRows.count
    let mappedRows = allRows.filter { !$0.journalEntries.isEmpty }.count
    let coverage = totalRows > 0 ? Double(mappedRows) / Double(totalRows) * 100 : 0

    print("\n" + String(repeating: "=", count: 80))
    print("Coverage: \(mappedRows)/\(totalRows) rows mapped (\(String(format: "%.1f", coverage))%)")
    print()

case "account":
    switch subcommand {
    case "list":
        let accounts = try! context.fetch(FetchDescriptor<Account>())
        print("\n📊 ACCOUNTS:")
        print(String(repeating: "=", count: 60))
        if accounts.isEmpty {
            print("  No accounts found")
        }
        for account in accounts {
            print("\n  • \(account.name)")
            if let inst = account.institution {
                print("    Institution: \(inst)")
            }
            print("    Mappings: \(account.mappings.count)")
            print("    Active Transactions: \(account.activeTransactions.count)")
            if let activeMapping = account.activeMapping {
                print("    Active Mapping: \(activeMapping.name)")
            }
        }
        print()

    case "create":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade account create <name> [--institution <name>] [--type <type>]")
            break
        }
        let name = CommandLine.arguments[3]

        var institution: String?
        var accountType: String?

        // Parse optional flags
        var i = 4
        while i < CommandLine.arguments.count - 1 {
            if CommandLine.arguments[i] == "--institution" {
                institution = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--type" {
                accountType = CommandLine.arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        let account = Account(name: name, institution: nil)
        context.insert(account)
        try! context.save()

        print("✓ Created account '\(name)'")
        if let inst = institution {
            print("  Note: Institution '\(inst)' (Institution model support coming soon)")
        }

    default:
        print("""
        Account commands:
          account list              List all accounts
          account create <name> [--institution <name>] [--type <type>]
        """)
    }

case "transaction":
    switch subcommand {
    case "create":
        // Parse required args
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade transaction create --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries> [--mapping <name>]")
            print("Entries format: \"AccountName:DR:Amount,AccountName:CR:Amount\"")
            print("Example: --entries \"Cash:DR:100.50,Revenue:CR:100.50\"")
            break
        }

        var rowNumbers: [Int] = []
        var txDate: Date?
        var description: String?
        var mappingName: String?
        var entriesSpec: String?

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--from-rows" && i + 1 < CommandLine.arguments.count {
                rowNumbers = parseRowNumbers(CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--date" && i + 1 < CommandLine.arguments.count {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yyyy"
                txDate = dateFormatter.date(from: CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--description" && i + 1 < CommandLine.arguments.count {
                description = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--entries" && i + 1 < CommandLine.arguments.count {
                entriesSpec = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--mapping" && i + 1 < CommandLine.arguments.count {
                mappingName = CommandLine.arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        guard !rowNumbers.isEmpty, let txDate = txDate, let description = description, let entriesSpec = entriesSpec else {
            print("Error: Missing required arguments")
            print("Usage: cascade transaction create --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries>")
            break
        }

        // Fetch source rows by global row number
        let rowsDesc = FetchDescriptor<SourceRow>(
            predicate: #Predicate { rowNumbers.contains($0.globalRowNumber) }
        )
        let sourceRows = try! context.fetch(rowsDesc)

        guard sourceRows.count == rowNumbers.count else {
            print("Error: Could not find all requested rows")
            print("  Requested: \(rowNumbers.count), Found: \(sourceRows.count)")
            break
        }

        // Get mapping
        guard let mapName = mappingName else {
            print("Error: --mapping is required")
            break
        }
        let mappingDesc = FetchDescriptor<Mapping>(
            predicate: #Predicate { $0.name == mapName }
        )
        guard let mapping = try? context.fetch(mappingDesc).first else {
            print("Error: Mapping '\(mapName)' not found")
            break
        }

        // Get account from mapping
        guard let account = mapping.account else {
            print("Error: Mapping has no associated account")
            break
        }

        // Parse journal entries: "Cash:DR:100,Revenue:CR:100"
        let entrySpecs = entriesSpec.split(separator: ",").map { String($0) }
        var parsedEntries: [(accountName: String, side: String, amount: Decimal)] = []

        for spec in entrySpecs {
            let parts = spec.split(separator: ":").map { String($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 3,
                  let amount = Decimal(string: parts[2]),
                  (parts[1] == "DR" || parts[1] == "CR") else {
                print("Error: Invalid entry spec '\(spec)'")
                print("Format: AccountName:DR:Amount or AccountName:CR:Amount")
                break
            }
            parsedEntries.append((accountName: parts[0], side: parts[1], amount: amount))
        }

        // Create transaction (type is optional now, default to transfer)
        let transaction = Transaction(
            date: txDate,
            description: description,
            type: .transfer,
            account: account
        )
        transaction.mapping = mapping

        // Set reported balance from last source row's balance field
        if let lastRow = sourceRows.sorted(by: { $0.rowNumber > $1.rowNumber }).first {
            transaction.csvBalance = lastRow.mappedData.balance
        }

        context.insert(transaction)

        // Create journal entries from specification
        for entry in parsedEntries {
            // Extract quantity for non-Cash assets from source rows
            var quantity: Decimal?
            var quantityUnit: String?

            if entry.accountName != "Cash" {
                // Get quantity from first source row
                if let firstRow = sourceRows.first {
                    quantity = firstRow.mappedData.quantity
                    // Use account name as unit (e.g., "shares")
                    quantityUnit = "shares"
                }
            }

            let journalEntry = JournalEntry(
                accountType: .asset,
                accountName: entry.accountName,
                debitAmount: entry.side == "DR" ? entry.amount : nil,
                creditAmount: entry.side == "CR" ? entry.amount : nil,
                quantity: quantity,
                quantityUnit: quantityUnit,
                transaction: transaction
            )
            journalEntry.sourceRows = sourceRows
            context.insert(journalEntry)
        }

        try! context.save()

        print("✓ Created transaction '\(description)'")
        print("  Date: \(txDate.formatted(date: .numeric, time: .omitted))")
        print("  Journal entries: \(parsedEntries.count)")
        for entry in parsedEntries {
            print("    \(entry.accountName): $\(entry.amount) \(entry.side)")
        }
        print("  Source rows: \(rowNumbers.sorted().map(String.init).joined(separator: ", "))")
        print("  Balanced: \(transaction.isBalanced ? "✅" : "❌")")
        if let csvBal = transaction.csvBalance {
            print("  Reported balance: $\(csvBal)")
        }

        // Calculate new coverage
        let allRows = mapping.sourceFiles.flatMap { $0.sourceRows }
        let mapped = allRows.filter { !$0.journalEntries.isEmpty }
        let coverage = allRows.count > 0 ? Double(mapped.count) / Double(allRows.count) * 100 : 0
        print("  Coverage: \(mapped.count)/\(allRows.count) (\(String(format: "%.1f", coverage))%)")

    case "list":
        var mappingName: String?
        var sourceFileName: String?

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--mapping" && i + 1 < CommandLine.arguments.count {
                mappingName = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--source-file" && i + 1 < CommandLine.arguments.count {
                sourceFileName = CommandLine.arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        var transactions: [Transaction] = []

        if let mapName = mappingName {
            let mappingDesc = FetchDescriptor<Mapping>(
                predicate: #Predicate { $0.name == mapName }
            )
            if let mapping = try? context.fetch(mappingDesc).first {
                transactions = mapping.transactions
            }
        } else if let fileName = sourceFileName {
            let fileDesc = FetchDescriptor<RawFile>(
                predicate: #Predicate { $0.fileName == fileName }
            )
            if let file = try? context.fetch(fileDesc).first {
                let rowTxs = file.sourceRows.flatMap { $0.journalEntries.compactMap { $0.transaction } }
                transactions = Array(Set(rowTxs))
            }
        } else {
            transactions = try! context.fetch(FetchDescriptor<Transaction>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            ))
        }

        print("\n💰 TRANSACTIONS:")
        print(String(repeating: "=", count: 80))
        if transactions.isEmpty {
            print("  No transactions found")
        }

        // Sort by date DESC, then by source row number ASC (earlier rows first)
        let sortedTxs = transactions.sorted(by: { tx1, tx2 in
            if tx1.date != tx2.date {
                return tx1.date > tx2.date
            }
            // Same date - sort by source row number (lower row number first)
            let rows1 = Set(tx1.journalEntries.flatMap { $0.sourceRows })
            let rows2 = Set(tx2.journalEntries.flatMap { $0.sourceRows })
            let minRow1 = rows1.map { $0.rowNumber }.min() ?? Int.max
            let minRow2 = rows2.map { $0.rowNumber }.min() ?? Int.max
            return minRow1 < minRow2
        })

        // Calculate running balance for display
        var runningBalance: Decimal = 0

        for tx in sortedTxs.reversed() { // Process chronologically for balance calculation
            // Update running balance with Cash entries
            for entry in tx.journalEntries {
                if entry.accountName == "Cash" {
                    if let debit = entry.debitAmount {
                        runningBalance += debit
                    }
                    if let credit = entry.creditAmount {
                        runningBalance -= credit
                    }
                }
            }
        }

        // Display in reverse chronological order
        runningBalance = 0
        for tx in sortedTxs.reversed() {
            // Calculate balance after this transaction
            for entry in tx.journalEntries {
                if entry.accountName == "Cash" {
                    if let debit = entry.debitAmount {
                        runningBalance += debit
                    }
                    if let credit = entry.creditAmount {
                        runningBalance -= credit
                    }
                }
            }

            print("\n  \(tx.date.formatted(date: .numeric, time: .omitted)) - \(tx.transactionDescription)")
            print("    ID: \(tx.id)")
            print("    Type: \(tx.transactionType.rawValue)")
            print("    Balanced: \(tx.isBalanced ? "✅" : "❌")")

            // Show journal entries
            print("    Journal Entries:")
            for entry in tx.journalEntries {
                let amount = entry.debitAmount ?? entry.creditAmount ?? 0
                let side = entry.debitAmount != nil ? "DR" : "CR"
                print("      \(entry.accountName): $\(amount) \(side)")
            }

            // Show source rows
            let sourceRows = Set(tx.journalEntries.flatMap { $0.sourceRows })
            if !sourceRows.isEmpty {
                let rowNums = sourceRows.map { $0.rowNumber }.sorted()
                print("    Source rows: \(rowNums.map(String.init).joined(separator: ", "))")
            }

            // Show balances
            if let csvBal = tx.csvBalance {
                print("    Reported balance: $\(csvBal)")
                print("    Derived balance:  $\(runningBalance)")
                let diff = abs(runningBalance - csvBal)
                if diff > 0.01 {
                    print("    ⚠️  Discrepancy: $\(diff)")
                }
            }
        }
        print()

    case "update":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade transaction update <id> [--link-rows <rows>] [--unlink-rows <rows>]")
            break
        }

        let txId = CommandLine.arguments[3]
        var linkRows: [Int] = []
        var unlinkRows: [Int] = []

        var i = 4
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--link-rows" && i + 1 < CommandLine.arguments.count {
                linkRows = parseRowNumbers(CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--unlink-rows" && i + 1 < CommandLine.arguments.count {
                unlinkRows = parseRowNumbers(CommandLine.arguments[i + 1])
                i += 2
            } else {
                i += 1
            }
        }

        // Find transaction by ID
        guard let txUUID = UUID(uuidString: txId) else {
            print("Error: Invalid transaction ID")
            break
        }

        let txDesc = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == txUUID }
        )
        guard let transaction = try? context.fetch(txDesc).first else {
            print("Error: Transaction not found")
            break
        }

        // Link new rows
        if !linkRows.isEmpty {
            let rowsDesc = FetchDescriptor<SourceRow>(
                predicate: #Predicate { linkRows.contains($0.globalRowNumber) }
            )
            let sourceRows = try! context.fetch(rowsDesc)

            // Add to first journal entry (simple approach)
            if let firstEntry = transaction.journalEntries.first {
                firstEntry.sourceRows.append(contentsOf: sourceRows)
            }
        }

        // Unlink rows
        if !unlinkRows.isEmpty {
            for entry in transaction.journalEntries {
                entry.sourceRows.removeAll { unlinkRows.contains($0.globalRowNumber) }
            }
        }

        try! context.save()

        print("✓ Updated transaction '\(transaction.transactionDescription)'")
        if !linkRows.isEmpty {
            print("  Linked rows: \(linkRows.sorted().map(String.init).joined(separator: ", "))")
        }
        if !unlinkRows.isEmpty {
            print("  Unlinked rows: \(unlinkRows.sorted().map(String.init).joined(separator: ", "))")
        }

        // Show updated source rows
        let sourceRows = Set(transaction.journalEntries.flatMap { $0.sourceRows })
        print("  Current source rows: \(sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", "))")

    case "show":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade transaction show <id>")
            break
        }

        let txId = CommandLine.arguments[3]
        guard let txUUID = UUID(uuidString: txId) else {
            print("Error: Invalid transaction ID")
            break
        }

        let txDesc = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.id == txUUID }
        )
        guard let transaction = try? context.fetch(txDesc).first else {
            print("Error: Transaction not found")
            break
        }

        print("\n💰 TRANSACTION DETAILS:")
        print(String(repeating: "=", count: 80))
        print("\n  ID: \(transaction.id)")
        print("  Date: \(transaction.date.formatted(date: .long, time: .omitted))")
        print("  Description: \(transaction.transactionDescription)")
        print("  Type: \(transaction.transactionType.rawValue)")
        print("  Balanced: \(transaction.isBalanced ? "✅" : "❌")")

        print("\n  Journal Entries:")
        for entry in transaction.journalEntries {
            let amount = entry.debitAmount ?? entry.creditAmount ?? 0
            let side = entry.debitAmount != nil ? "DR" : "CR"
            print("    \(entry.accountName): $\(amount) \(side)")
            if !entry.sourceRows.isEmpty {
                print("      Source rows: \(entry.sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", "))")
            }
        }

        let sourceRows = Set(transaction.journalEntries.flatMap { $0.sourceRows })
        if !sourceRows.isEmpty {
            print("\n  Source Rows (\(sourceRows.count)):")
            for row in sourceRows.sorted(by: { $0.rowNumber < $1.rowNumber }) {
                if let rawDict = try? JSONDecoder().decode([String: String].self, from: row.rawDataJSON) {
                    print("    Row \(row.rowNumber): \(rawDict["Description"] ?? "N/A")")
                }
            }
        }
        print()

    default:
        print("""
        Transaction commands:
          transaction create --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries> --mapping <name>
            Entries format: "Account:DR:Amount,Account:CR:Amount"
            Example: --entries "Cash:DR:2032.69,VS-Transfer:CR:2032.69"
          transaction list [--mapping <name>] [--source-file <file>]
          transaction update <id> [--link-rows <rows>] [--unlink-rows <rows>]
          transaction show <id>
        """)
    }

case "validate":
    // Get mapping name
    var mappingName: String?
    if CommandLine.arguments.count >= 3 && !CommandLine.arguments[2].starts(with: "--") {
        mappingName = CommandLine.arguments[2]
    } else if CommandLine.arguments.count >= 4 && CommandLine.arguments[2] == "--mapping" {
        mappingName = CommandLine.arguments[3]
    }

    // Find mapping
    var mapping: Mapping?
    if let mapName = mappingName {
        let mappingDesc = FetchDescriptor<Mapping>(
            predicate: #Predicate { $0.name == mapName }
        )
        mapping = try? context.fetch(mappingDesc).first
    } else {
        // Use first mapping if not specified
        mapping = try? context.fetch(FetchDescriptor<Mapping>()).first
    }

    guard let mapping = mapping else {
        print("Error: No mapping found")
        print("Usage: cascade validate [--mapping <name>]")
        break
    }

    print("\n🔍 VALIDATION REPORT: \(mapping.name)")
    print(String(repeating: "=", count: 80))

    // Coverage validation
    let allRows = mapping.sourceFiles.flatMap { $0.sourceRows }.sorted { $0.globalRowNumber < $1.globalRowNumber }
    let mappedRows = allRows.filter { !$0.journalEntries.isEmpty }
    let unmappedRows = allRows.filter { $0.journalEntries.isEmpty }
    let coverage = allRows.count > 0 ? Double(mappedRows.count) / Double(allRows.count) * 100 : 0

    print("\n📊 Coverage:")
    print("  Total rows: \(allRows.count)")
    print("  Mapped: \(mappedRows.count) (\(String(format: "%.1f", coverage))%)")
    print("  Unmapped: \(unmappedRows.count)")

    if !unmappedRows.isEmpty {
        print("\n  Unmapped row ranges:")
        // Group consecutive rows
        var ranges: [(Int, Int)] = []
        var currentStart = unmappedRows[0].rowNumber
        var currentEnd = currentStart

        for i in 1..<unmappedRows.count {
            if unmappedRows[i].rowNumber == currentEnd + 1 {
                currentEnd = unmappedRows[i].rowNumber
            } else {
                ranges.append((currentStart, currentEnd))
                currentStart = unmappedRows[i].rowNumber
                currentEnd = currentStart
            }
        }
        ranges.append((currentStart, currentEnd))

        for (start, end) in ranges.prefix(10) {
            if start == end {
                print("    Row \(start)")
            } else {
                print("    Rows \(start)-\(end)")
            }
        }
        if ranges.count > 10 {
            print("    ... and \(ranges.count - 10) more ranges")
        }
    }

    // Duplicate detection
    var duplicates: [(SourceRow, [Transaction])] = []
    for row in allRows {
        let txs = Set(row.journalEntries.compactMap { $0.transaction })
        if txs.count > 1 {
            duplicates.append((row, Array(txs)))
        }
    }

    if !duplicates.isEmpty {
        print("\n⚠️  Double-mapped rows:")
        for (row, txs) in duplicates.prefix(10) {
            print("  Row \(row.rowNumber) mapped to \(txs.count) transactions:")
            for tx in txs {
                print("    • \(tx.transactionDescription)")
            }
        }
    }

    // Transaction balance validation (debits = credits)
    let transactions = mapping.transactions.sorted(by: { $0.date < $1.date })
    let unbalanced = transactions.filter { !$0.isBalanced }

    print("\n⚖️  Transaction Balance (Debits = Credits):")
    print("  Total transactions: \(transactions.count)")
    print("  Balanced: \(transactions.count - unbalanced.count)")
    print("  Unbalanced: \(unbalanced.count)")

    if !unbalanced.isEmpty {
        print("\n  Unbalanced transactions:")
        for tx in unbalanced.prefix(5) {
            print("    • \(tx.transactionDescription)")
            print("      Debits: $\(tx.totalDebits) | Credits: $\(tx.totalCredits)")
            print("      Difference: $\(abs(tx.totalDebits - tx.totalCredits))")
        }
    }

    // Balance reconciliation (reported vs derived)
    print("\n💰 Balance Reconciliation (Reported vs Derived):")

    // Calculate running balance by summing Cash account entries chronologically
    var runningBalance: Decimal = 0
    var discrepancies: [(Transaction, Decimal, Decimal, Decimal)] = []

    for tx in transactions {
        // Update running balance with Cash entries (DR increases, CR decreases cash)
        for entry in tx.journalEntries {
            if entry.accountName == "Cash" {
                if let debit = entry.debitAmount {
                    runningBalance += debit
                }
                if let credit = entry.creditAmount {
                    runningBalance -= credit
                }
            }
        }

        // Compare with reported balance
        if let reportedBalance = tx.csvBalance {
            let difference = abs(runningBalance - reportedBalance)
            if difference > 0.01 { // More than 1 cent difference
                discrepancies.append((tx, reportedBalance, runningBalance, difference))
            }
        }
    }

    print("  Transactions with balance data: \(transactions.filter { $0.csvBalance != nil }.count)/\(transactions.count)")
    print("  Balance discrepancies: \(discrepancies.count)")

    if !discrepancies.isEmpty {
        print("\n  Discrepancies found:")
        for (tx, reported, derived, diff) in discrepancies.prefix(10) {
            print("    • \(tx.date.formatted(date: .numeric, time: .omitted)) - \(tx.transactionDescription)")
            print("      Reported: $\(reported) | Derived: $\(derived) | Diff: $\(diff)")
        }
    }

    // Overall status
    print("\n" + String(repeating: "=", count: 80))
    if coverage == 100 && duplicates.isEmpty && unbalanced.isEmpty && discrepancies.isEmpty {
        print("✅ VALID - Ready to activate!")
    } else {
        print("⚠️  INCOMPLETE - Address issues above before activating")
    }
    print()

case "coverage":
    // Get mapping name
    var mappingName: String?
    var detailed = false

    var i = 2
    while i < CommandLine.arguments.count {
        if CommandLine.arguments[i] == "--mapping" && i + 1 < CommandLine.arguments.count {
            mappingName = CommandLine.arguments[i + 1]
            i += 2
        } else if CommandLine.arguments[i] == "--detailed" {
            detailed = true
            i += 1
        } else if !CommandLine.arguments[i].starts(with: "--") {
            mappingName = CommandLine.arguments[i]
            i += 1
        } else {
            i += 1
        }
    }

    // Find mapping
    var mapping: Mapping?
    if let mapName = mappingName {
        let mappingDesc = FetchDescriptor<Mapping>(
            predicate: #Predicate { $0.name == mapName }
        )
        mapping = try? context.fetch(mappingDesc).first
    } else {
        mapping = try? context.fetch(FetchDescriptor<Mapping>()).first
    }

    guard let mapping = mapping else {
        print("Error: No mapping found")
        print("Usage: cascade coverage [<name>] [--mapping <name>] [--detailed]")
        break
    }

    print("\n📈 COVERAGE REPORT: \(mapping.name)")
    print(String(repeating: "=", count: 80))

    // Per-file coverage
    for file in mapping.sourceFiles {
        let allRows = file.sourceRows.sorted { $0.rowNumber < $1.rowNumber }
        let mappedRows = allRows.filter { !$0.journalEntries.isEmpty }
        let coverage = allRows.count > 0 ? Double(mappedRows.count) / Double(allRows.count) * 100 : 0

        print("\n  📁 \(file.fileName)")
        print("    Total rows: \(allRows.count)")
        print("    Mapped: \(mappedRows.count) (\(String(format: "%.1f", coverage))%)")

        if detailed {
            let unmapped = allRows.filter { $0.journalEntries.isEmpty }
            if !unmapped.isEmpty {
                print("    Unmapped: \(unmapped.map { String($0.rowNumber) }.joined(separator: ", "))")
            }
        }
    }

    // Overall stats
    let allRows = mapping.sourceFiles.flatMap { $0.sourceRows }
    let mapped = allRows.filter { !$0.journalEntries.isEmpty }
    let totalCoverage = allRows.count > 0 ? Double(mapped.count) / Double(allRows.count) * 100 : 0

    print("\n" + String(repeating: "=", count: 80))
    print("Overall: \(mapped.count)/\(allRows.count) rows mapped (\(String(format: "%.1f", totalCoverage))%)")
    print()

case "accounts":
    // Backwards compatibility - redirect to account list
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
      account create <name>           Create new account
      account list                    List accounts

      mapping list                    List all mappings
      mapping create <name>           Create new mapping
      mapping activate <name>         Activate a mapping

      source list                     List source files
      source add <file>               Add CSV file [--mapping <name>]

      rows <file>                     View source rows [--range 1-10]

      transaction create              Create transaction from rows
      transaction list                List transactions [--mapping <name>]
      transaction update <id>         Update row links [--link-rows/--unlink-rows]
      transaction show <id>           Show transaction details

      validate [<mapping>]            Validate mapping (coverage, balance, duplicates)
      coverage [<mapping>]            Show coverage report [--detailed]

      accounts                        List accounts (alias)
      tx [limit]                      List transactions (default: 10)
      unbalanced                      Find unbalanced transactions
      stats                           Statistics

    Examples:
      ./cascade account create "Fidelity" --institution "Fidelity Investments"
      ./cascade mapping create "v1" --account "Fidelity"
      ./cascade source add data.csv --mapping "v1"
      ./cascade rows data.csv --range 1-10
      ./cascade transaction create --from-rows 1,2 --type buy --description "Buy AAPL"
      ./cascade validate "v1"
      ./cascade coverage "v1" --detailed
      ./cascade rows data.csv --show-transactions

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
