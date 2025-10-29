# Add Source Row Provenance & Field Mapping

## Status
**Draft** - Awaiting approval

## Context
Current system has weak data lineage:
- Transactions reference row numbers but not files
- Journal entries don't link to source rows
- No standardized mapping of CSV fields
- Can't validate journal entry amounts against source data
- Over-grouping bugs go undetected (rows #455-456 grouped incorrectly)

**Current Architecture (Weak):**
```
Transaction uses rows [#455, #456]
  ├─ DR: SPY $2,019.24  ← Which row? Which file? Unknown!
  └─ CR: Cash $2,019.24
```

**Evidence of Problems:**
```
Txn #0: "Buy SPY and transfer from external account"
  Uses rows: #455, #456
  Cash impact: -$2,019.24  ← Only SPY purchase recorded!
  CSV balance: $2,032.69   ← But CSV shows positive balance!
  Discrepancy: $4,051.93   ← Massive mismatch = categorization error!
```

Row #456 contains a $2,032.69 transfer (separate transaction) but was grouped with row #455 SPY purchase.

## Problem
1. **No source row persistence** - Row data is ephemeral, not stored
2. **No journal entry → row linkage** - Can't trace journal entries to source
3. **No field mapping per account** - Hardcoded "Cash Balance ($)" field names
4. **No amount validation** - Journal entry amounts can't be verified against CSV
5. **Weak consistency** - Over-grouping creates silent errors
6. **No categorization context** - AI can't learn from corrections

## Proposed Solution
Build **Source Row Provenance System** with three components:

### 1. Source Row Persistence
Store every CSV row as a normalized entity:
```swift
@Model
class SourceRow {
    var id: UUID
    var sourceFile: RawFile
    var rowNumber: Int           // In this file
    var globalRowNumber: Int     // Across all files
    var rawData: Data            // Original CSV [String: String]
    var mappedData: Data         // Standardized MappedRowData
}

struct MappedRowData: Codable {
    var date: Date
    var action: String
    var symbol: String?
    var quantity: Decimal?
    var amount: Decimal?
    var price: Decimal?
    var balance: Decimal?        // Standardized field
    var settlementDate: Date?
    var description: String
}
```

### 2. Journal Entry → Source Row Linkage
```swift
@Model
class JournalEntry {
    // ... existing fields ...
    var sourceRows: [SourceRow]     // Many-to-many relationship
    var csvAmount: Decimal?         // Expected amount from CSV
    var amountDiscrepancy: Decimal? // Actual vs CSV
}
```

**Consistency Rule:** Every journal entry amount must match a source row amount

### 3. Account-Level Field Mapping
```swift
@Model
class Account {
    var csvFieldMapping: CSVFieldMapping?
    var categorizationContext: String?  // AI learning context
}

struct CSVFieldMapping: Codable {
    var dateField: String = "Run Date"
    var balanceField: String = "Cash Balance ($)"
    var amountField: String = "Amount ($)"
    var actionField: String = "Action"
    var symbolField: String = "Symbol"
    var quantityField: String = "Quantity"
    var priceField: String = "Price ($)"
    var settlementDateField: String? = "Settlement Date"
    var descriptionField: String? = "Description"
}
```

### 4. Categorization Context
Account-specific AI learning:
```
Categorization Context (Fidelity Brokerage):
- Settlement pattern: Dual-row structure (primary + settlement)
- Row with blank Action = settlement row (has balance)
- "transfer from external account" in description = separate deposit
- Multi-symbol transactions = separate purchases, not combined
```

## Success Criteria
- [ ] Every journal entry links to one or more source rows
- [ ] Every journal entry amount validates against source CSV amount
- [ ] Balance field automatically detected per account
- [ ] Categorization context persists with account
- [ ] Over-grouping detected via amount validation
- [ ] Can drill down: transaction → journal entry → source row → source file
- [ ] UI shows source row details in journal entry view

## Dependencies
- Requires: RawFile model (exists)
- Requires: Transaction/JournalEntry models (exist)
- Builds on: AI Direct Categorization (completed)
- Enables: Better balance reconciliation (in progress)

## Risks
- **Migration complexity** - Existing transactions have no source row linkage
- **Storage growth** - Persisting all source rows increases database size
- **Performance** - Many-to-many relationships may slow queries
- **Breaking change** - AI categorization prompt must change to include source rows per entry

## Mitigation
- Migration: Make source row linkage optional for old data
- Storage: Compress raw data, index efficiently
- Performance: Eager load source rows when needed
- Breaking: Update prompt gradually, support both formats during transition

## Timeline
- Foundation (models, migration): 2-3 hours
- Field mapping & detection: 1-2 hours
- Journal entry validation: 1-2 hours
- Categorization context: 2-3 hours
- UI integration: 1-2 hours
- Testing & refinement: 2-3 hours

Total: 9-15 hours of focused work
