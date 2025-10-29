# Transaction Review & Refinement System

## Overview

The review system enables **iterative refinement** of AI-categorized transactions instead of one-shot generation. This provides:

- **100% row coverage** via automatic gap filling
- **Quality improvements** by reviewing and fixing existing transactions
- **Incremental updates** when new data is uploaded
- **Explainable changes** with AI-generated reasons for each delta

---

## Architecture

```
CSV Data → Initial Categorization → 98% coverage → Gap Detection → Review → Deltas → 100% coverage
                                                                      ↓
                                                            (create/update/delete)
```

### Core Components

1. **ReviewSession** - Tracks a review operation
2. **TransactionDelta** - Describes a change (action + reason + transaction data)
3. **TransactionReviewService** - Orchestrates reviews and applies deltas
4. **IncrementalUpdateService** - Handles new CSV data uploads

---

## Usage Patterns

### 1. Automatic Gap Filling (Built-in)

**When:** After initial categorization completes
**What:** Automatically detects and fills any uncovered rows

This happens automatically in `DirectCategorizationService.categorizeRows()` starting at line 381.

**Output:**
```
═══════════════════════════════════════
Final coverage: 456/465 rows
Missing rows: 9
═══════════════════════════════════════

🔍 Detecting gaps in coverage...
   Found 9 uncovered rows: #148, #219, #220, ...

🔄 Starting gap-filling review...
📋 Starting review for May 1, 2024 → Oct 27, 2025
   Found 15 CSV rows in range (expanded context)
   Found 350 existing transactions in range
   Uncovered rows in range: 9

📝 Parsing deltas from response
✓ Found 5 deltas in response
  ✓ Delta #0: create - Rows #148, #149 form a sell transaction...

📝 Applying 5 deltas
  ✅ Created transaction: Sell FXAIX covering rows #148, #149
  ✅ Created transaction: Buy VOO covering rows #219, #220
  ...

✅ Gap filling complete:
   Created: 5 transactions
   Updated: 0 transactions
   Deleted: 0 transactions
   Final coverage: 465/465 rows
```

---

### 2. Manual Gap Filling

**When:** You have an existing session with gaps
**Use Case:** Previous runs stopped early, or you want to fix gaps manually

```swift
let reviewService = TransactionReviewService(modelContext: modelContext)

// Option A: Fill all gaps automatically
let reviewSession = try await reviewService.fillGaps(
    in: existingSession,
    csvRows: allCSVRows
)

// Option B: Review specific uncovered rows
let gaps = reviewService.findGaps(in: existingSession)
print("Uncovered rows: \(gaps.uncoveredRows)")

let reviewSession = try await reviewService.reviewUncoveredRows(
    session: existingSession,
    csvRows: allCSVRows,
    uncoveredRowNumbers: gaps.uncoveredRows
)

try reviewService.applyDeltas(from: reviewSession, to: existingSession)
```

---

### 3. Incremental Update (New Data Upload)

**When:** You upload a fresh CSV export with new transactions
**Use Case:** Monthly data refresh, adding latest transactions

```swift
let incrementalService = IncrementalUpdateService(modelContext: modelContext)

// Upload new CSV (e.g., October's data when you previously had through September)
let result = try await incrementalService.appendNewData(
    newCSVRows: freshCSVRows,
    headers: headers,
    to: existingSession
)

print("New rows found: \(result.newRowsFound)")
print("Transactions created: \(result.transactionsCreated)")
```

