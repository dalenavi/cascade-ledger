# Add Balance Reconciliation System

## Status
**Draft** - Awaiting approval

## Context
After AI Direct Categorization creates transactions from CSV data, there are often balance discrepancies between:
- **CSV Balance Field** (ground truth from institution)
- **Calculated Balance** (from our journal entries)

Currently, the Portfolio Value view shows USD: -$122,549.24, which is impossible - indicating missing or incorrect transactions.

Early transactions like "Buy SPY and transfer from external account" are incomplete - they record the purchase but not the funding, causing the account to start with negative balance.

## Problem
1. **No validation against source data** - We categorize transactions but never verify they're correct
2. **Balance field unused** - CSV contains running balance but we ignore it
3. **Silent failures** - Incorrect transactions aren't flagged
4. **No fix mechanism** - When discrepancies exist, no systematic way to investigate and resolve

## Proposed Solution
Build a **Balance Reconciliation System** where AI acts as a meticulous accountant:

1. **Balance Checkpoints** - Extract balance data from CSV, compare to calculated
2. **Discrepancy Detection** - Find mismatches, categorize by severity
3. **AI Investigation** - For each discrepancy, AI researches and proposes evidence-based fixes
4. **Confidence-Based Application** - High-confidence fixes auto-apply, medium requires approval, low flags for manual review
5. **Iterative Refinement** - Multiple investigation rounds until reconciled

### Key Principles
- **Evidence over assumptions** - Only fix with clear proof
- **Confidence scoring** - AI must justify each fix
- **Impact analysis** - Show ripple effects before applying
- **Audit trail** - Every change linked to investigation
- **Conservative** - Better to flag than fudge

## Success Criteria
- [ ] Portfolio value shows realistic positive cash balance
- [ ] All balance checkpoints validate within $0.01
- [ ] Critical discrepancies (>$100) have investigations
- [ ] High-confidence fixes (≥90%) applied automatically
- [ ] User can review medium-confidence fixes before applying
- [ ] Audit trail shows what was changed and why

## Dependencies
- Requires: AI Direct Categorization system (completed)
- Requires: Transaction Review system (completed)
- Builds on: TransactionDelta and ReviewSession models

## Risks
- AI might propose incorrect fixes (mitigated by confidence scoring)
- Balance field might include margin/unsettled funds (needs investigation logic)
- Iterative rounds might not converge (limit to 3 iterations)
- Cost: Each investigation = 1 AI call (use Haiku for efficiency)

## Timeline
- Foundation (checkpoints, discrepancies): 1-2 hours
- AI investigation: 2-3 hours
- UI integration: 1 hour
- Testing & refinement: 1-2 hours

Total: 5-8 hours of focused work
