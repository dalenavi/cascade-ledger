# Source Row Provenance & Field Mapping - Summary

## Problem
Current categorization has weak data lineage - can't trace journal entries back to source CSV rows, can't validate amounts, and over-grouping bugs go undetected.

## Solution
Persist every CSV row as a `SourceRow` entity with:
- Raw CSV data
- Standardized mapped data (using account-specific field mapping)
- Many-to-many linkage to journal entries
- Amount validation at journal entry level

## Key Capabilities
1. **Source Row Persistence** - Every CSV row stored with file provenance
2. **Field Mapping** - Account-level configuration for institution-specific CSV formats
3. **Journal Entry Linkage** - Each journal entry links to source rows
4. **Amount Validation** - Journal entry amounts validated against CSV amounts
5. **Categorization Context** - AI learns account-specific patterns

## Impact
- **Catch categorization errors immediately** (amount mismatches)
- **Detect over-grouping** (row #455-456 example)
- **Full data lineage** - trace any number back to source file
- **Better AI categorization** - learns from corrections
- **Flexible CSV support** - works with any institution's format

## Timeline
9-15 hours of focused work
