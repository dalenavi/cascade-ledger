# Balance Reconciliation System - Design

## Architecture Overview

```
CSV Balance Data → Balance Checkpoints → Discrepancy Detection → AI Investigation → Proposed Fixes → User Approval → Apply Deltas → Re-validate
                        ↓                         ↓                      ↓                                               ↓
                   (Ground Truth)        (Problems Found)      (Evidence + Reasoning)                        (Iterative Until Reconciled)
```

## Core Components

### 1. BalanceCheckpoint
**Purpose:** Compare CSV balance to calculated balance at specific points in time

```swift
@Model
class BalanceCheckpoint {
    var id: UUID
    var date: Date
    var rowNumber: Int

    // Ground truth
    var csvBalance: Decimal
    var csvBalanceField: String  // Original CSV value

    // Our calculation
    var calculatedBalance: Decimal

    // Analysis
    var discrepancy: Decimal { csvBalance - calculatedBalance }
    var hasDiscrepancy: Bool { abs(discrepancy) > 0.01 }
    var severity: DiscrepancySeverity

    // Context
    var transactionsSinceLastCheckpoint: [Transaction]
    var categorizationSession: CategorizationSession
}
```

### 2. Discrepancy
**Purpose:** Represents a problem that needs investigation

```swift
@Model
class Discrepancy {
    enum DiscrepancyType {
        case balanceMismatch      // Calculated ≠ CSV
        case unbalancedTxn        // DR ≠ CR
        case missingTransaction   // Pattern suggests missing data
        case incorrectAmount      // Amount doesn't match CSV
    }

    enum DiscrepancySeverity {
        case critical   // >$1000 or breaks accounting
        case high       // $100-1000
        case medium     // $10-100
        case low        // $0.01-10
    }

    var id: UUID
    var type: DiscrepancyType
    var severity: DiscrepancySeverity

    // Location
    var dateRange: (start: Date, end: Date)
    var affectedRowNumbers: [Int]
    var affectedTransactions: [Transaction]
    var relatedCheckpoint: BalanceCheckpoint?

    // Problem description
    var summary: String
    var evidence: String
    var expectedValue: Decimal?
    var actualValue: Decimal?
    var delta: Decimal?

    // Resolution
    var isResolved: Bool
    var investigations: [Investigation]
}
```

### 3. Investigation
**Purpose:** AI's research and analysis of a discrepancy

```swift
@Model
class Investigation {
    var id: UUID
    var createdAt: Date
    var discrepancy: Discrepancy

    // AI's analysis
    var hypothesis: String
    var evidenceAnalysis: String
    var uncertainties: [String]
    var needsMoreData: Bool

    // Proposed solutions
    var proposedFixes: [ProposedFix]

    // Metadata
    var aiModel: String
    var inputTokens: Int
    var outputTokens: Int
    var durationSeconds: Double

    // Status
    var wasApplied: Bool
    var appliedFixIndex: Int?
}
```

### 4. ProposedFix
**Purpose:** A specific correction with confidence and impact

```swift
struct ProposedFix: Codable {
    var description: String
    var confidence: Double  // 0.0-1.0
    var reasoning: String

    // Changes to apply
    var deltas: [TransactionDelta]

    // Impact prediction
    var impact: ImpactAnalysis

    // Evidence
    var supportingEvidence: [String]
    var assumptions: [String]
}

struct ImpactAnalysis: Codable {
    var balanceChange: Decimal
    var transactionsModified: Int
    var transactionsCreated: Int
    var transactionsDeleted: Int
    var checkpointsResolved: Int
    var newDiscrepanciesRisk: String?
}
```

### 5. ReconciliationSession
**Purpose:** Tracks a reconciliation run

```swift
@Model
class ReconciliationSession {
    var id: UUID
    var createdAt: Date
    var categorizationSession: CategorizationSession

    // Analysis
    var checkpointsBuilt: Int
    var discrepanciesFound: Int
    var discrepanciesResolved: Int

    // Investigations run
    var investigations: [Investigation]
    var fixesApplied: Int

    // Results
    var initialMaxDiscrepancy: Decimal
    var finalMaxDiscrepancy: Decimal
    var isFullyReconciled: Bool

    // Status
    var isComplete: Bool
    var iterations: Int
}
```

