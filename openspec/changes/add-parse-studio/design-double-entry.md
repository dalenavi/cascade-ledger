# Double-Entry Bookkeeping Architecture

## Problem Statement

The single-entry ledger model (LedgerEntry) suffers from fundamental accounting issues:

**USD Double-Counting:**
- Fidelity CSV has dual-row structure (asset + settlement rows)
- Current system creates one LedgerEntry per CSV row
- Settlement rows (blank Action, qty=0) counted as USD transactions
- Result: USD balance = $499k instead of actual $144k

**Example:**
```
CSV:
  Row 1: YOU BOUGHT SPY, amount=-$2,019, qty=4
  Row 2: [settlement], amount=+$2,019, qty=0

Current (Wrong):
  Entry 1: USD transaction -$2,019
  Entry 2: USD transaction +$2,019
  Net USD: $0 (should be -$2,019)

Correct (Double-Entry):
  Transaction "YOU BOUGHT SPY"
    ├─ Debit:  Asset:SPY  $2,019 (4 shares)
    └─ Credit: Cash:USD   $2,019
  Net Cash: -$2,019 ✓
```

## Solution Overview

Implement true double-entry bookkeeping with:
- **Transaction** (container for complete financial events)
- **JournalEntry** (individual debit/credit legs)
- **Account Types** (Asset, Cash, Income, Expense, Liability, Equity)
- **Balance Enforcement** (debits must equal credits)

## Data Models

### Transaction
```swift
@Model
final class Transaction {
    var id: UUID
    var date: Date
    var transactionDescription: String
    var transactionType: TransactionType

    // Relationships
    var journalEntries: [JournalEntry]  // 2+ legs
    var account: Account                 // Brokerage account
    var importBatch: ImportBatch?

    // Source tracking
    var sourceRowNumbers: [Int]          // CSV rows that created this
    var sourceHash: String?              // For deduplication

    // Computed properties
    var totalDebits: Decimal             // Sum of all debits
    var totalCredits: Decimal            // Sum of all credits
    var isBalanced: Bool                 // debits = credits (±0.01)
    var netCashImpact: Decimal          // Sum of cash entries
    var primaryAsset: String?           // Main asset involved

    // Methods
    func addDebit(accountType, accountName, amount, quantity)
    func addCredit(accountType, accountName, amount, quantity)
    func validate() throws              // Enforce accounting rules
}
```

### JournalEntry
```swift
@Model
final class JournalEntry {
    var id: UUID
    var accountType: AccountType        // Asset, Cash, etc.
    var accountName: String             // "SPY", "USD", "Dividend Income"
    var debitAmount: Decimal?           // One of these is nil
    var creditAmount: Decimal?
    var quantity: Decimal?              // For asset accounts
    var quantityUnit: String?

    var transaction: Transaction

    // Computed
    var netEffect: Decimal              // Accounting-aware net effect
    var netQuantityChange: Decimal      // For asset accounts
}
```

### AccountType
```swift
enum AccountType: String {
    case asset      // Stocks, bonds, crypto
    case cash       // USD and other currencies
    case liability  // Margin debt
    case equity     // Owner's equity
    case income     // Dividends, interest
    case expense    // Fees, commissions
}
```

## Transaction Patterns

### Buy Stock
```
Transaction: "YOU BOUGHT SPY"
├─ Debit:  Asset:SPY  $2,019 (4 shares)
└─ Credit: Cash:USD   $2,019
```

### Sell Stock
```
Transaction: "YOU SOLD QQQ"
├─ Credit: Asset:QQQ  $3,939 (8 shares)
└─ Debit:  Cash:USD   $3,939
```

### Dividend (Cash)
```
Transaction: "DIVIDEND SPY"
├─ Debit:  Cash:USD           $52,264
└─ Credit: Income:Dividend    $52,264
```

### Dividend (Reinvested)
```
Transaction: "DIVIDEND SPAXX"
├─ Debit:  Asset:SPAXX        $0.29 (0.29 shares)
└─ Credit: Income:Dividend    $0.29
```

### Transfer Out
```
Transaction: "TRANSFERRED TO"
├─ Credit: Cash:USD              $4,550
└─ Debit:  Equity:Withdrawals    $4,550
```

## CSV Row Grouping

**TransactionBuilder.groupRows()** logic:

1. **Detect settlement rows:**
   - `metadata.action` is empty/blank
   - `assetId` is empty/blank
   - `quantity` = 0

2. **Group consecutive rows:**
   - Start new group on non-settlement row
   - Add settlement rows to current group
   - Result: Each group = 1 transaction

**Example grouping:**
```
CSV Rows:
  Row 0: YOU BOUGHT SPY, qty=4      → Group 1 (primary)
  Row 1: [blank], qty=0              → Group 1 (settlement)
  Row 2: DIVIDEND, qty=0             → Group 2 (primary)
  Row 3: YOU SOLD QQQ, qty=-8        → Group 3 (primary)
  Row 4: [blank], qty=0              → Group 3 (settlement)

Result: 3 transactions (not 5)
```

