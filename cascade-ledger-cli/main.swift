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
    var content = try String(contentsOf: fileURL, encoding: .utf8)

    // Remove UTF-8 BOM if present
    if content.hasPrefix("\u{FEFF}") {
        content.removeFirst()
    }

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

// MARK: - JSON Batch Structures

struct BatchTransactionInput: Codable {
    let fromRows: [Int]
    let date: String  // MM/DD/YYYY format
    let description: String
    let entries: [BatchEntryInput]
    let category: String?
}

struct BatchEntryInput: Codable {
    let account: String
    let side: String  // "DR" or "CR"
    let amount: String  // Will parse to Decimal
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
        // Check for --all flag
        let showArchived = CommandLine.arguments.contains("--all")

        let descriptor = FetchDescriptor<RawFile>(
            predicate: showArchived ? nil : #Predicate { !$0.isArchived },
            sortBy: [SortDescriptor(\.uploadedAt, order: .reverse)]
        )
        let files = try! context.fetch(descriptor)

        print("\n📁 SOURCE FILES:")
        print(String(repeating: "=", count: 60))
        if files.isEmpty {
            print("  No source files found")
            if !showArchived {
                print("  Use --all flag to show archived files")
            }
        }
        for file in files {
            let archived = file.isArchived ? " [ARCHIVED]" : ""
            print("\n  • \(file.fileName)\(archived)")
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

    case "archive":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade source archive <filename>")
            break
        }
        let fileName = CommandLine.arguments[3]

        // Find file by name
        let descriptor = FetchDescriptor<RawFile>(
            predicate: #Predicate { $0.fileName == fileName }
        )

        guard let file = try? context.fetch(descriptor).first else {
            print("Error: Source file '\(fileName)' not found")
            print("Use 'cascade source list' to see available files")
            break
        }

        print("Archiving source file: \(file.fileName)")
        print("  Rows: \(file.sourceRows.count)")
        print("  Size: \(file.fileSize) bytes")

        file.isArchived = true
        try! context.save()

        print("✓ Source file archived (will be hidden from list)")

