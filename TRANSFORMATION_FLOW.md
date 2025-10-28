# Data Transformation Flow

## Overview

```
CSV File → Parse & Transform → Grouped Rows → Transaction Builder → Domain Entities
```

## Current Structure (What We Have)

### Stage 1: CSV → Transformed Rows
**Input:** Raw CSV file
**Output:** Array of dictionaries `[[String: Any]]`

**Example:**
```swift
[
  [
    "date": Date(2024-12-20),
    "amount": Decimal(-999.50),
    "description": "FIDELITY 500 INDEX FUND",
    "assetId": "FXAIX",
    "quantity": Decimal(5.123),
    "metadata.action": "YOU BOUGHT",
    "metadata.price": Decimal(195.00),
    "metadata.settlement_date": Date(2024-12-23),
    "metadata.cash_balance": Decimal(10050.25)
  ],
  // Settlement row (empty action/symbol, zero quantity)
  [
    "date": Date(2024-12-20),
    "amount": Decimal(0),
    "description": "No Description",
    "assetId": "",
    "quantity": Decimal(0),
    "metadata.action": "",
    "metadata.cash_balance": Decimal(9050.75)
  ]
]
```

### Stage 2: Row Grouping (Settlement Detection)
**Input:** `[[String: Any]]` (transformed rows)
**Output:** `[[[String: Any]]]` (grouped rows)

Using `SettlementDetector`:
- Fidelity: Groups asset row + settlement row(s) together
- Coinbase: Each row is its own group

**Example:**
```swift
[
  // Group 1: Buy transaction (2 rows grouped)
  [
    ["date": ..., "metadata.action": "YOU BOUGHT", "assetId": "FXAIX", "quantity": 5.123],
    ["date": ..., "metadata.action": "", "assetId": "", "quantity": 0]  // settlement
  ],
  // Group 2: Dividend (1 row, no settlement)
  [
    ["date": ..., "metadata.action": "DIVIDEND RECEIVED", "assetId": "SPY", "quantity": 0]
  ]
]
```

## Target Structure (Domain Model)

### Stage 3: Transaction Building
**Input:** Grouped rows `[[[String: Any]]]`
**Output:** `Transaction` objects with `JournalEntry` legs

**TransactionBuilder.createTransaction()** produces:

```swift
Transaction {
  id: UUID
  date: 2024-12-20
  transactionDescription: "FIDELITY 500 INDEX FUND"
  transactionType: .buy
  account: Account(fidelity investment)

  journalEntries: [
    // Debit leg: Asset increases
    JournalEntry {
      accountType: .asset
      accountName: "FXAIX"
      debitAmount: 999.50
      creditAmount: nil
      quantity: 5.123
      quantityUnit: "shares"
      asset: Asset(symbol: "FXAIX", id: UUID(...))  // From AssetRegistry
    },

    // Credit leg: Cash decreases
    JournalEntry {
      accountType: .cash
      accountName: "USD"
      debitAmount: nil
      creditAmount: 999.50
      asset: Asset(symbol: "USD", id: UUID(...))  // From AssetRegistry
    }
  ]

  sourceRowNumbers: [42, 43]  // Which CSV rows created this
  sourceHash: "sha256..."
  isDuplicate: false
  isBalanced: true  // debits == credits
}
```

## Key Characteristics

### Intermediate Format (Current)
- **Flat dictionaries** with string keys
- **Flexible** - can handle any CSV structure
- **Institution-agnostic** - same format for all
- **Metadata preservation** - everything stored as `metadata.*`

### Domain Model (Target)
- **Double-entry accounting** - every transaction balanced
- **Asset relationships** - linked to Asset master registry
- **Type-safe** - Decimal, Date, enums
- **Queryable** - can ask "show all FXAIX transactions"
- **Auditable** - source tracking, validation

## Why This Separation?

1. **ParsePlan operates on dictionaries** - flexible, easy to configure
2. **TransactionBuilder enforces accounting rules** - rigid, correct
3. **SettlementDetector is institution-specific** - Fidelity vs Coinbase patterns
4. **AssetRegistry ensures FBTC ≠ BTC** - one source of truth

## Processing Flow in UI

```
User uploads CSV → Data Uploads panel
User selects Parse Plan version → Parse Rules panel
User clicks "Process" →
  1. CSV parsed
  2. Transforms applied (ParsePlan)
  3. Rows grouped (SettlementDetector)
  4. Transactions created (TransactionBuilder)
  5. Assets resolved (AssetRegistry)
  6. Positions updated (PositionCalculator)
```

Result: **Transactions with JournalEntries** stored in database

## Current vs Target

**Current (Legacy ParseEngine):**
- Creates single-entry Transaction with amount/quantity/assetId as strings
- No journal entries
- No asset registry lookup
- Basic validation

**Target (TransactionBuilder - Already Built!):**
- Creates proper double-entry Transaction
- Multiple JournalEntry legs
- AssetRegistry resolution (FBTC ≠ BTC)
- Balance validation (debits == credits)

We have the target structure implemented! We just need to wire it into the UI workflow.
