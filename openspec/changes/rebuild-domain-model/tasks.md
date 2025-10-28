# Implementation Tasks

## Phase 0: Setup and Teardown (Day 1 Morning)

### Preparation
- [ ] Create new branch `domain-rewrite-v2`
- [ ] Document what we're preserving in REWRITE_LOG.md
- [ ] Export existing parse plans as JSON backup
- [ ] Delete LedgerEntry.swift and references
- [ ] Create test fixtures directory with sample CSVs

### Validation Checkpoint
```bash
# Verify clean slate
swift build # Should fail due to missing LedgerEntry
git status  # Should show deleted files
```

## Phase 1: Core Domain Models (Day 1-2)

### Asset Model
- [ ] Create Models/Asset.swift with id, symbol, name, assetClass
- [ ] Add isCashEquivalent flag for money market funds
- [ ] Add priceFeed configuration enum
- [ ] Write AssetTests with symbol normalization tests
- [ ] Test asset equality semantics

### Position Model
- [ ] Create Models/Position.swift with account, asset, quantity
- [ ] Add lots array (stubbed for future)
- [ ] Add recalculate(from:) method
- [ ] Write PositionTests with calculation accuracy tests
- [ ] Test zero position removal logic

### ImportSession Model
- [ ] Create Models/ImportSession.swift replacing ImportBatch
- [ ] Add date range tracking (dataStartDate, dataEndDate)
- [ ] Add file deduplication via SHA256 hash
- [ ] Add rollback() method
- [ ] Write ImportSessionTests with date validation

### Update Existing Models
- [ ] Add asset relationship to JournalEntry
- [ ] Update Transaction to ensure Asset links
- [ ] Remove string-based asset references

### Checkpoint 1: Domain Models Complete
```bash
swift test --filter DomainModelTests
# Expected: 15+ tests passing
# Asset, Position, ImportSession models working
```

## Phase 2: Service Layer (Day 2-3)

### AssetRegistry Service
- [ ] Create Services/AssetRegistry.swift as singleton
- [ ] Implement two-level cache (canonical + institution)
- [ ] Add findOrCreate method with normalization
- [ ] Write thread-safety tests
- [ ] Test deduplication logic

### PositionCalculator Service
- [ ] Create Services/PositionCalculator.swift as actor
- [ ] Implement async queue for batch processing
- [ ] Add recalculation scheduling
- [ ] Write async/await tests
- [ ] Test batch processing efficiency

### ImportPipeline Protocol
- [ ] Define ImportPipeline protocol with clear stages
- [ ] Create ImportContext for passing state between stages
- [ ] Add error handling at each stage
- [ ] Write stage isolation tests

### Checkpoint 2: Services Operational
```bash
swift test --filter ServiceTests
# Expected: 20+ tests passing
# AssetRegistry and PositionCalculator working
```

## Phase 3: Import Pipeline Refactor (Day 3-4)

### Institution Detection
- [ ] Create InstitutionDetector with pattern matching
- [ ] Add Fidelity detection rules
- [ ] Add Coinbase detection rules
- [ ] Test with various CSV headers

### Settlement Row Handling
- [ ] Create SettlementDetector protocol
- [ ] Implement FidelitySettlementDetector
- [ ] Implement TransactionGrouper with institution-specific logic
- [ ] Test grouping accuracy with fixtures

### Transaction Materialization
- [ ] Update TransactionBuilder to use AssetRegistry
- [ ] Ensure balanced transactions
- [ ] Add rounding adjustment for penny differences
- [ ] Test with real-world data

### Checkpoint 3: Import Pipeline Working
```bash
# Test with sample CSV
swift run cascade-ledger import \
  --file samples/fidelity.csv \
  --dry-run
# Should show grouped transactions with assets
```

## Phase 4: ParsePlan Relationship Fix (Day 4-5)

### Institution Model
- [ ] Create Models/Institution.swift
- [ ] Add relationship to ParsePlans
- [ ] Add default plan selection

### ParsePlan Refactor
- [ ] Update ParsePlan to belong to Institution
- [ ] Fix Account to select ParsePlan for import
- [ ] Update ParsePlanVersion relationships
- [ ] Add fork() method for plan customization

### Migration of Existing Plans
- [ ] Create migration to reassign plans to institutions
- [ ] Update UI to show institution → plan hierarchy
- [ ] Test plan selection during import

### Checkpoint 4: ParsePlan Relationships Fixed
```bash
swift test --filter ParsePlanTests
# Institution → ParsePlan → Version flow working
```

## Phase 5: Agent Integration Improvement (Day 5-6)

### Structured Prompts
- [ ] Create StructuredPrompt builder
- [ ] Define expected response schemas
- [ ] Add validation for agent responses
- [ ] Implement retry logic for malformed responses

