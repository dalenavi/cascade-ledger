# Category and Tag System Design

## Conceptual Model

### Three-Layer Classification System

**1. Transaction Type (Enum, One-Of, Editable)**
- Initial classification from CSV data
- Parse plan suggests type based on CSV fields
- **User can override** (stored in `userTransactionType`)
- Raw CSV value preserved in `rawTransactionType`
- Computed `effectiveTransactionType` returns user override or original
- Examples: `buy`, `sell`, `transfer`, `dividend`, `interest`, `deposit`, `withdrawal`, `fee`, `tax`
- **Why editable:** CSV might say "Debit" but actual meaning is "Rent Payment Transfer"

**2. Category (String, Primary, User-Editable)**
- High-level bucket for organizing transactions
- One primary category per transaction
- Can be auto-detected or manually assigned
- User category overrides auto category
- Hierarchical structure: `Category: Subcategory`

**3. Tags (Array of Strings, Stackable, User-Editable)**
- Additional contextual labels
- Multiple tags per transaction
- User-defined and system-suggested
- Used for filtering, search, and analysis

## Taxonomy

### Default Categories (Hierarchical)

```
Income
├── Salary
├── Bonus
├── Dividend
├── Interest
├── Capital Gains
└── Freelance

Housing
├── Rent
├── Mortgage
├── Utilities
├── Maintenance
└── Insurance

Food & Dining
├── Groceries
├── Restaurants
├── Coffee Shops
└── Meal Delivery

Transportation
├── Auto: Fuel
├── Auto: Maintenance
├── Auto: Insurance
├── Public Transit
└── Ride Share

Shopping
├── Clothing
├── Electronics
├── Home Goods
└── Personal Care

Healthcare
├── Medical
├── Dental
├── Pharmacy
└── Insurance

Entertainment
├── Streaming Services
├── Movies & Events
├── Hobbies
└── Gaming

Investments
├── Stock Purchase
├── Stock Sale
├── Fund Purchase
├── Cryptocurrency
└── Retirement Contributions

Transfers
├── Between Accounts
├── Payment Services (Venmo, Cash App, Zelle)
├── Person-to-Person
└── Savings Transfer

Fees & Charges
├── Bank Fees
├── Service Fees
├── Late Fees
└── Foreign Transaction

Taxes
├── Income Tax
├── Property Tax
├── Sales Tax
└── Capital Gains Tax

Uncategorized
```

### Common Tags

**Payment Method Tags:**
- `Cash App Transfer`
- `Venmo`
- `Zelle`
- `Wire Transfer`
- `ACH`
- `Check`
- `Direct Deposit`

**Frequency Tags:**
- `Recurring`
- `One-Time`
- `Quarterly`
- `Annual`

**Context Tags:**
- `Rent Payment`
- `Landlord: {Name}`
- `Merchant: {Name}`
- `Vendor: {Name}`
- `Payee: {Name}`

**Investment Tags:**
- `Tech Stocks`
- `Index Funds`
- `Bonds`
- `Retirement Account`
- `Taxable Account`

**Custom Tags:**
- User can create any tag
- Suggested based on transaction patterns
- Learned from user behavior

## Data Model

### Updated LedgerEntry
```swift
@Model
final class LedgerEntry {
    // Existing fields...

    // Transaction type (editable)
    var transactionType: TransactionType      // Auto-detected type
    var rawTransactionType: String?           // Original CSV value (preserved)
    var userTransactionType: TransactionType? // User override

    // Category (editable)
    var category: String?                     // Auto-detected category
    var subcategory: String?                  // Auto-detected subcategory
    var userCategory: String?                 // User-assigned (overrides auto)

    // Tags (stackable)
    var tags: [String]                        // Multiple tags

    // Annotations
    var notes: String?                        // User notes/context

    // Computed properties
    var effectiveTransactionType: TransactionType {
        userTransactionType ?? transactionType
    }

    var effectiveCategory: String {
        userCategory ?? category ?? "Uncategorized"
    }
}
```

