# Parse Studio - Current Implementation State

## Summary

Parse Studio is a production-ready financial data import and analysis system with AI-assisted parse plan creation, **double-entry bookkeeping**, transaction categorization, and comprehensive portfolio analytics.

**Current Phase:** Migrating from single-entry to double-entry bookkeeping to fix USD calculation accuracy. Core double-entry models and import engine complete (85%). View migration in progress.

## Completed Features

### Core Import System (100%)
- ✅ CSV file upload (drag & drop, file picker)
- ✅ Raw CSV storage with SHA256 deduplication
- ✅ Parse plan creation with Claude Haiku 4.5
- ✅ Working copy + commit-based versioning
- ✅ Full CSV processing (no row limits)
- ✅ Duplicate transaction prevention
- ✅ Import batch metadata (name, date range)
- ✅ Re-import functionality
- ✅ Clear all imports per account
- ✅ Parse plan reuse per account

### Data Models (100%)
- ✅ Account & Institution
- ✅ ImportBatch & RawFile (with parsePlanVersion tracking)
- ✅ ParsePlan & ParsePlanVersion
- ✅ LedgerEntry with quantity tracking (single-entry, deprecated)
- ✅ Transaction & JournalEntry (double-entry bookkeeping)
- ✅ AccountType enum (Asset, Cash, Income, Expense, Liability, Equity)
- ✅ CategorizationAttempt & CategorizationPrompt
- ✅ AssetPrice for market data
- ✅ ViewPreferences (created, not wired)

### Parse Engine (100%)
- ✅ Frictionless Data standards
- ✅ CSVParser with BOM handling
- ✅ Trailing field normalization
- ✅ Legal disclaimer detection
- ✅ JSONata transformations
- ✅ Field validation
- ✅ Quantity extraction
- ✅ Metadata field support
- ✅ Lineage tracking

### AI Integration (100%)
- ✅ Claude API with Haiku 4.5
- ✅ Streaming responses
- ✅ Parse plan generation from CSV
- ✅ System prompt with Frictionless standards
- ✅ Metadata field documentation
- ✅ Floating chat window (draggable, minimizable)
- ✅ Tool definitions (get_csv_data, get_transformed_data)
- ✅ Tool use in conversation loop (fully wired)
- ✅ Iterative parse plan refinement
- ✅ Target schema documentation
- ✅ Settlement row pattern detection
- ✅ Batched categorization (10 transactions per call)
- ✅ Confidence-based suggestions
- ✅ Prompt learning from corrections
- ✅ API key storage via UserDefaults (no password prompts)

### Double-Entry Bookkeeping (85%)
- ✅ Transaction container model (groups CSV rows)
- ✅ JournalEntry model (individual debit/credit legs)
- ✅ AccountType taxonomy (6 account types)
- ✅ TransactionBuilder (CSV row grouping logic)
- ✅ ParseEngineV2 (double-entry import engine)
- ✅ Balance enforcement (debits must equal credits)
- ✅ Settlement row detection and grouping
- ✅ Net cash impact calculation
- ✅ Quantity change tracking per asset
- ✅ DoubleEntryTestView (test interface)
- ❌ Migration service (designed, partial implementation)
- ❌ View updates for double-entry (pending)
- ❌ Deprecate single-entry LedgerEntry (after migration)

### Views (100%)
1. **Parse Studio** - CSV import & parse plan creation
2. **Transactions** - Multi-select, categorization, filtering
3. **Timeline** - Filtered transaction list with analytics
4. **Analytics** - Category/type/asset breakdown with charts
5. **Positions** - Quantity holdings (shares, BTC)
6. **Portfolio Value** - Market value with price data
7. **Total Wealth** - Stacked composition chart
8. **Balance** - Cash flow & holdings modes
9. **Import History** - Re-import, data quality badges
10. **Price Data** - Fetch/delete price history
11. **Settings** - API key management (UserDefaults storage)
12. **Double-Entry Test** - Testing interface for new system
13. **Parse Plan Debug** - Inspect parse plan structure

### Transaction Management (90%)
- ✅ Transaction detail view
- ✅ Notes & annotations
- ✅ Manual categorization
- ✅ Editable transaction type
- ✅ Category & tag system designed
- ✅ AI categorization with review UI
- ❌ Conversational pattern matching (designed)
- ❌ Bulk categorization UI refinement

