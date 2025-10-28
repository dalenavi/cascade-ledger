# AI Direct Categorization Design

## Core Concept

Instead of teaching AI to create generalized transformation rules, we give the AI ALL the CSV rows and ask it to **directly output the final Transaction objects with JournalEntry legs**.

## Input Format

```json
{
  "account": "Fidelity Investment",
  "institution": "Fidelity",
  "csvRows": [
    {
      "rowNumber": 0,
      "Run Date": "12/31/2024",
      "Action": "REINVESTMENT FIDELITY GOVERNMENT MONEY MARKET (SPAXX) (Cash)",
      "Symbol": "SPAXX",
      "Quantity": "283.06",
      "Amount ($)": "-283.06",
      "Description": "FIDELITY GOVERNMENT MONEY MARKET",
      ...
    },
    {
      "rowNumber": 1,
      "Run Date": "12/31/2024",
      "Action": "",
      "Symbol": "",
      "Quantity": "0.000",
      "Amount ($)": "283.06",
      ...
    },
    // ... all 474 rows
  ]
}
```

## Expected Output Format

```json
{
  "action": "categorize_transactions",
  "transactions": [
    {
      "sourceRows": [0, 1],
      "date": "2024-12-31",
      "description": "FIDELITY GOVERNMENT MONEY MARKET Reinvestment",
      "transactionType": "dividend",
      "journalEntries": [
        {
          "type": "debit",
          "accountType": "asset",
          "accountName": "SPAXX",
          "amount": 283.06,
          "quantity": 283.06,
          "quantityUnit": "shares",
          "assetSymbol": "SPAXX"
        },
        {
          "type": "credit",
          "accountType": "income",
          "accountName": "Dividend Income",
          "amount": 283.06
        }
      ],
      "notes": "Rows 0-1 grouped as reinvestment. Row 1 is settlement row (empty action/symbol)."
    },
    {
      "sourceRows": [2, 3],
      "date": "2024-12-20",
      "description": "FIDELITY 500 INDEX FUND Purchase",
      "transactionType": "buy",
      "journalEntries": [
        {
          "type": "debit",
          "accountType": "asset",
          "accountName": "FXAIX",
          "amount": 999.50,
          "quantity": 5.123,
          "quantityUnit": "shares",
          "assetSymbol": "FXAIX"
        },
        {
          "type": "credit",
          "accountType": "cash",
          "accountName": "USD",
          "amount": 999.50,
          "assetSymbol": "USD"
        }
      ],
      "notes": "YOU BOUGHT action with settlement row."
    }
  ],
  "summary": {
    "totalRows": 474,
    "transactionsCreated": 237,
    "allBalanced": true,
    "orphanedRows": []
  }
}
```

## AI Prompt Structure

```
You are a financial data categorization specialist. Your task is to analyze CSV transaction
data and produce double-entry accounting Transaction objects with JournalEntry legs.

INPUT DATA:
I'm providing you with 474 rows from a Fidelity investment account CSV export.

CSV Structure:
- Run Date: Transaction date (MM/dd/yyyy)
- Action: Transaction type (YOU BOUGHT, YOU SOLD, DIVIDEND RECEIVED, REINVESTMENT, etc.)
- Symbol: Asset ticker
- Quantity: Number of shares/units (can be negative for sells, 0 for settlement rows)
- Amount ($): Transaction amount (negative for purchases, positive for sales/deposits)
- Description: Asset name
- Type: Cash or Margin
- Settlement Date, Price, Commission, Fees, Accrued Interest, Cash Balance

FIDELITY PATTERN:
Fidelity uses a dual-row structure for many transactions:
- Row N: Primary transaction (has Action, Symbol, Quantity != 0)
- Row N+1: Settlement row (Action="", Symbol="", Quantity=0, Amount with opposite sign)

Settlement rows should be GROUPED with their primary row, not created as separate transactions.

DOUBLE-ENTRY ACCOUNTING RULES:

For each transaction, create journal entries that BALANCE (debits = credits):

Buy Transaction:
  DR: Asset {symbol}     {amount}    ({quantity} shares)
  CR: Cash USD           {amount}

Sell Transaction:
  DR: Cash USD           {amount}
  CR: Asset {symbol}     {amount}    ({quantity} shares)

Dividend (Cash):
  DR: Cash USD           {amount}
  CR: Income "Dividend Income"  {amount}

Dividend (Reinvested):
  DR: Asset {symbol}     {amount}    ({quantity} shares)
  CR: Income "Dividend Income"  {amount}

Transfer In:
  DR: Cash USD           {amount}
  CR: Equity "Owner Contributions"  {amount}

Transfer Out:
  DR: Equity "Owner Withdrawals"  {amount}
  CR: Cash USD           {amount}

Fee:
  DR: Expense "Fees & Commissions"  {amount}
  CR: Cash USD           {amount}

CRITICAL ASSET REGISTRY RULE:
- FBTC != BTC (they are different assets with different prices)
- Each symbol is a distinct asset
- Use exact symbol from CSV (FXAIX, SPAXX, NVDA, SPY, GLD, etc.)

YOUR TASK:

Analyze ALL 474 rows and produce Transaction objects following the output format above.

For each transaction:
1. Identify which CSV row(s) belong together (group settlement rows with primary)
2. Determine the transaction type
3. Create balanced journal entries (debits must equal credits)
4. Link to correct asset symbols
5. Add explanatory notes about your grouping/categorization decisions

OUTPUT FORMAT:
Return a JSON object following the structure shown above with:
- transactions: Array of Transaction objects
- summary: Statistics about your categorization

Focus on:
- Correct grouping (don't create transactions from settlement rows alone)
- Balanced entries (every transaction must balance)
- Proper asset linkage (use exact symbols)
- Clear notes explaining your decisions
```

## Implementation Plan

### 1. New Service: `DirectCategorizationService`
```swift
@MainActor
class DirectCategorizationService {
    func categorizeRows(
        csvRows: [[String: String]],
        account: Account
    ) async -> [Transaction] {
        // Send ALL rows to Claude
        // Get back Transaction objects with JournalEntry legs
        // Parse and return
    }
}
```

### 2. New UI Mode
In Parse Rules panel, add button:
```
[AI Direct Categorization]
  ↓
  Sends all 474 rows to Claude
  ↓
  Shows progress: "Analyzing 474 rows..."
  ↓
  Returns categorized transactions
```

### 3. Output Storage
Instead of Parse Plan, we store:
```swift
@Model
class CategorizationSession {
    var csvRows: [String]  // Row hashes
    var aiResponse: Data   // Full JSON response
    var transactions: [Transaction]  // Generated txns
    var createdAt: Date
}
```

This is **not a reusable parse plan** - it's a **specific categorization for this dataset**.

Want me to implement this AI Direct Categorization approach?