### Category Model
```swift
@Model
final class Category {
    var id: UUID
    var name: String              // e.g., "Housing: Rent"
    var parentCategory: String?   // e.g., "Housing"
    var subcategory: String?      // e.g., "Rent"
    var icon: String?             // SF Symbol name
    var color: String?            // Hex color
    var isSystemCategory: Bool    // vs user-created
    var usageCount: Int           // Track popularity
}
```

### Tag Model
```swift
@Model
final class Tag {
    var id: UUID
    var name: String              // e.g., "Cash App Transfer"
    var category: TagCategory     // Enum: payment_method, frequency, context, custom
    var isSystemTag: Bool
    var usageCount: Int
}

enum TagCategory: String, Codable {
    case paymentMethod
    case frequency
    case context
    case investment
    case merchant
    case custom
}
```

### Categorization Rule
```swift
@Model
final class CategorizationRule {
    var id: UUID
    var priority: Int

    // Matching conditions
    var descriptionPattern: String?     // Regex or contains
    var amountRange: (min: Decimal?, max: Decimal?)?
    var transactionTypes: [TransactionType]?
    var account: Account?               // Rule specific to account
    var institution: Institution?        // Rule for institution

    // Actions
    var assignCategory: String?
    var assignTags: [String]
    var confidence: Double              // 0-1, for suggested vs auto-applied

    // Learning
    var isUserCreated: Bool
    var successCount: Int
    var rejectionCount: Int
    var lastUsed: Date?
}
```

## Auto-Categorization System

### Rule Matching Priority
1. **User-created rules** (highest priority)
2. **Institution-specific rules** (e.g., Fidelity dividend patterns)
3. **Account-specific rules** (e.g., checking account patterns)
4. **Global pattern rules** (e.g., "ACH CREDIT" → Salary)
5. **Transaction type defaults** (e.g., dividend → Income: Dividend)

### Default Rules

**Salary Detection:**
```
IF transactionType == deposit
AND description contains ["payroll", "salary", "direct dep"]
THEN category = "Income: Salary", tags = ["Direct Deposit", "Recurring"]
```

**Rent Detection:**
```
IF transactionType == transfer
AND description contains ["rent", "landlord"]
OR notes contains "rent"
THEN category = "Housing: Rent", tags = ["Rent Payment", "Recurring"]
```

**Cash App Transfer:**
```
IF transactionType == transfer
AND description contains ["cash app", "cashapp"]
THEN category = "Transfers", tags = ["Cash App Transfer"]
```

**Dividend:**
```
IF transactionType == dividend
THEN category = "Income: Dividend", tags = ["Investment Income"]
```

**Stock Purchase:**
```
IF transactionType == buy
THEN category = "Investments: Stock Purchase"
```

### Confidence Levels

**High Confidence (≥0.9) - Auto-apply:**
- Dividend → Income: Dividend
- Interest → Income: Interest
- Description matches known pattern exactly

**Medium Confidence (0.5-0.9) - Suggest:**
- Partial description match
- Amount pattern match
- Historical pattern match

**Low Confidence (<0.5) - Don't suggest:**
- Ambiguous description
- No clear pattern

## UI Design

### Transaction Detail View
```
┌─────────────────────────────────────┐
│ Transaction Details                 │
├─────────────────────────────────────┤
│ Date: Oct 15, 2025                  │
│ Amount: $1,250.00                   │
│ Description: ACH Electronic CreditX │
│ Type: Transfer                      │
├─────────────────────────────────────┤
│ Category: [Dropdown ▼]              │
│   └─ Housing: Rent                  │
│                                     │
│ Tags: [+ Add Tag]                   │
│   [Rent Payment] [x]                │
│   [Recurring] [x]                   │
│   [Landlord: Smith Properties] [x]  │
│                                     │
│ Notes:                              │
│ ┌─────────────────────────────────┐ │
│ │ Monthly rent payment             │ │
│ │                                  │ │
│ └─────────────────────────────────┘ │
├─────────────────────────────────────┤
│ Import Info:                        │
│ Source: fidelity_oct.csv, row 42   │
│ Batch: Q4 2025 Transactions         │
│ Parse Plan: v2                      │
└─────────────────────────────────────┘
```