### ParseAssistant Service
- [ ] Create Services/ParseAssistant.swift as actor
- [ ] Implement suggestParsePlan with structured prompts
- [ ] Add validateMapping for checking transformations
- [ ] Test with various CSV formats

### Agent Error Handling
- [ ] Add timeout handling
- [ ] Implement fallback for API failures
- [ ] Add manual override option
- [ ] Log all agent interactions for debugging

### Checkpoint 5: Agent Integration Stable
```bash
# Test agent suggestions
swift test --filter ParseAssistantTests
# Should produce consistent parse plans
```

## Phase 6: UI Updates (Day 6-7)

### Position Center View
- [ ] Create Views/PositionCenterView.swift
- [ ] Add grouping by asset/account/class
- [ ] Implement drill-down navigation
- [ ] Add refresh indicators

### Import Session Manager
- [ ] Create Views/ImportSessionView.swift
- [ ] Add timeline visualization
- [ ] Implement rollback UI
- [ ] Add reprocess functionality

### Asset Management UI
- [ ] Create Views/AssetManagementView.swift
- [ ] Add metadata editing
- [ ] Implement data source configuration
- [ ] Add search and filtering

### Transaction Updates
- [ ] Update TransactionDetailView for new model
- [ ] Add Asset information display
- [ ] Show journal entries properly

### Checkpoint 6: UI Functional
```bash
# Manual testing required
# 1. Import a CSV
# 2. View positions
# 3. Check asset management
# All views should display correct data
```

## Phase 7: Comprehensive Testing (Day 7-8)

### Integration Tests
- [ ] End-to-end import test for each institution
- [ ] Multi-account aggregation tests
- [ ] Position calculation accuracy tests
- [ ] Import rollback tests

### Performance Tests
- [ ] Benchmark position calculation speed
- [ ] Test with 10,000+ transactions
- [ ] Memory profiling for caches
- [ ] Import speed benchmarks

### Data Validation
- [ ] Compare calculations with spreadsheet
- [ ] Verify USD balances match statements
- [ ] Test duplicate detection
- [ ] Validate settlement row grouping

### Checkpoint 7: All Tests Green
```bash
swift test
# Expected: 100+ tests passing
# No performance regressions
```

## Phase 8: Migration and Documentation (Day 8-9)

### User Migration Guide
- [ ] Document breaking changes
- [ ] Create step-by-step migration instructions
- [ ] Provide parse plan export/import tool
- [ ] Add troubleshooting section

### Developer Documentation
- [ ] Update architecture diagrams
- [ ] Document new domain model
- [ ] Add service interaction flows
- [ ] Create extension guide for new institutions

### Rollback Plan
- [ ] Document how to revert to old branch
- [ ] Keep old data export accessible
- [ ] Test rollback procedure

## Phase 9: Final Validation (Day 9-10)

### Acceptance Testing
- [ ] Import real user data
- [ ] Verify all positions calculate correctly
- [ ] Test all UI workflows
- [ ] Performance meets targets

### Bug Fixes
- [ ] Address any issues found
- [ ] Update tests for edge cases
- [ ] Polish UI interactions

### Deployment Preparation
- [ ] Final code review
- [ ] Update version number
- [ ] Create release notes
- [ ] Tag release

### Final Checkpoint: Ready for Production
```bash
# Full system test
./scripts/full_system_test.sh
# All features working
# Performance acceptable
# No data loss
```

## Success Criteria

### Functional Requirements
- [ ] Can import Fidelity CSV without errors
- [ ] Positions calculate correctly
- [ ] Multi-account aggregation works
- [ ] Import sessions can be rolled back
- [ ] Assets have proper identity

### Performance Requirements
- [ ] Position lookup < 10ms
- [ ] Import 1000 transactions < 5 seconds
- [ ] UI remains responsive during import
- [ ] Memory usage < 200MB for typical usage

### Code Quality
- [ ] Test coverage > 80% for domain models
- [ ] No compiler warnings
- [ ] All TODOs addressed or documented
- [ ] Clean separation of concerns

## Risk Register

| Risk | Impact | Mitigation |
|------|---------|------------|
| Position calculations wrong | High | Extensive test coverage, validation against spreadsheet |
| Import breaks for edge cases | Medium | Comprehensive fixtures, graceful error handling |
| Performance regression | Medium | Benchmark before/after, profile critical paths |
| Agent suggestions incorrect | Low | Manual override, validation layer |

## Dependencies and Parallelization

### Can Run in Parallel
- Phase 1 (Domain Models) and Phase 2 (Services) after Asset model done
- UI updates can start once models are complete
- Documentation can begin early

### Must Run Sequentially
1. Phase 0 → Phase 1 (need clean slate first)
2. Phase 3 → Phase 4 (import needs working services)
3. Phase 6 → Phase 7 (need UI for integration tests)