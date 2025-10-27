# Transaction Grouping & Double-Entry Ledger Design

## Problem: Current Model is Single-Entry

**Current (broken):**
```
CSV Row → LedgerEntry (1:1 mapping)

Buy 100 SPY:
  LedgerEntry 1: SPY, qty=100, amount=-$45,000
  LedgerEntry 2: USD settlement, amount=+$45,000

Result: Can't determine net cash position (counts both sides)
```

## Rigorous Solution: Double-Entry Accounting

### Core Principle

**Every transaction must balance:**
```
Assets + Expenses = Liabilities + Equity + Income
Debits = Credits

For any transaction: Σ(amounts) = 0
```

### Proposed Data Model

```swift
@Model
final class Transaction {
    var id: UUID
    var date: Date
    var description: String
    var sourceRowNumbers: [Int]  // Which CSV rows contributed

    @Relationship
    var importBatch: ImportBatch?

    // The transaction legs (multi-sided)
    @Relationship(deleteRule: .cascade, inverse: \JournalEntry.transaction)
    var entries: [JournalEntry]

    // Metadata
    var transactionType: TransactionType  // Buy, Sell, Dividend, etc.
    var notes: String?

    // Validation
    var isBalanced: Bool {
        entries.reduce(0) { $0 + $1.amount } == 0
    }
}

@Model
final class JournalEntry {
    var id: UUID

    @Relationship
    var transaction: Transaction

    // What account this affects
    var accountType: AccountType
    var accountIdentifier: String?  // SPY, VOO, USD, etc.

    // The movement
    var amount: Decimal      // Signed: + = debit, - = credit
    var quantity: Decimal?   // For assets
    var quantityUnit: String?

    // Price tracking
    var pricePerUnit: Decimal?

    // Which side of the ledger
    var debitCredit: DebitCredit
}

enum AccountType: String, Codable {
    case asset       // SPY, VOO, FBTC shares
    case cash        // USD, AUD, etc.
    case expense     // Fees, commissions
    case income      // Dividends, interest
    case liability   // Margin loan
}

enum DebitCredit: String, Codable {
    case debit   // Increase in assets/expenses
    case credit  // Increase in liabilities/income
}
```

### Example: Buy 100 SPY with Commission

**CSV rows:**
```
Row 1: BUY, SPY, 100, -$45,000
Row 2: COMMISSION, , 0, -$10
Row 3: SETTLEMENT, , 0, +$45,010
```

**Grouped into ONE Transaction:**
```swift
Transaction(
    date: Oct 15, 2024,
    description: "BUY 100 SPY",
    type: .buy,
    entries: [
        JournalEntry(
            accountType: .asset,
            accountIdentifier: "SPY",
            debit: $45,000,      // Asset increases
            quantity: 100
        ),
        JournalEntry(
            accountType: .expense,
            accountIdentifier: "Commission",
            debit: $10           // Expense
        ),
        JournalEntry(
            accountType: .cash,
            accountIdentifier: "USD",
            credit: $45,010      // Cash decreases
        )
    ]
)

Balance check: +$45,000 + $10 - $45,010 = 0 ✓
```

### Grouping Strategies

**Strategy 1: Settlement Date Linking**
```swift
// Group rows with same Settlement Date
let groups = rows.grouped(by: { $0.settlementDate })
```

**Strategy 2: Trade ID (if available)**
```swift
// Some brokers include trade/order ID
let groups = rows.grouped(by: { $0.tradeId })
```

**Strategy 3: Temporal + Pattern Matching**
```swift
// Rows within 1 second + matching description pattern
func groupByPattern(_ rows: [CSVRow]) -> [[CSVRow]] {
    var groups: [[CSVRow]] = []
    var currentGroup: [CSVRow] = []

    for row in rows {
        if shouldStartNewGroup(row, currentGroup) {
            if !currentGroup.isEmpty {
                groups.append(currentGroup)
            }
            currentGroup = [row]
        } else {
            currentGroup.append(row)
        }
    }

    return groups
}

func shouldStartNewGroup(_ row: CSVRow, _ currentGroup: [CSVRow]) -> Bool {
    guard let last = currentGroup.last else { return false }

    // Different date → new transaction
    if row.date != last.date { return true }

    // Has quantity (new asset action) → new transaction
    if row.quantity != 0 && last.quantity != 0 { return true }

    // Large time gap → new transaction
    if row.timestamp - last.timestamp > 60 { return true }

    return false
}
```

**Strategy 4: Fidelity-Specific Heuristic**
```swift
// Your pattern: Asset row followed by 0-2 settlement rows
// Action != "" → Main row (start new group)
// Action == "" && qty == 0 → Settlement row (add to current group)
```

## USD Calculation (With Grouping)

**Per transaction group:**
```swift
func extractCashImpact(group: [CSVRow]) -> Decimal {
    // Find the row with asset action
    if let assetRow = group.first(where: { $0.quantity != 0 }) {
        // Cash impact = the amount on asset row (already includes direction)
        return assetRow.amount
    }

    // If no asset row, it's a pure cash transaction
    // (deposit, withdrawal, dividend)
    return group.reduce(0) { $0 + $1.amount }
}
```

**Example:**
```
Group [BUY SPY row, SETTLEMENT row]:
  Asset row: amount=-$45,000
  Cash impact: -$45,000 (cash decreased) ✓

Group [DIVIDEND row, SETTLEMENT row]:
  Dividend row: amount=+$500
  Cash impact: +$500 (cash increased) ✓
```

## Implementation Path

### Phase 1: Backward Compatible (Add Cash Tracking)

**Add to LedgerEntry:**
```swift
var cashImpact: Decimal?  // Net cash effect of this transaction
var isSettlementEntry: Bool  // Flag settlement rows
```

**During import:**
```swift
// Asset transaction: cash impact = amount
if quantity != 0 {
    ledgerEntry.cashImpact = amount
    ledgerEntry.isSettlementEntry = false
}
// Settlement: mark but don't use for cash
else if description.isEmpty || description == "No Description" {
    ledgerEntry.cashImpact = 0
    ledgerEntry.isSettlementEntry = true
}
// Real cash transaction
else {
    ledgerEntry.cashImpact = amount
    ledgerEntry.isSettlementEntry = false
}
```

**USD calculation:**
```swift
usdBalance = allEntries
    .filter { !$0.isSettlementEntry }
    .reduce(0) { $0 + ($0.cashImpact ?? $1.amount) }
```

### Phase 2: Full Grouping (Proper Model)

**New models:**
- Transaction (container)
- JournalEntry (legs)
- CSV rows → grouped → Transaction with multiple JournalEntries

**Migration strategy:**
- Parse plan includes grouping rules
- Institution-specific strategies
- Claude helps identify patterns

## Question for You

**Looking at your CSV:**
1. Does it have "Settlement Date" column?
2. Do settlement rows always have qty=0?
3. Do settlement rows always say "No Description"?
4. Are they always immediately after the asset row?

**I need to understand the pattern to implement the grouping.**

Should I start with Phase 1 (add `cashImpact` and `isSettlementEntry` flags) or go straight to Phase 2 (full Transaction grouping)?