---

## Service Layer

### ReconciliationService

```swift
class ReconciliationService {

    // Phase 1: Build checkpoints
    func buildBalanceCheckpoints(
        session: CategorizationSession,
        csvRows: [[String: String]]
    ) -> [BalanceCheckpoint] {
        // Extract rows with balance data
        // Calculate running balance from journal entries
        // Create checkpoint for each comparison point
    }

    // Phase 2: Detect discrepancies
    func findDiscrepancies(
        checkpoints: [BalanceCheckpoint],
        session: CategorizationSession
    ) -> [Discrepancy] {
        // Balance mismatches
        // Unbalanced transactions
        // Pattern detection (e.g., negative starting balance)
    }

    // Phase 3: Investigate (AI call per discrepancy)
    func investigate(
        discrepancy: Discrepancy,
        session: CategorizationSession,
        csvRows: [[String: String]],
        thoroughness: InvestigationThoroughness = .balanced
    ) async throws -> Investigation {
        // Build investigation prompt
        // Call Claude API
        // Parse proposed fixes
        // Return investigation with fixes
    }

    // Phase 4: Apply fixes
    func applyFix(
        _ fix: ProposedFix,
        investigation: Investigation,
        session: CategorizationSession
    ) throws {
        // Apply deltas via TransactionReviewService
        // Mark investigation as applied
        // Update discrepancy status
    }

    // Phase 5: Full reconciliation (iterative)
    func reconcile(
        session: CategorizationSession,
        csvRows: [[String: String]],
        maxIterations: Int = 3
    ) async throws -> ReconciliationSession {
        // Iterate: detect → investigate → apply
        // Stop when: fully reconciled OR no high-confidence fixes OR max iterations
    }
}

enum InvestigationThoroughness {
    case quick     // Focus only on discrepancy
    case balanced  // ±3 days context
    case thorough  // ±7 days, deeper analysis
}
```

---

## AI Investigation Prompt Structure

