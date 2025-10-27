# Parse Studio Design

## Account Workflow

### Account Creation Paths
1. **Standalone**: Accounts → New Account → Enter details → Select institution
2. **During Import**: Parse Studio → No account → Create inline → Continue import

### Account Model
```swift
Account {
    id: UUID
    name: String // "My Fidelity 401k"
    institution: Institution
    parsePlans: [ParsePlan] // Associated plans
    defaultParsePlan: ParsePlan?
}

Institution {
    id: String // "fidelity"
    displayName: String // "Fidelity Investments"
    commonParsePlans: [ParsePlan] // Shareable
}
```

### Import Flow with Account
1. User uploads CSV to Parse Studio
2. System prompts for account selection (or creation)
3. System checks for compatible parse plans:
   - Account's default plan
   - Other plans from same institution
   - Generic plans for similar CSV structure
4. User selects plan or starts fresh
5. Parse Studio opens with account context

## Architecture Overview

### Data Flow
```
CSV Upload → Parse Plan → Transform → Validate → Ledger Entry
     ↓          ↓           ↓          ↓           ↓
  RawFile   ParsePlan   ParseRun   Validation  LedgerStore
            (versioned)  (lineage)   Report    (append-only)
```

### Core Components

#### Parse Engine
- **Dialect Parser**: Frictionless Table Dialect for CSV structure
- **Schema Mapper**: Frictionless Table Schema for field typing
- **Transform Executor**: JSONata/JOLT via JavaScriptCore
- **Validator**: Great Expectations-style rules
- **Lineage Tracker**: Maps source rows to output entries

#### Parse Studio UI
- **Account Context Bar**: Shows selected account, institution, quick switch
- **Three-Panel Layout**: Raw → Editor → Results
- **Agent Chat Interface**: Natural language interaction with parse agent
- **Live Preview**: Incremental recomputation on changes
- **Error Highlighting**: Row-level validation feedback
- **Lineage Viewer**: Trace outputs to source cells
- **Commit Workflow**: Explicit versioning on user action

#### Agent Integration
- **Mapping Suggester**: Analyzes headers and samples
- **Error Fixer**: Proposes corrections for failures
- **Semantic Validator**: Checks financial consistency

## Key Design Decisions

### Why Frictionless Standards?
- Industry-standard for tabular data
- Extensive tooling ecosystem
- JSON-based, diffable, versionable
- Supports complex CSV dialects

### Why JSONata/JOLT?
- Declarative transformations
- Well-tested implementations
- Sandboxable execution
- Human-readable rules

### Why Partial Success?
- Real-world data is messy
- Users can fix incrementally
- Maintains forward progress
- Preserves valid data

### Version Strategy
- Working copy for all edits (no auto-versioning)
- Explicit commit creates immutable version
- Each import locks to committed parser version
- Can replay imports with newer versions
- Full lineage tracking
- Parsed data requires version reference

## Chat Interface Workflow

### Agent Interaction Model
```
User Message → Agent Analysis → Suggestion → User Review → Apply/Reject
                      ↓                           ↓
                Parse Plan Delta            Working Copy Update
                      ↓                           ↓
                 Chat History                Live Preview
```

### Chat Features
- Natural language queries
- Contextual suggestions based on current data
- Visual diff of proposed changes
- Action history with undo capability
- Feedback incorporation for learning

### Commit Workflow
1. User works with parse plan in working copy
2. Agent suggestions modify working copy
3. Live preview shows results
4. User commits when satisfied
5. Version created and data persisted
6. Import batch references committed version

## Transaction Identity

### Deduplication Strategy
```swift
transactionHash = SHA256(
    date + accountId + assetId +
    type + amount + normalizedDescription
)
```

### Fuzzy Matching
- Date range overlaps
- Amount similarity (±0.01)
- Description Levenshtein distance

## Performance Considerations

### Live Preview
- Sample-based (first 100 rows)
- Cached intermediate results
- Debounced recomputation
- Column-level incrementality

### Full Import
- Chunked processing (1000 rows)
- Streaming CSV parser
- Progress reporting
- Resumable on failure

## Security & Privacy
- All parsing on-device
- No data leaves device
- Sandboxed transform execution
- Resource limits on transforms

## Field Extensibility Model

### Canonical Fields vs Metadata
The `LedgerEntry` model supports both canonical fields and extensible metadata:

**Canonical Fields (strongly typed):**
- `date` (Date) - Required
- `amount` (Decimal) - Required
- `transactionDescription` (String) - Required
- `transactionType` (TransactionType enum)
- `category`, `subcategory` (String)
- `assetId` (String) - For investments

**Metadata Dictionary (flexible):**
- `metadata: [String: String]` - Any additional fields
- Preserves institution-specific data
- Searchable and queryable
- Examples: broker reference numbers, lot IDs, exchange rates

### Mapping Strategy
1. Map standard fields to canonical properties
2. Map custom fields to metadata dictionary
3. Agent suggests which fields are canonical vs metadata
4. All data preserved for audit trail

## Claude Agent Integration

### System Prompt Structure
```
You are a financial data parsing assistant helping users import CSV data into their ledger.

CONTEXT:
- File: {fileName}
- Headers: {csvHeaders}
- Sample Data: {first10Rows}
- Account: {accountName}
- Institution: {institutionName}

PARSE PLAN SCHEMA:
You can create/modify parse plans using Frictionless Data standards:
- Fields: name, type (date|currency|string|number), mapping
- Types available: date, currency, string, number, integer, boolean

CANONICAL LEDGER FIELDS (map here when possible):
- date (required) - Transaction date
- amount (required) - Transaction amount
- transactionDescription (required) - Description text
- transactionType - Type: debit, credit, buy, sell, transfer, dividend, interest, fee, tax
- category - Transaction category
- subcategory - Subcategory
- assetId - Asset identifier (stocks, crypto, etc.)

METADATA FIELDS (for institution-specific data):
Any fields not matching canonical schema can be mapped to "metadata.{fieldname}"
Examples: metadata.lot_id, metadata.exchange_rate, metadata.confirmation_number

RESPONSE FORMAT:
When creating a parse plan, respond with:
{
  "action": "create_parse_plan",
  "explanation": "Brief explanation",
  "fields": [
    {"name": "Date", "type": "date", "mapping": "date"},
    {"name": "Amount", "type": "currency", "mapping": "amount"},
    {"name": "Lot ID", "type": "string", "mapping": "metadata.lot_id"}
  ]
}

When explaining or discussing, use natural language.
```

### API Configuration
- Model: claude-3-5-haiku-20241022
- Max Tokens: 4096
- Temperature: 0.3 (deterministic parsing)
- API Key: Stored in macOS Keychain
- Streaming: Enabled for better UX

## Extension Points

### Future Enrichers
- `CategoryEnricher`: Auto-categorization
- `MerchantNormalizer`: Clean names
- `SplitDetector`: Multi-part transactions
- `TransferMatcher`: Pair transfers

### Future Sources
- PDF statement OCR
- API connectors
- Email parsing
- Screen scraping