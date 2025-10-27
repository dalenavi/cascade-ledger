# Transaction Deduplication Design

## Problem Statement

**Current behavior:**
- Same CSV imported multiple times → Duplicate transactions
- Positions accumulate incorrectly (100 shares + 100 shares = 200, should be 100)
- Parse plans multiply instead of being reused
- No prevention, only flagging

## Two-Level Deduplication Strategy

### Level 1: File-Level Detection

**At import time, before processing:**

```
User uploads: History_Oct.csv (SHA256: abc123...)

System checks:
1. Is this file hash already imported?
   → YES: Found import from Oct 26, 2025

2. Prompt user:
   ┌────────────────────────────────────────────┐
   │ This file was already imported             │
   │                                            │
   │ Original import: Oct 26, 2025              │
   │ Transactions: 411                          │
   │                                            │
   │ Options:                                   │
   │ [Re-import] Replace old data with new      │
   │ [Skip]      Cancel this import             │
   │ [Force]     Import anyway (creates dupes)  │
   └────────────────────────────────────────────┘
```

**Decision point:**
- **Re-import:** Delete old batch, import fresh
- **Skip:** Abort upload
- **Force:** Continue (for overlapping but non-identical files)

### Level 2: Transaction-Level Deduplication

**During import, for each transaction:**

```
Processing row 42: Oct 15, DIVIDEND AAPL, $25.50

1. Calculate transaction hash:
   SHA256(date + accountId + assetId + type + amount + description)
   → hash: def456...

2. Check existing ledger entries:
   Query: LedgerEntry where transactionHash == "def456..."

3. If found:
   a. Skip creation
   b. Log: "Skipped duplicate: DIVIDEND AAPL"
   c. Increment skippedCount

4. If not found:
   a. Create ledger entry
   b. Set hash
   c. Increment successCount
```

**Import result:**
```
Import Complete:
✓ 320 new transactions imported
⊘ 91 duplicates skipped
Total processed: 411
```

## Deduplication Timing

### Option A: Pre-Import Check (Recommended)

**Before any processing:**
1. Calculate file hash
2. Look up in RawFile table
3. If exists → Offer re-import or skip
4. User decides

**Advantages:**
- Fast (no processing wasted)
- Clear user choice
- No duplicate data created

### Option B: During Import (Fallback)

**While creating ledger entries:**
1. Calculate transaction hash
2. Check if exists
3. Skip if duplicate

**Advantages:**
- Handles partial overlaps (Nov 1-15 vs Nov 10-30)
- Robust against edge cases

### Option C: Hybrid (Best)

**Combine both:**
1. File-level check → Offer re-import
2. If user proceeds, transaction-level dedup anyway
3. Report skipped duplicates

## Transaction Hash Refinement

**Current hash:**
```swift
SHA256(date + accountId + assetId + type + amount + description)
```

**Issues:**
- Description might vary slightly
- Amount might have rounding differences
- Type might be corrected by user

**Improved hash:**
```swift
SHA256(
    date (day precision) +
    accountId +
    assetId +
    roundedAmount (to cents) +
    normalizedDescription (trimmed, lowercase)
)
```

**Exclude from hash:**
- User-assigned fields (category, tags, notes)
- Transaction type (might be corrected)
- Quantity (might be missing in old data)

**Why:** Allow correcting type/category without breaking dedup

## Fuzzy Matching for Near-Duplicates

**Beyond exact hash matches, detect near-duplicates:**

```
Transaction A: Oct 15, DIVIDEND, AAPL, $25.50
Transaction B: Oct 15, DIVIDEND, AAPL, $25.51 (off by 1 cent)

Fuzzy match criteria:
- Same date (±1 day tolerance)
- Same account
- Same asset
- Amount within 1% or $0.10
- Description Levenshtein distance < 3

Mark as "Possible duplicate" for review
```

## UI Design

### Import Flow with Dedup

```
1. Drop CSV file

2. System checks file hash:
   ┌────────────────────────────────────────┐
   │ ⚠️ File Already Imported               │
   │                                        │
   │ This file: History_Oct.csv             │
   │ Previously imported: Oct 26, 2025      │
   │ Contains: 411 transactions             │
   │                                        │
   │ Imported with: Parse Plan v1           │
   │ Current plan: Parse Plan v2 (updated)  │
   │                                        │
   │ What would you like to do?             │
   │                                        │
   │ [Re-import with v2]  Recommended       │
   │   Delete old data, import with new     │
   │   parse plan (adds quantity data)      │
   │                                        │
   │ [Skip Import]                          │
   │   Keep existing data, cancel upload    │
   │                                        │
   │ [Import Anyway]  Advanced              │
   │   Create duplicates (for testing/debug)│
   └────────────────────────────────────────┘
```

### Import Results

```
Import Complete: History_Oct.csv

✓ 320 new transactions created
⊘ 91 exact duplicates skipped
⚠️ 5 possible duplicates detected

[View Details] [Go to Transactions]
```

### Duplicate Review View

```
Possible Duplicates (5):

┌────────────────────────────────────────┐
│ Oct 15 - DIVIDEND AAPL - $25.50        │
│ Oct 15 - DIVIDEND AAPL - $25.51        │
│ Difference: $0.01                      │
│ [Keep Both] [Delete Newer] [Merge]     │
└────────────────────────────────────────┘
```

## Implementation Questions

**1. File-level dedup behavior:**
- Auto-skip if exact file match?
- Always prompt user?
- **Recommendation:** Always prompt with re-import option

**2. Transaction-level strictness:**
- Skip all exact hash matches?
- Warn on fuzzy matches?
- **Recommendation:** Skip exact, flag fuzzy for review

**3. Re-import behavior:**
- Delete old batch entirely?
- Or keep batch but replace entries?
- **Recommendation:** Keep batch metadata, replace entries

**4. Partial overlaps:**
- CSV has Nov 1-30, existing has Nov 15-30
- Import first half, skip second half?
- **Recommendation:** Transaction-level dedup handles this

**5. Parse plan versioning:**
- Force re-import if parse plan version changed?
- Suggest re-import?
- **Recommendation:** Show version difference, suggest re-import

## Proposed Implementation

### Phase 1: File-Level Check
- Check RawFile.sha256Hash on upload
- Prompt user with re-import option
- Show parse plan version difference

### Phase 2: Transaction-Level Dedup
- Before `modelContext.insert(ledgerEntry)`
- Check transaction hash exists
- Skip if duplicate, increment counter

### Phase 3: Fuzzy Detection (Future)
- After import completes
- Scan for near-duplicates
- Present review UI

### Phase 4: Batch Operations (Future)
- "Re-import All Old Batches"
- Bulk duplicate cleanup
- Merge duplicate detection

## Questions for You

**1. When you upload same file twice:**
- Prefer: Auto-skip with notification?
- Or: Prompt with re-import option?

**2. Overlapping date ranges (different files):**
- Prevent duplicates automatically?
- Or warn and let you decide?

**3. Parse plan version changes:**
- Auto-suggest re-importing old data?
- Or manual re-import only?

**4. Current duplicates:**
- Want tool to find and delete them?
- Or leave existing, prevent future?

Let me know your preferences and I'll implement!