### Price & Market Value (95%)
- ✅ AssetPrice model
- ✅ Yahoo Finance integration (stocks/ETFs)
- ✅ CoinGecko integration (crypto)
- ✅ 2-year automated fetching
- ✅ Delete/re-fetch per asset
- ✅ Market value calculation
- ✅ Portfolio Value view
- ✅ Total Wealth stacked chart
- ✅ SPAXX locked to $1.00
- ✅ USD cash tracking (with debug logging)
- ❌ Transaction grouping (in progress)
- ❌ Exchange rate tracking (designed, not implemented)

### Analytics & Visualization (100%)
- ✅ Time series charts (Swift Charts)
- ✅ Flow & cumulative modes
- ✅ 4 grouping dimensions (Category, Type, Top-Level, Asset)
- ✅ Legend toggles
- ✅ Dense price point plotting
- ✅ Stacked area charts
- ✅ X-axis with year labels
- ✅ Performance optimization (100x faster)

## Known Issues

### Critical
1. **USD calculation in single-entry mode** - Double-counting settlement rows (~$500k instead of actual)
   - Status: Root cause identified - settlement rows counted as USD transactions
   - Solution: **Double-entry bookkeeping system built** (85% complete)
   - Single-entry mode deprecated, use double-entry for accurate calculations
   - Migration path: Re-process imports with ParseEngineV2
   - Next: Complete view migration to double-entry models

2. **Parse plan field mappings** - Previous parse plans incorrectly combine fields
   - Status: Agent now generates correct mappings with tool use
   - Solution: Regenerate parse plans using enhanced agent
   - Agent now maps Action → metadata.action (critical for settlement detection)
   - Agent now preserves Quantity as numeric field

### Minor
3. **SPAXX quantity** - Only shows imported data (~4,500 shares vs expected 80-110k)
   - Status: Working as designed
   - Solution: Import earlier CSVs or use Cash Balance column

4. **ViewPreferences** - Asset order/selection not persisted across restarts
   - Status: Model created, not wired to views
   - Next: Implement persistence layer

5. **CoreData Array warnings** - "Could not materialize Array<Int/String>"
   - Status: Warnings only for tags and sourceRowNumbers
   - Impact: None (data persists correctly)
   - Occurs with Transaction.sourceRowNumbers and LedgerEntry.tags

## Architecture Decisions

### Parse Plans
- **Versioning:** Commit-based (working copy → commit → immutable version)
- **Reuse:** Per-account, not per-file
- **Storage:** JSON in Data field (SwiftData limitation)

### Categorization
- **AI-driven:** Natural language prompts (global + per-account)
- **Learning:** Corrections update prompts
- **Review:** Bulk scan with selective correction
- **Confidence:** Auto-apply ≥90%, review 50-90%, flag <50%

### Price Data
- **Storage:** Separate AssetPrice model (date + asset + price)
- **Sources:** Yahoo Finance (free), CoinGecko (free)
- **Granularity:** Daily
- **Special cases:** SPAXX=$1.00 always

### Double-Entry Bookkeeping (New Architecture)
- **Model:** Transaction (container) + JournalEntry (legs)
- **Rule:** Sum(debits) must equal sum(credits) for every transaction
- **Account Types:** Asset, Cash, Income, Expense, Liability, Equity
- **Row Grouping:** Detect settlement rows (blank action, blank symbol, qty=0)
- **Transaction Patterns:** Buy/Sell/Dividend/Transfer/Fee/Interest
- **USD Tracking:** Sum cash account debits minus credits
- **Benefits:** Eliminates double-counting, enforces accounting rules, clear audit trail
- **Status:** Core models complete, migration to views in progress

### USD Tracking (Single-Entry - Deprecated)
- **Method:** Sum all transactions without assetId
- **Issue:** Includes settlement rows (double-counting ~$500k instead of $144k)
- **Status:** Use double-entry system instead

### API Key Storage
- **Method:** UserDefaults (plain text)
- **Previous:** Keychain (constant password prompts - abandoned)
- **Security:** Local to device, not synced, app sandboxed
- **Migration:** Automatic from keychain to UserDefaults on first run

## Next Steps

