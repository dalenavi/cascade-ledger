# Domain Model Rewrite Log

## Date: 2025-01-27

## Overview
Complete domain model rebuild (Plan B) - No backward compatibility, users will reimport data.

## What We're Preserving

### Parse Infrastructure (It Works)
- `ParsePlan.swift` - Elegant versioning system
- `ParsePlanVersion.swift` - Immutable snapshots
- `CSVParser.swift` - Frictionless Data standards implementation
- `TransformExecutor.swift` - JSONata transforms via JavaScriptCore
- Working copy → commit workflow

### Double-Entry Foundation
- `Transaction.swift` - Container for economic events (enhancing)
- `JournalEntry.swift` - Debit/credit legs (enhancing with Asset links)
- Balance validation logic
- Settlement row detection pattern (will improve)

### UI Components
- ParseStudioView three-panel design
- Most of the 24 existing views (updating data backing)
- Chart visualizations (already optimized)

## What We're Deleting

### Confused Domain Models
- `LedgerEntry.swift` - Legacy single-entry, fundamentally flawed
- String-based asset tracking throughout
- `ImportBatch.swift` - Weak concept, replacing with ImportSession

### Problems Being Fixed
- No Asset master registry
- No Position model (expensive on-demand calculations)
- ParsePlan ↔ Account relationship backwards
- No import session rollback capability
- Settlement detection hardcoded instead of pluggable

## Key Architectural Changes

### New Models
1. **Asset** - Master registry of all securities/currencies
2. **Position** - Materialized holdings per account-asset
3. **ImportSession** - Replaces ImportBatch with proper semantics

### New Services
1. **AssetRegistry** - Singleton with caching for asset identity
2. **PositionCalculator** - Actor for async position updates
3. **ImportPipeline** - Clear stages from CSV to domain

### Design Decisions
- FBTC ≠ BTC (distinct assets, no automatic aliasing)
- ParsePlans belong to Institutions, not Accounts
- Settlement detection is pluggable per institution
- Positions are materialized, not computed on-demand
- Institution-specific importers, not generic

## Implementation Phases

1. **Phase 0**: Setup and teardown (this phase)
2. **Phase 1**: Core domain models (Asset, Position, ImportSession)
3. **Phase 2**: Service layer (AssetRegistry, PositionCalculator)
4. **Phase 3**: Import pipeline refactor
5. **Phase 4**: ParsePlan relationship fix
6. **Phase 5**: Agent integration improvements
7. **Phase 6**: UI updates
8. **Phase 7**: Comprehensive testing
9. **Phase 8**: Migration and documentation
10. **Phase 9**: Final validation

## Success Criteria
- Can import Fidelity CSV without errors
- Positions calculate correctly
- Multi-account aggregation works
- All tests pass (100+ expected)
- Performance meets targets
- UI remains responsive