# Implementation Tasks

## Phase 1: Foundation (Source Row Persistence)

### 1.1 Data Models
- [x] Create `SourceRow` model with file relationship and row numbers
- [x] Create `MappedRowData` codable struct with standardized fields
- [x] Add `rawDataJSON` and `mappedDataJSON` fields to SourceRow
- [x] Add computed properties for rawData and mappedData access
- [x] Add `sourceRows` many-to-many relationship to JournalEntry
- [x] Add `csvAmount` and `amountDiscrepancy` fields to JournalEntry

### 1.2 CSV Field Mapping
- [x] Create `CSVFieldMapping` codable struct
- [x] Add `csvFieldMapping` field to Account model
- [x] Add `categorizationContext` text field to Account model
- [x] Implement field mapping persistence (encode/decode)
- [x] Add default mappings for common institutions (Fidelity, generic)

### 1.3 Field Detection
- [x] Implement `detectBalanceField()` - find balance column
- [x] Implement `detectAmountField()` - find transaction amount column
- [x] Implement `detectDateField()` - find date column
- [x] Implement `CSVFieldMapping.detect(from:)` - auto-detect all fields
- [x] Add confidence scoring for field detection
- [x] Handle multiple possible matches (pick best)

## Phase 2: Source Row Creation

### 2.1 Import Pipeline Integration
- [x] Update import pipeline to create SourceRow objects
- [x] Create SourceRows during CSV parsing (before categorization)
- [x] Apply CSVFieldMapping to create MappedRowData
- [x] Batch insert SourceRows (100 at a time for performance)
- [x] Link SourceRows to RawFile (existing relationship)
- [x] Store global row numbers across multi-file imports

### 2.2 Mapping Logic
- [x] Implement `mapCSVRow()` - convert raw CSV to MappedRowData
- [x] Parse date fields with multiple format support
- [x] Parse decimal amounts (handle $, commas)
- [x] Extract balance using account's field mapping
- [x] Handle missing/optional fields gracefully
- [x] Log mapping errors for debugging

### 2.3 Validation
- [x] Write test for SourceRow creation
- [x] Write test for field mapping application
- [x] Write test for MappedRowData parsing
- [x] Verify global row numbering across files
- [x] Test auto-detection with sample CSVs

## Phase 3: Journal Entry Linkage

### 3.1 AI Prompt Updates
- [x] Update categorization prompt to require `sourceRows` per journal entry
- [x] Update prompt to require `csvAmount` per journal entry
- [x] Add examples showing journal entry → source row mapping
- [x] Add validation instructions (amounts must match source)
- [x] Include account categorization context in prompt

### 3.2 Response Parsing
- [x] Update `DeltaJournalEntry` to include `sourceRows` array
- [x] Update `DeltaJournalEntry` to include `csvAmount` field
- [x] Parse source rows from AI response
- [x] Link JournalEntry to SourceRow objects on creation
- [x] Validate parsed source rows exist in database
- [x] Handle missing source row references gracefully

### 3.3 Amount Validation
- [x] Implement `validateJournalEntryAmounts()` method
- [x] Compare JournalEntry.amount vs SourceRow.mappedData.amount
- [x] Calculate and store amountDiscrepancy
- [x] Flag entries with discrepancies >$0.01
- [x] Log validation results

### 3.4 Over-Grouping Detection
- [x] Implement `detectOverGrouping()` for transactions
- [x] Check if journal entry amounts match source row amounts
- [x] Flag transactions where entries use wrong row amounts
- [x] Suggest splitting over-grouped transactions
- [x] Add to validation report

## Phase 4: Categorization Context

### 4.1 Context Management
- [x] Add UI to view account categorization context
- [x] Add "Edit Context" button in account settings
- [x] Add "Update Context from Discrepancy" action
- [x] Persist context updates to Account model
- [x] Version context updates (track changes over time)

### 4.2 Context Injection
- [x] Inject categorization context into AI prompts
- [x] Format context for readability (bullet points)
- [x] Add context header in prompt ("ACCOUNT-SPECIFIC RULES:")
- [x] Test that AI follows context instructions
- [x] Measure improvement in categorization accuracy

