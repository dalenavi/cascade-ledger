# Balance Reconciliation

## Overview
System for validating transaction categorization accuracy by comparing calculated balances against CSV balance fields, using AI to investigate and resolve discrepancies.

---

## ADDED Requirements

### Requirement: Balance Checkpoint Extraction
The system SHALL extract balance checkpoints from CSV data for validation.

#### Scenario: Extract balance from Fidelity CSV
```
GIVEN a CSV row with Balance field "46175.80"
WHEN building checkpoints
THEN create BalanceCheckpoint with:
  - csvBalance = 46175.80
  - date from Run Date field
  - rowNumber for traceability
```

#### Scenario: Handle balance formatting variations
```
GIVEN CSV balance values like "$1,234.56" or "1234.56"
WHEN parsing balance field
THEN normalize to Decimal correctly (1234.56)
```

#### Scenario: Skip rows without balance data
```
GIVEN CSV row with empty Balance field
WHEN building checkpoints
THEN skip this row (settlement rows often have balance, trade rows don't)
```

---

### Requirement: Calculated Balance Comparison
The system SHALL calculate running balance from journal entries and compare to CSV checkpoints.

#### Scenario: Calculate balance at checkpoint date
```
GIVEN transactions with journal entries up to April 22, 2024
WHEN calculating balance at checkpoint
THEN sum all Cash USD debits minus credits through that date
```

#### Scenario: Detect balance mismatch
```
GIVEN CSV shows balance $46,175.80
AND calculated balance is -$2,019.24
WHEN comparing at checkpoint
THEN detect discrepancy of $48,195.04
```

#### Scenario: Validate within tolerance
```
GIVEN CSV balance $1,000.00
AND calculated balance $1,000.005
WHEN comparing (≤$0.01 tolerance)
THEN mark as balanced (no discrepancy)
```

---

### Requirement: Discrepancy Severity Classification
The system SHALL classify discrepancies by financial impact.

#### Scenario: Critical severity for large discrepancy
```
GIVEN discrepancy of $48,195.04
WHEN classifying severity
THEN mark as CRITICAL (>$1000)
```

#### Scenario: Critical severity for broken accounting rules
```
GIVEN transaction with debits ≠ credits
WHEN classifying
THEN mark as CRITICAL (breaks double-entry)
```

#### Scenario: Low severity for rounding
```
GIVEN discrepancy of $0.03
WHEN classifying
THEN mark as LOW ($0.01-$10)
```

---

### Requirement: AI-Powered Discrepancy Investigation
The system SHALL use AI to analyze discrepancies and propose evidence-based fixes.

#### Scenario: Investigate balance mismatch
```
GIVEN discrepancy: Expected $46,175.80, Got -$2,019.24
WHEN investigating
THEN AI receives:
  - Discrepancy details
  - CSV context window (±7 days)
  - Existing transactions in range
  - Balance progression
AND returns Investigation with:
  - Hypothesis
  - Evidence analysis
  - 1-3 proposed fixes with confidence scores
  - Uncertainties noted
```

#### Scenario: AI proposes opening balance fix
```
GIVEN negative starting balance pattern
AND first CSV checkpoint shows positive balance
WHEN AI investigates
THEN propose "Opening Balance" entry as high-confidence fix (≥0.85)
```

#### Scenario: AI notes uncertainty
```
GIVEN ambiguous transaction description
AND multiple valid interpretations
WHEN AI investigates
THEN:
  - Propose multiple fixes with different confidence
  - List uncertainties explicitly
  - Recommend highest-confidence approach
```

---

### Requirement: Confidence-Based Fix Application
The system SHALL apply fixes based on AI's confidence scoring.

#### Scenario: Auto-apply high-confidence fixes
```
GIVEN proposed fix with confidence ≥0.95
WHEN reconciliation runs
THEN automatically apply fix without user approval
AND log application to audit trail
```

#### Scenario: Require approval for medium confidence
```
GIVEN proposed fix with confidence 0.70-0.94
WHEN reconciliation runs
THEN present to user for review
AND wait for approval before applying
```

