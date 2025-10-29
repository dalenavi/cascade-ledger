# Source Row Provenance - Design

## Architecture Overview

```
RawFile → SourceRow (persisted) → JournalEntry → Transaction
   ↓           ↓                        ↓              ↓
fileName   rawData                  amount      description
           mappedData             csvAmount
           (balance!)          sourceRows[]
```

## Core Components

### 1. SourceRow Model
**Purpose:** Persistent representation of every CSV row with standardized field mapping

```swift
@Model
class SourceRow {
    var id: UUID
    var rowNumber: Int           // 1-based index in file
    var globalRowNumber: Int     // Unique across all imports

    // Provenance
    @Relationship
    var sourceFile: RawFile

    // Data
    var rawDataJSON: Data        // Original CSV [String: String]
    var mappedDataJSON: Data     // Standardized MappedRowData

    // Relationships
    @Relationship(deleteRule: .nullify, inverse: \JournalEntry.sourceRows)
    var journalEntries: [JournalEntry]

    // Computed properties
    var rawData: [String: String] { /* decode from rawDataJSON */ }
    var mappedData: MappedRowData { /* decode from mappedDataJSON */ }
}
```

### 2. MappedRowData Struct
**Purpose:** Standardized view of CSV row regardless of source format

```swift
struct MappedRowData: Codable {
    // Core fields (always present)
    var date: Date
    var action: String

    // Transaction details (optional)
    var symbol: String?
    var quantity: Decimal?
    var amount: Decimal?
    var price: Decimal?
    var description: String?

    // Settlement details
    var settlementDate: Date?
    var balance: Decimal?        // CRITICAL: Standardized balance field

    // Fees & charges
    var commission: Decimal?
    var fees: Decimal?
    var accruedInterest: Decimal?

    // Metadata
    var transactionType: String?
}
```

### 3. CSVFieldMapping
**Purpose:** Define how to map institution-specific CSV headers to standard fields

```swift
struct CSVFieldMapping: Codable {
    // Required fields
    var dateField: String = "Run Date"
    var actionField: String = "Action"

    // Amount & balance
    var amountField: String = "Amount ($)"
    var balanceField: String = "Cash Balance ($)"  // Institution-specific!

    // Transaction details
    var symbolField: String? = "Symbol"
    var quantityField: String? = "Quantity"
    var priceField: String? = "Price ($)"
    var descriptionField: String? = "Description"

    // Optional fields
    var settlementDateField: String? = "Settlement Date"
    var commissionField: String? = "Commission ($)"
    var feesField: String? = "Fees ($)"
    var accruedInterestField: String? = "Accrued Interest ($)"
    var typeField: String? = "Type"

    /// Auto-detect field names from CSV headers
    static func detect(from headers: [String]) -> CSVFieldMapping {
        var mapping = CSVFieldMapping()

        // Find balance field (multiple possible names)
        if headers.contains("Cash Balance ($)") {
            mapping.balanceField = "Cash Balance ($)"
        } else if headers.contains("Balance") {
            mapping.balanceField = "Balance"
        } else if headers.contains("Account Balance") {
            mapping.balanceField = "Account Balance"
        }

        // Similar detection for other fields...

        return mapping
    }
}
```

### 4. Updated JournalEntry Model
**Purpose:** Link journal entries to source rows for validation

```swift
@Model
class JournalEntry {
    // ... existing fields ...

    // Source provenance
    @Relationship
    var sourceRows: [SourceRow]  // Many-to-many: one entry can use multiple rows

    // Validation
    var csvAmount: Decimal?         // Expected amount from source row
    var amountDiscrepancy: Decimal? // amount - csvAmount

    // Computed
    var hasAmountDiscrepancy: Bool {
        guard let csvAmount = csvAmount else { return false }
        return abs(amount - csvAmount) > 0.01
    }
}
```

### 5. Categorization Context
**Purpose:** Persistent AI learning per account

```swift
@Model
class Account {
    // ... existing fields ...

    var csvFieldMapping: CSVFieldMapping?
    var categorizationContext: String?  // AI instructions

    func updateCategorizationContext(_ update: String) {
        if let existing = categorizationContext {
            categorizationContext = "\(existing)\n\n\(update)"
        } else {
            categorizationContext = update
        }
    }
}
```