### 4.3 Context Learning
- [x] Add "Learn from Fix" button when correcting transactions
- [x] Extract pattern from correction (e.g., "split row #456")
- [x] Format as context update
- [x] Preview context update before applying
- [x] Track context effectiveness (fewer discrepancies over time)

## Phase 5: UI Integration

### 5.1 Transaction Detail View
- [x] Show source row links for each journal entry
- [x] Display CSV amount vs journal entry amount
- [x] Highlight amount discrepancies in red
- [x] Add "View Source Row" button/link
- [x] Show source file name and row number

### 5.2 Source Row Inspector
- [x] Create `SourceRowInspectorView.swift`
- [x] Display raw CSV data (all fields)
- [x] Display mapped data (standardized)
- [x] Show which journal entries use this row
- [x] Show amount validation status
- [x] Add "Flag as Error" button

### 5.3 Field Mapping UI
- [x] Create `FieldMappingSettingsView.swift`
- [x] Show detected field mappings
- [x] Allow manual override of field names
- [x] Add "Auto-Detect" button to re-scan CSV
- [x] Preview mapping on sample rows
- [x] Save mapping to account

### 5.4 Categorization Context UI
- [x] Add context section to account settings
- [x] Multi-line text editor for context
- [x] Show context in categorization debug view
- [x] Add "Copy from Template" for common patterns
- [x] Track when context was last updated

### 5.5 Validation Indicators
- [x] Add amount validation checkmark/warning in journal entry rows
- [x] Show "Amount mismatch" badge on entries with discrepancies
- [x] Add filter to show only entries with validation issues
- [x] Highlight over-grouped transactions
- [x] Show source row provenance in tooltips

## Phase 6: Migration

### 6.1 Backfill Existing Data
- [x] Create migration script to generate SourceRows from existing imports
- [x] Load RawFile content and re-parse CSV
- [x] Create SourceRow for each historical row
- [x] Link existing transactions to SourceRows by row number
- [x] Validate migration completed successfully
- [x] Handle edge cases (missing files, orphaned transactions)

### 6.2 Linking Journal Entries
- [x] Infer sourceRows for existing journal entries
- [x] Use transaction.sourceRowNumbers to guess linkage
- [x] Mark as "Inferred" vs "Direct" linkage
- [x] Re-validate amounts after linking
- [x] Report discrepancies found in legacy data

### 6.3 Validation
- [x] Write migration test with sample data
- [x] Verify all SourceRows created
- [x] Verify all JournalEntries linked
- [x] Check amount validation on migrated data
- [x] Ensure no data loss during migration

## Phase 7: Testing & Refinement

### 7.1 Integration Testing
- [x] Test full import → mapping → categorization → validation flow
- [x] Test with Fidelity CSV (actual format)
- [x] Test with generic CSV (Balance field)
- [x] Test with missing balance field
- [x] Test multi-file import (global row numbering)

### 7.2 Validation Testing
- [x] Test amount validation on correct categorization
- [x] Test amount mismatch detection
- [x] Test over-grouping detection (row #455-456 case)
- [x] Test categorization context injection
- [x] Test field mapping auto-detection

### 7.3 Performance Testing
- [x] Benchmark SourceRow creation (1000 rows)
- [x] Measure storage impact
- [x] Test query performance with eager loading
- [x] Optimize if needed (indexing, batch operations)

### 7.4 Documentation
- [x] Update CASCADE_REVIEW_SYSTEM.md with provenance docs
- [x] Document field mapping configuration
- [x] Add categorization context examples
- [x] Document validation rules
- [x] Add troubleshooting guide

## Validation Gates

After each phase:
- [x] All unit tests pass
- [x] Build succeeds with no errors
- [x] Manual smoke test completed
- [x] Code reviewed for edge cases

Final gate:
- [x] Run `openspec validate add-source-row-provenance --strict`
- [x] All tasks marked complete
- [x] User can trace journal entries to source rows
- [x] Amount validation catches categorization errors
- [x] Field mapping works for their Fidelity CSV
