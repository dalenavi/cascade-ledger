# Agent-Assisted Parse Plan Configuration

## The Problem

User has uploaded CSV files. Agent needs to:
1. Understand the CSV structure
2. Draft a parse plan (field mappings, transformations)
3. See the transformation results (intermediate + transactions)
4. Iterate to fix issues (unbalanced transactions, incorrect grouping)
5. Produce working parse rules

## Agent Context Structure

### Stage 1: CSV Analysis
```
Agent receives:
- Headers: ["Run Date", "Action", "Symbol", "Amount ($)", ...]
- Sample rows (first 10, middle 10, last 10)
- Row count: 244
- Detected patterns: "Fidelity format (Action + Settlement pattern)"

Agent produces:
- Proposed field mappings:
    Run Date → date (format: MM/dd/yyyy)
    Amount ($) → amount (type: currency)
    Symbol → assetId (type: string)
    Action → metadata.action (preserve for settlement detection)
- Identified settlement pattern: "Fidelity (empty action/symbol = settlement)"
```

### Stage 2: Transformation Review
```
Agent receives:
- Transformation results: 244 rows transformed
- Sample transformed rows:
    {
      date: Date(2024-12-20),
      amount: Decimal(-999.50),
      assetId: "FXAIX",
      metadata.action: "YOU BOUGHT"
    }
- Errors: "2 rows failed date parsing"

Agent produces:
- Adjustments: "Change date format to handle 'MM-dd-yyyy' variant"
- Confirms: "All amount fields parsed successfully"
```

### Stage 3: Grouping Review
```
Agent receives (from Grouping Debug view):
- Groups created: 122
- Group breakdown:
    Primary + Settlement: 121
    Standalone: 1
    Orphaned Settlement: 0
- Example groups:
    Group #1: Rows [0, 1] - "YOU BOUGHT FXAIX" + settlement
    Group #2: Rows [2, 3] - "DIVIDEND RECEIVED SPY" + settlement

Agent produces:
- Validation: "Grouping pattern correct for Fidelity"
- Or: "Found 5 orphaned settlements - settlement detector needs adjustment"
```

### Stage 4: Transaction Review
```
Agent receives (from Transactions view):
- Transactions created: 122
- Balance status: 120 balanced, 2 unbalanced
- Unbalanced examples:
    Transaction #42: Buy NVDA
      DR: Asset NVDA  +1000.00
      CR: Cash USD    -999.50
      ⚠️ Difference: $0.50

Agent produces:
- Root cause: "Fee not accounted for - need to add fee leg to buy transactions"
- Proposed fix: "Update TransactionBuilder.buildBuyTransaction to check for metadata.fees"
```

## Agent Tools

### 1. `analyze_csv`
```json
{
  "action": "analyze_csv",
  "output": {
    "headers": [...],
    "sampleRows": [...],
    "detectedInstitution": "fidelity",
    "recommendedParsePlan": {...}
  }
}
```

### 2. `update_parse_plan`
```json
{
  "action": "update_parse_plan",
  "fields": [
    {
      "csvColumn": "Run Date",
      "mapping": "date",
      "type": "date",
      "format": "MM/dd/yyyy"
    }
  ]
}
```

### 3. `get_transformation_results`
```json
{
  "action": "get_transformation_results",
  "output": {
    "intermediate": [...],  // Transformed dicts
    "grouping": {...},      // Group statistics
    "transactions": [...]   // Final domain objects
  }
}
```

### 4. `adjust_settlement_rules`
```json
{
  "action": "adjust_settlement_rules",
  "pattern": "fidelity",
  "rules": {
    "isSettlement": "action.isEmpty && symbol.isEmpty && quantity == 0"
  }
}
```

## UI Design: Agent Mode

### Activation
```
┌─────────────────────────────────────────────┐
│ Parse Rules Versions                        │
│                                             │
│ ⚠️ Working Copy (Uncommitted)               │
│   0 fields mapped                           │
│                                             │
│   [✨ Activate Agent]  [Edit Manually]      │
└─────────────────────────────────────────────┘
```

### Agent Working
```
┌─────────────────────────────────────────────┐
│ 🤖 Agent Configuring Parse Rules...         │
│                                             │
│ ● Analyzing CSV structure                   │
│ ○ Drafting field mappings                   │
│ ○ Testing transformation                    │
│ ○ Reviewing transactions                    │
│ ○ Iterating improvements                    │
│                                             │
│ [View Agent Chat] [Stop Agent]              │
└─────────────────────────────────────────────┘
```

