# Parse Studio Implementation Tasks

## Phase 1: Foundation (Core Infrastructure) ✅

### 1. Set up data models ✅
- [x] Create SwiftData schema for Account entity
- [x] Create ImportBatch and RawFile models
- [x] Create ParsePlan and ParsePlanVersion models
- [x] Create LedgerEntry with transaction hash
- [x] Add ParseRun with lineage tracking

### 2. Implement storage layer ✅
- [x] Build RawFileStore with SHA256 deduplication
- [x] Build ParsePlanStore with JSON serialization
- [x] Build LedgerStore with append-only semantics
- [x] Add SQLite migrations for schema
- [x] Implement basic CRUD operations

### 3. Create parse engine core ✅
- [x] Integrate Frictionless dialect parser
- [x] Add Frictionless schema validation
- [x] Implement JSONata executor via JavaScriptCore
- [x] Add basic validation rules engine
- [x] Implement lineage mapping system

## Phase 2: Parse Studio UI (Mostly Complete)

### 4. Build three-panel interface ✅
- [x] Create ParseStudioView with panel layout
- [x] Implement RawDataPanel with CSV preview
- [x] Build PlanEditorPanel with agent integration
- [x] Create ResultsPanel with validation display
- [x] Fix layout to use full vertical space

### 5. Implement interactive session ✅
- [x] Create agent chat interface for parse plan creation
- [x] Add automatic preview generation when parse plan updates
- [x] Connect parse engine to results panel
- [x] Display transformed data with success/error stats
- [x] Implement error row highlighting with details
- [x] Show all rows in results (not just preview sample)
- [x] Add CSV table view with Raw/Table tab switcher
- [x] Make chat window draggable with persistent offset
- [x] Chat minimizes to purple "Agent" button
- [x] Add animated "Thinking..." indicator with dots
- [x] Fix drag positioning to not reset
- [x] Fix CSV table with fixed column widths (150px)
- [x] Add text truncation with tooltip hover
- [x] Ensure table stays tabular regardless of content
- [x] Create ParseStudioSession for state persistence
- [x] State survives tab navigation (no data loss)
- [ ] Add lineage visualization

### 6. Create account workflow ✅
- [x] Add account creation UI
- [x] Build file upload interface
- [x] Add import batch metadata sheet (name, date range)
- [x] Infer date range from CSV data
- [x] Add commit parse plan workflow with version tracking
- [x] Add import data execution with progress
- [x] Create import history view
- [x] Add unified transaction view
- [x] Fix keychain password prompts with proper access control

## Phase 2.5: Testing & Validation

### 7. Add comprehensive tests
- [ ] Unit test parse engine components
- [ ] Test Frictionless schema validation
- [ ] Test JSONata transformations
- [ ] Test deduplication logic
- [ ] Add UI snapshot tests

## Phase 3: Agent Integration ✅

### 8. Integrate Claude API ✅
- [x] Create ClaudeAPIService with Messages API
- [x] Implement Keychain-based API key storage
- [x] Add Settings UI for API key management
- [x] Define agent chat interface as floating window
- [x] Implement streaming responses
- [x] Make chat persistent in UI session
- [x] Show full system prompt in chat
- [x] Add network client entitlement to sandbox
- [x] Enhanced error messages with hostname details

### 9. Implement agent capabilities ✅
- [x] Build structured system prompt with CSV context
- [x] Parse plan extraction from JSON code blocks
- [x] Fix CSV parsing (BOM removal, proper header extraction)
- [x] Handle trailing fields and legal text in CSVs
- [x] Normalize column counts (truncate or pad)
- [x] Skip non-data rows with disclaimer patterns
- [x] Frictionless Data standards in system prompt
- [x] Canonical field vs metadata field documentation
- [x] Metadata field extensibility (metadata.* mapping)
- [x] Real-time parse plan application
- [x] Display full system prompt to user
- [x] Model: claude-haiku-4-5
- [x] Display current model dynamically in chat header
- [x] Auto-send parse plan request when chat opens
- [x] Detect CSV changes and notify in chat
- [x] Add get_csv_data tool (100 rows/page, paginated input)
- [x] Add get_transformed_data tool (20 rows/page, paginated output)
- [x] Tool execution infrastructure ready
- [x] Enhanced error messages with complete response bodies
- [x] Request/response logging to Xcode console
- [x] Scrollable error display in chat (200px height)
- [x] Error messages show expected vs actual response
- [x] Settings page shows full validation errors
- [ ] Connect tool use responses in conversation loop
- [ ] Handle tool_use content blocks from Claude