**How it works:**
1. Computes SHA256 hash for each new row
2. Compares against `session.sourceRowHashes`
3. Filters to truly new rows (not duplicates)
4. Assigns sequential global row numbers (#466, #467, ...)
5. Uses review service in gap-filling mode
6. Applies deltas to add new transactions
7. Updates session metadata (totalSourceRows, sourceRowHashes)

**Example scenario:**
```
October 28: Upload Fidelity_Jan_Oct_2025.csv → 465 rows, 356 transactions
November 30: Upload Fidelity_Jan_Nov_2025.csv → 520 rows
   - System detects 55 new rows (520 - 465)
   - Assigns them #466-#520
   - Creates ~30 new transactions
   - Final: 386 transactions covering 520 rows
```

---

### 4. Quality Review (Future)

**When:** You want to verify existing transactions are correct
**Use Case:** Audit, fixing AI mistakes, refining categories

```swift
// Review a specific date range
let reviewSession = try await reviewService.reviewDateRange(
    session: existingSession,
    csvRows: allCSVRows,
    startDate: Date(year: 2024, month: 5, day: 1),
    endDate: Date(year: 2024, month: 5, day: 31),
    mode: .qualityCheck  // or .fullReview
)

// Preview deltas before applying
for delta in reviewSession.deltas {
    print("\(delta.action): \(delta.reason)")
}

// Apply if approved
try reviewService.applyDeltas(from: reviewSession, to: existingSession)
```

---

## Data Models

### ReviewSession

Tracks a review operation:
- **Scope**: date range, row numbers
- **Results**: deltas created, transactions changed
- **Audit**: AI model, tokens used, duration

### TransactionDelta

Describes a single change:
```swift
{
  action: .create | .update | .delete,
  reason: "AI explanation",
  originalTransactionId: UUID?,  // For update/delete
  newTransactionData: Data?      // For create/update
}
```

### ReviewMode

```swift
enum ReviewMode {
    case gapFilling    // Create transactions for uncovered rows
    case qualityCheck  // Verify/fix existing transactions
    case fullReview    // Both gap filling and quality check
    case targeted      // Address specific flagged issues
}
```

---

## Coverage Analysis

### Check Coverage

```swift
let session: CategorizationSession = ...

// Get coverage percentage
print("Coverage: \(session.coveragePercentage * 100)%")

// Find uncovered rows
let uncovered = session.findUncoveredRows()
print("Missing rows: \(uncovered)")

// Build detailed index
let index = session.buildCoverageIndex()
for (rowNum, coverage) in index {
    print("Row #\(rowNum): covered by \(coverage.transactionIds.count) transaction(s)")
}

// Find quality issues
let unbalanced = session.findUnbalancedTransactions()
print("Unbalanced transactions: \(unbalanced.count)")
```

---

## Current Status

### ✅ Implemented (Phase 1 & 2)

- ReviewSession and TransactionDelta models
- Coverage analysis helpers
- TransactionReviewService with gap filling
- IncrementalUpdateService for new data
- Automatic gap filling in main categorization flow
- Delta parsing and application

### 🚧 To Be Implemented

- **UI Integration:**
  - "Fill Gaps" button in Parse Studio
  - "Upload New Data" incremental flow
  - Delta preview before applying
  - Review history view

- **Quality Check Mode:**
  - Review existing transactions for errors
  - Suggest improvements
  - Fix unbalanced transactions

- **Advanced Features:**
  - Tags on transactions
  - Custom categorization fields
  - Bulk operations (tag all dividends, etc.)
  - Audit trail visualization

---

## How to Use Right Now

### Option 1: Fresh Run (Recommended)
1. Clear existing session in Parse Studio
2. Run "AI Direct Categorization"
3. System will automatically achieve 100% coverage via gap filling

### Option 2: Fill Gaps in Existing Session
Add this temporary function to test:

```swift
// In ParsePlanVersionsPanel or similar
func fillGapsInCurrentSession() {
    Task {
        guard let session = selectedCategorizationSession else { return }

        // Get all CSV rows (from import batches)
        let allRows = getAllCSVRows()  // Your existing method

        let reviewService = TransactionReviewService(modelContext: modelContext)

        do {
            let reviewSession = try await reviewService.fillGaps(
                in: session,
                csvRows: allRows
            )

            print("✅ Filled gaps: created \(reviewSession.transactionsCreated) transactions")
        } catch {
            print("❌ Gap filling failed: \(error)")
        }
    }
}
```

### Option 3: Incremental Update (New CSV)

```swift
func uploadNewData(_ newCSVFile: URL) {
    Task {
        guard let session = selectedCategorizationSession else { return }

        // Parse new CSV
        let parser = CSVParser()
        let csvData = try parser.parse(String(contentsOf: newCSVFile))
        let headers = csvData.headers

        // Convert to dictionary format
        let newRows = csvData.rows.map { row -> [String: String] in
            var dict: [String: String] = [:]
            for (index, header) in headers.enumerated() {
                if index < row.count {
                    dict[header] = row[index]
                }
            }
            return dict
        }

        let incrementalService = IncrementalUpdateService(modelContext: modelContext)

        let result = try await incrementalService.appendNewData(
            newCSVRows: newRows,
            headers: headers,
            to: session
        )

        print("✅ Added \(result.newRowsFound) new rows, created \(result.transactionsCreated) transactions")
    }
}
```

---

## Technical Details

### Row Hashing
Rows are hashed using SHA256 of concatenated values:
```swift
hash = SHA256(header1Value + "|" + header2Value + "|" + ...)
```

This enables deduplication and incremental update detection.

### Context Expansion
When reviewing gaps, the system expands context by ±2 days to give AI better understanding of surrounding transactions.

### Delta Application
- **Create**: Insert new transaction
- **Update**: Delete old + insert new (safer than in-place modification)
- **Delete**: Remove transaction and orphan its rows

### Error Handling
If gap filling fails, the main categorization continues with partial coverage rather than failing completely.

---

## Next Steps

1. **Test automatic gap filling** with a fresh run
2. **Add UI buttons** for manual gap filling
3. **Test incremental update** by uploading new CSV
4. **Implement quality check mode** for reviewing existing transactions
