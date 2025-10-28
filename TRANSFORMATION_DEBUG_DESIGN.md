# Transformation Stage Visualization & Debugging

## The Core Problem

How do you debug a 4-stage data pipeline that transforms CSV rows → Transactions?

```
CSV Rows → Transformed Dicts → Grouped Rows → Transactions with JournalEntries
 (244)         (244)              (122 groups)        (122 objects)
```

## Current 5-Column Layout

```
┌──────────┬─────────┬────────────┬──────────────┬──────────────┐
│ Data     │ Raw CSV │ Parse      │ Intermediate │ Transactions │
│ Uploads  │ (Stage0)│ Rules      │ (Stage 2)    │ (Stage 4)    │
│          │         │ Versions   │              │              │
│ ☑ File1  │ Row #   │ ☑ v2       │ Transformed  │ Transaction  │
│ ☑ File2  │ Headers │ v1         │ Dictionaries │ + Journal    │
│          │ 244rows │            │              │ Entries      │
└──────────┴─────────┴────────────┴──────────────┴──────────────┘
```

## Debugging Strategies

### Option 1: Hover Trace (Interactive Debugging)
Hover over a row in any column → highlights its path through all stages

```
Raw CSV                  Grouped              Transaction
Row 42: "YOU BOUGHT..." ─┐
Row 43: ""              ─┴─→ Group #21 ─→  Txn #21: Buy FXAIX
                                             DR: Asset +999.50
                                             CR: Cash  -999.50
```

**Implementation:**
- Add `@State var tracedRowId: Int?`
- Each row gets hover handler: `.onHover { tracedRowId = rowIndex }`
- Grouped/Transaction views highlight if they contain tracedRowId

### Option 2: Expandable Transaction (Drill-Down)
Each transaction card can expand to show source

```
▼ Transaction #21: Buy FXAIX - $999.50 ✓ Balanced

  Source Rows:
  ┌─────────────────────────────────────────┐
  │ Row 42: "12/20/2024, YOU BOUGHT, FXAIX" │
  │ Row 43: "12/20/2024, , , 0"             │ ← Settlement row
  └─────────────────────────────────────────┘

  Transformed Data:
    date: 2024-12-20
    amount: -999.50
    assetId: "FXAIX"
    quantity: 5.123
    metadata.action: "YOU BOUGHT"

  Journal Entries:
    DR: Asset FXAIX   +999.50  (5.123 shares)
    CR: Cash USD      -999.50

  Validation:
    ✓ Balanced (debits == credits)
    ✓ Asset found in registry
    ✓ Both legs have assets linked
```

### Option 3: Row Grouping Visualization (Settlement Stage)
Show how settlement detector grouped rows

```
Grouping Stage (Fidelity Settlement Detection)
┌───────────────────────────────────────────────┐
│ Group 1: Buy Transaction (2 rows)            │
│   ├─ Row 42: YOU BOUGHT FXAIX (primary)      │
│   └─ Row 43: [settlement, no action]         │
│                                               │
│ Group 2: Dividend (1 row)                    │
│   └─ Row 44: DIVIDEND RECEIVED SPY           │
│                                               │
│ Group 3: Buy Transaction (2 rows)            │
│   ├─ Row 45: YOU BOUGHT NVDA                 │
│   └─ Row 46: [settlement]                    │
└───────────────────────────────────────────────┘
```

### Option 4: Pipeline Diagram (Educational)
Show the transformation as a flowchart with validation

```
┌─────────────┐
│ 244 CSV     │
│ Rows        │
└──────┬──────┘
       │ Parse Plan v2: field mappings, date format
       ↓
┌─────────────┐
│ 244 Trans-  │ ✓ All dates parsed
│ formed Rows │ ✓ All amounts valid
└──────┬──────┘   ⚠ 2 rows missing assetId
       │ Settlement Detector: Fidelity pattern
       ↓
┌─────────────┐
│ 122 Row     │ ✓ All groups have primary row
│ Groups      │ ✓ 121 have settlement rows
└──────┬──────┘
       │ Transaction Builder: double-entry rules
       ↓
┌─────────────┐
│ 122 Trans-  │ ✓ All balanced
│ actions     │ ✓ All assets linked
└─────────────┘   → 244 Journal Entries
```

## Recommended Hybrid Approach

### Primary View: Transaction-Centric (Option 2)
- Default: Collapsed list of transactions
- Click to expand → see full lineage
- Good for: "Why did this transaction get created?"

### Secondary View: Grouping Inspector (Option 3)
- Toggle: `[Transactions] [Grouping Debug]`
- Shows how rows were grouped
- Highlights which rule matched
- Good for: "Why are these rows grouped together?"

### Hover Enhancement (Option 1)
- Add to both views
- Lightweight visual feedback
- Good for: Quick exploration

## Implementation Plan

1. **Add to TransactionPreviewCard:**
   - Disclosure group to show/hide details
   - Source rows section
   - Transformed data section
   - Validation results section

2. **Add Grouping Debug View:**
   - New tab/toggle in Transactions panel
   - Visual tree structure
   - Color-code by settlement pattern matched

3. **Add Hover Tracing:**
   - Track `@State var hoveredRowIndex: Int?` in workspace
   - Pass to all panels
   - Highlight matching elements

## Key Insight for Your Question

**The transformation is fundamentally:**

```swift
func transform(
  rows: [CSVRow],           // Union of all selected uploads
  parsePlan: ParsePlanVersion,  // Versioned transformation rules
  institution: Institution      // Settlement pattern
) -> [Transaction] {

  // Declarative mapping at each stage
  let typed = rows.map { applySchema($0, parsePlan.schema) }
  let grouped = detectSettlements(typed, institution.pattern)
  let transactions = grouped.map { buildTransaction($0, accountingRules) }

  return transactions
}
```

It's a **declarative, versioned, pure transformation** - same inputs always produce same outputs.

The UI should make each stage **inspectable and debuggable** so you can see:
- Where did this value come from?
- Why were these rows grouped?
- Which accounting rule fired?
- Does the transaction balance?

This is essentially building a **data lineage and transformation debugger**.

Want me to implement the expandable transaction cards first, or the grouping debug view?