#### Scenario: Flag low-confidence issues
```
GIVEN proposed fix with confidence <0.70
WHEN reconciliation runs
THEN flag discrepancy for manual investigation
AND do NOT apply fix
```

---

### Requirement: Impact Analysis
The system SHALL predict and validate the impact of each proposed fix.

#### Scenario: Predict balance change
```
GIVEN proposed fix: Add opening balance $48,195.04
WHEN analyzing impact
THEN predict:
  - balanceChange: +$48,195.04
  - transactionsCreated: 1
  - checkpointsResolved: 1+
```

#### Scenario: Detect cascading effects
```
GIVEN fix that resolves Apr 22 discrepancy
WHEN analyzing impact
THEN predict resolution of downstream checkpoints (Apr 23-30)
```

#### Scenario: Warn about new discrepancies
```
GIVEN fix makes assumptions about opening balance
WHEN analyzing impact
THEN warn: "May affect subsequent checkpoints if assumption incorrect"
```

---

### Requirement: Iterative Reconciliation
The system SHALL reconcile in multiple rounds until complete or max iterations reached.

#### Scenario: Converge in 2 iterations
```
GIVEN 10 discrepancies initially
WHEN iteration 1 fixes 8 (high confidence)
AND iteration 2 fixes 2 (high confidence)
THEN reconciliation complete (0 discrepancies)
AND iterations = 2
```

#### Scenario: Stop at max iterations
```
GIVEN discrepancies persist after 3 iterations
WHEN max iterations reached
THEN stop reconciliation
AND mark as "partially reconciled"
AND report remaining discrepancy count
```

#### Scenario: Early termination on full reconciliation
```
GIVEN all checkpoints validate after iteration 1
WHEN checking for next iteration
THEN stop (fully reconciled)
AND iterations = 1
```

---

### Requirement: Conservative Fix Strategy
The system SHALL prioritize correctness over forced matching.

#### Scenario: No fix when uncertain
```
GIVEN AI cannot determine correct fix (all confidence <0.60)
WHEN investigation completes
THEN return empty proposedFixes array
AND flag discrepancy as "needs manual review"
AND do NOT create placeholder/fudge transaction
```

#### Scenario: Multiple hypotheses
```
GIVEN 2 equally valid interpretations
WHEN AI investigates
THEN propose both as separate fixes
AND assign appropriate confidence to each
AND let user choose OR apply highest confidence
```

#### Scenario: Document assumptions
```
GIVEN fix requires assumption (e.g., "CSV starts mid-history")
WHEN creating proposed fix
THEN list assumption explicitly in fix.assumptions array
AND factor into confidence score
```

---

### Requirement: Audit Trail
The system SHALL maintain complete history of reconciliation decisions.

#### Scenario: Link fixes to investigations
```
GIVEN investigation produces 2 proposed fixes
WHEN user applies fix #1
THEN record:
  - Investigation ID
  - Applied fix index
  - Timestamp
  - User approval (if manual)
```

#### Scenario: Track reconciliation sessions
```
GIVEN reconciliation run with 3 iterations
WHEN session completes
THEN ReconciliationSession stores:
  - All investigations run
  - All fixes applied
  - Initial vs final discrepancy count
  - Iteration count
```

#### Scenario: Delta audit trail
```
GIVEN fix creates/updates transactions
WHEN applied
THEN TransactionDelta records:
  - Linked to investigation
  - Reason from AI analysis
  - Applied timestamp
```

---

## Success Metrics

### Accuracy
- Balance checkpoints validate within $0.01 tolerance
- No unbalanced transactions remain
- Calculated balance matches CSV balance at all checkpoints

### Coverage
- All CSV rows with balance data become checkpoints
- All critical discrepancies investigated
- High-confidence fixes applied automatically

### Usability
- User sees clear explanation for each proposed fix
- Impact analysis shows before/after state
- Can review and approve medium-confidence fixes
- Can flag for manual if AI is uncertain

### Performance
- Checkpoint building: <1 second for 500 rows
- Discrepancy detection: <1 second
- AI investigation: <10 seconds per discrepancy
- Full reconciliation: <5 minutes for 50 discrepancies