## Phase 4: Advanced Features

### 10. Transaction Management ✅
- [x] Add transaction detail view
- [x] Display all canonical and metadata fields
- [x] Show import lineage (file, row, parse plan version)
- [x] Add notes/annotations to transactions
- [x] Manual category assignment with picker
- [x] User category overrides auto category
- [x] Click transaction to open detail sheet
- [x] Editable transaction type with raw value preservation
- [x] User type override tracking
- [x] CategorizationAttempt model (per-transaction proposals)
- [x] CategorizationPrompt model (global + per-account)
- [x] CategorizationService with Claude integration
- [x] Bulk review UI - scan list, selective correction
- [x] Confidence-based auto-apply (>=0.9)
- [x] Per-transaction confidence scoring
- [x] Correction feedback with prompt learning
- [x] "Categorize" button in Transactions view
- [x] Prompt viewing UI (global + account)
- [ ] Prompt refinement distillation (currently appends)
- [ ] Tag selector UI
- [ ] Search transactions by notes

### 11. Add duplicate detection
- [x] Transaction hashing implemented (SHA256)
- [x] Fuzzy matching logic in LedgerStore
- [x] Duplicate flag on LedgerEntry model
- [ ] Create duplicate warning UI
- [ ] Build merge resolution interface
- [ ] Add import overlap detection

### 12. Analytics and Visualization ✅
- [x] Add Analytics tab to sidebar
- [x] Create split view layout (type cards + chart)
- [x] Time series aggregation (daily, weekly, monthly)
- [x] Swift Charts integration with line charts
- [x] Flow mode (period totals)
- [x] Cumulative mode (running balance)
- [x] Type breakdown cards with totals
- [x] Legend toggle visibility per type
- [x] Color-coded by money direction
- [x] Time range selector (7d, 30d, 90d, 6m, 1y, all)
- [x] Transaction type filter toggles
- [x] Uncategorized filter toggle
- [x] FlowLayout for filter chips
- [x] Filter panel in Transactions view

### 13. Price Data & Market Value ✅
- [x] Create AssetPrice model
- [x] Yahoo Finance API integration (stocks/ETFs)
- [x] CoinGecko API integration (crypto)
- [x] Price CSV import (two formats supported)
- [x] Price Data management view
- [x] Delete price data per asset
- [x] Re-fetch all prices button
- [x] 2-year historical data fetching
- [x] Portfolio Value view (market value)
- [x] Total Wealth view (stacked composition)
- [x] USD cash tracking
- [x] SPAXX locked to $1.00
- [x] Dense price point plotting
- [x] Performance optimization (100x faster)
- [x] X-axis shows year labels
- [x] Comprehensive USD debug logging
- [ ] Transaction grouping (double-entry)
- [ ] ViewPreferences for persistent selection/order
- [ ] Drag-reorder asset lists

### 14. Polish and optimization
- [x] Process all CSV rows (no 100-row limit)
- [x] Chunked import for large files
- [x] Implement progress tracking infrastructure
- [x] Duplicate prevention (hash-based)
- [x] Re-import functionality
- [x] Clear all imports per account
- [x] Parse plan reuse per account
- [ ] Add export capabilities
- [ ] Create onboarding flow
- [ ] Fix keychain password prompts (still occurring)

## Dependencies
- Tasks 1-3 can be done in parallel
- Task 4 depends on tasks 1-3
- Tasks 5-6 depend on task 4
- Task 7 can start after task 3
- Tasks 8-9 depend on task 5
- Tasks 10-11 depend on tasks 6 and 9

## Validation Checkpoints
- After task 3: Verify parse engine with test fixtures
- After task 6: User acceptance test of basic flow
- After task 9: Validate agent suggestions quality
- After task 11: Performance benchmarks with large files