### Immediate (Complete Double-Entry Migration)
1. Regenerate parse plans with enhanced agent (correct field mappings)
2. Test double-entry import with new parse plan
3. Verify USD balance = $144,218 (from Cash Balance column)
4. Complete migration service for existing data
5. Update PortfolioValueView to use Transaction model
6. Update PositionsView to use Transaction model
7. Update all other views for double-entry

### Short Term (Polish)
1. Implement ViewPreferences persistence
2. Add drag-reorder to asset lists
3. Fix CoreData Array warnings (use Transformable with custom coder)
4. Add balance verification UI (show unbalanced transactions)

### Medium Term (Advanced Features)
1. Pluggable import strategies per institution
2. Institution-specific parsers (beyond Fidelity)
3. Cash Balance column extraction (authoritative balance)
4. Multi-currency support
5. Exchange rate tracking

### Long Term (Features)
1. Multi-account net worth aggregation
2. Budget tracking and forecasting
3. Tax reporting (capital gains, dividends)
4. Export capabilities (CSV, QIF, OFX)
5. Real-time price updates (WebSocket feeds)

## Design Documents

Key design decisions documented in:
- `design.md` - Overall architecture
- `design-categories-tags.md` - Category and tag taxonomy
- `design-transaction-grouping.md` - Initial double-entry analysis
- `design-double-entry.md` - **Full double-entry implementation** (NEW)
- `design-iterative-categorization.md` - Conversational AI refinement
- `design-positions-tracking.md` - Quantity vs market value
- `design-market-value-tracking.md` - Price data strategy
- `design-price-api.md` - API integrations
- `design-stacked-wealth.md` - Wealth composition charts
- `design-multi-account.md` - Multi-account support
- `design-deduplication.md` - Duplicate prevention

## Quick Start Guides

- `DOUBLE_ENTRY_QUICKSTART.md` - **How to use the double-entry system** (NEW)
- `SESSION_2025-10-27.md` - Latest session work summary (NEW)

## Data Flow

### Single-Entry (Deprecated)
```
CSV Upload → RawFile → ImportBatch → Parse Plan
  ↓
Transform (all rows)
  ↓
Validate & Deduplicate
  ↓
LedgerEntry (1 per CSV row)
  ↓
Problem: Settlement rows double-count USD
```

### Double-Entry (Current)
```
CSV Upload → RawFile → ImportBatch → Parse Plan
  ↓
Transform (all rows, preserve metadata.action)
  ↓
Group Rows (settlement row detection)
  ↓
Transaction (1 per economic event)
  ├─ JournalEntry (Debit)
  └─ JournalEntry (Credit)
  ↓
Validate Balance (debits = credits)
  ↓
AI Categorization (optional)
  ↓
Price Data (fetch from APIs)
  ↓
Market Value Calculation (quantity × price)
  ↓
Analytics & Visualizations
```

## Test Coverage

**Manual testing with:**
- Fidelity transaction history (411+ rows)
- Multiple CSVs (overlapping dates)
- Various assets (SPY, VOO, QQQ, FBTC, NVDA, GLD, FXAIX, SCHD, SPAXX)
- Dividends, buys, sells, transfers
- Price data from Yahoo Finance & CoinGecko

**Sample data:**
- `sample_data/fidelity_sample_transactions.csv` - Representative format
- `sample_data/README.md` - Format documentation

## Performance Metrics

- CSV import: 411 rows in <1 second
- Preview generation: All rows, instant
- AI categorization: 50 transactions in ~30 seconds (5 API calls)
- Price fetching: 500 days × 8 assets in ~30 seconds
- Total Wealth calculation: Optimized from 60s → <1s (100x improvement)
- Chart rendering: 4,000+ data points smoothly

## User Feedback Incorporated

- ✅ All rows processed (not just 100)
- ✅ Parse plan reuse (not create duplicates)
- ✅ Deduplication (prevent inflation)
- ✅ FBTC as shares (not BTC)
- ✅ USD tracking (with logging)
- ✅ Dense price plotting (every price date)
- ✅ Year labels on X-axis
- ✅ Delete price data per asset
- ✅ Re-fetch button
- ✅ Performance optimization
- ⏳ Transaction grouping (in design)
- ⏳ Drag-reorder (planned)