```
ACCOUNTANT MODE: Discrepancy Investigation

You are a meticulous accountant investigating balance discrepancies in a financial ledger.

=== DISCREPANCY ===
Type: Balance Mismatch
Date: April 22, 2024
Expected (CSV): $46,175.80
Calculated (Ledger): -$2,019.24
DISCREPANCY: $48,195.04

Severity: CRITICAL (starting balance is negative)

=== CSV DATA (Context Window: Apr 15-29, 2024) ===
```csv
Run Date,Action,Symbol,Quantity,Amount,Price,Settlement Date,Balance
04/22/2024,YOU BOUGHT,SPY,4,$2019.24,$504.81,04/24/2024,
04/22/2024,,,0,$2019.24,,,46175.80
04/23/2024,ELECTRONIC FUNDS TRANSFER RECEIVED,,,52264.00,,,98439.80
```

=== EXISTING TRANSACTIONS (Apr 15-29) ===
Transaction #1 [ID: a1b2c3d4] (Rows #455, #456):
  Date: 2024-04-22
  Description: "Buy SPY and transfer from external account"
  Type: buy
  Journal Entries: 2 (BALANCED)
    DR: SPY $2,019.24 (qty: 4)
    CR: Cash USD $2,019.24
  Net Cash Impact: -$2,019.24

Transaction #2 [ID: e5f6g7h8] (Row #457):
  Date: 2024-04-23
  Description: "Wire transfer from bank"
  Type: deposit
  Journal Entries: 2 (BALANCED)
    DR: Cash USD $52,264.00
    CR: Owner Contributions $52,264.00
  Net Cash Impact: +$52,264.00

=== CALCULATED BALANCE PROGRESSION ===
Start (Apr 21): $0.00
Apr 22 after Txn #1: -$2,019.24 ❌
Apr 23 after Txn #2: $50,244.76

=== YOUR TASK ===
Investigate this discrepancy and propose corrections.

INVESTIGATION GUIDELINES:
1. Form a hypothesis about what's wrong
2. Analyze the evidence (CSV patterns, transaction structure)
3. Propose 1-3 potential fixes
4. Rate your confidence in each fix (0.0-1.0)
5. Predict the impact of each fix
6. Identify any uncertainties or assumptions

IMPORTANT CONSTRAINTS:
- Do NOT fudge numbers to force a match
- Only propose fixes supported by CSV evidence
- If uncertain, say so (confidence < 0.7)
- Consider multiple possibilities
- Explain your reasoning clearly

RESPONSE FORMAT:
{
  "hypothesis": "Transaction #1's description mentions 'transfer from external account' but journal entries only record the SPY purchase. The balance field of $46,175.80 suggests funds were already in the account or transferred simultaneously.",

  "evidenceAnalysis": "
    - Transaction description explicitly mentions TWO operations: buy AND transfer
    - Journal entries only record ONE operation: the buy
    - Row #456 (settlement) shows balance of $46,175.80
    - If account started at $0 and we bought $2k of SPY, balance would be -$2k ❌
    - If account had $48,195.04 deposited first, then bought $2k, balance = $46,175.80 ✓
    - BUT: No separate deposit row visible before row #455
    - PATTERN: Fidelity margin accounts may show combined operations
  ",

  "proposedFixes": [
    {
      "description": "Create opening balance entry for account (standard practice when CSV starts mid-history)",
      "confidence": 0.90,
      "reasoning": "CSV data starts April 22 but balance shows $46,175.80 immediately. This indicates prior activity. Creating opening balance is standard accounting practice.",
      "deltas": [{
        "action": "create",
        "reason": "Account balance at first transaction indicates prior deposits",
        "transaction": {
          "sourceRows": [],
          "date": "2024-04-21",
          "description": "Opening Balance (prior to CSV data)",
          "transactionType": "deposit",
          "journalEntries": [
            {"type": "debit", "accountType": "cash", "accountName": "Cash USD", "amount": 48195.04},
            {"type": "credit", "accountType": "equity", "accountName": "Opening Balance Equity", "amount": 48195.04}
          ]
        }
      }],
      "impact": {
        "balanceChange": 48195.04,
        "transactionsCreated": 1,
        "transactionsModified": 0,
        "checkpointsResolved": 1,
        "newDiscrepanciesRisk": "May affect subsequent checkpoints if opening balance is incorrect"
      },
      "supportingEvidence": [
        "First CSV row has balance of $46,175.80",
        "Account spent $2,019.24 to reach that balance",
        "Implies starting balance of $48,195.04"
      ],
      "assumptions": [
        "CSV starts mid-account-history",
        "No prior transactions exist in dataset",
        "Balance field is cumulative from account opening"
      ]
    },
    {
      "description": "Add funding legs to Transaction #1 (treat as 4-leg combined transaction)",
      "confidence": 0.70,
      "reasoning": "Description says 'and transfer' suggesting combined operation. Fidelity margin accounts may record both in dual-row format.",
      "deltas": [{
        "action": "update",
        "originalTransactionId": "a1b2c3d4",
        "reason": "Transaction description indicates combined buy+funding operation",
        "transaction": {
          "sourceRows": [455, 456],
          "journalEntries": [
            {"type": "debit", "accountType": "cash", "accountName": "Cash USD", "amount": 48195.04},
            {"type": "credit", "accountType": "equity", "accountName": "Owner Contributions", "amount": 48195.04},
            {"type": "debit", "accountType": "asset", "accountName": "SPY", "amount": 2019.24, "quantity": 4},
            {"type": "credit", "accountType": "cash", "accountName": "Cash USD", "amount": 2019.24}
          ]
        }
      }],
      "impact": {
        "balanceChange": 48195.04,
        "transactionsModified": 1,
        "checkpointsResolved": 1,
        "newDiscrepanciesRisk": "If transfer was actually separate transaction, this creates duplicate"
      },
      "supportingEvidence": [
        "Transaction description mentions both operations",
        "Dual-row pattern (primary + settlement) matches Fidelity format"
      ],
      "assumptions": [
        "Both operations belong to same transaction",
        "Row #456's balance reflects combined operation"
      ]
    }
  ],

  "uncertainties": [
    "Cannot definitively determine if transfer is separate or combined from CSV alone",
    "Margin account mechanics may affect balance calculation",
    "Prior account activity unknown"
  ],

  "needsMoreData": false,
  "recommendation": "Fix #1 (Opening Balance) is safer and more standard. Fix #2 requires more evidence about Fidelity's margin account format."
}
```

