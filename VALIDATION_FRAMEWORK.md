# Accounting Validation Framework

## Core Principle

**Accounting is deterministic** - given source data, there's a correct answer. Validations ensure we found it.

## Critical Validations

### 1. Row Coverage (Completeness)
**Rule:** Every source CSV row must be accounted for exactly once.

```
Validation:
- Count source rows: 474
- Sum of all transaction.sourceRowNumbers: Should = 474
- Set(transaction.sourceRowNumbers): No duplicates
- Missing rows: []
- Duplicate rows: []

Pass: ✓ All 474 rows accounted for exactly once
Fail: ⚠️ Row #42 appears in 2 transactions
Fail: ⚠️ Rows #100-105 not used in any transaction
```

**Why:** Ensures no data loss, no double-counting.

### 2. Transaction Balance (Accounting Integrity)
**Rule:** For each transaction, Σ debits = Σ credits (within $0.01 rounding tolerance)

```
Validation per transaction:
- totalDebits: $999.50
- totalCredits: $999.50
- difference: $0.00

Pass: ✓ 14/14 transactions balanced
Fail: ⚠️ Transaction #5: Buy NVDA - Debits $6000, Credits $5999.99 (diff: $0.01)
```

**Why:** Fundamental accounting equation. Unbalanced = data error.

### 3. Running Cash Balance (External Reconciliation)
**Rule:** Calculated cash position should match CSV "Cash Balance ($)" column.

```
For each transaction chronologically:
  expectedBalance = CSV row "Cash Balance ($)"
  calculatedBalance = previousBalance + transaction.netCashImpact

Compare:
  Row #1: Expected $110,225.35, Calculated $110,225.35 ✓
  Row #2: Expected $113,460.36, Calculated $113,460.36 ✓
  ...
  Row #42: Expected $95,123.45, Calculated $95,200.00 ⚠️ Diff: $76.55

Pass: ✓ All balances match
Fail: ⚠️ 3 transactions have balance discrepancies (avg diff: $12.34)
```

**Why:** Validates our categorization against Fidelity's own calculations. If we're off, we misunderstood something.

### 4. Asset Position Tracking (Quantity Integrity)
**Rule:** For each asset, cumulative quantities should make sense.

```
FXAIX position over time:
  Start: 0 shares
  Row #5: Buy 61.125 shares → 61.125
  Row #8: Dividend reinvest 2.071 → 63.196
  Row #12: Sell 1.438 → 61.758
  Row #20: Buy 5.123 → 66.881
  End: 66.881 shares

Validation:
  - No negative quantities (can't own -5 shares)
  - Sells don't exceed holdings
  - Running total tracks

Pass: ✓ All assets have valid position history
Fail: ⚠️ NVDA: Row #42 sells 50 shares but only 46 owned
```

**Why:** Catches impossible trades (selling what you don't own).

### 5. Settlement Row Validation (Grouping Correctness)
**Rule:** Settlement rows must be paired with primary rows, amounts should net.

```
For each settlement row (Action="", Symbol="", Qty=0):
  Row #2: Amount = $283.06 (positive, settlement)
  Paired with Row #1: Amount = -$283.06 (negative, primary)
  Net: $0.00 ✓

Pass: ✓ All 120 settlement rows properly paired
Fail: ⚠️ Row #87 (settlement) not grouped with any primary row
Fail: ⚠️ Rows #44-45: Amounts don't net to zero ($0.50 difference)
```

**Why:** Validates settlement detection logic. Fidelity's dual-row pattern must be understood correctly.

### 6. Asset Registry Integrity
**Rule:** All asset symbols must exist in registry and be used consistently.

```
Validation:
- All symbols in JournalEntry.assetSymbol exist in AssetRegistry
- Same symbol always maps to same Asset.id
- FBTC != BTC (different Asset records)

Pass: ✓ All 15 unique assets registered
Fail: ⚠️ JournalEntry references "BTC" but Asset registry has no BTC
Fail: ⚠️ Transaction #12 and #25 both reference "FBTC" but different Asset.id
```

**Why:** Ensures FBTC != BTC rule is enforced. Symbol aliasing would be catastrophic for pricing.

### 7. Date Integrity
**Rule:** Transactions should be chronologically sound.

```
Validation:
- All dates parseable
- No future dates (> today)
- Chronological order in source
- Date gaps analysis

Pass: ✓ Dates range from 2024-01-02 to 2024-12-31
Warn: ⚠️ 14-day gap between 2024-03-15 and 2024-03-29 (missing data?)
Fail: ❌ Transaction on 2025-10-28 (future date)
```

**Why:** Catches data corruption, missing imports.

## Implementation Design

### ValidationService

```swift
actor ValidationService {
    func validate(
        session: CategorizationSession,
        sourceRows: [[String: String]],
        csvData: CSVData
    ) async -> ValidationReport

    struct ValidationReport {
        let rowCoverage: RowCoverageReport
        let transactionBalance: TransactionBalanceReport
        let runningBalance: RunningBalanceReport
        let assetPositions: AssetPositionReport
        let settlementPairing: SettlementReport
        let assetRegistry: AssetRegistryReport
        let dateIntegrity: DateIntegrityReport

        var overallStatus: Status  // pass, warning, fail
        var criticalIssues: [Issue]
        var warnings: [Issue]
    }
}
```

### UI Integration

**Option A: Validation Badge in Session Card**
```
🧠 Categorization Oct 27, 2PM
20 rows → 14 txns ✓ Validated
```

**Option B: Dedicated Validation Panel**
```
[Transactions] [Validation] [Agent View]
```

**Option C: Inline Validation (My Recommendation)**

Show validation results in the AI Categorization panel:

```
┌─────────────────────────────────────────┐
│ Validation Results                      │
├─────────────────────────────────────────┤
│ ✓ Row Coverage: 20/20 rows accounted    │
│ ✓ Balance: 14/14 transactions balanced  │
│ ✓ Cash Balance: Matches CSV             │
│ ✓ Assets: All symbols in registry       │
│ ⚠️ Settlement: 2 unpaired settlements    │
└─────────────────────────────────────────┘
```

**Option D: Agent View Shows Validation**

The "Agent View" tab already exists - make it show validation context:

```
[Transactions] [Grouping Debug] [Agent View + Validation]

Agent View content:
- Grouping statistics
- Pattern analysis
- VALIDATION REPORT ← New!
- Suggested fixes
```

## My Recommendation

**Implement as part of Agent View** with automatic validation on every categorization.

Workflow:
1. AI categorizes → Creates session
2. **Auto-run validation** → Generate report
3. Store report in session
4. Agent View tab shows validation results
5. If issues found → Agent can re-iterate

This gives the agent (and you) immediate feedback on categorization quality.

Want me to implement this validation framework?
