# Implementation Tasks

## Phase 1: Foundation (Balance Checkpoints & Discrepancy Detection)

### 1.1 Data Models
- [x] Create `BalanceCheckpoint` model with CSV vs calculated balance comparison
- [x] Create `Discrepancy` model with type, severity, affected rows/transactions
- [x] Create `Investigation` model to track AI analysis
- [x] Create `ProposedFix` codable struct with confidence and impact
- [x] Create `ReconciliationSession` model to track reconciliation runs
- [x] Add `reconciliationSessions` relationship to `CategorizationSession`

### 1.2 Balance Calculation Service
- [x] Create `BalanceCalculationService` class
- [x] Implement `calculateBalanceAtDate()` - compute balance from journal entries up to date
- [x] Implement `calculateBalanceProgression()` - running balance for all transactions
- [x] Add timezone handling for date comparisons
- [ ] Add caching for performance (balance at checkpoints)

### 1.3 Checkpoint Building
- [x] Create `ReconciliationService` class
- [x] Implement `buildBalanceCheckpoints()` - extract balance from CSV rows
- [x] Parse Fidelity balance field format (may have commas, $ signs)
- [x] Match CSV rows to dates (handle settlement vs trade date)
- [x] Calculate ledger balance at each checkpoint
- [x] Compute discrepancy (CSV - calculated)
- [x] Classify severity based on absolute delta

### 1.4 Discrepancy Detection
- [x] Implement `findDiscrepancies()` method
- [x] Detect balance mismatches (threshold: $0.01)
- [x] Detect unbalanced transactions (existing function)
- [x] Detect negative starting balance pattern
- [x] Prioritize by severity (critical → high → medium → low)
- [ ] Group related discrepancies (same date range)

### 1.5 Validation
- [ ] Write unit test for balance calculation
- [ ] Write test for checkpoint building with sample CSV
- [ ] Write test for discrepancy detection with known issues
- [ ] Verify checkpoint counts match balance field occurrences

## Phase 2: AI Investigation

### 2.1 Investigation Prompt
- [x] Implement `buildInvestigationPrompt()` method
- [x] Include discrepancy details (expected, actual, delta)
- [x] Include CSV context window (±7 days)
- [x] Include existing transactions in range
- [x] Include calculated balance progression
- [x] Add year context for date parsing
- [x] Add confidence scoring instructions
- [x] Add impact analysis requirements

### 2.2 Investigation Execution
- [x] Implement `investigate()` method
- [x] Build context window (expand ±7 days from discrepancy)
- [x] Call Claude API with investigation prompt
- [x] Parse JSON response into `Investigation` object
- [x] Extract `proposedFixes` array
- [x] Parse confidence scores (0.0-1.0)
- [x] Parse impact analysis
- [x] Store investigation in database

### 2.3 Response Parsing
- [x] Implement `parseInvestigationResponse()` method
- [x] Extract hypothesis and evidence analysis
- [x] Parse proposed fixes array
- [x] Validate confidence scores (must be 0.0-1.0)
- [x] Parse deltas within each fix
- [x] Extract uncertainties and assumptions
- [x] Handle malformed responses gracefully

### 2.4 Validation
- [ ] Write test for prompt building
- [ ] Write test for response parsing with sample AI output
- [ ] Write test for confidence score validation
- [ ] Verify impact analysis calculations

## Phase 3: Fix Application

### 3.1 Fix Application Logic
- [x] Implement `applyFix()` method
- [x] Reuse `TransactionReviewService.applyDeltas()` for applying changes
- [x] Mark investigation as applied
- [x] Update discrepancy status to resolved
- [x] Record which fix was applied (by index)
- [ ] Handle application failures (rollback)

### 3.2 Impact Validation
- [ ] Implement `validateFixImpact()` method
- [ ] Recalculate balance after applying fix
- [ ] Verify discrepancy actually resolved
- [ ] Check for new discrepancies created
- [ ] Compare predicted vs actual impact
- [ ] Log discrepancies in impact prediction

### 3.3 Batch Processing
- [x] Implement `applyHighConfidenceFixes()` method (integrated in reconcile())
- [x] Filter fixes by confidence threshold (≥95%)
- [x] Apply in order of confidence (highest first)
- [ ] Stop on first failure
- [ ] Report results (fixes applied, failures)