    case "unarchive":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade source unarchive <filename>")
            break
        }
        let fileName = CommandLine.arguments[3]

        // Find file by name (including archived)
        let descriptor = FetchDescriptor<RawFile>(
            predicate: #Predicate { $0.fileName == fileName }
        )

        guard let file = try? context.fetch(descriptor).first else {
            print("Error: Source file '\(fileName)' not found")
            break
        }

        file.isArchived = false
        try! context.save()

        print("✓ Source file unarchived")

    default:
        print("""
        Source file commands:
          source list [--all]          List source files (--all shows archived)
          source add <file>            Add CSV file [--mapping <name>]
          source archive <filename>    Archive a source file
          source unarchive <filename>  Unarchive a source file
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
            print("Usage: cascade transaction create --from-file <file> --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries> [--mapping <name>] [--category <path>] [--quantity <amount>]")
            print("File format: Name of source file (e.g., \"file.csv\")")
            print("Rows format: Single number, comma-separated, or ranges (e.g., \"1\", \"1,2,3\", \"1-5\")")
            print("Entries format: \"AccountName:DR:Amount,AccountName:CR:Amount\"")
            print("Category format: \"primary/secondary/tertiary\" (e.g., \"investment/equity/tech\")")
            print("Quantity: Optional quantity for asset purchases (e.g., --quantity \"0.00181432\" for BTC)")
            print("")
            print("Examples:")
            print("  cascade transaction create --from-file \"cashapp.csv\" --from-rows 245 --date \"10/14/2025\" --description \"BTC Buy\" --entries \"BTC:DR:196.51,Cash:CR:196.51\" --mapping \"cashapp-2025\" --category \"investment/crypto\" --quantity \"0.00171\"")
            break
        }

        var sourceFileName: String?
        var rowNumbers: [Int] = []
        var txDate: Date?
        var description: String?
        var mappingName: String?
        var entriesSpec: String?
        var category: String?
        var explicitQuantity: Decimal?

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--from-file" && i + 1 < CommandLine.arguments.count {
                sourceFileName = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--from-rows" && i + 1 < CommandLine.arguments.count {
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
            } else if CommandLine.arguments[i] == "--category" && i + 1 < CommandLine.arguments.count {
                category = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--quantity" && i + 1 < CommandLine.arguments.count {
                explicitQuantity = Decimal(string: CommandLine.arguments[i + 1])
                i += 2
            } else {
                i += 1
            }
        }

        guard !rowNumbers.isEmpty, let txDate = txDate, let description = description, let entriesSpec = entriesSpec else {
            print("Error: Missing required arguments")
            print("Usage: cascade transaction create --from-file <file> --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries>")
            break
        }

        // Fetch source rows by file name + row number (NEW - globalRowNumber deprecated)
        var sourceRows: [SourceRow] = []

        if let fileName = sourceFileName {
            // New method: Query by fileName + rowNumber
            // First find the RawFile
            let fileDesc = FetchDescriptor<RawFile>(
                predicate: #Predicate { $0.fileName == fileName }
            )
            guard let rawFile = try? context.fetch(fileDesc).first else {
                print("Error: File '\(fileName)' not found")
                print("Use 'cascade source list' to see available files")
                break
            }

            // Fetch rows by file + row numbers
            let fileId = rawFile.id
            for rowNum in rowNumbers {
                let rowDesc = FetchDescriptor<SourceRow>(
                    predicate: #Predicate<SourceRow> { row in
                        row.rowNumber == rowNum
                    }
                )
                if let row = (try? context.fetch(rowDesc))?.first(where: { $0.sourceFile.id == fileId }) {
                    sourceRows.append(row)
                }
            }

            guard sourceRows.count == rowNumbers.count else {
                print("Error: Could not find all requested rows in file '\(fileName)'")
                print("  Requested: \(rowNumbers.sorted())")
                print("  Found: \(sourceRows.count) rows")
                let found = sourceRows.map { $0.rowNumber }.sorted()
                print("  Found rows: \(found)")
                break
            }
        } else {
            // Legacy fallback: Use globalRowNumber (DEPRECATED)
            print("Warning: Using deprecated globalRowNumber lookup")
            print("Please use --from-file parameter: --from-file \"filename.csv\" --from-rows 1,2,3")

            let rowsDesc = FetchDescriptor<SourceRow>(
                predicate: #Predicate { rowNumbers.contains($0.globalRowNumber) }
            )
            sourceRows = try! context.fetch(rowsDesc)

            guard sourceRows.count == rowNumbers.count else {
                print("Error: Could not find all requested rows")
                print("  Requested: \(rowNumbers.count), Found: \(sourceRows.count)")
                break
            }
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
        transaction.userCategory = category  // Set hierarchical category

        // Set reported balance from last source row's balance field
        if let lastRow = sourceRows.sorted(by: { $0.rowNumber > $1.rowNumber }).first {
            transaction.csvBalance = lastRow.mappedData.balance
        }

        context.insert(transaction)

        // Determine primary asset for quantity tracking
        // Primary asset is the first debit entry that's a security (not Cash, not Fee/Expense)
        let primaryAssetName = parsedEntries.first { entry in
            entry.side == "DR" &&
            entry.accountName != "Cash" &&
            !entry.accountName.contains("Fee") &&
            !entry.accountName.contains("Purchase") &&
            !entry.accountName.contains("Payment") &&
            !entry.accountName.contains("Expense")
        }?.accountName

        // Create journal entries from specification
        for entry in parsedEntries {
            // Infer account type from account name patterns
            let accountName = entry.accountName
            let accountType: AccountType
            var quantity: Decimal?
            var quantityUnit: String?
            var asset: Asset?

            // Determine account type based on name patterns
            if accountName == "Cash" {
                accountType = .cash
            } else if accountName.contains("Payroll") || accountName.contains("Dividend") || accountName.contains("Income") || accountName.contains("Wire-Transfer") || accountName.contains("Bank-Transfer") || accountName.contains("P2P-Income") || accountName.contains("Check-Deposit") {
                accountType = .income
            } else if accountName.contains("Fee") || accountName.contains("Interest") || accountName.contains("Purchase") || accountName.contains("Payment") || accountName.contains("Expense") || accountName.contains("Card-") || accountName.contains("Merchant-") || accountName.contains("Venmo") || accountName.contains("EFT") || accountName.contains("Discover") {
                accountType = .expense
            } else if accountName.contains("Transfer") || accountName.contains("VS-") {
                accountType = .equity  // Transfers are equity movements
            } else {
                accountType = .asset  // Securities: BTC, SPY, QQQ, NVDA, FXAIX, etc.
            }

            // Handle quantity ONLY for the primary asset (not fees, not cash, not expenses)
            if accountType == .asset && accountName == primaryAssetName {
                // Use explicit quantity if provided (for crypto/securities)
                if let explicitQty = explicitQuantity {
                    quantity = explicitQty
                    quantityUnit = "shares"
                } else {
                    // Get quantity from first source row
                    if let firstRow = sourceRows.first {
                        // Don't use dollar amount as quantity
                        if let qty = firstRow.mappedData.quantity, qty < 1000 {
                            // Likely actual share count (< 1000)
                            quantity = qty
                            quantityUnit = "shares"
                        }
                    }
                }

                // Create or fetch Asset record for securities
                // Only if we have a valid quantity
                if let qty = quantity, qty > 0 {
                    let assetDesc = FetchDescriptor<Asset>(
                        predicate: #Predicate { $0.symbol == accountName }
                    )
                    if let existingAsset = try? context.fetch(assetDesc).first {
                        asset = existingAsset
                    } else {
                        let newAsset = Asset(symbol: accountName, name: accountName)
                        context.insert(newAsset)
                        asset = newAsset
                    }
                }
            }

            let journalEntry = JournalEntry(
                accountType: accountType,
                accountName: accountName,
                debitAmount: entry.side == "DR" ? entry.amount : nil,
                creditAmount: entry.side == "CR" ? entry.amount : nil,
                quantity: quantity,
                quantityUnit: quantityUnit,
                transaction: transaction
            )
            journalEntry.asset = asset
            journalEntry.sourceRows = sourceRows
            context.insert(journalEntry)
        }

        try! context.save()

        print("✓ Created transaction '\(description)'")
        print("  Date: \(txDate.formatted(date: .numeric, time: .omitted))")
        if let cat = category {
            print("  Category: \(cat)")
        }
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
            print("       cascade transaction update <id> --update-entry <account> --quantity <qty> [--debit <amt>] [--credit <amt>]")
            print("")
            print("Examples:")
            print("  cascade transaction update ABC123... --link-rows 5,6")
            print("  cascade transaction update ABC123... --update-entry FXAIX --quantity -10.11 --credit 1915.54")
            break
        }

        let txId = CommandLine.arguments[3]
        var linkRows: [Int] = []
        var unlinkRows: [Int] = []
        var updateEntryAccount: String?
        var updateQuantity: Decimal?
        var updateDebit: Decimal?
        var updateCredit: Decimal?

        var i = 4
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--link-rows" && i + 1 < CommandLine.arguments.count {
                linkRows = parseRowNumbers(CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--unlink-rows" && i + 1 < CommandLine.arguments.count {
                unlinkRows = parseRowNumbers(CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--update-entry" && i + 1 < CommandLine.arguments.count {
                updateEntryAccount = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--quantity" && i + 1 < CommandLine.arguments.count {
                updateQuantity = Decimal(string: CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--debit" && i + 1 < CommandLine.arguments.count {
                updateDebit = Decimal(string: CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--credit" && i + 1 < CommandLine.arguments.count {
                updateCredit = Decimal(string: CommandLine.arguments[i + 1])
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

        // Update journal entry fields
        if let accountName = updateEntryAccount {
            // Find the journal entry matching this account
            guard let entry = transaction.journalEntries.first(where: { $0.accountName == accountName }) else {
                print("Error: No journal entry found for account '\(accountName)'")
                print("Available accounts: \(transaction.journalEntries.map { $0.accountName }.joined(separator: ", "))")
                break
            }

            var updated = false

            // Update quantity
            if let qty = updateQuantity {
                entry.quantity = qty
                entry.quantityUnit = "shares"
                updated = true
                print("✓ Updated quantity for \(accountName): \(qty)")
            }

            // Update debit amount
            if let debit = updateDebit {
                entry.debitAmount = debit
                entry.creditAmount = nil  // Clear credit when setting debit
                updated = true
                print("✓ Updated debit for \(accountName): $\(debit)")
            }

            // Update credit amount
            if let credit = updateCredit {
                entry.creditAmount = credit
                entry.debitAmount = nil  // Clear debit when setting credit
                updated = true
                print("✓ Updated credit for \(accountName): $\(credit)")
            }

            if !updated {
                print("Warning: No updates specified for entry '\(accountName)'")
                print("Use --quantity, --debit, or --credit flags")
            }
        }

        try! context.save()

        print("\n✓ Updated transaction '\(transaction.transactionDescription)'")
        if !linkRows.isEmpty {
            print("  Linked rows: \(linkRows.sorted().map(String.init).joined(separator: ", "))")
        }
        if !unlinkRows.isEmpty {
            print("  Unlinked rows: \(unlinkRows.sorted().map(String.init).joined(separator: ", "))")
        }

        // Show updated source rows
        let sourceRows = Set(transaction.journalEntries.flatMap { $0.sourceRows })
        if !sourceRows.isEmpty {
            print("  Current source rows: \(sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", "))")
        }

        // Show updated journal entries
        if updateEntryAccount != nil {
            print("\n  Updated Journal Entries:")
            for entry in transaction.journalEntries {
                let amt = entry.debitAmount ?? entry.creditAmount ?? 0
                let side = entry.debitAmount != nil ? "DR" : "CR"
                let qtyStr = entry.quantity.map { "\($0) shares " } ?? ""
                print("    \(entry.accountName): \(qtyStr)$\(amt) \(side)")
            }
            print("\n  Balanced: \(transaction.isBalanced ? "✅" : "❌")")
        }

    case "categorize":
        guard CommandLine.arguments.count >= 5 else {
            print("Usage: cascade transaction categorize <id> <category>")
            print("Example: cascade transaction categorize ABC123... investment/equity/tech")
            break
        }

        let txId = CommandLine.arguments[3]
        let category = CommandLine.arguments[4]

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

        transaction.userCategory = category
        try! context.save()

        print("✓ Categorized transaction")
        print("  \(transaction.date.formatted(date: .numeric, time: .omitted)) - \(transaction.transactionDescription)")
        print("  Category: \(category)")

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

    case "delete":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade transaction delete <id> [--yes]")
            print("")
            print("Deletes a transaction and all its journal entries.")
            print("Source row links are removed but source rows are preserved.")
            print("")
            print("Use --yes to skip confirmation.")
            break
        }

        let txId = CommandLine.arguments[3]
        let skipConfirm = CommandLine.arguments.contains("--yes")

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

        // Show what will be deleted
        print("\n⚠️  DELETE TRANSACTION:")
        print("  Date: \(transaction.date.formatted(date: .numeric, time: .omitted))")
        print("  Description: \(transaction.transactionDescription)")
        print("  Amount: $\(transaction.totalDebits)")
        print("  Journal Entries: \(transaction.journalEntries.count)")

        let sourceRows = Set(transaction.journalEntries.flatMap { $0.sourceRows })
        if !sourceRows.isEmpty {
            print("  Source Rows: \(sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", "))")
        }

        // Confirm
        if !skipConfirm {
            print("\nType 'yes' to confirm deletion:")
            guard let input = readLine(), input.lowercased() == "yes" else {
                print("Cancelled")
                break
            }
        }

        // Delete transaction (cascade deletes journal entries)
        context.delete(transaction)
        try! context.save()

        print("\n✓ Transaction deleted")
        if !sourceRows.isEmpty {
            print("  Source rows \(sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", ")) are now unmapped")
        }

    case "batch-create":
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade transaction batch-create --input <file.json> --mapping <name> [--dry-run] [--continue-on-error]")
            break
        }

        var inputFile: String?
        var mappingName: String?
        var dryRun = false
        var continueOnError = false

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--input" && i + 1 < CommandLine.arguments.count {
                inputFile = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--mapping" && i + 1 < CommandLine.arguments.count {
                mappingName = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--dry-run" {
                dryRun = true
                i += 1
            } else if CommandLine.arguments[i] == "--continue-on-error" {
                continueOnError = true
                i += 1
            } else {
                i += 1
            }
        }

        guard let inputFile = inputFile, let mapName = mappingName else {
            print("Error: --input and --mapping are required")
            break
        }

        // Read and parse JSON
        guard let jsonData = try? Data(contentsOf: URL(fileURLWithPath: inputFile)) else {
            print("Error: Could not read file: \(inputFile)")
            break
        }

        let decoder = JSONDecoder()
        guard let batchInput = try? decoder.decode([BatchTransactionInput].self, from: jsonData) else {
            print("Error: Invalid JSON format")
            print("Expected: Array of {fromRows, date, description, entries, category}")
            break
        }

        print("Processing batch: \(batchInput.count) transactions...")
        if dryRun {
            print("DRY RUN - No changes will be saved")
        }
        print("")

        // Get mapping
        let mappingDesc = FetchDescriptor<Mapping>(
            predicate: #Predicate { $0.name == mapName }
        )
        guard let mapping = try? context.fetch(mappingDesc).first else {
            print("Error: Mapping '\(mapName)' not found")
            break
        }

        guard let account = mapping.account else {
            print("Error: Mapping has no account")
            break
        }

        // Process each transaction
        var succeeded = 0
        var failed = 0
        var errors: [(Int, String)] = []
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd/yyyy"

        for (index, txInput) in batchInput.enumerated() {
            // Validate and create transaction
            guard let txDate = dateFormatter.date(from: txInput.date) else {
                let error = "Row \(txInput.fromRows.first ?? 0): Invalid date format '\(txInput.date)'"
                errors.append((index, error))
                if !continueOnError {
                    print("❌ \(error)")
                    break
                }
                failed += 1
                continue
            }

            // Parse and validate entries
            var parsedEntries: [(accountName: String, side: String, amount: Decimal)] = []
            var totalDR: Decimal = 0
            var totalCR: Decimal = 0
            var hasError = false

            for entry in txInput.entries {
                guard let amount = Decimal(string: entry.amount) else {
                    let error = "Row \(txInput.fromRows.first ?? 0): Invalid amount '\(entry.amount)'"
                    errors.append((index, error))
                    hasError = true
                    break
                }

                guard entry.side == "DR" || entry.side == "CR" else {
                    let error = "Row \(txInput.fromRows.first ?? 0): Invalid side '\(entry.side)' (must be DR or CR)"
                    errors.append((index, error))
                    hasError = true
                    break
                }

                parsedEntries.append((accountName: entry.account, side: entry.side, amount: amount))

                if entry.side == "DR" {
                    totalDR += amount
                } else {
                    totalCR += amount
                }
            }

            if hasError {
                if !continueOnError {
                    print("❌ Validation failed")
                    break
                }
                failed += 1
                continue
            }

            // Check balance
            if abs(totalDR - totalCR) > 0.01 {
                let error = "Row \(txInput.fromRows.first ?? 0): Unbalanced (DR: $\(totalDR), CR: $\(totalCR))"
                errors.append((index, error))
                if !continueOnError {
                    print("❌ \(error)")
                    break
                }
                failed += 1
                continue
            }

            // Fetch source rows
            let rowNumbers = txInput.fromRows
            let rowsDesc = FetchDescriptor<SourceRow>(
                predicate: #Predicate { rowNumbers.contains($0.globalRowNumber) }
            )
            let sourceRows = try! context.fetch(rowsDesc)

            if sourceRows.count != rowNumbers.count {
                let error = "Row \(txInput.fromRows.first ?? 0): Could not find all source rows"
                errors.append((index, error))
                if !continueOnError {
                    print("❌ \(error)")
                    break
                }
                failed += 1
                continue
            }

            if !dryRun {
                // Create transaction
                let transaction = Transaction(
                    date: txDate,
                    description: txInput.description,
                    type: .transfer,
                    account: account
                )
                transaction.mapping = mapping
                transaction.userCategory = txInput.category

                if let lastRow = sourceRows.sorted(by: { $0.rowNumber > $1.rowNumber }).first {
                    transaction.csvBalance = lastRow.mappedData.balance
                }

                context.insert(transaction)

                // Create journal entries
                for entry in parsedEntries {
                    var quantity: Decimal?
                    var quantityUnit: String?
                    var asset: Asset?

                    if entry.accountName != "Cash" {
                        if let firstRow = sourceRows.first {
                            quantity = firstRow.mappedData.quantity
                            quantityUnit = "shares"
                        }

                        if let qty = quantity, qty > 0 {
                            let symbolToFind = entry.accountName
                            let assetDesc = FetchDescriptor<Asset>(
                                predicate: #Predicate { $0.symbol == symbolToFind }
                            )
                            if let existingAsset = try? context.fetch(assetDesc).first {
                                asset = existingAsset
                            } else {
                                let excludePatterns = ["Dividend", "Transfer", "Payroll", "Wire", "Check", "Venmo", "EFT", "Margin", "Expense", "Interest"]
                                let shouldCreateAsset = !excludePatterns.contains { symbolToFind.contains($0) }

                                if shouldCreateAsset {
                                    let newAsset = Asset(symbol: symbolToFind, name: symbolToFind)
                                    context.insert(newAsset)
                                    asset = newAsset
                                }
                            }
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
                    journalEntry.asset = asset
                    journalEntry.sourceRows = sourceRows
                    context.insert(journalEntry)
                }
            }

            print("✓ Row \(txInput.fromRows.map(String.init).joined(separator: ",")): \(txInput.description)")
            succeeded += 1
        }

        if !dryRun {
            try! context.save()
        }

        print("")
        print("Summary:")
        print("  Succeeded: \(succeeded)/\(batchInput.count)")
        if failed > 0 {
            print("  Failed: \(failed)")
            print("")
            print("Failed transactions:")
            for (_, error) in errors {
                print("  • \(error)")
            }
        }

    default:
        print("""
        Transaction commands:
          transaction create --from-rows <rows> --date <MM/dd/yyyy> --description <desc> --entries <entries> --mapping <name>
            Entries format: "Account:DR:Amount,Account:CR:Amount"
            Example: --entries "Cash:DR:2032.69,VS-Transfer:CR:2032.69"
          transaction batch-create --input <file.json> --mapping <name> [--dry-run] [--continue-on-error]
          transaction list [--mapping <name>] [--source-file <file>]
          transaction update <id> [--link-rows <rows>] [--unlink-rows <rows>]
          transaction update <id> --update-entry <account> --quantity <qty> [--debit <amt>] [--credit <amt>]
          transaction delete <id> [--yes]
          transaction show <id>
          transaction categorize <id> <category>
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

    // Duplicate transaction detection
    let transactions = mapping.transactions.sorted(by: { $0.date < $1.date })
    var potentialDuplicates: [(Transaction, [Transaction])] = []

    for (index, tx) in transactions.enumerated() {
        // Find transactions with same date and similar description/amount
        let candidates = transactions[(index + 1)...].filter { other in
            // Same date
            guard Calendar.current.isDate(tx.date, inSameDayAs: other.date) else { return false }

            // Same description
            guard tx.transactionDescription == other.transactionDescription else { return false }

            // Same total amount (within 1 cent)
            let txTotal = tx.totalDebits
            let otherTotal = other.totalDebits
            guard abs(txTotal - otherTotal) < 0.01 else { return false }

            return true
        }

        if !candidates.isEmpty {
            potentialDuplicates.append((tx, Array(candidates)))
        }
    }

    if !potentialDuplicates.isEmpty {
        print("\n🔄 Potential Duplicate Transactions:")
        print("  Found \(potentialDuplicates.count) sets of potential duplicates")
        for (original, dups) in potentialDuplicates {
            print("\n  • \(original.date.formatted(date: .numeric, time: .omitted)) - \(original.transactionDescription) ($\(original.totalDebits))")
            print("    Original ID: \(original.id)")
            for dup in dups {
                print("    Duplicate ID: \(dup.id)")
            }
            // Show source rows for comparison
            let origRows = Set(original.journalEntries.flatMap { $0.sourceRows }).map { $0.rowNumber }.sorted()
            let dupRows = Set(dups.first!.journalEntries.flatMap { $0.sourceRows }).map { $0.rowNumber }.sorted()
            print("    Source rows: \(origRows) vs \(dupRows)")
        }
    }

    // Transaction balance validation (debits = credits)
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

    // Category coverage
    let categorized = transactions.filter { $0.userCategory != nil }
    let uncategorized = transactions.filter { $0.userCategory == nil }

    print("\n🏷️  Category Coverage:")
    print("  Categorized: \(categorized.count)/\(transactions.count) (\(transactions.count > 0 ? String(format: "%.1f", Double(categorized.count) / Double(transactions.count) * 100) : "0")%)")
    print("  Uncategorized: \(uncategorized.count)")

    if !uncategorized.isEmpty && uncategorized.count <= 10 {
        print("\n  Uncategorized transactions:")
        for tx in uncategorized.prefix(10) {
            print("    • \(tx.date.formatted(date: .numeric, time: .omitted)) - \(tx.transactionDescription)")
        }
    }

    if !discrepancies.isEmpty {
        print("\n  Discrepancies found:")
        for (tx, reported, derived, diff) in discrepancies.prefix(10) {
            print("    • \(tx.date.formatted(date: .numeric, time: .omitted)) - \(tx.transactionDescription)")
            print("      Reported: $\(reported) | Derived: $\(derived) | Diff: $\(diff)")
        }
    }

    // Overall status
    print("\n" + String(repeating: "=", count: 80))
    let hasIssues = coverage < 100 || !duplicates.isEmpty || !potentialDuplicates.isEmpty || !unbalanced.isEmpty || !discrepancies.isEmpty

    if !hasIssues {
        print("✅ VALID - Ready to activate!")
    } else {
        print("⚠️  ISSUES FOUND:")
        if coverage < 100 {
            print("  • \(unmappedRows.count) unmapped rows")
        }
        if !duplicates.isEmpty {
            print("  • \(duplicates.count) double-mapped rows")
        }
        if !potentialDuplicates.isEmpty {
            print("  • \(potentialDuplicates.count) sets of duplicate transactions")
        }
        if !unbalanced.isEmpty {
            print("  • \(unbalanced.count) unbalanced transactions")
        }
        if !discrepancies.isEmpty {
            print("  • \(discrepancies.count) balance discrepancies")
        }
        print("\n  Review and resolve before activating")
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

case "reset":
    // Reset command now only supports mapping-specific reset
    guard CommandLine.arguments.count >= 4 else {
        print("Usage: cascade reset mapping <mapping-name> [--force]")
        print("")
        print("Delete a specific mapping and all its transactions.")
        print("Use --force to skip confirmation prompt.")
        print("")
        print("Example: cascade reset mapping cashapp-2025")
        break
    }

    let subcommand = CommandLine.arguments[2]
    guard subcommand == "mapping" else {
        print("Error: Only 'mapping' reset is supported")
        print("Usage: cascade reset mapping <mapping-name> [--force]")
        break
    }

    let mappingName = CommandLine.arguments[3]
    let hasForceFlag = CommandLine.arguments.contains("--force")

    // Find the mapping
    let mappingDesc = FetchDescriptor<Mapping>(
        predicate: #Predicate { $0.name == mappingName }
    )
    guard let mapping = try? context.fetch(mappingDesc).first else {
        print("Error: Mapping '\(mappingName)' not found")
        print("Use 'cascade mapping list' to see available mappings")
        break
    }

    // Check if it's active
    if let account = mapping.account, account.activeMappingId == mapping.id {
        print("Error: Cannot delete active mapping '\(mappingName)'")
        print("Deactivate it first or activate a different mapping")
        break
    }

    // Show what will be deleted
    let txCount = mapping.transactions.count
    let sourceFileCount = mapping.sourceFiles.count
    let accountName = mapping.account?.name ?? "none"

    print("\n⚠️  Delete mapping '\(mappingName)'?")
    print("   Account: \(accountName)")
    print("   Transactions: \(txCount)")
    print("   Source files: \(sourceFileCount)")
    print("")

    // Confirm unless --force
    if !hasForceFlag {
        print("Type 'yes' to confirm: ", terminator: "")
        guard let response = readLine()?.lowercased(), response == "yes" else {
            print("Cancelled")
            break
        }
    }

    // Delete the mapping (cascade delete handles transactions)
    context.delete(mapping)
    try! context.save()

    print("✓ Deleted mapping '\(mappingName)'")
    print("  Removed \(txCount) transactions")
    print("  Source files remain in database for reuse")

case "price":
    let subcommand = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "help"

    switch subcommand {
    case "fetch":
        // Parse arguments
        var assetSymbol: String?
        var fromDate: Date?
        var toDate: Date = Date()

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--asset" && i + 1 < CommandLine.arguments.count {
                assetSymbol = CommandLine.arguments[i + 1]
                i += 2
            } else if CommandLine.arguments[i] == "--from" && i + 1 < CommandLine.arguments.count {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yyyy"
                fromDate = dateFormatter.date(from: CommandLine.arguments[i + 1])
                i += 2
            } else if CommandLine.arguments[i] == "--to" && i + 1 < CommandLine.arguments.count {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "MM/dd/yyyy"
                toDate = dateFormatter.date(from: CommandLine.arguments[i + 1]) ?? Date()
                i += 2
            } else {
                i += 1
            }
        }

        guard let symbol = assetSymbol else {
            print("Error: --asset is required")
            print("Usage: cascade price fetch --asset <symbol> [--from MM/dd/yyyy] [--to MM/dd/yyyy]")
            print("Example: cascade price fetch --asset BTC --from 10/01/2025 --to 11/01/2025")
            break
        }

        // Default to last 30 days if no from date
        if fromDate == nil {
            fromDate = Calendar.current.date(byAdding: .day, value: -30, to: toDate)!
        }

        guard let from = fromDate else {
            print("Error: Invalid date format")
            break
        }

        print("Fetching \(symbol) prices from \(from.formatted(date: .numeric, time: .omitted)) to \(toDate.formatted(date: .numeric, time: .omitted))...")

        // Determine if crypto
        let cryptoSymbols = ["BTC", "ETH", "SOL", "ADA"]
        let isCrypto = cryptoSymbols.contains(symbol.uppercased())

        if !isCrypto {
            print("Error: Currently only crypto symbols supported (BTC, ETH, SOL, ADA)")
            print("For stocks/ETFs, use the GUI Price Data view")
            break
        }

        // Map symbol to CoinGecko ID
        let coinId: String
        switch symbol.uppercased() {
        case "BTC": coinId = "bitcoin"
        case "ETH": coinId = "ethereum"
        case "SOL": coinId = "solana"
        case "ADA": coinId = "cardano"
        default: coinId = symbol.lowercased()
        }

        // Build CoinGecko API URL
        let urlString = "https://api.coingecko.com/api/v3/coins/\(coinId)/market_chart/range"
        var components = URLComponents(string: urlString)!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "from", value: "\(Int(from.timeIntervalSince1970))"),
            URLQueryItem(name: "to", value: "\(Int(toDate.timeIntervalSince1970))")
        ]

        guard let requestURL = components.url else {
            print("Error: Invalid URL")
            break
        }

        // Fetch from CoinGecko
        print("Calling CoinGecko API for \(coinId)...")

        let task = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: requestURL)

                guard let httpResponse = response as? HTTPURLResponse else {
                    print("Error: Invalid HTTP response")
                    return
                }

                print("HTTP Status: \(httpResponse.statusCode)")

                if httpResponse.statusCode == 429 {
                    print("Error: Rate limited by CoinGecko")
                    print("Free API allows ~50 calls/minute")
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    print("Error: CoinGecko returned status \(httpResponse.statusCode)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("Response: \(errorBody)")
                    }
                    return
                }

                let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

                guard let pricesArray = json["prices"] as? [[Any]] else {
                    print("Error: No prices data in response")
                    print("Response keys: \(json.keys.joined(separator: ", "))")
                    return
                }

                print("✓ Received \(pricesArray.count) price points")

                // Store prices
                var importedCount = 0
                var updatedCount = 0

                for item in pricesArray {
                    guard let timestamp = item[0] as? TimeInterval,
                          let priceValue = item[1] as? Double else {
                        continue
                    }

                    let date = Date(timeIntervalSince1970: timestamp / 1000)  // CoinGecko uses milliseconds
                    let dayStart = Calendar.current.startOfDay(for: date)
                    let price = Decimal(priceValue)

                    // Check if exists
                    let descriptor = FetchDescriptor<AssetPrice>(
                        predicate: #Predicate<AssetPrice> { existing in
                            existing.assetId == symbol && existing.date == dayStart
                        }
                    )

                    let existing = try context.fetch(descriptor)
                    if existing.isEmpty {
                        let assetPrice = AssetPrice(
                            assetId: symbol,
                            date: dayStart,
                            price: price,
                            source: .api
                        )
                        context.insert(assetPrice)
                        importedCount += 1
                    } else {
                        updatedCount += 1
                    }
                }

                try context.save()

                print("")
                print("✓ Import complete:")
                print("  Imported: \(importedCount) new prices")
                print("  Skipped: \(updatedCount) existing prices")
                print("  Asset: \(symbol)")

            } catch {
                print("Error fetching prices: \(error)")
            }
        }

        // Wait for async task
        let _ = await task.value

    case "import":
        // Import prices from CSV file
        // Expected format: Date,Symbol,Close
        guard CommandLine.arguments.count >= 4 else {
            print("Usage: cascade price import <csv-file> [--asset <symbol>]")
            print("Expected CSV format: Date,Symbol,Close")
            print("Example: cascade price import btc_prices.csv --asset BTC")
            break
        }

        let csvPath = CommandLine.arguments[3]
        var assetFilter: String?

        // Parse optional --asset filter
        var i = 4
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--asset" && i + 1 < CommandLine.arguments.count {
                assetFilter = CommandLine.arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        // Read CSV file
        let fileURL = URL(fileURLWithPath: (csvPath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("Error: File not found at \(fileURL.path)")
            break
        }

        do {
            let csvContent = try String(contentsOf: fileURL, encoding: .utf8)
            let lines = csvContent.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard lines.count > 1 else {
                print("Error: CSV file is empty")
                break
            }

            // Parse header
            let header = lines[0].components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let dateIdx = header.firstIndex(where: { $0.lowercased().contains("date") }),
                  let symbolIdx = header.firstIndex(where: { $0.lowercased().contains("symbol") }),
                  let priceIdx = header.firstIndex(where: { $0.lowercased().contains("close") || $0.lowercased().contains("price") }) else {
                print("Error: Invalid CSV format. Expected columns: Date, Symbol, Close")
                print("Found columns: \(header.joined(separator: ", "))")
                break
            }

            print("Importing prices from \(fileURL.lastPathComponent)...")
            print("Columns: \(header.joined(separator: ", "))")

            var importedCount = 0
            var updatedCount = 0
            var skippedCount = 0
            var errorCount = 0

            let dateFormatter = DateFormatter()
            let dateFormats = ["yyyy-MM-dd", "MM/dd/yyyy", "M/d/yyyy"]

            for (_, line) in lines.dropFirst().enumerated() {
                let fields = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }

                guard fields.count > max(dateIdx, symbolIdx, priceIdx) else {
                    errorCount += 1
                    continue
                }

                let dateStr = fields[dateIdx]
                let symbol = fields[symbolIdx]
                let priceStr = fields[priceIdx]

                // Apply asset filter if specified
                if let filter = assetFilter, symbol != filter {
                    skippedCount += 1
                    continue
                }

                // Parse date
                var date: Date?
                for format in dateFormats {
                    dateFormatter.dateFormat = format
                    if let parsedDate = dateFormatter.date(from: dateStr) {
                        date = parsedDate
                        break
                    }
                }

                guard let validDate = date else {
                    errorCount += 1
                    continue
                }

                // Parse price
                guard let price = Decimal(string: priceStr.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) else {
                    errorCount += 1
                    continue
                }

                let dayStart = Calendar.current.startOfDay(for: validDate)

                // Check if exists
                let descriptor = FetchDescriptor<AssetPrice>(
                    predicate: #Predicate<AssetPrice> { existing in
                        existing.assetId == symbol && existing.date == dayStart
                    }
                )

                let existing = try context.fetch(descriptor)
                if existing.isEmpty {
                    let assetPrice = AssetPrice(
                        assetId: symbol,
                        date: dayStart,
                        price: price,
                        source: .csvImport
                    )
                    context.insert(assetPrice)
                    importedCount += 1
                } else if let existingPrice = existing.first, existingPrice.price != price {
                    existingPrice.price = price
                    existingPrice.source = .csvImport
                    updatedCount += 1
                } else {
                    skippedCount += 1
                }

                // Save periodically
                if (importedCount + updatedCount) % 1000 == 0 {
                    try context.save()
                    print("  Progress: \(importedCount + updatedCount) processed...")
                }
            }

            // Final save
            try context.save()

            print("")
            print("✓ Import complete:")
            print("  Imported: \(importedCount) new prices")
            print("  Updated: \(updatedCount) existing prices")
            print("  Skipped: \(skippedCount) (no change)")
            print("  Errors: \(errorCount)")

        } catch {
            print("Error reading or processing CSV: \(error)")
        }

    case "list":
        // List all prices, optionally filtered by asset
        var assetFilter: String?

        var i = 3
        while i < CommandLine.arguments.count {
            if CommandLine.arguments[i] == "--asset" && i + 1 < CommandLine.arguments.count {
                assetFilter = CommandLine.arguments[i + 1]
                i += 2
            } else {
                i += 1
            }
        }

        let descriptor: FetchDescriptor<AssetPrice>
        if let asset = assetFilter {
            descriptor = FetchDescriptor<AssetPrice>(
                predicate: #Predicate { $0.assetId == asset },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor<AssetPrice>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
        }

        let prices = try! context.fetch(descriptor)

        if prices.isEmpty {
            print("No price data found")
            if let asset = assetFilter {
                print("For asset: \(asset)")
            }
        } else {
            print("\n📈 PRICE DATA:")
            print(String(repeating: "=", count: 60))
            if let asset = assetFilter {
                print("Asset: \(asset)")
            }
            print("Total: \(prices.count) price points")
            print("")

            // Group by asset
            let grouped = Dictionary(grouping: prices, by: { $0.assetId })
            for (asset, assetPrices) in grouped.sorted(by: { $0.key < $1.key }) {
                let sorted = assetPrices.sorted { $0.date > $1.date }
                if let latest = sorted.first, let oldest = sorted.last {
                    print("  \(asset): \(assetPrices.count) prices")
                    print("    Latest: \(latest.date.formatted(date: .numeric, time: .omitted)) @ $\(latest.price)")
                    print("    Oldest: \(oldest.date.formatted(date: .numeric, time: .omitted)) @ $\(oldest.price)")
                }
            }
            print()
        }

    default:
        print("""
        Price commands:
          price fetch --asset <symbol> [--from MM/dd/yyyy] [--to MM/dd/yyyy]
            Fetch historical prices for a crypto asset from CoinGecko

          price import <csv-file> [--asset <symbol>]
            Import historical prices from CSV (Date,Symbol,Close format)

          price list [--asset <symbol>]
            List price data in database

        Examples:
          cascade price fetch --asset BTC --from 10/01/2025 --to 11/01/2025
          cascade price fetch --asset BTC  # Last 30 days
          cascade price import btc_prices.csv --asset BTC
          cascade price import all_prices.csv  # Import all symbols
          cascade price list --asset BTC
          cascade price list  # All assets
        """)
    }

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