---

## Data Flow

### Phase 1: Detection
```
CSV Rows → Extract Balance Field → Build Checkpoints → Calculate Running Balance → Compare → Find Discrepancies
```

### Phase 2: Investigation
```
Discrepancy → Gather Context (±7 days) → Build Investigation Prompt → Claude API → Parse Fixes → Rank by Confidence
```

### Phase 3: Application
```
Proposed Fix → Impact Analysis → User Approval (if needed) → Apply Deltas → Mark Investigation Complete → Re-validate
```

### Phase 4: Iteration
```
Re-detect Discrepancies → If none OR no high-confidence fixes: DONE
                       → If found: Investigate next batch
                       → Max 3 iterations to prevent infinite loops
```

---

## Key Design Decisions

### 1. Checkpoint Strategy
**Decision:** Checkpoint at every CSV row with non-empty Balance field

**Rationale:**
- Fidelity includes balance on settlement rows
- Not every row has balance (primary transaction rows are often blank)
- Gives us ~100-200 checkpoints per year of data
- Enough granularity to isolate issues

**Alternative considered:** Daily checkpoints (cheaper but less precise)

### 2. Investigation Scope
**Decision:** ±7 days context window per discrepancy

**Rationale:**
- Transactions often settle T+2, need context
- Multi-day operations (wire transfers) span windows
- Balance context from nearby checkpoints
- Token-efficient (vs whole ledger)

**Alternative considered:** Whole ledger (too expensive), single day (too little context)

### 3. Confidence Scoring
**Decision:** AI self-assigns confidence with forced reasoning

**Rationale:**
- AI must justify score ("90% because X, Y, Z")
- Prevents arbitrary scores
- Reasoning visible to user
- Can audit later

**Thresholds:**
- **≥95%**: Auto-apply (very high certainty)
- **70-95%**: Requires user review
- **<70%**: Flag only, don't apply

### 4. Fix Application
**Decision:** Reuse TransactionDelta system from review

**Rationale:**
- Consistent with gap-filling
- Same audit trail
- Leverages existing infrastructure
- Deltas are already versioned and explainable

**Alternative considered:** Special reconciliation fixes (too complex)

### 5. Iteration Limit
**Decision:** Max 3 investigation rounds

**Rationale:**
- Prevents infinite loops
- 3 rounds should handle cascading fixes
- User can manually trigger more if needed
- Cost control

---

## Edge Cases

### Case 1: Opening Balance Unknown
**Problem:** CSV starts mid-history, no account opening data

**Solution:** AI proposes "Opening Balance Equity" entry
- Inferred from first checkpoint
- Marked as assumption
- User can override if they know true opening balance

### Case 2: Margin Accounts
**Problem:** Balance might include borrowed funds

**Solution:**
- AI notes uncertainty in investigation
- Proposes fixes but flags margin complexity
- User reviews before applying

### Case 3: Unsettled Transactions
**Problem:** Balance shows pending transactions

**Solution:**
- Use settlement date for checkpoint comparison
- Skip checkpoints on trade date if settlement date differs

### Case 4: Multiple Valid Fixes
**Problem:** 2+ fixes both seem reasonable

**Solution:**
- AI ranks by confidence
- Shows all to user
- User picks OR AI applies highest confidence

### Case 5: No Fix Found
**Problem:** AI can't determine correct fix

**Solution:**
- Investigation returns empty fixes array
- Discrepancy flagged as "needs manual review"
- System continues to next discrepancy

---

## Performance Considerations

### Token Optimization
- Context window: ±7 days (not whole ledger)
- Batch similar discrepancies (same date range)
- Use Haiku (fast, cheap) for investigations
- Cache investigation results