---

## Data Flow

### Import & Mapping
```
1. CSV File Imported
   ↓
2. Parse to [String: String] rows
   ↓
3. Create SourceRow objects (persisted)
   ↓
4. Apply CSVFieldMapping to create MappedRowData
   ↓
5. SourceRows available for categorization
```

### Categorization with Provenance
```
1. AI receives MappedRowData (standardized)
   ↓
2. AI returns transactions with sourceRows per journal entry
   ↓
3. Create JournalEntry objects linked to SourceRows
   ↓
4. Validate: JournalEntry.amount vs SourceRow.mappedData.amount
   ↓
5. Flag discrepancies immediately
```

### Validation Rules
```swift
// Rule 1: Amount validation
for entry in transaction.journalEntries {
    guard let sourceRow = entry.sourceRows.first else { continue }
    let csvAmount = sourceRow.mappedData.amount

    if let csvAmount = csvAmount, abs(entry.amount - csvAmount) > 0.01 {
        entry.amountDiscrepancy = entry.amount - csvAmount
        // Flag for review
    }
}

// Rule 2: Balance validation
if let lastEntry = transaction.journalEntries.last,
   let sourceRow = lastEntry.sourceRows.last,
   let csvBalance = sourceRow.mappedData.balance {

    let calculatedBalance = calculateRunningBalance(upTo: transaction)
    transaction.balanceDiscrepancy = csvBalance - calculatedBalance
}

// Rule 3: Over-grouping detection
for entry in transaction.journalEntries {
    // If entry uses row #456 but amount doesn't match row #456, likely over-grouped
    if entry.sourceRows.count == 1 {
        let row = entry.sourceRows[0]
        if let csvAmount = row.mappedData.amount,
           abs(entry.amount - csvAmount) > 0.01 {
            // PROBABLE OVER-GROUPING
        }
    }
}
```

---

## AI Categorization Prompt Changes

### Updated Response Format
```json
{
  "transactions": [
    {
      "sourceRows": [455, 456],
      "date": "2024-04-23",
      "description": "...",
      "transactionType": "buy",
      "journalEntries": [
        {
          "type": "debit",
          "accountType": "asset",
          "accountName": "SPY",
          "amount": 2019.24,
          "quantity": 4,
          "sourceRows": [455],     // NEW: Which row(s) this entry came from
          "csvAmount": 2019.24     // NEW: Amount from CSV to validate
        },
        {
          "type": "credit",
          "accountType": "cash",
          "accountName": "Cash USD",
          "amount": 2019.24,
          "sourceRows": [455]      // NEW: Same source row
        }
      ]
    }
  ]
}
```

### Categorization Context Injection
```
CATEGORIZATION CONTEXT FOR THIS ACCOUNT:
{account.categorizationContext}

IMPORTANT: Follow these account-specific patterns when categorizing.
```

---

## Field Mapping Auto-Detection

### Strategy
1. **On first import**: Analyze CSV headers
2. **Detect common patterns**:
   - Balance field: `Cash Balance ($)`, `Balance`, `Account Balance`, `Ending Balance`
   - Amount field: `Amount ($)`, `Amount`, `Transaction Amount`
   - Date field: `Run Date`, `Date`, `Transaction Date`, `Trade Date`
3. **Store mapping with account**
4. **User can override** in settings

### Detection Algorithm
```swift
func detectBalanceField(headers: [String]) -> String? {
    let patterns = [
        "Cash Balance",
        "Balance",
        "Account Balance",
        "Ending Balance",
        "Running Balance"
    ]

    for pattern in patterns {
        if let match = headers.first(where: {
            $0.lowercased().contains(pattern.lowercased())
        }) {
            return match
        }
    }

    return nil
}
```

---

## Migration Strategy

### For Existing Data
**Option 1: Backfill (Recommended)**
- Re-import CSV files to create SourceRow objects
- Link existing journal entries to source rows by row number
- Validate and flag discrepancies

**Option 2: Lazy Migration**
- New imports use SourceRow system
- Old transactions remain as-is (no source row linkage)
- UI shows "Legacy" badge for old data

**Option 3: Hybrid**
- Create SourceRows for existing imports (from RawFile)
- Link where possible, mark as "Inferred" where uncertain

