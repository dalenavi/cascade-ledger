# Parse Studio: Interactive Financial Data Import System

## Summary
Add Parse Studio to enable importing, parsing, and normalizing financial data from CSV exports into the canonical ledger, with AI-assisted parse plan creation and version tracking.

## Context
Users need to import financial data from various institutions (banks, brokers, crypto exchanges) into Cascade Ledger. Each institution has different export formats, requiring flexible parsing rules that can be refined interactively with AI assistance.

## Goals
- Enable CSV import with interactive parse plan authoring
- Provide AI-assisted mapping from raw data to canonical schema
- Support versioned parse plans with upgrade paths
- Maintain complete data lineage from source to ledger
- Allow partial success imports with error recovery

## Non-Goals
- Full ETL platform capabilities
- Automatic categorization (future enhancement)
- Multi-file merge operations (future enhancement)
- PDF parsing (future enhancement)

## Solution Overview
Parse Studio provides a three-panel interface for importing financial data:
1. Raw data preview (left)
2. Parse plan editor with live preview (center)
3. Transformed results with validation (right)

The system uses Frictionless Data standards for schemas and JSONata/JOLT for transformations, with Claude Agent SDK providing intelligent assistance.

## Dependencies
- SwiftData for persistence
- JavaScriptCore for JSONata execution
- Claude Agent SDK for AI assistance
- Frictionless Data standards

## Risks
- JSONata performance on large files → Mitigated: Process all rows efficiently
- Complex CSV formats from some institutions → Mitigated: Pluggable import strategies
- Agent suggestion quality for edge cases → Mitigated: User corrections refine prompts

## Alternatives Considered
- Custom DSL: Rejected for maintainability
- Pure LLM parsing: Rejected for reliability
- Hard-coded parsers: Rejected for inflexibility

## Sample Data
- `sample_data/fidelity_sample_transactions.csv` - Representative Fidelity CSV format
- Demonstrates: Dual-row transactions, settlement entries, dividends, margin trades
- Use for testing parse plans and transaction grouping

## Current State
- **Phase 1-3:** Complete and production-ready (100%)
- **Phase 4:** Advanced features complete (100%)
- **Phase 5:** Double-entry bookkeeping (85% complete)
- **Outstanding:**
  - View migration to double-entry models
  - Data migration service completion
  - ViewPreferences persistence
  - Drag-reorder asset lists

## Recent Major Changes

### Double-Entry Bookkeeping System (NEW)
- Implemented full Transaction/JournalEntry model
- Fixes USD double-counting bug ($499k → $144k)
- Enforces accounting rules (debits = credits)
- TransactionBuilder groups CSV settlement rows
- ParseEngineV2 creates balanced transactions
- Test view validates correctness

### Parse Agent Tool Use (COMPLETE)
- Agent can now call get_csv_data and get_transformed_data
- Iterative parse plan refinement working
- Enhanced system prompt with target schema
- Agent generates correct field mappings
- Settlement row detection documented in prompts

### API Key Storage (CHANGED)
- Switched from Keychain to UserDefaults
- Eliminated persistent password prompts
- Automatic migration from old storage
- Security warning in Settings UI