# Balance Reconciliation System - Summary

## What This Adds

A system where **AI acts as a skilled accountant** to investigate and resolve balance discrepancies between CSV data and calculated ledger balances.

## Current Problem

Your portfolio shows **USD: -$122,549.24** because early transactions are incomplete:
- Transaction: "Buy SPY and transfer from external account"
- Only records the buy, not the funding
- Account starts negative instead of positive

## How It Works

### 1. Detection Phase
```
CSV: "Balance after Apr 22: $46,175.80"
Ledger: Calculated balance: -$2,019.24
→ Discrepancy: $48,195.04 (CRITICAL)
```

### 2. Investigation Phase (AI)
AI analyzes the evidence and proposes fixes:

**Hypothesis:** "Transaction missing funding leg or account has opening balance"

**Proposed Fix #1** (90% confidence):
- Create "Opening Balance" entry for $48,195.04
- Reasoning: CSV starts mid-history, balance indicates prior deposits
- Impact: Resolves this and downstream checkpoints

**Proposed Fix #2** (70% confidence):
- Add funding legs to Transaction #1
- Reasoning: Description mentions "transfer"
- Impact: Resolves checkpoint but may duplicate if separate

### 3. Application Phase
- High confidence (≥95%): Auto-apply
- Medium (70-95%): User reviews and approves
- Low (<70%): Flag for manual review

### 4. Validation Phase
- Re-check all balances
- Verify discrepancy resolved
- Check for new discrepancies created

### 5. Iteration
Repeat until fully reconciled or max 3 rounds.

## Key Features

✅ **Evidence-based** - Only fixes with clear proof
✅ **Confidence scoring** - AI must justify each fix
✅ **Impact analysis** - Shows ripple effects
✅ **Conservative** - Won't fudge numbers
✅ **Auditable** - Every change has reasoning
✅ **Iterative** - Multiple investigation rounds

## UI Flow

1. User sees: **"⚠️ -$122,549 USD"** in Portfolio
2. Clicks: **"Reconcile"**
3. System shows: **"23 discrepancies found"**
4. User clicks: **"Investigate All"**
5. AI analyzes each, proposes fixes
6. User reviews medium-confidence fixes
7. High-confidence auto-apply
8. Portfolio now shows: **"+$50,234 USD"** ✅

## Implementation Status

**Validation:** ✅ `openspec validate add-balance-reconciliation --strict` passes

**Next Step:** Approval to implement

**Estimated Time:** 5-8 hours focused work

## Related Work

- Builds on: Transaction Review System (just implemented)
- Reuses: TransactionDelta, ReviewSession models
- Extends: CategorizationSession with reconciliation tracking
