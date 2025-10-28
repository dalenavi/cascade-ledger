# Rebuild Domain Model

## Why

The current domain model has fundamental architectural issues that compound as we add features:

**Confused Domain Boundaries**
- `LedgerEntry` mixes single-entry and double-entry concepts
- Assets are strings scattered throughout, preventing aggregation
- ImportBatch lacks session semantics (rollback, date ranges, reprocessing)
- No Position model forces expensive recalculation on every query

**Parse Infrastructure Problems**
- ParsePlan ↔ Account relationship is backwards (plans should belong to institutions)
- Agent integration is brittle and produces inconsistent mappings
- Settlement row detection hardcoded instead of pluggable
- No clear import pipeline stages

**Missing Core Capabilities**
- Cannot see total holdings across accounts
- No asset registry for managing symbols and metadata
- Import sessions can't be rolled back or reprocessed
- Position calculations happen on-demand (performance killer)

Since we don't need to preserve existing data, we can fix these issues with a clean rewrite rather than incremental migration.

## What

Complete domain model rebuild with clean architecture:

### Core Domain Models
- **Asset**: Master registry of all securities/currencies
- **Position**: Materialized holdings per account-asset
- **ImportSession**: Replaces ImportBatch with proper session semantics
- **Transaction/JournalEntry**: Keep double-entry model but with Asset links

### Service Layer
- **AssetRegistry**: Singleton managing asset identity and caching
- **PositionCalculator**: Async actor for efficient position updates
- **ImportPipeline**: Clear stages from CSV to domain models

### Parse Infrastructure Fixes
- ParsePlans belong to Institutions, not Accounts
- Institution-specific settlement detection
- Structured agent prompts for consistent results
- Clear versioning and rollback capabilities

### Key Architectural Changes
- Delete LedgerEntry completely
- Separate read models (Position) from write models (Transaction)
- Institution-specific importers instead of generic approach
- Explicit asset identity (no automatic aliasing)

## Impact

### Breaking Changes
- Complete data model change - users must reimport
- No backward compatibility with existing data
- UI will be updated to new models

### Performance Improvements
- Position queries: O(1) instead of O(n) transaction scan
- Asset lookups: In-memory cache
- Import processing: Batched position updates

### New Capabilities Enabled
- Multi-account portfolio view
- Import session rollback
- Asset metadata management
- Future: cost basis tracking, transfers, tax reporting