## Import Processing

### ParseEngineV2.importWithDoubleEntry()

1. **Transform all rows** (filter invalid rows like disclaimers)
2. **Preserve metadata.action** from CSV Action column
3. **Group rows** into transaction groups
4. **Create transactions** using TransactionBuilder
5. **Validate** each transaction (isBalanced check)
6. **Calculate USD balance** from net cash impact

### TransactionBuilder.createTransaction()

1. **Find primary row** (non-blank action)
2. **Extract fields:**
   - action from metadata.action
   - symbol from assetId
   - quantity from quantity field
   - amount from amount field

3. **Build journal entries** based on action pattern:
   - `if actionUpper.contains("YOU BOUGHT")` → buildBuyTransaction()
   - `else if actionUpper.contains("YOU SOLD")` → buildSellTransaction()
   - `else if actionUpper.contains("DIVIDEND")` → buildDividendTransaction()
   - etc.

4. **Validate** transaction.isBalanced

## USD Calculation

### Old (Single-Entry - Wrong):
```swift
usdBalance = allEntries
    .filter { $0.assetId == nil }  // No asset = USD
    .reduce(0) { $0 + $1.amount }

// Problem: Includes settlement rows!
// Result: $499k (double-counted)
```

### New (Double-Entry - Correct):
```swift
usdBalance = transactions
    .flatMap { $0.journalEntries }
    .filter { $0.accountType == .cash && $0.accountName == "USD" }
    .reduce(0) { sum, entry in
        sum + (entry.debitAmount ?? 0) - (entry.creditAmount ?? 0)
    }

// Result: $144k ✓ (matches Cash Balance column)
```

## Parse Plan Requirements

For double-entry to work, parse plans must:

1. **Preserve Action field** in metadata:
   ```
   "Action" → "metadata.action"  (NOT transactionType!)
   ```

2. **Extract quantity correctly:**
   ```
   "Quantity" → "quantity" (numeric value preserved)
   ```

3. **Map symbol to assetId:**
   ```
   "Symbol" → "assetId"
   ```

4. **Settlement row detection** relies on:
   - metadata.action = empty/blank
   - assetId = empty/blank
   - quantity = 0

## Migration Strategy

### Phase 1: Dual-Write (Current)
- Keep LedgerEntry for backward compatibility
- Add Transaction/JournalEntry in parallel
- Views can query either model

### Phase 2: View Migration
- Update each view to use Transaction queries
- PortfolioValueView: Use transaction.netCashImpact
- PositionsView: Use journalEntry.netQuantityChange
- Analytics: Group by transaction metadata

### Phase 3: Data Migration
```swift
ParseEngineV2.migrateExistingData()
- Group LedgerEntries by date + import batch
- Create Transactions from groups
- Validate balances
- Mark LedgerEntries as migrated
```

### Phase 4: Deprecation
- Remove LedgerEntry model
- Remove ParseEngine (keep ParseEngineV2)
- Clean up migration code

## Testing Validation

### Sample CSV Test
- Import: `sample_data/fidelity_sample_transactions.csv`
- Expected: Final USD = $144,218.26 (from Cash Balance column)
- Transactions: ~100-120 (not 244 rows)
- All transactions: `isBalanced = true`

### Balance Checks
```swift
for transaction in transactions {
    assert(transaction.isBalanced)
    assert(abs(transaction.totalDebits - transaction.totalCredits) < 0.01)
}
```

### Position Verification
```swift
let spyPosition = transactions
    .flatMap { $0.journalEntries }
    .filter { $0.accountType == .asset && $0.accountName == "SPY" }
    .reduce(0) { $0 + $1.netQuantityChange }

// Should match Fidelity's position report
```

## Benefits

1. **Accurate USD tracking** - No double-counting settlement rows
2. **Enforced correctness** - Every transaction must balance
3. **Clear audit trail** - See all debits/credits per transaction
4. **Industry standard** - True double-entry bookkeeping
5. **Extensible** - Supports complex transactions (splits, multi-leg)
6. **Verifiable** - Can prove books balance at any point in time

## Current Status

- ✅ Core models implemented
- ✅ TransactionBuilder with row grouping
- ✅ ParseEngineV2 working
- ✅ Test view created
- ✅ Parse agent enhanced for correct mappings
- ⏳ View migration in progress
- ⏳ Data migration service partial
- ❌ Full cutover pending testing

## Files

- `Models/Transaction.swift` - Transaction container
- `Models/JournalEntry.swift` - Individual legs with AccountType
- `ParseEngine/TransactionBuilder.swift` - Row grouping and transaction creation
- `ParseEngine/ParseEngineV2.swift` - Double-entry import engine
- `Views/DoubleEntryTestView.swift` - Testing interface
- `Views/AccountsView.swift` - Enhanced clear to delete both models