### 3.4 Validation
- [ ] Write test for fix application
- [ ] Write test for rollback on failure
- [ ] Write test for impact validation
- [ ] Verify balance improves after fix

## Phase 4: Iterative Reconciliation

### 4.1 Reconciliation Orchestration
- [x] Implement `reconcile()` method
- [x] Build initial checkpoints
- [x] Detect discrepancies (iteration 1)
- [x] Investigate each discrepancy
- [x] Apply high-confidence fixes (≥95%)
- [x] Re-detect discrepancies (iteration 2)
- [x] Repeat until: fully reconciled OR no fixes OR max iterations (3)
- [x] Create `ReconciliationSession` to track progress

### 4.2 Progress Tracking
- [x] Update `ReconciliationSession` after each iteration
- [x] Track: discrepancies found, investigated, resolved
- [x] Track: fixes applied, by confidence tier
- [x] Calculate: initial vs final max discrepancy
- [x] Mark as fully reconciled if all checkpoints ≤$0.01

### 4.3 Validation
- [ ] Write integration test for full reconciliation cycle
- [ ] Test iteration convergence
- [ ] Test max iteration limit
- [ ] Test early termination (fully reconciled)

## Phase 5: UI Integration

### 5.1 Portfolio View Warning
- [ ] Detect balance discrepancies on portfolio load
- [ ] Show warning banner if calculated balance seems wrong (e.g., negative)
- [ ] Add "Reconcile" button to portfolio view
- [ ] Link to reconciliation panel

### 5.2 Reconciliation Panel
- [x] Create `ReconciliationView.swift`
- [x] Show list of discrepancies grouped by severity
- [x] Display checkpoint details (expected vs calculated)
- [ ] Add "Investigate" button per discrepancy
- [x] Add "Investigate All" button for batch processing
- [x] Show progress during investigation

### 5.3 Investigation Results View
- [ ] Create `InvestigationResultsView.swift`
- [ ] Display AI's hypothesis and evidence
- [ ] Show proposed fixes list with confidence stars
- [ ] Display impact analysis per fix
- [ ] Show uncertainties and assumptions
- [ ] Add "Apply" button for high-confidence fixes
- [ ] Add "View Details" to expand full reasoning
- [ ] Add "Flag for Manual" option

### 5.4 Fix Review Sheet
- [ ] Create approval sheet for medium-confidence fixes
- [ ] Show before/after balance comparison
- [ ] Display full delta details
- [ ] Show impact prediction
- [ ] Add "Approve" / "Reject" buttons
- [ ] Allow multi-select for batch approval

### 5.5 Reconciliation History
- [ ] Show past reconciliation sessions
- [ ] Display fixes applied in each session
- [ ] Show iteration count and final status
- [ ] Allow rollback of reconciliation session (future)

## Phase 6: Testing & Refinement

### 6.1 Integration Testing
- [ ] Test on current dataset (456 transactions, -$122k balance)
- [ ] Verify opening balance fix resolves issue
- [ ] Check subsequent checkpoints validate
- [ ] Ensure no cascading discrepancies

### 6.2 Edge Case Testing
- [ ] Test with fully reconciled session (no discrepancies)
- [ ] Test with missing balance data
- [ ] Test with multi-day transactions
- [ ] Test with margin account operations
- [ ] Test iteration limit (3 rounds)

### 6.3 Error Handling
- [ ] Test API failures during investigation
- [ ] Test malformed AI responses
- [ ] Test fix application failures
- [ ] Test rollback on error
- [ ] Test user cancellation mid-reconciliation

### 6.4 Documentation
- [ ] Update `CASCADE_REVIEW_SYSTEM.md` with reconciliation docs
- [ ] Add usage examples
- [ ] Document confidence thresholds
- [ ] Add troubleshooting guide

## Validation Gates

After each phase:
- [ ] All unit tests pass
- [ ] Build succeeds with no errors
- [ ] Manual smoke test completed
- [ ] Code reviewed for edge cases

Final gate:
- [ ] Run `openspec validate add-balance-reconciliation --strict`
- [ ] All tasks marked complete
- [ ] User can successfully reconcile their -$122k balance issue