### Category Management View
```
┌─────────────────────────────────────┐
│ Categories                          │
├─────────────────────────────────────┤
│ [+ New Category]                    │
│                                     │
│ 📊 Income (45 transactions)         │
│   └─ Salary (40)                   │
│   └─ Dividend (5)                  │
│                                     │
│ 🏠 Housing (12 transactions)        │
│   └─ Rent (12)                     │
│                                     │
│ 💰 Investments (120 transactions)   │
│   └─ Stock Purchase (60)           │
│   └─ Stock Sale (45)               │
│   └─ Dividend (15)                 │
└─────────────────────────────────────┘
```

### Auto-Categorization UI
```
┌─────────────────────────────────────┐
│ Categorization Suggestions          │
├─────────────────────────────────────┤
│ 15 uncategorized transactions       │
│                                     │
│ [Ask Claude to Categorize]          │
│                                     │
│ Suggested Rules:                    │
│ ┌─────────────────────────────────┐ │
│ │ "ACH CREDIT" → Income: Salary   │ │
│ │ Apply to 8 transactions   [✓][×]│ │
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ "DIVIDEND" → Income: Dividend   │ │
│ │ Apply to 5 transactions   [✓][×]│ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

## Claude Integration

### Agent Capabilities for Categorization

**1. Single Transaction Analysis:**
```
User: "What category should this be?"
Claude analyzes:
- Description: "ACH ELECTRONIC CREDIT PPD ID: PAYROLL"
- Amount: $3,250.00
- Type: deposit
- Historical patterns
Response: "This appears to be a salary payment. Suggest category: Income: Salary, tags: Direct Deposit, Recurring"
```

**2. Batch Categorization:**
```
User: "Categorize all my uncategorized transactions"
Claude:
- Groups similar transactions
- Suggests rules based on patterns
- Returns categorization suggestions with confidence
- User approves in bulk
```

**3. Rule Creation:**
```
User: "Always categorize Cash App transfers to 'Transfers' with 'Cash App Transfer' tag"
Claude:
- Creates categorization rule
- Applies to existing transactions
- Auto-applies to future imports
```

## Implementation Plan

### Phase 1: Data Model Enhancement
1. Add `Category` model with hierarchy
2. Add `Tag` model with categorization
3. Add `CategorizationRule` model
4. Update `LedgerEntry` with computed `effectiveCategory`
5. Migrate existing data

### Phase 2: UI Components
1. Transaction detail view with category picker
2. Tag selector with add custom tag
3. Category management view
4. Tag management view
5. Visual indicators in transaction list (category badges, tag chips)

### Phase 3: Rule Engine
1. Build rule matching engine
2. Default rule set for common patterns
3. Rule priority system
4. Confidence scoring
5. Apply rules on import
6. Bulk rule application

### Phase 4: Claude Integration
1. Add categorization tools for agent
2. `suggest_category` tool
3. `create_categorization_rule` tool
4. `analyze_transaction_patterns` tool
5. Batch categorization workflow
6. Learning from user corrections

### Phase 5: Analytics
1. Category breakdown views
2. Tag-based filtering
3. Spending by category charts
4. Tag co-occurrence analysis
5. Category trends over time

## Key Design Decisions

### 1. Type vs Category vs Tag

**Transaction Type** (immutable, from data):
- Reflects what the transaction IS
- Set by institution/CSV
- Used for accounting logic

**Category** (mutable, for organization):
- Reflects what the transaction is FOR
- User's mental model
- Used for budgeting and analysis

**Tags** (stackable, for context):
- Additional details and filtering
- Flexible and user-driven
- Can overlap (e.g., "Recurring" + "Rent Payment")

### 2. Hierarchy vs Flat

**Categories:** Hierarchical
- Primary: Secondary format
- "Housing: Rent" allows rollup to "Housing"
- Supports drill-down analysis

**Tags:** Flat
- No hierarchy needed
- Simple string matching
- Easy to add/remove

### 3. Auto vs Manual

**Auto-categorization when:**
- High confidence (>0.9)
- Clear pattern match
- Transaction type implies category (dividend → Income: Dividend)

**Suggest when:**
- Medium confidence (0.5-0.9)
- User can approve/reject
- Builds learning data

**Manual when:**
- Low confidence (<0.5)
- Ambiguous transactions
- New patterns

### 4. Storage Strategy

**Categories and Tags:**
- Stored as SwiftData models
- Referenced by string name in transactions
- Allows dynamic creation
- Tracks usage count for popularity

**Rules:**
- Stored as SwiftData models
- Evaluated on import and on-demand
- Versioned with success/rejection counts
- Can be edited/disabled

## Example Scenarios

### Scenario 1: Rent Payment
```
Raw CSV Type: "Debit"
Raw CSV Description: "ACH TRANSFER TO SMITH PROPERTIES"