case "query":
    // Parse filters
    var assetFilters: [String] = []
    var accountFilter: String?
    var categoryFilter: String?
    var startDate: Date?
    var endDate: Date?
    var outputMode = "transactions" // default

    var i = 2
    while i < CommandLine.arguments.count {
        if CommandLine.arguments[i] == "--asset" && i + 1 < CommandLine.arguments.count {
            assetFilters = [CommandLine.arguments[i + 1]]
            i += 2
        } else if CommandLine.arguments[i] == "--assets" && i + 1 < CommandLine.arguments.count {
            assetFilters = CommandLine.arguments[i + 1].split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            i += 2
        } else if CommandLine.arguments[i] == "--account" && i + 1 < CommandLine.arguments.count {
            accountFilter = CommandLine.arguments[i + 1]
            i += 2
        } else if CommandLine.arguments[i] == "--category" && i + 1 < CommandLine.arguments.count {
            categoryFilter = CommandLine.arguments[i + 1]
            i += 2
        } else if CommandLine.arguments[i] == "--from" && i + 1 < CommandLine.arguments.count {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yyyy"
            startDate = dateFormatter.date(from: CommandLine.arguments[i + 1])
            i += 2
        } else if CommandLine.arguments[i] == "--to" && i + 1 < CommandLine.arguments.count {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yyyy"
            endDate = dateFormatter.date(from: CommandLine.arguments[i + 1])
            i += 2
        } else if CommandLine.arguments[i] == "--positions" {
            outputMode = "positions"
            i += 1
        } else if CommandLine.arguments[i] == "--balances" {
            outputMode = "balances"
            i += 1
        } else if CommandLine.arguments[i] == "--summary" {
            outputMode = "summary"
            i += 1
        } else {
            i += 1
        }
    }

    // Get transactions to query
    var allTransactions = try! context.fetch(FetchDescriptor<Transaction>(
        sortBy: [SortDescriptor(\.date, order: .forward)]
    ))

    // Apply filters
    if let accountName = accountFilter {
        allTransactions = allTransactions.filter { $0.account?.name.contains(accountName) ?? false }
    }

    if let start = startDate {
        allTransactions = allTransactions.filter { $0.date >= start }
    }

    if let end = endDate {
        allTransactions = allTransactions.filter { $0.date <= end }
    }

    if !assetFilters.isEmpty {
        allTransactions = allTransactions.filter { tx in
            tx.journalEntries.contains { entry in
                assetFilters.contains(entry.accountName)
            }
        }
    }

    if let category = categoryFilter {
        allTransactions = allTransactions.filter { tx in
            tx.matchesCategory(category)
        }
    }

    // Output based on mode
    switch outputMode {
    case "positions":
        print("\n📊 POSITIONS")
        if !assetFilters.isEmpty {
            print("Assets: \(assetFilters.joined(separator: ", "))")
        }
        print(String(repeating: "=", count: 80))

        // Calculate positions by asset (only real holdings)
        var securityPositions: [String: (quantity: Decimal, txCount: Int)] = [:]
        var cashPosition: Decimal = 0
        var cashTxCount = 0

        // Securities that should be tracked as positions (not income/expense/transfer accounts)
        let knownSecurities = ["SPY", "QQQ", "NVDA", "FBTC", "GLD", "SPAXX", "FXAIX", "VOO", "VXUS", "VTI"]
        let excludeSuffixes = ["-Dividend", "-Transfer", "-Interest", "-Out"]

        for tx in allTransactions {
            for entry in tx.journalEntries {
                // Securities positions (use Asset link if available, otherwise accountName for known securities)
                if let asset = entry.asset, let qty = entry.quantity {
                    let symbol = asset.symbol
                    if assetFilters.isEmpty || assetFilters.contains(symbol) {
                        let current = securityPositions[symbol] ?? (quantity: 0, txCount: 0)
                        var newQuantity = current.quantity

                        if entry.debitAmount != nil {
                            newQuantity += qty // Buy/receive
                        } else {
                            newQuantity -= qty // Sell/deliver
                        }

                        securityPositions[symbol] = (quantity: newQuantity, txCount: current.txCount + 1)
                    }
                } else if let qty = entry.quantity, qty > 0 {
                    // Fallback: Check if accountName is a known security
                    let accountName = entry.accountName
                    let isExcluded = excludeSuffixes.contains { accountName.hasSuffix($0) }
                    let isKnownSecurity = knownSecurities.contains(accountName)

                    if !isExcluded && isKnownSecurity && accountName != "Cash" {
                        if assetFilters.isEmpty || assetFilters.contains(accountName) {
                            let current = securityPositions[accountName] ?? (quantity: 0, txCount: 0)
                            var newQuantity = current.quantity

                            if entry.debitAmount != nil {
                                newQuantity += qty
                            } else {
                                newQuantity -= qty
                            }

                            securityPositions[accountName] = (quantity: newQuantity, txCount: current.txCount + 1)
                        }
                    }
                }

                // Cash position (USD)
                if entry.accountName == "Cash" {
                    if assetFilters.isEmpty || assetFilters.contains("USD") || assetFilters.contains("Cash") {
                        if let debit = entry.debitAmount {
                            cashPosition += debit
                            cashTxCount += 1
                        }
                        if let credit = entry.creditAmount {
                            cashPosition -= credit
                        }
                    }
                }
            }
        }

        if securityPositions.isEmpty && cashPosition == 0 {
            print("  No positions found")
        } else {
            print("\nAsset           Quantity            Unit        Transactions")
            print(String(repeating: "─", count: 70))

            // Show Cash/USD first
            if assetFilters.isEmpty || assetFilters.contains("USD") || assetFilters.contains("Cash") {
                let cashNum = (cashPosition as NSDecimalNumber).doubleValue
                let assetPadded = "Cash (USD)".padding(toLength: 15, withPad: " ", startingAt: 0)
                let qtyStr = String(format: "%.2f", cashNum).padding(toLength: 16, withPad: " ", startingAt: 0)
                print("  \(assetPadded) \(qtyStr)  USD           \(cashTxCount)")
            }

            // Show securities
            for (symbol, data) in securityPositions.sorted(by: { $0.key < $1.key }) {
                let qtyNum = (data.quantity as NSDecimalNumber).doubleValue
                let assetPadded = symbol.padding(toLength: 15, withPad: " ", startingAt: 0)
                let qtyStr = String(format: "%.3f", qtyNum).padding(toLength: 16, withPad: " ", startingAt: 0)
                print("  \(assetPadded) \(qtyStr)  shares        \(data.txCount)")
            }

            print(String(repeating: "─", count: 70))
            print("Total holdings: \(securityPositions.count + (cashPosition != 0 ? 1 : 0)) assets")
        }
        print()

    case "transactions":
        print("\n💰 QUERY RESULTS")
        if !assetFilters.isEmpty {
            print("Assets: \(assetFilters.joined(separator: ", "))")
        }
        if let start = startDate {
            print("From: \(start.formatted(date: .abbreviated, time: .omitted))")
        }
        if let end = endDate {
            print("To: \(end.formatted(date: .abbreviated, time: .omitted))")
        }
        print(String(repeating: "=", count: 80))

        if allTransactions.isEmpty {
            print("  No transactions match filters")
        } else {
            for tx in allTransactions.reversed() { // Show newest first
                print("\n  \(tx.date.formatted(date: .numeric, time: .omitted)) - \(tx.transactionDescription)")
                if let cat = tx.userCategory {
                    print("    Category: \(cat)")
                }

                // Journal entries (minimal)
                for entry in tx.journalEntries {
                    let amount = entry.debitAmount ?? entry.creditAmount ?? 0
                    let side = entry.debitAmount != nil ? "DR" : "CR"

                    if let qty = entry.quantity {
                        print("    \(entry.accountName): \(qty) shares \(side) ($\(amount))")
                    } else {
                        print("    \(entry.accountName): $\(amount) \(side)")
                    }
                }

                // Source rows
                let sourceRows = Set(tx.journalEntries.flatMap { $0.sourceRows })
                if !sourceRows.isEmpty {
                    print("    Source: Row \(sourceRows.map { $0.rowNumber }.sorted().map(String.init).joined(separator: ", "))")
                }
            }

            print("\n" + String(repeating: "=", count: 80))
            print("Total: \(allTransactions.count) transactions")
        }
        print()

    default:
        print("""
        Query commands:
          query [--transactions]      List transactions (default)
          query --positions           Show asset positions
          query --balances            Show balance progression

        Filters:
          --asset <name>              Single asset (SPY, QQQ, etc.)
          --assets <list>             Multiple assets (SPY,QQQ,NVDA)
          --account <name>            Filter by account
          --category <path>           Filter by category (supports partial match)
          --from <MM/dd/yyyy>         Start date
          --to <MM/dd/yyyy>           End date

        Examples:
          cascade query --asset SPY
          cascade query --category investment
          cascade query --category investment/equity
          cascade query --positions --assets SPY,QQQ
          cascade query --asset SPY --from "05/01/2024" --to "05/31/2024"
          cascade query --category income --from "01/01/2024"
        """)
    }

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
                                      Update journal entries [--update-entry --quantity --debit --credit]
      transaction delete <id>         Delete transaction [--yes to skip confirmation]
      transaction show <id>           Show transaction details

      validate [<mapping>]            Validate mapping (coverage, balance, duplicates)
      coverage [<mapping>]            Show coverage report [--detailed]

      query [--positions]             Query/filter transactions
                                      [--asset <name>] [--category <path>]
                                      [--from <date>] [--to <date>]

      price fetch --asset <symbol>    Fetch crypto prices from CoinGecko
                                      [--from MM/dd/yyyy] [--to MM/dd/yyyy]
      price import <csv>              Import prices from CSV (Date,Symbol,Close)
                                      [--asset <symbol>]

      reset mapping <name> [--force]  Delete a specific mapping and its transactions

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
      ./cascade reset mapping "experimental" --force
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