### Cost Estimates
- 100 discrepancies × 1 investigation each = 100 API calls
- ~2000 tokens/call × 100 = 200k tokens
- Haiku: ~$0.50 total
- Can batch to reduce calls: 10 batches = $0.05

### Processing Time
- Checkpoint building: <1 second (local)
- Discrepancy detection: <1 second (local)
- AI investigation: ~5 seconds per call
- Total: ~10 minutes for 100 discrepancies (parallelizable)

---

## UI Integration

### 1. Portfolio View Warning
```
⚠️ Balance Discrepancy Detected
USD: -$122,549.24 (calculated)
Expected: ~$50,000 (from CSV)

[Reconcile Now]
```

### 2. Reconciliation Panel
```
┌─ Balance Reconciliation ─────────────────┐
│                                           │
│ Status: 23 discrepancies found            │
│                                           │
│ Critical (5):                             │
│  • Apr 22: -$48,195 [Investigate]        │
│  • May 15: +$12,000 [Investigate]        │
│  ...                                      │
│                                           │
│ High (8): ...                             │
│ Medium (10): ...                          │
│                                           │
│ [Investigate All] [Auto-Fix (≥95%)]     │
└───────────────────────────────────────────┘
```

### 3. Investigation Results
```
┌─ Investigation: Apr 22 Discrepancy ──────┐
│                                           │
│ Hypothesis:                               │
│ "Transaction missing funding leg"         │
│                                           │
│ Evidence:                                 │
│ • Description mentions "transfer"         │
│ • Balance shows $46k but we have -$2k    │
│ • Implies $48k deposit                    │
│                                           │
│ Proposed Fixes:                           │
│                                           │
│ ⭐⭐⭐⭐⭐ 90% Confidence                    │
│ "Add opening balance entry"               │
│ Impact: +$48,195 balance                  │
│ Resolves: 1 checkpoint                    │
│ [View Details] [Apply]                    │
│                                           │
│ ⭐⭐⭐ 70% Confidence                       │
│ "Add funding legs to transaction"         │
│ [View Details]                            │
│                                           │
│ Uncertainties:                            │
│ • CSV doesn't show account opening        │
│ • Margin account may affect balance       │
│                                           │
│ [Apply Fix #1] [Skip] [Flag Manual]      │
└───────────────────────────────────────────┘
```

---

## Error Handling

### Investigation Failures
- AI returns empty fixes → Flag discrepancy as "needs manual"
- API error → Retry once, then skip discrepancy
- Parse error → Log and continue to next

### Fix Application Failures
- Delta apply fails → Rollback, mark investigation failed
- Creates new discrepancy → Undo fix, flag issue
- Balance doesn't improve → Revert, try next fix

### Iteration Failures
- Max iterations reached → Report "partially reconciled"
- No progress made → Stop, show remaining discrepancies
- User cancels → Save progress, can resume later

---

## Testing Strategy

### Unit Tests
- Balance checkpoint calculation
- Discrepancy severity classification
- Confidence score parsing
- Impact analysis

### Integration Tests
- Full reconciliation cycle
- Fix application
- Iteration convergence

### Test Data
- Known discrepancy scenarios
- CSV with balance field
- Expected fixes for each

---

## Migration Path

### For Existing Sessions
1. Run reconciliation on demand ("Reconcile" button)
2. Show discrepancies found
3. Let user approve fixes
4. Session becomes reconciled

### For New Sessions
1. After categorization completes
2. Auto-run reconciliation (if balance field exists)
3. Auto-apply high-confidence fixes (≥95%)
4. Show medium-confidence for review
5. Flag low-confidence

---

## Future Enhancements

### Phase 2 Features
- **Multi-currency reconciliation** (FX rate validation)
- **Cost basis reconciliation** (for capital gains)
- **Quantity reconciliation** (share counts vs CSV)
- **Pattern learning** (remember fix patterns for similar issues)

### Advanced
- **Anomaly detection** (flag suspicious patterns)
- **Cross-session validation** (detect duplicates across imports)
- **Regulatory compliance** (tax lot tracking)