Initial Classification:
- transactionType: debit (inferred from CSV)
- rawTransactionType: "Debit" (preserved)
- category: "Transfers" (auto from type)

User Refinement:
- userTransactionType: transfer (user corrects: it's a transfer, not just a debit)
- userCategory: "Housing: Rent"
- tags: ["Rent Payment", "Recurring", "Landlord: Smith Properties"]
- notes: "Monthly rent to landlord"

Result:
- effectiveTransactionType: transfer
- effectiveCategory: "Housing: Rent"
- Searchable by rent, housing, recurring, or landlord name
```

### Scenario 2: Cash App Transfer
```
Raw CSV Type: "Transfer"
Raw CSV Description: "CASH APP TRANSFER"

Initial Classification:
- transactionType: transfer (from CSV - correct!)
- rawTransactionType: "Transfer"
- category: "Transfers" (auto from type)

User Refinement:
- (type is correct, no override needed)
- userCategory: "Transfers" (keeps auto category)
- tags: ["Cash App Transfer"]
- Creates rule: description contains "cash app" → add tag "Cash App Transfer"

Result:
- effectiveTransactionType: transfer
- effectiveCategory: "Transfers"
- Future Cash App transfers auto-tagged
```

### Scenario 3: Stock Dividend
```
Raw CSV: "DIVIDEND PAYMENT AAPL"
Type: dividend (from CSV)
Auto Category: "Income: Dividend" (high confidence from type)
Auto Tags: ["Investment Income"]
User adds tag: ["Tech Stocks"]
Result: Correctly categorized with no user input
```

### Scenario 4: Ambiguous EFT
```
Raw CSV: "EFT DEBIT 1234567890"
Type: withdrawal
Auto Category: None (low confidence)
User views detail → adds notes: "Monthly gym membership"
User assigns category: "Healthcare: Fitness"
User adds tag: ["Recurring", "Gym Membership"]
Claude learns: "For similar EFT debits with notes about gym → Healthcare: Fitness"
```

## Migration Path

### Existing Transactions
1. Run auto-categorization on all existing
2. Show categorization suggestions view
3. User reviews and approves in batches
4. Rules created from approvals

### Future Imports
1. Parse plan extracts type and initial category
2. Rules engine runs on import
3. High-confidence rules auto-apply
4. Medium-confidence shown as suggestions
5. Low-confidence left uncategorized

## Questions for User

1. **Category Granularity:** Is "Housing: Rent" vs just "Rent" preferred?
2. **Default Categories:** Should we pre-populate all categories above or let user create as needed?
3. **Tag Suggestions:** Should Claude suggest tags during parse plan creation or only on manual review?
4. **Rule Visibility:** Should users see/edit categorization rules or keep them behind the scenes?
5. **Batch Actions:** Priority on bulk categorization vs one-at-a-time?

## Next Steps

1. Review this design
2. Answer key questions above
3. Create formal OpenSpec for categories/tags
4. Implement data models
5. Build UI components
6. Integrate with Claude agent