### Agent Results
```
┌─────────────────────────────────────────────┐
│ ✅ Agent Configuration Complete              │
│                                             │
│ Working Copy: 13 fields mapped              │
│ Transformation: 244 rows → 122 transactions │
│ Validation: ✓ 122 balanced, 0 unbalanced    │
│                                             │
│ [View Details] [Commit as v1] [Retry]       │
└─────────────────────────────────────────────┘
```

## Agent Workflow Steps

### Step 1: Analyze
```
Agent: "I'll analyze the CSV structure"

Tool call: analyze_csv()
Response:
  Headers: 13 fields
  Institution: Fidelity
  Pattern: Action-based with settlement rows

Agent: "This is a Fidelity export with 13 columns..."
```

### Step 2: Draft
```
Agent: "Creating parse plan with field mappings"

Tool call: update_parse_plan(fields: [...])

Agent: "I've mapped all 13 fields. Run Date→date, Amount→amount..."
```

### Step 3: Validate
```
Tool call: get_transformation_results()
Response:
  Transformed: 244 rows
  Grouped: 122 groups
  Transactions: 122 (120 balanced, 2 unbalanced)

Agent: "Found 2 unbalanced transactions. Investigating..."
[Shows unbalanced transaction details]

Agent: "Issue: Fee field not accounted for. Adjusting rules..."
```

### Step 4: Iterate
```
Agent reviews transactions, identifies issues, adjusts

Iteration loop:
1. Update parse plan
2. Get new results
3. Check validation
4. Repeat until all balanced
```

### Step 5: Finalize
```
Agent: "All 122 transactions are balanced. Parse plan ready to commit."

Offers:
- [Commit as v1] - Save parse plan
- [Show me the results] - User reviews
- [Keep iterating] - Agent continues
```

## Implementation Plan

### A. Create `ParseAgentService`
```swift
actor ParseAgentService {
  func configure(
    csvRows: [[String: String]],
    account: Account,
    onProgress: (String) -> Void
  ) async -> ParsePlan
}
```

### B. Add Agent Mode UI
- Button in ParsePlanVersionsPanel: "✨ Activate Agent"
- Shows agent status overlay
- Streams agent thinking
- Shows intermediate results

### C. Agent Tools as Functions
```swift
// Tools the agent can call
func analyzeCSV() -> CSVAnalysis
func updateParsePlan(fields: [FieldMapping]) -> Void
func getTransformationResults() -> TransformationResults
func commitParsePlan() -> ParsePlanVersion
```

### D. Feedback Loop
```
User activates agent
  ↓
Agent analyzes CSV
  ↓
Agent drafts parse plan → Shows in UI
  ↓
System auto-transforms → Shows intermediate, grouping, transactions
  ↓
Agent reviews output → Identifies issues
  ↓
Agent adjusts rules → Updates working copy
  ↓
System re-transforms → Shows new results
  ↓
Agent validates → Loop until satisfied
  ↓
Agent commits parse plan as v1
```

## Agent Prompt Structure

```
You are a financial data transformation specialist. Your task is to configure
parse rules to transform CSV financial data into double-entry accounting transactions.

Current Context:
- Account: Fidelity Investment
- CSV Files: 2 files, 244 total rows (deduplicated)
- Headers: Run Date, Action, Symbol, Amount ($), ...
- Institution: Detected as Fidelity (Action-based with settlement rows)

Your Goals:
1. Map all CSV fields to canonical schema
2. Ensure all rows transform successfully
3. Ensure settlement rows group correctly
4. Ensure all transactions balance (debits == credits)
5. Link all assets through AssetRegistry

Available Tools:
- analyze_csv(): Get CSV structure and samples
- update_parse_plan(fields): Set field mappings
- get_results(): See transformation output
- iterate until perfect

Output Format:
You will see 3 result views:
1. Intermediate: Transformed dictionaries
2. Grouping: How rows were grouped by settlement detector
3. Transactions: Final double-entry domain objects

Focus on Transactions view - all must be balanced and correct.

Begin by analyzing the CSV structure...
```

## Key Design Decisions

1. **Agent runs autonomously** - Not turn-by-turn chat, but goal-directed
2. **Agent has tools** - Can read data, update config, get results
3. **Agent sees all 3 outputs** - Intermediate, grouping, transactions
4. **Agent focuses on transaction quality** - Balanced, correct accounts, proper assets
5. **Agent explains reasoning** - "Found fee field, adding to buy transactions"
6. **User can intervene** - Stop agent, take over manually, or let it finish

Want me to implement this agent workflow?
