# Double-Entry Bookkeeping - Quick Start Guide

## What Is This?

The double-entry bookkeeping system fixes the USD calculation bug by properly grouping Fidelity's dual-row CSV structure into balanced transactions.

**The Problem:**
- Your USD balance shows $499k (single-entry mode)
- It should be $144k (from Cash Balance column)
- Settlement rows are being double-counted

**The Solution:**
- Re-process imports with double-entry bookkeeping
- Settlement rows grouped with their parent transactions
- Accurate USD calculation

## Prerequisites

1. **API Key Setup:**
   - Go to **Settings**
   - Enter your Claude API key (starts with `sk-ant-`)
   - Click **Save** (no password prompt!)
   - API key is now stored in UserDefaults

2. **Clean Start:**
   - Go to **Accounts**
   - Click **Clear All Imports** for your Fidelity account
   - This removes both single-entry and double-entry data

## Step-by-Step Workflow

### Step 1: Generate Correct Parse Plan

1. Go to **Parse Studio**
2. Upload your Fidelity CSV file
3. Click **"Ask Agent"** to open chat
4. Agent will automatically:
   - Analyze CSV structure using `get_csv_data` tool
   - Create a parse plan
   - Call `get_transformed_data` to verify output
   - Iterate if needed to fix field mappings

5. **Verify the parse plan** has these critical mappings:
   - `Action` → `metadata.action` (NOT transactionType!)
   - `Symbol` → `assetId`
   - `Quantity` → `quantity` (numeric field)
   - `Amount ($)` → `amount`
   - `Type` → `metadata.account_type`

6. **Commit the parse plan** when satisfied

7. **Execute Import** (creates single-entry data - needed for compatibility)

### Step 2: Re-Process with Double-Entry

1. Go to **"Testing" → "Double-Entry Test"**
2. Click **"Import CSV"** button
3. **Step 1:** Select "fidelity investment" account
4. **Step 2:** Select the import batch you just created (244 rows)
5. Click **"Re-process with Double-Entry"**

### Step 3: Verify Results

In the Double-Entry Test view, you should see:

**Transaction Count:**
- ~100-120 transactions (not 235)
- Each CSV row pair (asset + settlement) becomes one transaction

**USD Balance:**
- Should show **~$144,218** (matching Cash Balance column)
- NOT $48k or $499k

**Transaction Structure:**
- Click any transaction to expand
- See journal entries (debits and credits)
- Verify "Balanced" indicator shows green checkmark
- Each transaction shows net cash impact

## What Good Output Looks Like

### Example Transaction: Stock Purchase
```
Transaction: "YOU BOUGHT SPY"
Date: Apr 23, 2024
Net Cash: -$2,019.24

Journal Entries:
  Debit  Asset:SPY  $2,019.24  (4 shares)
  Credit Cash:USD   $2,019.24

Balance Check: ✓ Balanced
Debits: $2,019.24
Credits: $2,019.24
```

### Example Transaction: Dividend
```
Transaction: "DIVIDEND SPY"
Date: May 1, 2024
Net Cash: +$52,264

Journal Entries:
  Debit  Cash:USD           $52,264
  Credit Income:Dividend    $52,264

Balance Check: ✓ Balanced
```

## Troubleshooting

### "No parse plan found for this account"
- Go to Parse Studio first
- Create and commit a parse plan
- Parse plan is now stored on the ImportBatch

### "Many buy/sell transactions failing with invalidQuantity"
- Parse plan has incorrect field mappings
- Regenerate parse plan using enhanced agent
- Verify Quantity field is mapped to `quantity` (not combined with other fields)

### "USD balance still wrong"
- Check that parse plan maps Action → metadata.action
- Settlement row detection requires this field
- Use Parse Plan Debug view to inspect mappings

### "All rows becoming separate transactions (no grouping)"
- Parse plan isn't preserving metadata.action
- TransactionBuilder can't detect settlement rows without it
- Regenerate parse plan with enhanced agent

## Current Limitations

1. **Views not yet migrated:**
   - PortfolioValue, Positions, TotalWealth still use single-entry
   - Use Double-Entry Test view to see correct data
   - Full migration coming soon

2. **Parse plan regeneration needed:**
   - Old parse plans have incorrect mappings
   - Enhanced agent now generates correct ones
   - One-time regeneration required

3. **Migration service incomplete:**
   - Can't automatically convert all existing LedgerEntry data
   - Re-import recommended for clean slate

## Expected Results

Using `sample_data/fidelity_sample_transactions.csv`:
- **Rows:** 244 (including disclaimers)
- **Valid rows:** 235 (after filtering)
- **Transactions:** ~30 (settlement rows grouped)
- **Final Cash Balance:** $144,218.26
- **Settlement rows:** Properly grouped, not counted as USD
- **All transactions:** Balanced (debits = credits)

## Technical Details

### How Settlement Row Grouping Works

**TransactionBuilder.groupRows():**
1. Iterate through transformed rows
2. Detect settlement: `metadata.action` empty + `assetId` empty + `quantity` = 0
3. If non-settlement: Start new group
4. If settlement: Add to current group
5. Result: Groups of related CSV rows

**Settlement Row Pattern:**
```
CSV Row 1: Action="YOU BOUGHT", Symbol="SPY", Quantity=4, Amount=-2019.24
CSV Row 2: Action="", Symbol="", Quantity=0, Amount=2019.24

Becomes:
Transaction "YOU BOUGHT SPY"
  ├─ Asset row used for primary data
  └─ Settlement row filtered out
```

### USD Calculation

**Single-Entry (Wrong):**
```swift
usdBalance = entries.filter { $0.assetId == nil }.reduce(0) { $0 + $1.amount }
// Counts both asset and settlement rows
// Result: $499k
```

**Double-Entry (Correct):**
```swift
usdBalance = transactions
    .flatMap { $0.journalEntries }
    .filter { $0.accountType == .cash && $0.accountName == "USD" }
    .reduce(0) { $0 + (debit ?? 0) - (credit ?? 0) }
// Only counts actual cash movements
// Result: $144k ✓
```

## Files Reference

**Core Models:**
- `cascade-ledger/Models/Transaction.swift`
- `cascade-ledger/Models/JournalEntry.swift`

**Import Engine:**
- `cascade-ledger/ParseEngine/TransactionBuilder.swift`
- `cascade-ledger/ParseEngine/ParseEngineV2.swift`

**Views:**
- `cascade-ledger/Views/DoubleEntryTestView.swift`
- `cascade-ledger/Views/ParsePlanDebugView.swift`

**Services:**
- `cascade-ledger/Services/ParseAgentService.swift` (tool use)
- `cascade-ledger/Services/KeychainService.swift` (UserDefaults storage)

**Design Docs:**
- `openspec/changes/add-parse-studio/design-double-entry.md`
- `openspec/changes/add-parse-studio/design-transaction-grouping.md`

## Success Criteria

After following this guide, you should have:
- ✅ API key saved without password prompts
- ✅ Parse plan with correct field mappings
- ✅ Double-entry transactions created
- ✅ USD balance = $144,218 (not $499k)
- ✅ All transactions balanced (debits = credits)
- ✅ Settlement rows properly grouped
