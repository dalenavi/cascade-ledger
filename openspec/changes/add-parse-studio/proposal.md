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
- Phase 1-3: Complete and production-ready
- Phase 4: Advanced features 80% complete
- Outstanding: Transaction grouping (double-entry), drag-reorder, preference persistence