### Chosen Approach: Option 1 (Backfill)
Rationale:
- Clean data model (all transactions have provenance)
- Enables full validation on existing data
- One-time cost, long-term benefit
- Can detect existing categorization errors

---

## UI Changes

### Transaction Detail View
```
Transaction: Buy SPY and transfer from external account
├─ DR: SPY $2,019.24
│  └─ Source: Row #455 (CSV: $2,019.24) ✓
├─ CR: Cash USD $2,019.24
│  └─ Source: Row #455
├─ DR: Cash USD $2,032.69
│  └─ Source: Row #456 (CSV: $2,032.69) ✓
└─ CR: Owner Contributions $2,032.69
   └─ Source: Row #456
```

### Source Row Inspector
Click on source row link shows:
```
Source Row #456 (Fidelity_2024.csv)
─────────────────────────────────────
Raw CSV Data:
  Run Date: 04/23/2024
  Action: [blank]
  Amount ($): 2032.69
  Cash Balance ($): 2032.69
  Description: Transfer from ext...

Mapped Data:
  date: 2024-04-23
  action: ""
  amount: $2,032.69
  balance: $2,032.69
  description: "Transfer from ext..."

Used By:
  ├─ Transaction #1 → Journal Entry #3 (DR: Cash) ✓
  └─ Transaction #1 → Journal Entry #4 (CR: Contributions) ✓
```

### Field Mapping Settings
```
Account Settings → CSV Field Mapping

Balance Field: [Cash Balance ($)     ▼]
Amount Field:  [Amount ($)           ▼]
Date Field:    [Run Date             ▼]

[Auto-Detect from CSV] [Save Mapping]
```

---

## Performance Considerations

### Storage Impact
- 465 CSV rows × ~500 bytes/row = ~230 KB per import
- Negligible compared to transaction data
- Benefits outweigh storage cost

### Query Performance
- Index on globalRowNumber for fast lookups
- Eager load sourceRows when displaying transactions
- Lazy load rawData/mappedData (only when inspecting)

### Import Performance
- Create SourceRows in batch (100 at a time)
- Use background queue for mapping
- Incremental save every 1000 rows

---

## Edge Cases

### Case 1: Multiple Files, Overlapping Row Numbers
**Problem:** Row #1 exists in file A and file B

**Solution:** globalRowNumber is unique across files, rowNumber is per-file
```
File A, Row #1 → globalRowNumber = 1
File B, Row #1 → globalRowNumber = 466
```

### Case 2: Journal Entry Uses Multiple Source Rows
**Problem:** Combined transaction spans rows

**Solution:** Many-to-many relationship supports this
```
JournalEntry: DR SPY $8,599.94
  sourceRows: [#441, #442]  // Combined from two rows
  csvAmount: 8599.94        // Sum of row amounts
```

### Case 3: Source Row Used Multiple Times
**Problem:** Row #456 balance appears in multiple entries

**Solution:** SourceRow can be referenced by multiple JournalEntries
```
SourceRow #456 (balance: $2,032.69)
  ├─ Used by: Transaction #1, Entry #3
  └─ Used by: Transaction #5, Entry #2 (duplicate!)  ← Detectable!
```

### Case 4: Missing CSV Field
**Problem:** CSV doesn't have balance field

**Solution:** MappedRowData.balance = nil, validation skips balance check

---

## Testing Strategy

### Unit Tests
- SourceRow creation and mapping
- Field mapping auto-detection
- Amount validation logic
- Discrepancy calculation

### Integration Tests
- Full import → SourceRow creation → Categorization → Validation
- Multi-file imports with global row numbering
- Field mapping persistence and retrieval

### Test Data
- Fidelity CSV with "Cash Balance ($)"
- Generic CSV with "Balance"
- CSV without balance field
- Multi-file import test

---

## Future Enhancements

### Phase 2
- **Smart field detection** - ML-based field mapping
- **Cross-account learning** - Share categorization patterns
- **Anomaly detection** - Flag unusual patterns automatically
- **Historical correction** - Update context based on reconciliation fixes

### Phase 3
- **Visual lineage graph** - Show data flow from file → row → entry → transaction
- **Provenance export** - Include source row info in exports
- **Audit trail** - Track who changed what when
